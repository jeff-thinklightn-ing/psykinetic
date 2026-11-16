class_name BuilderUI
extends Node
## Builder mode on a client (BuilderHost on the server does the asking): B
## turns it on and off. On, a left drag picks an area (outlined on the
## ground) and the builder's window opens for the request ("a pond here";
## BuilderPanel, decision 885); the server's proposal shows over the area as a
## ghost, its answer in the window. Then Enter
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
## The window (decision 885): the answer, the box, the keys and the cost.
var panel: BuilderPanel
var _box: LineEdit
var _status: Label
## The status line's backed plate (ui-design, 2026-11-16: the bare line was pale on Umbrage's pale wall):
## the HUD key hints' dark plate, hugging the words, at the top centre.
var _status_plate: PanelContainer
## The cursor's cell and the player's, while on (decision 537).
var _coords: Label
var _coords_at := Vector2i(-2, -2)
var _coords_me := Vector2i(-2, -2)
var _proposal := {}
## The request being worked on, for the panel's "Checking:" line (867 amended (1)).
var _asked := ""
## Esc pressed while it was worked on: the server stops it when its checks end (867 amended (1)).
var _cancelling := false
## --test-builder with a request starting "+": accept the proposal when it comes.
var _test_accept := false
## --test-builder with a request starting "*": the answer shown with every fold open (a shot's).
var _test_unfold := false


func _ready() -> void:
	_status_plate = PanelContainer.new()
	_status_plate.name = "BuilderStatusPlate"
	_status_plate.theme_type_variation = &"HintStrip"
	_status_plate.anchor_left = 0.5
	_status_plate.anchor_right = 0.5
	_status_plate.offset_top = 90
	_status_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status_plate.visible = false
	main.get_node("HUD").add_child(_status_plate)
	_status = Label.new()
	_status.name = "BuilderStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.theme_type_variation = &"HintWords"
	_status_plate.add_child(_status)
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
	panel = BuilderPanel.new()
	panel.visible = false
	panel.closed.connect(escape)
	# 885 amended (1): whole, the box takes the keys; cut down, it has none (Enter, Esc, Tab and
	# Ctrl+Z come to handle_input).
	panel.full_changed.connect(func(full: bool) -> void:
		if full:
			_box.grab_focus()
		else:
			_box.release_focus())
	_box = panel.box
	_box.text_submitted.connect(_submitted)
	_box.gui_input.connect(_on_box_key)
	main.get_node("HUD").add_child(panel)


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
	return ("%s %s" % [building.get("code", ""), plain_name(building)]).strip_edges()


## A building's name without its code: "house", "dwarven forge".
static func plain_name(building: Dictionary) -> String:
	var name := str(building.get("kind", ""))
	if name.is_empty():
		name = str(building.get("slot", "building")).trim_prefix("building.")
	return name.replace("_", " ")


## The cursor hint over a building (decision 537; the coordinator's fix,
## 2026-10-24): in builder mode ([param builder]) its code, name and build
## state, "H3 house, being built 40%"; else a town's building (a use and a
## town, not solid or doorless) by its plain name and state, "house, being
## built 40%", and nothing for one that serves no town (a pillar, a table,
## the Halls' forge): the codes are the builder's.
static func hint_words(building: Dictionary, states: Dictionary, builder: bool) -> String:
	var state := build_state(building, states)
	var name := building_words(building)
	if not builder:
		var slot := str(building.get("slot", ""))
		if str(building.get("use", "")).is_empty() or str(building.get("town_id", "")).is_empty() or slot in Level.SOLID or slot in Level.DOORLESS:
			return ""
		name = plain_name(building)
	return name + (", " + state if not state.is_empty() else "")


