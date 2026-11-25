extends RefCounted
## axecarry (TASK 16, 451 amended (13)): the strip for a person running with a reached two-hander. After: Axe_Carry on the
## arms in Jog_Short and Sprint_Short (Client3D._carry_two). Before: the same run with "carry_two" taken out of the player's
## puppet's moves, main's arms (the key is absent on main; nothing else differs). Out of doors in the wilds at (210, 211),
## Jeff's goblin (the held imp, laid by the console's foes) beside the place, the low camera at its nearest zoom (zoom_min) on
## the player standing in the place, pan zero, never a panned lens. Run it with a window for the stills:
##   TOUR_SERVER_ARGS="--test-hp --no-companions --test-foe=imp,,1,held" sh tools/tour.sh axecarry --offscreen
## Rows: the man with the battle axe, the giant axe and the tomb sledge; the woman with the battle axe, the giant axe and the
## pick (seed 11, middling; the look set by a reconnect, the settings pointed at the run's own folder). Each weapon: a still
## standing beside the goblin, then a run west from (210, 211), before and after, at the jog (both rows), then a stamina potion
## (speed +0.25) drunk by a right click on its pack square, and the same runs at the sprint. Each run: four stills side on a
## stride's quarter apart and two from the front quarter; the giant axe's runs also a clip, one frame each 40 ms cropped round
## the runner (clip_<run>/NNN.png). Each run's frames.txt logs every frame: time, base clip, carry clip and amount, the
## upper layer's state (bow_state), the cell. The moves are the bot's click on the cell (bot.click); the pack's key and squares
## are input events (Input.parse_input_event) at the square's own point. Headless it stops at once: no Client3D, no bodies.

const TAG := "AXECARRY"
const HOME := Vector2i(210, 211)
const RUN_TO := Vector2i(194, 211)
const CLIP_WEAPON := "giant_axe"
const SIDE_AT: Array[float] = [0.8, 0.95, 1.1, 1.25]  # s after the first click: side on
const FRONT_AT: Array[float] = [1.75, 1.95]  # from the front quarter
const CLIP_FROM := 0.5
const CLIP_TO := 2.9
const ROWS: Array[Array] = [
	["man", &"male", "seed=11 build=middling hair=cropped hair_colour=brown beard=none", ["battle_axe", "giant_axe", "tomb_sledge"]],
	["woman", &"female", "seed=11 build=middling hair=bound hair_colour=brown", ["battle_axe", "giant_axe", "pick"]],
]


func _view(bot: Node) -> Node:
	return bot.main.get("_client3d")


func _cam(bot: Node) -> Camera3D:
	return _view(bot).get("_camera") as Camera3D


func _pup(bot: Node, e: GridEntity) -> Node3D:
	if _view(bot) == null:
		return null
	var puppets: Dictionary = _view(bot).get("_puppets")
	return puppets.get(e.get_instance_id()) if e != null and is_instance_valid(e) else null


func _rig(bot: Node) -> AnimRig:
	var pup := _pup(bot, bot.me())
	return pup.get_meta("rig") as AnimRig if pup != null and pup.has_meta("rig") else null


func _near(bot: Node) -> void:
	Net.set_camera_low(true, false)
	var view := _view(bot)
	view.set("pan", Vector3.ZERO)
	var z := float(view.call("zoom_min"))
	view.set("_zoom_to", z)
	view.set("zoom", z)
	view.call("_apply_size")


func _yaw(bot: Node, yaw: float) -> void:
	var view := _view(bot)
	for key: String in ["yaw", "_yaw_step", "_ease_from", "_ease_to", "_hand_yaw"]:
		view.set(key, yaw)
	view.set("_ease_t", 1.0)


## The yaw whose lens looks along [param look] (world x, z): yaw 45 looks along (-1, 0), 135 along (0, 1), 315 along (0, -1).
func _yaw_for(look: Vector2) -> float:
	return fposmod(45.0 + rad_to_deg(atan2(look.y, -look.x)), 360.0)


func _hands(bot: Node) -> String:
	var slots: Array = bot.me().get("slots")
	return "right '%s', left '%s'" % [str(slots[Items.RIGHT_HAND]), str(slots[Items.LEFT_HAND])]


func _state(bot: Node) -> String:
	var pup := _pup(bot, bot.me())
	var rig := _rig(bot)
	if rig == null:
		return "no rig"
	return "%s carry '%s' %.2f bow_state '%s' at %s" % [rig.base_clip(), rig.carry_clip(), rig.carry_amount(), str(pup.get_meta("bow_state", "")), bot.cell()]