## How far a building's town has built it (decision 566), from the town's
## buildings state as the "town" message carries it (Main.town_states):
## "being built 40%" while a job runs, "planned" with none yet, "damaged";
## "" for a standing one, or a building that serves no town.
static func build_state(building: Dictionary, states: Dictionary) -> String:
	if str(building.get("use", "")).is_empty():
		return ""
	var record: Dictionary = states.get(str(building.get("town_id", "")), {}).get(str(building["use"]), {})
	var progress := float(record.get("progress", -1.0))
	if progress >= 0.0:
		return "being built %d%%" % roundi(progress * 100.0)
	return {Towns.PLANNED: "planned", Towns.DAMAGED: "damaged"}.get(str(record.get("state", "")), "")


## The party log's line for a building clicked in builder mode:
## "H3 house at 212, 207, facing south, use: inn, being built 40%".
static func building_line(building: Dictionary, states := {}) -> String:
	var at: Vector2i = building.get("cell", Vector2i.ZERO)
	var facing: Vector2i = building.get("facing", Vector2i(0, 1))
	var side: String = {Vector2i(0, -1): "north", Vector2i(1, 0): "east", Vector2i(0, 1): "south", Vector2i(-1, 0): "west"}.get(facing, str(facing))
	var line := "%s at %d, %d, facing %s" % [building_words(building), at.x, at.y, side]
	if not str(building.get("use", "")).is_empty():
		line += ", use: %s" % building["use"]
	if not str(building.get("town", "")).is_empty():
		line += ", town: %s" % building["town"]
	var state := build_state(building, states)
	if not state.is_empty():
		line += ", " + state
	return line


func is_typing() -> bool:
	return _box != null and panel.visible and _box.has_focus()


## A key in the typing box, taken there before Godot or Main see it (885 amended (1)): Tab with an
## answer shown cuts the pane down again, and does nothing while he asks; Esc with an answer
## shown whole clears the box, or from an empty box cuts the pane down; else Esc is escape()'s, as before.
func _on_box_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.keycode not in [KEY_TAB, KEY_ESCAPE]:
		return
	# Tab is the box's always (the LineEdit's own Tab would move the focus off it, leaving the box
	# shown while the game took the keys, ui's read); a held key's echo does nothing.
	_box.accept_event()
	if key.echo:
		return
	if key.keycode == KEY_TAB:
		if panel.has_answer():
			panel.set_full(false)
	else:
		if panel.has_answer() and panel.full:
			if _box.text.is_empty():
				panel.set_full(false)
			else:
				_box.text = ""
		else:
			escape()


## Main's input, first: true if builder mode took it.
func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if Keys.matches(key.keycode, "builder") and not key.ctrl_pressed and not is_typing():
			toggle()
			return true
		if not active:
			return false
		# 885 amended (1): Tab opens the answer whole while he reads it cut down (before Main's
		# talk log, as Enter's accept comes before its talk).
		if key.keycode == KEY_TAB and state == "proposal" and panel.visible and panel.has_answer():
			panel.set_full(not panel.full)
			return true
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
				main.talk.add_line("Builder", building_line(clicked, main.town_states), true, true)
		if button.pressed and at != main.NONE and state in ["idle", "asking", "proposal"]:
			if state == "proposal":
				_send({"op": "discard"})
			_drag_from = at
			_set_area(Rect2i(at, Vector2i.ONE))
		elif not button.pressed and _drag_from != Vector2i(-1, -1):
			_drag_from = Vector2i(-1, -1)
			_open_box(true)
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
		_status_plate.visible = false


## Esc: the proposal discarded, else the box closed, else the area let go.
func escape() -> void:
	if state == "working":
		# 867 amended (1): the panel's "Esc cancel" while it works; the server ends it whole, then says "discarded".
		if not _cancelling:
			_cancelling = true
			_send({"op": "discard"})
			_say("Cancelling: %s ..." % _asked)
			panel.working("Cancelling: %s" % _asked, true)
	elif state == "proposal":
		_send({"op": "discard"})
		_proposal = {}
		state = "asking"
		_show_area()
		_open_box()
		_say("Discarded. Ask again, or drag out another area.")
	elif panel.visible:
		_reset()
		_say("Builder mode: drag out an area.   B leaves.")
	else:
		_reset()


func _reset() -> void:
	state = "idle"
	area = Rect2i()
	_proposal = {}
	panel.visible = false
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
	main._client3d.show_builder(area, _proposal.get("cells", []), _proposal.get("edges", []), beyond, _proposal.get("heights", []), _proposal.get("roofs", []),
		_proposal.get("spots", []))


## The pane open on the area; [param new_area] (a drag's end, --test-builder) picks its home first.
func _open_box(new_area := false) -> void:
	if area.size == Vector2i.ZERO:
		return
	state = "asking" if state != "proposal" else state
	if state != "proposal":
		panel.asking(area, "what goes in these %d x %d cells?" % [area.size.x, area.size.y])
	if new_area:
		_place_panel()
	panel.visible = true
	_box.grab_focus()


## The cut-down pane's least height (ui-design's mock: 358 units), for the choice before it is laid out.
const BRIEF_HEIGHT := 358.0


## 885 amended (1): the pane's home picked before it is drawn, when an answer or a new area comes
## (never as the camera turns; choose_home's rules). [param kept]: at an answer, the home the pane
## already has for this area ("" for a new area).
func _place_panel(kept := "") -> void:
	var holder := panel.get_parent_control()
	var screen := holder.size if holder != null else panel.get_viewport_rect().size
	var pane := panel.pane_size()
	pane.y = maxf(pane.y, BRIEF_HEIGHT)
	var taken: Array = main.call("open_window_rects") if main.has_method("open_window_rects") else []
	var points := outline_points()
	# The bodies count only as the home is first chosen (the ask, a new area); an answer keeps it.
	var bodies := body_rects() if kept == "" else {}
	var marks := answer_marks() if kept != "" else {}
	var home := choose_home(points, pane, screen, taken, kept, bodies, marks)
	panel.place(home)
	# A still's log says which home and why (its outline seen from the camera as it stood then).
	var middle := Vector2.ZERO
	for point: Vector2 in points:
		middle += point
	var shown := points.filter(func(point: Vector2) -> bool: return Rect2(Vector2.ZERO, screen).has_point(point)).size()
	print("[builder] the pane's home: %s (kept %s; the outline's middle %s, %d of %d points on a %s screen; %d windows open%s; bodies %s)" % [
		home, kept if kept != "" else "none", (middle / maxf(points.size(), 1)).round(), shown, points.size(), screen.round(), taken.size(),
		", one at the right, so left" if window_at_right(pane, screen, taken) else "",
		"not counted" if kept != "" else "on the lines below"])
	if not marks.is_empty():
		print("[builder]   the ghost's marks under each home: left %d of %d counted (%d of %d in all), right %d (%d)" % [
			covered(marks["counted"], BuilderPanel.home_rect("left", pane, screen)), marks["counted"].size(),
			covered(marks["all"], BuilderPanel.home_rect("left", pane, screen)), marks["all"].size(),
			covered(marks["counted"], BuilderPanel.home_rect("right", pane, screen)), covered(marks["all"], BuilderPanel.home_rect("right", pane, screen))])
	# One line a box, short (stills12's one line was cut off at the companion's box): x, y, width, height.
	for who: String in ["player", "companion"]:
		for box: Rect2 in bodies.get(who, []):
			print("[builder]   %s's box: x %d, y %d, %d wide, %d high" % [who, box.position.x, box.position.y, box.size.x, box.size.y])
	for why: String in bodies.get("unseen", []):
		print("[builder]   an own companion unseen: %s" % why)