func _grab(bot: Node) -> Image:
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	return bot.get_viewport().get_texture().get_image()


func _save(bot: Node, img: Image, name: String) -> bool:
	var path := (bot.own_dir() as String).path_join(name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img != null and not img.is_empty() and img.save_png(path) == OK


func _key(bot: Node, keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await bot.frames(2)


func _pack_open(bot: Node, open: bool) -> bool:
	var panel: Node = bot.main.get("pack_panel")
	if panel == null:
		return false
	if bool(panel.get("shown")) != open:
		await _key(bot, KEY_I)
		await bot.until(func() -> bool: return bool(panel.get("shown")) == open, 3.0)
	await bot.frames(3)
	return bool(panel.get("shown")) == open


## The local player's own square [param index] in the pack window, shown, or null.
func _box(bot: Node, index: int) -> Control:
	var panel: Node = bot.main.get("pack_panel")
	for n: Node in panel.find_children("*", "", true, false):
		if n is Control and n.get("panel") == panel and n.get("mine") == true and n.get("index") == index and (n as Control).is_visible_in_tree():
			return n as Control
	return null


## A press (a double one when [param double]) at square [param index]'s centre, as input events in the window's coordinates.
func _press_box(bot: Node, index: int, button: MouseButton, double: bool) -> bool:
	var box := _box(bot, index)
	if box == null:
		return false
	var at: Vector2 = bot.get_viewport().get_final_transform() * (box.get_global_transform_with_canvas() * (box.size / 2.0))
	for k in (2 if double else 1):
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = pressed
			event.double_click = double and k == 1 and pressed
			event.position = at
			event.global_position = at
			Input.parse_input_event(event)
			await bot.frames(1)
	await bot.frames(3)
	return true


## Both hands put away (a double-click on each hand's square), then [param id] given by the console: the hands free, it goes
## to the right hand (World.room_for).
func _hold(bot: Node, id: String) -> bool:
	await _pack_open(bot, true)
	for hand: int in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		if str(bot.me().get("slots")[hand]) == "":
			continue
		var pressed := await _press_box(bot, hand, MOUSE_BUTTON_LEFT, true)
		var gone: bool = await bot.until(func() -> bool: return str(bot.me().get("slots")[hand]) == "", 3.0)
		if not gone:
			bot.log_line("%s hand %d: the double-click %s; put away by the equip command (not a press)" % [TAG, hand, "missed" if pressed else "found no square"])
			World.command(bot.me(), "equip", {"slot": hand})
			await bot.until(func() -> bool: return str(bot.me().get("slots")[hand]) == "", 3.0)
	await _pack_open(bot, false)
	bot.log_line("%s give %s: %s" % [TAG, id, str(await bot.admin("give Tourbot %s" % id)).strip_edges()])
	var ok: bool = await bot.until(func() -> bool: return str(bot.me().get("slots")[Items.RIGHT_HAND]) == id, 4.0)
	bot.expect(ok, "%s in the right hand" % id, _hands(bot))
	return ok


func _pack_slot(bot: Node, id: String) -> int:
	var slots: Array = bot.me().get("slots")
	for s: int in World.pack_slots(bot.me()):
		if s < slots.size() and str(slots[s]) == id:
			return s
	return -1


## A stamina potion given and drunk by a right click on its pack square (the pack's own use).
func _drink(bot: Node) -> void:
	bot.log_line("%s give potion: %s" % [TAG, str(await bot.admin("give Tourbot stamina_potion")).strip_edges()])
	await bot.until(func() -> bool: return _pack_slot(bot, "stamina_potion") >= 0, 4.0)
	var slot := _pack_slot(bot, "stamina_potion")
	await _pack_open(bot, true)
	var pressed := await _press_box(bot, slot, MOUSE_BUTTON_RIGHT, false)
	var drunk: bool = await bot.until(func() -> bool: return _pack_slot(bot, "stamina_potion") < 0, 4.0)
	if not drunk:
		bot.log_line("%s potion: the right click %s; drunk by the use command (not a press)" % [TAG, "missed" if pressed else "found no square"])
		World.command(bot.me(), "use", {"slot": slot})
		drunk = await bot.until(func() -> bool: return _pack_slot(bot, "stamina_potion") < 0, 4.0)
	await _pack_open(bot, false)
	bot.expect(drunk, "the stamina potion drunk", "buffs %s" % str(bot.me().get("buffs")))


func _join(bot: Node, row: Array) -> bool:
	Net.set("_settings_override", (bot.own_dir() as String).path_join("settings_tour.cfg"))
	Net.player_body = row[1]
	Net.player_look = Net.tidy_look(str(row[2]))
	var authed: int = bot.server_lines("authenticated as Tourbot").size()
	Net.reconnect()
	await bot.until(func() -> bool: return bot.server_lines("authenticated as Tourbot").size() > authed, 20.0)
	await bot.seconds(2.0)
	var ok: bool = await bot.until(func() -> bool: return bot.me() != null and _pup(bot, bot.me()) != null, 30.0)
	await bot.seconds(2.0)
	bot.expect(ok and bot.me().get("body") == row[1], "joined as the %s" % row[0], "body %s" % (bot.me().get("body") if bot.me() != null else "nobody"))
	return ok


func _home(bot: Node) -> void:
	await bot.admin("hp Tourbot 100")
	await bot.admin("move Tourbot %d %d wilds" % [HOME.x, HOME.y])
	await bot.until(func() -> bool: return bot.cell() == HOME, 15.0)
	await bot.seconds(1.5)
	var pup := _pup(bot, bot.me())
	await bot.until(func() -> bool: return pup != null and str(pup.get_meta("bow_state", "")) != "ready", 16.0)
	await bot.seconds(0.5)


func _goblin(bot: Node) -> GridEntity:
	for x: GridEntity in World.get_entities():
		if x is Monster and is_instance_valid(x) and World.distance(x.tile, bot.cell()) <= 8:
			return x
	return null


## After (true): the puppet's moves as built, "carry_two" in. Before (false): the key taken out and the carry let go at once.
func _mode(bot: Node, carry: bool) -> void:
	var pup := _pup(bot, bot.me())
	var moves: Dictionary = (pup.get_meta("moves", {}) as Dictionary).duplicate()
	if carry:
		moves["carry_two"] = Client3D.HUMANOID_MOVES["carry_two"]
	else:
		moves.erase("carry_two")
		_rig(bot).carry("", 0.0)
	pup.set_meta("moves", moves)


func _stand(bot: Node, row: Array, weapon: String) -> void:
	await _home(bot)
	_mode(bot, true)
	_near(bot)
	_yaw(bot, _yaw_for(Vector2(0, -1)))
	await bot.seconds(1.0)
	var gob := _goblin(bot)
	var name := "%s_%s_stand" % [row[0], weapon]
	var ok := _save(bot, await _grab(bot), name)
	bot.log_line("%s still %s %s: standing beside the goblin (%s), %s, zoom %.2f" % [TAG, name, "saved" if ok else "FAILED",
		gob.tile if gob != null else "not found", _state(bot), float(_view(bot).get("zoom"))])


## One run west from HOME, before or after: stills side on and from the front quarter, the clip for CLIP_WEAPON, every frame logged.
func _run(bot: Node, row: Array, weapon: String, gait: String, carry: bool) -> void:
	await _home(bot)
	_mode(bot, carry)
	_near(bot)
	var name := "%s_%s_%s_%s" % [row[0], weapon, gait, "after" if carry else "before"]
	var dir := Vector2i(signi(RUN_TO.x - HOME.x), signi(RUN_TO.y - HOME.y))
	var side := _yaw_for(Vector2(-dir.y, dir.x))
	var front := _yaw_for(Vector2(-dir.x - dir.y, dir.x - dir.y).normalized())
	_yaw(bot, side)
	await bot.frames(3)
	var rig := _rig(bot)
	var pup := _pup(bot, bot.me())
	var lines: PackedStringArray = []
	var clip: Array[Image] = []
	var bases := {}
	var most := 0.0
	var least := 1.0
	var taken := 0
	var last_click := -1000
	var last_grab := -1000
	var t0 := Time.get_ticks_msec()
	var clips := weapon == CLIP_WEAPON
	while bot.cell() != RUN_TO and Time.get_ticks_msec() - t0 < 8000:
		var ms := Time.get_ticks_msec() - t0
		if ms - last_click >= 300:
			last_click = ms
			for k in range(6, 1, -1):
				var to: Vector2i = bot.cell() + dir * k
				if (to.x - RUN_TO.x) * dir.x > 0:
					to = RUN_TO
				if not is_nan((bot.screen_point(to) as Vector2).x):
					await bot.click(to)
					break
		var s := ms / 1000.0
		if taken < SIDE_AT.size() + FRONT_AT.size():
			var when: float = SIDE_AT[taken] if taken < SIDE_AT.size() else FRONT_AT[taken - SIDE_AT.size()]
			if s >= when:
				var still := "%s_%s%d" % [name, "side" if taken < SIDE_AT.size() else "front", taken + 1 if taken < SIDE_AT.size() else taken - SIDE_AT.size() + 1]
				if taken == SIDE_AT.size():
					_yaw(bot, front)
					await bot.frames(2)
				var ok := _save(bot, await _grab(bot), still)
				bot.log_line("%s still %s %s: %.2f s, %s" % [TAG, still, "saved" if ok else "FAILED", (Time.get_ticks_msec() - t0) / 1000.0, _state(bot)])
				taken += 1
		if clips and s >= CLIP_FROM and s <= CLIP_TO and ms - last_grab >= 40:
			last_grab = ms
			await RenderingServer.frame_post_draw
			var img := bot.get_viewport().get_texture().get_image()
			var vp := Vector2(img.get_size())
			var p := _cam(bot).unproject_position(pup.global_position + Vector3.UP * 0.9)
			var w := int(vp.y * 0.55)
			var h := int(vp.y * 0.8)
			var rect := Rect2i(int(p.x) - w / 2, int(p.y) - int(h * 0.55), w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			clip.append(img.get_region(rect))
		else:
			await bot.get_tree().process_frame
		bases[rig.base_clip()] = true
		if rig.base_clip() in ["Jog_Short", "Sprint_Short"]:
			most = maxf(most, rig.carry_amount())
			least = minf(least, rig.carry_amount())
		lines.append("%.3f %s" % [(Time.get_ticks_msec() - t0) / 1000.0, _state(bot)])
	var file := FileAccess.open((bot.own_dir() as String).path_join(name + "_frames.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for i in clip.size():
		_save(bot, clip[i], "clip_%s/%03d" % [name, i])
		if i % 4 == 3:
			await bot.frames(1)
	var ran := "Sprint_Short" if gait == "sprint" else "Jog_Short"
	bot.log_line("%s run %s: %.1f s to %s; clips %s; carry while running %.2f..%.2f; %d stills, %d clip frames" % [TAG, name,
		(Time.get_ticks_msec() - t0) / 1000.0, bot.cell(), ",".join(bases.keys()), least if most > 0.0 or least < 1.0 else 0.0, most, taken, clip.size()])
	bot.expect(ran in bases, "%s ran in %s" % [name, ran], ",".join(bases.keys()))
	if carry:
		bot.expect(most > 0.9, "%s: the carry on while running" % name, "most %.2f" % most)
	else:
		bot.expect(most == 0.0, "%s: no carry (main's arms)" % name, "most %.2f" % most)


func run(bot: Node) -> void:
	if not bot.expect(_view(bot) != null, "a 3D view (the tour needs tour.sh's --offscreen window: headless has no Client3D)"):
		return
	await bot.until(func() -> bool: return bot.me() != null and _pup(bot, bot.me()) != null, 40.0)
	if not bot.expect(bot.me() != null, "joined"):
		return
	if not bot.expect(Client3D.HUMANOID_MOVES.has("carry_two"), "this build has the carry (HUMANOID_MOVES' carry_two)"):
		return
	await bot.admin("day_minutes 100000")
	bot.log_line("%s console: %s" % [TAG, str(await bot.admin("hour 11")).strip_edges()])
	var joined := ""
	var order: Array[Array] = ROWS.duplicate()
	for gait: String in ["jog", "sprint"]:
		for row: Array in order:
			if joined != row[0]:
				if not await _join(bot, row):
					return
				joined = row[0]
			if _goblin(bot) == null:
				await _home(bot)
				bot.log_line("%s goblin laid: %s" % [TAG, str(await bot.admin("foes Tourbot")).strip_edges().left(80)])
				await bot.seconds(1.0)
			var buffs: Dictionary = bot.me().get("buffs")
			if gait == "sprint" and not buffs.has("speed"):
				await _drink(bot)
			bot.log_line("%s %s %s: buffs %s" % [TAG, row[0], gait, str(bot.me().get("buffs"))])
			for weapon: String in row[3]:
				if not await _hold(bot, weapon):
					continue
				if gait == "jog":
					await _stand(bot, row, weapon)
				for carry: bool in [false, true]:
					await _run(bot, row, weapon, gait, carry)
		order.reverse()
	bot.log_line("%s done: server script errors %d" % [TAG, bot.server_lines("SCRIPT ERROR").size()])