## The answer's ghost as drawn on the screen (HUD units, as outline_points'), for choose_home at an answer:
## {"counted": the marks of what the change takes up or alters (gone and changed spots, changed cells),
## "all": those and the new and kept spots}; each spot its mark with its arrow (Client3D.spot_mark_rect),
## each cell its square. Empty without the view or an answer.
func answer_marks() -> Dictionary:
	var view: Client3D = main._client3d
	if view == null or _proposal.is_empty():
		return {}
	var counted: Array = []
	var all: Array = []
	for spot: Variant in _proposal.get("spots", []):
		if not spot is Array or (spot as Array).size() < 7:
			continue
		var rect := view.spot_mark_rect(spot)
		if not rect.has_area():
			continue
		all.append(rect)
		if str(spot[6]) in ["gone", "changed"]:
			counted.append(rect)
	for cell: Variant in _proposal.get("cells", []):
		if cell is Array and (cell as Array).size() >= 2:
			var rect := view.cell_screen_rect(Vector2i(int(cell[0]), int(cell[1])))
			if rect.has_area():
				counted.append(rect)
				all.append(rect)
	return {"counted": counted, "all": all}


## The player's and his own companions' figures on the screen ({"player": [Rect2], "companion":
## [Rect2]}, HUD units as outline_points'), each its HUD name plate with it as last drawn
## (UiNamePlates.placed_rect), for choose_home; empty without the view.
func body_rects() -> Dictionary:
	var view: Client3D = main._client3d
	var me: Player = main._local_player()
	if view == null or me == null:
		return {}
	var plates: UiNamePlates = main.name_plates if "name_plates" in main else null
	var with_plate := func(entity: GridEntity) -> Rect2:
		var box := view.screen_rect_of(entity)
		var plate := plates.placed_rect(entity.get_instance_id()) if plates != null and box.has_area() else Rect2()
		return box.merge(plate) if plate.has_area() else box
	var player: Array = []
	var own: Rect2 = with_plate.call(me)
	if own.has_area():
		player.append(own)
	var companion: Array = []
	var unseen: Array[String] = []  # Why an own companion has no box (the log's: stills9 and stills11's 4K list empty).
	for entity: GridEntity in World.get_entities():
		if not main._is_own_companion(entity):
			continue
		var puppet: Node3D = view._puppets.get(entity.get_instance_id())
		var box: Rect2 = with_plate.call(entity)
		if box.has_area():
			companion.append(box)
		else:
			unseen.append("no puppet" if puppet == null else ("hidden" if not puppet.is_visible_in_tree() else "off the view"))
	return {"player": player, "companion": companion, "unseen": unseen}


## "left" or "right" for a pane [param pane] big on a [param screen] (HUD units), [param points] the
## area's outline on the screen (the coordinator's rules, 2026-11-14). The right home gives way to any
## rect of [param taken] that meets the room the pane may take there: full (Tab) it is WIDTH wide and
## runs to the screen's foot, and it never changes home on Tab, so a window under its reading size
## (the pack, below the corner map) still sends it left (window_at_right). An answer for an area already
## shown keeps the home in [param kept], the one chosen at the ask (the coordinator, 2026-11-14: "the home is
## chosen once, when the ask is made, and kept until the answer is closed"; stills13 moved it over Juno at the
## answer by the outline's count). Else a new area's home is ranked first by
## [param bodies] ({"player": [Rect2], "companion": [Rect2]}, their figures on the screen with the plates
## over their heads): one over neither body wins, then one over the companion only, one over the player
## last (the coordinator, 2026-11-14, on ui-design's stills6: the right home over Juno's head; and on
## stills12, 2026-11-15: a person outranks a line on the ground, so the bodies come before the outline).
## Equal on bodies, the home covering fewer of the points, and on a tie the one whose middle is farther
## from the points' middle (the side away from the area), left if those are equal too.
##
## At an answer, [param marks] ({"counted": [Rect2], "all": [Rect2]}, the ghost's marks as drawn on the
## screen: answer_marks) may move it once (ui-design's ruling, 2026-11-16, on builderlook_bd50a9723: the
## one spot an ask took up lay under the pane's corner): the home covering fewer of the counted marks (gone
## and changed spots, changed cells), each grown MARK_ROOM; on a tie the one covering fewer of all of them,
## new ones too; still tied, the kept home. The other home must be free of [param taken], else the kept
## one stays whatever it covers.
static func choose_home(points: Array, pane: Vector2, screen: Vector2, taken: Array, kept := "", bodies := {}, marks := {}) -> String:
	var left := BuilderPanel.home_rect("left", pane, screen)
	var right := BuilderPanel.home_rect("right", pane, screen)
	if window_at_right(pane, screen, taken):
		return "left"
	if kept in ["left", "right"]:
		var other := "right" if kept == "left" else "left"
		var other_rect := right if other == "right" else left
		var kept_rect := left if other == "right" else right
		if marks.is_empty() or taken.any(func(rect: Variant) -> bool: return rect is Rect2 and (rect as Rect2).intersects(other_rect)):
			return kept
		for key: String in ["counted", "all"]:
			var on_kept := covered(marks.get(key, []), kept_rect)
			var on_other := covered(marks.get(key, []), other_rect)
			if on_kept != on_other:
				return other if on_other < on_kept else kept
		return kept
	var under := func(home: Rect2) -> int: return points.filter(func(point: Variant) -> bool: return home.has_point(point)).size()
	var on_left: int = under.call(left)
	var on_right: int = under.call(right)
	if not bodies.is_empty():
		var over := func(home: Rect2) -> int:
			var meets := func(rect: Variant) -> bool: return rect is Rect2 and (rect as Rect2).intersects(home, true)
			if (bodies.get("player", []) as Array).any(meets):
				return 2
			return 1 if (bodies.get("companion", []) as Array).any(meets) else 0
		var over_left: int = over.call(left)
		var over_right: int = over.call(right)
		if over_left != over_right:
			return "left" if over_left < over_right else "right"
	if on_left != on_right:
		return "right" if on_right < on_left else "left"
	if points.is_empty():
		return "left"
	var middle := Vector2.ZERO
	for point: Vector2 in points:
		middle += point
	middle /= points.size()
	return "right" if right.get_center().distance_to(middle) > left.get_center().distance_to(middle) else "left"


## How far round a ghost's mark a home counts it as covered (HUD px; ui-design, 2026-11-16).
const MARK_ROOM := 12.0


## How many of [param rects] (marks as drawn) meet [param home] once grown by MARK_ROOM.
static func covered(rects: Array, home: Rect2) -> int:
	return rects.filter(func(rect: Variant) -> bool: return rect is Rect2 and (rect as Rect2).grow(MARK_ROOM).intersects(home)).size()


## Whether a rect of [param taken] meets the room a [param pane] pane may take in the right home on a
## [param screen]: full (Tab) it is WIDTH wide and runs to the screen's foot (choose_home sends it left).
static func window_at_right(pane: Vector2, screen: Vector2, taken: Array) -> bool:
	var reach := BuilderPanel.home_rect("right", Vector2(maxf(pane.x, BuilderPanel.WIDTH),
		maxf(pane.y, screen.y - BuilderPanel.RIGHT_TOP - BuilderPanel.FOOT_ROOM)), screen)
	return taken.any(func(rect: Variant) -> bool: return rect is Rect2 and (rect as Rect2).intersects(reach))


## The area's outline on the screen: each cell round its edge, where the 3D view draws it (HUD units);
## none without the view.
func outline_points() -> Array:
	var points: Array = []
	if main._client3d == null or area.size == Vector2i.ZERO:
		return points
	for x in range(area.position.x, area.end.x):
		points.append(main._client3d.screen_of_tile(Vector2i(x, area.position.y)))
		points.append(main._client3d.screen_of_tile(Vector2i(x, area.end.y - 1)))
	for y in range(area.position.y + 1, area.end.y - 1):
		points.append(main._client3d.screen_of_tile(Vector2i(area.position.x, y)))
		points.append(main._client3d.screen_of_tile(Vector2i(area.end.x - 1, y)))
	return points


func _submitted(text: String) -> void:
	var asked := text.strip_edges()
	_box.text = ""
	if asked.is_empty():
		if state == "proposal":
			_send({"op": "accept"})
		return
	_send({"op": "ask", "area": [area.position.x, area.position.y, area.size.x, area.size.y], "text": asked})
	state = "working"
	_asked = asked
	_say("Asking: %s ..." % asked)
	panel.working("Asking: %s" % asked, true)


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
			# 867 amended (1): Claude's answer came, its changes being checked (voice's words).
			if data.get("checking", false) and not _asked.is_empty() and not _cancelling:
				_say("Checking: %s ..." % _asked)
				panel.working("Checking: %s" % _asked, true)
		"proposal":
			_cancelling = false  # A server before 867 amended (1) said "discarded" at once and went on.
			state = "proposal"
			_proposal = data
			if _test_answer_exit > 0.0:
				_test_exit_in(_test_answer_exit, "its answer")
				_test_answer_exit = 0.0
			var given: Array = data.get("area", [])
			if given.size() == 4:
				area = Rect2i(int(given[0]), int(given[1]), int(given[2]), int(given[3]))
			_show_area()
			var made: Dictionary = data.get("new_area", {})
			var beyond := "" if made.is_empty() else "A new level, %s (%d x %d), beyond the %s edge (outlined in orange)." % [
				made.get("name", ""), int(made.get("size", [0, 0])[0]), int(made.get("size", [0, 0])[1]), made.get("side", "")]
			# The answer is the panel's (885); the status line stands aside.
			_status_plate.visible = false
			panel.show_answer(data, beyond)
			if _test_unfold:
				panel.unfold_all()
				panel.set_full(true)  # A shot's "*": the answer whole, every fold open.
			print("[builder] proposal ($%.3f): %s" % [float(data.get("cost", 0.0)), str(data.get("summary", "")).get_slice("\n", 0)])
			# 885 amended (1): cut down while he reads the ghost, in the home chosen at the ask (a window
			# opened at the right still sends it left); the box has no keys till Tab or a click opens it whole.
			_place_panel(panel.home if panel.visible else "")
			panel.visible = true
			if not panel.full:
				_box.release_focus()
			if _test_accept:
				_test_accept = false
				_send({"op": "accept"})
		"accepted":
			_reset()
			_say("Built. Drag out another area, Ctrl+Z takes it back, B leaves.")
		"discarded":
			if _cancelling:
				# 867 amended (1): the Esc pressed while it worked, done; as a proposal's discard reads.
				_cancelling = false
				_proposal = {}
				state = "asking"
				_show_area()
				_open_box()
				_say("Discarded. Ask again, or drag out another area.")
		"undone":
			_say("Taken back.")
		"nothing":
			_say("Nothing to do.")
		"error":
			_cancelling = false
			state = "proposal" if not _proposal.is_empty() else ("asking" if area.size != Vector2i.ZERO else "idle")
			_say("Builder: %s" % data.get("error", "something went wrong"))
			if panel.visible and _proposal.is_empty():
				panel.working("Builder: %s" % data.get("error", "something went wrong"))


## --test-builder waits for this before it asks (Main calls it each world tick): the 3D view's
## camera following [param player] (Client3D.camera_on) for VIEW_STILL_TICKS ticks running, or
## VIEW_WAIT_TICKS gone, so the pane's home is picked from the view he would drag in. The joined
## stills of 885 amended (1) asked at tick 20 while the camera still sat at the level's middle
## (stills5); his place on the screen, still and near its middle, read the same parked camera as
## settled (stills6) and then, counted in frames from a tick-paced caller, never let the ask go
## (stills7). Without a 3D view, at once. The cap is 30 s: a 4K start under its arrival card took the
## camera longer than the first cap's 10 s to reach him (stills8). Which let the ask go, said once.
## The camera stands still too (Client3D.camera_pose: its eye, its look, its ortho size and fov), within
## EYE_STILL of where it stood as the run began (camera_moved), the whole run: at stills9's ask the target was
## on him while the zoom still eased in, so the whole area read on the screen and then sat off it once the
## camera came close; stills10's bodies read from the same zoom (the eye stood still while the ortho size
## eased); stills11's from an ease's tail creeping under EYE_STILL a tick (the roofs' pull eases out at 1.2 a
## second), so the run is measured from its start, 2 s of ticks, not tick to tick.
func view_settled(player: Player) -> bool:
	if main._client3d == null or player == null:
		return true
	var settled := settle_step(main._client3d.camera_on(player), main._client3d.camera_pose())
	if settled:
		print("[builder] --test-builder asks at view tick %d: %s" % [_view_ticks,
			"the camera on him %d ticks" % _view_still if _view_still >= VIEW_STILL_TICKS else "the cap, the camera not on him"])
	return settled


## One tick's look for view_settled: [param on_him], whether the camera follows him this tick, and
## [param pose], Client3D.camera_pose's (empty: no view, still). The run goes on while he is followed and
## the camera within EYE_STILL of the pose it began at; else it starts again from this tick.
func settle_step(on_him: bool, pose: Array = []) -> bool:
	_view_ticks += 1
	var holds := on_him and _view_still > 0 and (pose.is_empty() or camera_moved(_pose_anchor, pose) < EYE_STILL)
	if holds:
		_view_still += 1
	elif on_him:
		_view_still = 1
		_pose_anchor = pose
	else:
		_view_still = 0
		_pose_anchor = []
	return _view_still >= VIEW_STILL_TICKS or _view_ticks >= VIEW_WAIT_TICKS


const VIEW_STILL_TICKS := 24
const VIEW_WAIT_TICKS := 360
const EYE_STILL := 0.02
var _pose_anchor: Array = []


## How far the camera moved between [param was] and [param now] (Client3D.camera_pose's): its eye in
## metres, its look's turn, its ortho size's change and its fov's in hundredths of a degree, summed;
## INF when either is missing.
static func camera_moved(was: Array, now: Array) -> float:
	if was.size() != 4 or now.size() != 4:
		return INF
	return (was[0] as Vector3).distance_to(now[0]) + (was[1] as Vector3).distance_to(now[1]) 			+ absf(float(was[2]) - float(now[2])) + absf(float(was[3]) - float(now[3])) * 0.01
var _view_ticks := 0
var _view_still := 0


## --test-builder: "x,y,w,h:request" asked as if dragged out and typed; a
## request starting "+" accepted when it comes, "*" shown unfolded.
func test_ask(spec: String) -> void:
	var parts := spec.split(":", true, 1)
	var numbers := parts[0].split(",")
	if parts.size() < 2 or numbers.size() != 4:
		push_warning("[builder] --test-builder=%s: x,y,w,h:request" % spec)
		return
	active = true
	var request := parts[1]
	_test_unfold = request.begins_with("*")
	request = request.trim_prefix("*")
	_test_accept = request.begins_with("+")
	_set_area(Rect2i(numbers[0].to_int(), numbers[1].to_int(), numbers[2].to_int(), numbers[3].to_int()))
	_open_box(true)
	_submitted(request.trim_prefix("+"))
	_test_answer_exit = Net.test_exit_after_answer
	_test_exit_in(Net.test_exit_after_ask, "its ask")


## --test-exit-after-ask / --test-exit-after-answer: the quit (and its --screenshot) [param seconds] after
## [param what], so a joined still is taken at a moment of the builder's, not of the start; 0, none.
func _test_exit_in(seconds: float, what: String) -> void:
	if seconds <= 0.0 or main == null or not main.has_method("_on_test_exit"):
		return
	print("[builder] --test-builder quits %.1f s after %s" % [seconds, what])
	get_tree().create_timer(seconds).timeout.connect(main._on_test_exit)


## Set by test_ask, armed once by the answer that comes after it.
var _test_answer_exit := 0.0


func _say(text: String) -> void:
	_status.text = text
	_status_plate.visible = true
	var wide := _status_plate.get_combined_minimum_size().x  # Hugging the words, about the top centre.
	_status_plate.offset_left = -wide / 2.0
	_status_plate.offset_right = wide / 2.0
	print("[builder] " + text.get_slice("\n", 0))
