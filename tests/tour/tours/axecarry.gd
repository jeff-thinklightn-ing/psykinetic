extends RefCounted
## axecarry (TASK 16, 451 amended (13)): the strip for a person running with a reached two-hander. After: Axe_Carry on the
## arms in Jog_Short and Sprint_Short (Client3D._carry_two). Before: the same run with "carry_two" taken out of the player's
## puppet's moves, main's arms (the key is absent on main; nothing else differs). Out of doors in the wilds at (210, 211),
## Jeff's goblin (the held imp, laid by the console's foes) beside the place, the low camera at its nearest zoom (zoom_min) on
## the player standing in the place, pan zero, never a panned lens. Run it with a window for the stills:
##   TOUR_SERVER_ARGS="--test-hp --no-companions --test-foe=imp,,1,held" sh tools/tour.sh axecarry --offscreen
## Rows: the man with the battle axe, the giant axe and the tomb sledge; the woman with the battle axe, the giant axe and the
## pick (seed 11, middling; the look set by a reconnect, the settings pointed at the run's own folder). Each weapon: a still
## standing beside the goblin, the goblin struck down (the console's strike: at 1d3acca3f it came on and struck the plain
## runs), then a run west from RUN_FROM (205, 211) to (196, 211), before and after. First the walk, as a player walks (each
## row with WALK_RUNS, the battle axe and the giant axe; the player slowed to the walk's pace by the console's quick at
## Main.QUICK_LEAST, test-only, logged), each also a clip from standing to standing, its start and its stop
## (clip_<run>/times.txt gives each frame's time, the first step's and the stop's); then the jog (both rows; a plain
## jog's steady pace expected within PLAIN_PACE), then
## the same runs at the sprint, the speed admin-set before each by the console's quick (test-only, QUICK_SHARE: a stamina potion's
## +0.25 stays under the man's sprint change) and Sprint_Short checked. Before each run the camera's distance settles and is
## logged, and an after's is checked against its before's. Each run: four stills side on a stride's quarter apart, two from
## the other side and two from the front quarter, each with an enlarged crop of the chest and arms (<still>_crop, 3x), (kept
## in memory and saved after the run: saved mid-run they
## stalled the frames, and the body, about a second a cell at 1d3acca3f); the giant axe's runs also a clip, one frame each 40 ms cropped round
## the runner (clip_<run>/NNN.png), from 0.4 s standing to 1.2 s after the stop. The rot hammer is run on the man at the jog only (all five shot). The man's rot
## hammer and giant axe also run once more at the jog, before and after, as one side-on clip of the whole run from
## standing: the start, the jog at the goblin (a click on it from RUN_FROM) and the blow on arrival, 2.4 s after it
## (<row>_<weapon>_jog_swing_<before|after>, SWING_RUNS). Last, the giant axe at
## the sprint in the most a player wears round the legs (ARMOURED: plate, its cuisses on the thighs, on the heavy man; robes
## to the shins on the heavy woman), the armour put on by a double-click on its pack square. Each run's frames.txt starts
## with a "#" line naming the hands and what is worn (the armour slot, the body, the look), then logs every frame: time,
## base clip, carry clip and amount, the upper layer's state (bow_state), the cell. The moves are the bot's click on the cell (bot.click); the pack's key and squares
## are input events (Input.parse_input_event) at the square's own point. Headless it stops at once: no Client3D, no bodies.

const TAG := "AXECARRY"
const HOME := Vector2i(210, 211)
## The runs go from RUN_FROM to RUN_TO, six cells and more west of the held goblin (at a426bca29 they started at HOME,
## beside it, and it struck the runner as it passed: Hit_ clips mid-run). (194, 211) took no step (every run stood
## beside it at (195, 211) and waited out its time), so the run ends at (196, 211), and its stop is read from the body
## standing (the base clip Idle), not from the cell.
const RUN_FROM := Vector2i(205, 211)
const RUN_TO := Vector2i(196, 211)
const CLIP_WEAPON := "giant_axe"
const SIDE_AT: Array[float] = [0.8, 0.95, 1.1, 1.25]  # s after the first click: side on, the runner's left
const OTHER_AT: Array[float] = [1.4, 1.55]  # side on from the other side, the runner's right
const FRONT_AT: Array[float] = [1.75, 1.95]  # from the front quarter
## The sprint's speed: the console's quick (test-only), a share on the body's speed. A stamina potion's +0.25 makes a plain
## 4.0 tiles a second 5.0, under the man's sprint change (5.13): at 1d3acca3f no run reached Sprint_Short.
const QUICK_SHARE := 0.6
const QUICK_SECONDS := 60
## The walk (the coordinator's 11-25 (1): the carry is on at the walk too, and no look had shown it): nothing in the game
## slows a player to the walk's own pace for long (a winded, loaded body still jogs), so the console's quick slows it,
## Main.QUICK_LEAST (-0.75: a plain 4.0 tiles a second one, the walk's own pace 0.94), admin-set and logged, then off.
## The man and the woman, these weapons, before and after, each a clip from standing to standing: the first step (the
## ready gone and the carry on in one frame) and the stop (the carry held, eased out, the ready eased in).
const WALK_RUNS: Array[String] = ["battle_axe", "giant_axe"]
const WALK_CLIP_START := 1.6  # s after the first click the walk's clip runs to; then again from the cell before RUN_TO
## A plain jog's steady pace (tiles a second, from the second cell to the seventh), expected: the coordinator's 11-25
## (6), a run read about 2 at 1d3acca3f, put down to the stills saved mid-run; this run settles it.
const PLAIN_PACE: Array[float] = [3.6, 4.4]
## The swing runs (the coordinator's (2)): at the jog, before and after, one clip from standing to standing. A swing
## "where you stand" (Shift and a click) is not a player's mid-run: a free body's walk drops a swing order at once
## (World._free_drop_order, any intent of WIND_UP_LEAVE_INTENT; at a426bca29 the Shift click came 1.4 s in and never
## struck), so the swing out of a run is the one a player makes: a click on the goblin from RUN_FROM, the jog at it and
## the blow on arrival.
const SWING_RUNS := {"man": ["rot_hammer", "giant_axe"]}
const SWING_LEAD := 0.4  # s of standing clipped before the first click
const SWING_TAIL := 1.2  # s clipped after the stop (a swing run: after its first blow, SWING_TAIL twice)
## [name, body, look, weapons at the jog and the sprint, weapons at the jog only]
const ROWS: Array[Array] = [
	["man", &"male", "seed=11 build=middling hair=cropped hair_colour=brown beard=none", ["battle_axe", "giant_axe", "tomb_sledge"], ["rot_hammer"]],
	["woman", &"female", "seed=11 build=middling hair=bound hair_colour=brown", ["battle_axe", "giant_axe", "pick"], []],
]
## Last, the sprint with the giant axe in the most a player wears round the legs (the coordinator's (1b)): there is no leg
## armour; plate's cuisses cover the thighs (body_gen's plate_armour), on the heavy man; robes flare past the knees to the
## shins (the nearest a player wears to a long hem: a woman's hem is her tunic's, the body's own), on the heavy woman.
## [name, body, look, armour]
const ARMOURED: Array[Array] = [
	["man_heavy_plate", &"male", "seed=11 build=heavy hair=cropped hair_colour=brown beard=none", "plate_armour"],
	["woman_heavy_robes", &"female", "seed=11 build=heavy hair=bound hair_colour=brown", "robes"],
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
	return "%s carry '%s' %.2f upper '%s'%s bow_state '%s' cam %.2f m at %s" % [rig.base_clip(), rig.carry_clip(), rig.carry_amount(), rig.upper_clip(),
		" striking" if rig.striking() else "", str(pup.get_meta("bow_state", "")), _cam(bot).global_position.distance_to(pup.global_position), bot.cell()]


## The camera's distance from the runner, once it has held within 2 cm for 0.5 s (the eye's pull-in near a roofed box eases out
## only after a hold, 864: at 1d3acca3f the rot hammer's after clip began closer than its before), at most 6 s; logged.
func _settle(bot: Node, name: String) -> float:
	var t0 := Time.get_ticks_msec()
	var last := -1.0
	var since := t0
	while Time.get_ticks_msec() - t0 < 6000:
		await bot.get_tree().process_frame
		var d := _cam(bot).global_position.distance_to(_pup(bot, bot.me()).global_position)
		if absf(d - last) > 0.02:
			last = d
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since >= 500:
			break
	bot.log_line("%s %s: camera %.2f m from the runner, settled in %.1f s" % [TAG, name, last, (Time.get_ticks_msec() - t0) / 1000.0])
	return last


## The runner's chest and arms cut from [param img] (the window's pixels) round its projected chest, for the enlarged crop
## saved beside each full still as <still>_crop (both wrists readable).
func _crop_of(bot: Node, img: Image) -> Image:
	var size := Vector2(img.get_size())
	var cam := _cam(bot)
	var seen := cam.get_viewport().get_visible_rect().size
	var p := cam.unproject_position(_pup(bot, bot.me()).global_position + Vector3.UP * 1.2) * size / Vector2(maxf(seen.x, 1.0), maxf(seen.y, 1.0))
	var w := int(size.y * 0.4)
	var h := int(size.y * 0.4)
	var rect := Rect2i(int(p.x) - w / 2, int(p.y) - h / 2, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return img.get_region(rect) if rect.has_area() else null


func _save_crop(bot: Node, img: Image, name: String) -> bool:
	if img == null or img.is_empty():
		return false
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_LANCZOS)
	return _save(bot, img, name + "_crop")


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


## What the body wears: the armour slot and the look the body was joined with.
func _worn(bot: Node) -> String:
	var armour := str(bot.me().get("slots")[Items.ARMOUR])
	return "armour '%s', body %s, look '%s'" % [armour, str(bot.me().get("body")), Net.player_look]


## [param id] worn in the armour slot: what is there put away by a double-click on its square, [param id] given by the
## console, and put on by a double-click on its pack square if it went to the pack.
func _wear(bot: Node, id: String) -> bool:
	await _pack_open(bot, true)
	var now := str(bot.me().get("slots")[Items.ARMOUR])
	if now != "" and now != id:
		var pressed := await _press_box(bot, Items.ARMOUR, MOUSE_BUTTON_LEFT, true)
		if not await bot.until(func() -> bool: return str(bot.me().get("slots")[Items.ARMOUR]) == "", 3.0):
			bot.log_line("%s armour: the double-click %s; taken off by the equip command (not a press)" % [TAG, "missed" if pressed else "found no square"])
			World.command(bot.me(), "equip", {"slot": Items.ARMOUR})
			await bot.until(func() -> bool: return str(bot.me().get("slots")[Items.ARMOUR]) == "", 3.0)
	if str(bot.me().get("slots")[Items.ARMOUR]) != id:
		bot.log_line("%s give %s: %s" % [TAG, id, str(await bot.admin("give Tourbot %s" % id)).strip_edges()])
		if not await bot.until(func() -> bool: return str(bot.me().get("slots")[Items.ARMOUR]) == id, 3.0):
			await bot.until(func() -> bool: return _pack_slot(bot, id) >= 0, 3.0)
			var slot := _pack_slot(bot, id)
			var pressed := await _press_box(bot, slot, MOUSE_BUTTON_LEFT, true)
			if not await bot.until(func() -> bool: return str(bot.me().get("slots")[Items.ARMOUR]) == id, 3.0):
				bot.log_line("%s armour: the double-click %s; worn by the equip command (not a press)" % [TAG, "missed" if pressed else "found no square"])
				World.command(bot.me(), "equip", {"slot": slot})
				await bot.until(func() -> bool: return str(bot.me().get("slots")[Items.ARMOUR]) == id, 3.0)
	await _pack_open(bot, false)
	var ok := str(bot.me().get("slots")[Items.ARMOUR]) == id
	bot.expect(ok, "%s worn" % id, _worn(bot))
	await bot.seconds(1.0)
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


func _home(bot: Node, at := HOME) -> void:
	await bot.admin("hp Tourbot 100")
	await bot.admin("move Tourbot %d %d wilds" % [at.x, at.y])
	await bot.until(func() -> bool: return bot.cell() == at, 15.0)
	await bot.seconds(1.5)
	var pup := _pup(bot, bot.me())
	await bot.until(func() -> bool: return pup != null and str(pup.get_meta("bow_state", "")) != "ready", 16.0)
	await bot.seconds(0.5)


## The goblin laid beside HOME (the console's foes) when none is there. A held foe only waits for "foes"; once laid it
## sees the player and comes on (at 1d3acca3f it reached the plain runs 8 cells off: Hit_ clips), so it is laid for the
## stills beside it and the swing runs only.
func _lay(bot: Node) -> void:
	if _goblin(bot) != null:
		return
	await _home(bot)
	bot.log_line("%s goblin laid: %s" % [TAG, str(await bot.admin("foes Tourbot")).strip_edges().left(80)])
	await bot.seconds(1.0)


## Every foe within 30 cells of HOME struck down (the console's strike, test-only) before the plain runs.
func _clear(bot: Node) -> void:
	for i in 4:
		var any := false
		for x: GridEntity in World.get_entities():
			if x is Monster and is_instance_valid(x) and World.distance(x.tile, HOME) <= 30:
				any = true
		if not any:
			return
		var said := ""
		for called: String in ["imp", "the imp", "Foe"]:
			said = str(await bot.admin("strike Tourbot %s" % called)).strip_edges()
			if said.begins_with("strike: Tourbot struck"):
				break
		bot.log_line("%s goblin cleared for the runs: %s" % [TAG, said.left(80)])
		await bot.seconds(0.5)


func _goblin(_bot: Node, within := 8) -> GridEntity:
	for x: GridEntity in World.get_entities():
		if x is Monster and is_instance_valid(x) and World.distance(x.tile, HOME) <= within:
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
	await _settle(bot, name)
	var img := await _grab(bot)
	var ok := _save(bot, img, name) and _save_crop(bot, _crop_of(bot, img), name)
	bot.log_line("%s still %s %s: standing beside the goblin (%s), %s, zoom %.2f" % [TAG, name, "saved" if ok else "FAILED",
		gob.tile if gob != null else "not found", _state(bot), float(_view(bot).get("zoom"))])


## One frame of the clip: the view cropped round the runner. The camera projects into the viewport's visible rect (the
## project's 3840 x 2160, stretched to the window), the image is the window's own pixels (at a426bca29 a 1600 x 900 window
## put every crop off the image, width 0): the point is scaled from one to the other, and a crop that misses still keeps
## the image's middle (the camera follows the runner, pan zero) and says so once in the log.
var _crop_missed := false
func _clip_frame(bot: Node) -> Image:
	await RenderingServer.frame_post_draw
	var img := bot.get_viewport().get_texture().get_image()
	var size := Vector2(img.get_size())
	var cam := _cam(bot)
	var seen := cam.get_viewport().get_visible_rect().size
	var p := cam.unproject_position(_pup(bot, bot.me()).global_position + Vector3.UP * 0.9) * size / Vector2(maxf(seen.x, 1.0), maxf(seen.y, 1.0))
	var w := int(size.y * 0.55)
	var h := int(size.y * 0.8)
	var whole := Rect2i(Vector2i.ZERO, img.get_size())
	var rect := Rect2i(int(p.x) - w / 2, int(p.y) - int(h * 0.55), w, h).intersection(whole)
	if not rect.has_area():
		if not _crop_missed:
			_crop_missed = true
			bot.log_line("%s crop missed: point %s, image %s, visible rect %s; the image's middle kept" % [TAG, p, img.get_size(), seen])
		rect = Rect2i(int(size.x) / 2 - w / 2, int(size.y) / 2 - int(h * 0.55), w, h).intersection(whole)
	return img.get_region(rect)


## The runner's next click on the run, every 300 ms till it is at [param end]: the cell 6 to 2 ahead ([param end] at most)
## that has a point on the screen.
func _click_on(bot: Node, dir: Vector2i, end := RUN_TO) -> void:
	if bot.cell() == end:
		return
	for k in range(6, 1, -1):
		var to: Vector2i = bot.cell() + dir * k
		if (to.x - end.x) * dir.x >= 0:
			to = end
		if not is_nan((bot.screen_point(to) as Vector2).x):
			await bot.click(to)
			return


## The sprint's change for this body (Client3D.gait_for's: the people's sprint takes over above its change times
## GAIT_HYSTERESIS, at the puppet's pace), tiles a second.
func _sprint_from(bot: Node) -> float:
	var gaits: Array = Client3D.HUMAN_F_GAITS if bot.me().get("body") == &"female" else Client3D.HUMAN_GAITS
	return Client3D.gait_change(gaits, 2) * Client3D.GAIT_HYSTERESIS * float(_pup(bot, bot.me()).get_meta("pace", 1.0))


## A swing run at the jog, side on, before or after (the coordinator's (2)): from RUN_FROM, standing, a click on the held
## goblin, once (the bot's click on its cell: an attack, far off a walk to it; a click toward it each 300 ms while it is
## off the screen), the jog at it and
## the blow on arrival; one clip (each 40 ms) from SWING_LEAD s standing before the first click to SWING_TAIL s twice after
## the first blow.
func _swing_run(bot: Node, row: Array, weapon: String, carry: bool) -> void:
	await _lay(bot)
	await _home(bot, RUN_FROM)
	var gob := _goblin(bot)
	var name := "%s_%s_jog_swing_%s" % [row[0], weapon, "after" if carry else "before"]
	if not bot.expect(gob != null, "%s: the goblin within 8 cells of %s" % [name, HOME]):
		return
	_mode(bot, carry)
	_near(bot)
	var dir := Vector2i(signi(gob.tile.x - RUN_FROM.x), 0)
	_yaw(bot, _yaw_for(Vector2(-dir.y, dir.x)))
	await bot.frames(3)
	var camera := await _settle(bot, name)
	var rig := _rig(bot)
	var lines: PackedStringArray = []
	var clip: Array[Image] = []
	var bases := {}
	var struck := -1.0
	var last_click := -1000
	var last_grab := -1000
	var aimed := false
	var again := 0  # the second click's time, ms, when one was needed
	var from := gob.tile
	var t0 := Time.get_ticks_msec() + int(SWING_LEAD * 1000.0)  # the first click's time
	while Time.get_ticks_msec() - t0 < 9000:
		var ms := Time.get_ticks_msec() - t0
		var s := ms / 1000.0
		if struck >= 0.0 and s > struck + SWING_TAIL * 2.0:
			break
		if s >= 0.0 and not aimed and ms - last_click >= 300 and is_instance_valid(gob):
			# One click on the goblin, as a player's: at 1d3acca3f a click each 300 ms till the blow began the giant axe's
			# attack again each time, and it never struck. Off the screen at the nearest zoom: a click toward it first.
			last_click = ms
			if not is_nan((bot.screen_point(gob.tile) as Vector2).x):
				aimed = true
				await bot.click(gob.tile)
				bot.log_line("%s %s: clicked the goblin at %s from %s, %.2f s" % [TAG, name, gob.tile, bot.cell(), (Time.get_ticks_msec() - t0) / 1000.0])
			else:
				await _click_on(bot, dir, gob.tile - dir)
		elif aimed and again == 0 and struck < 0.0 and ms - last_click >= 2500 and rig.base_clip() == Client3D.CLIP_IDLE and is_instance_valid(gob):
			# Stood 2.5 s after the click with no blow: one click more, as a player's, and logged.
			again = ms
			last_click = ms
			await bot.click(gob.tile)
			bot.log_line("%s %s: no blow 2.5 s after the click, standing at %s: clicked the goblin at %s again, %.2f s" % [TAG, name, bot.cell(), gob.tile, s])
		if Time.get_ticks_msec() - t0 - last_grab >= 40:
			last_grab = Time.get_ticks_msec() - t0
			clip.append(await _clip_frame(bot))
		else:
			await bot.get_tree().process_frame
		bases[rig.base_clip()] = true
		if struck < 0.0 and rig.striking():
			struck = (Time.get_ticks_msec() - t0) / 1000.0
		lines.append("%.3f %s" % [(Time.get_ticks_msec() - t0) / 1000.0, _state(bot)])
	var file := FileAccess.open((bot.own_dir() as String).path_join(name + "_frames.txt"), FileAccess.WRITE)
	if file != null:
		file.store_line("# %s: %s; worn: %s; camera %.2f m from the runner at the start; the goblin at %s (then %s), clicked from %s; seconds after the first click (negative: standing before it), base clip, carry clip and amount, upper clip (striking), bow_state, cell; the first blow at %.2f s%s" % [
			name, _hands(bot), _worn(bot), camera, from, gob.tile if is_instance_valid(gob) else "gone", RUN_FROM, struck,
			"; clicked again at %.2f s" % (again / 1000.0) if again > 0 else ""])
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for i in clip.size():
		_save(bot, clip[i], "clip_%s/%03d" % [name, i])
		if i % 4 == 3:
			await bot.frames(1)
	bot.log_line("%s run %s: the first blow at %.2f s; clips %s; %d clip frames; camera %.2f m" % [TAG, name, struck, ",".join(bases.keys()), clip.size(), camera])
	_cameras[name] = camera
	bot.expect("Jog_Short" in bases, "%s ran in Jog_Short" % name, ",".join(bases.keys()))
	bot.expect(struck >= 0.0, "%s: the blow struck from the run" % name, "the upper layer never striking")
	if carry:
		var was := name.replace("_after", "_before")
		bot.expect(_cameras.has(was) and absf(float(_cameras[was]) - camera) <= 0.1, "%s: the camera as far as its before's" % name,
			"before %s m, after %.2f m" % [str(_cameras.get(was, "none")), camera])


## One run from RUN_FROM to RUN_TO, before or after: stills side on and from the front quarter, every frame logged, and for
## CLIP_WEAPON a clip (each 40 ms) of the whole run, from SWING_LEAD s standing before the first click to SWING_TAIL s after
## the stop: the start from standing and the stop from the jog (the coordinator's (2)). The stop is the base clip's Idle
## after the first step.
func _run(bot: Node, row: Array, weapon: String, gait: String, carry: bool) -> void:
	await _home(bot, RUN_FROM)
	_mode(bot, carry)
	_near(bot)
	var name := "%s_%s_%s_%s" % [row[0], weapon, gait, "after" if carry else "before"]
	var dir := Vector2i(signi(RUN_TO.x - RUN_FROM.x), signi(RUN_TO.y - RUN_FROM.y))
	var side := _yaw_for(Vector2(-dir.y, dir.x))
	var other := _yaw_for(Vector2(dir.y, -dir.x))
	var front := _yaw_for(Vector2(-dir.x - dir.y, dir.x - dir.y).normalized())
	_yaw(bot, side)
	await bot.frames(3)
	var camera := await _settle(bot, name)
	var all := SIDE_AT.size() + OTHER_AT.size() + FRONT_AT.size()
	var rig := _rig(bot)
	var lines: PackedStringArray = []
	var clip: Array[Image] = []
	var stills: Array[Array] = []  # [name, image, its crop, the state for its log line], saved after the run: a 1600 x 900 png saved
	# mid-run stalled the frames, and the free body with them (at 1d3acca3f about a second a cell from 0.7 to 2.6 s)
	var bases := {}
	var most := 0.0
	var least := 1.0
	var taken := 0
	var last_click := -1000
	var last_grab := -1000
	var clips := weapon == CLIP_WEAPON or gait == "walk"
	var clip_at: PackedStringArray = []  # each clip frame's time
	var moved := -1.0
	var at_two := -1.0  # the times the runner's cell is 2 and 7 cells on: the steady pace between
	var at_seven := -1.0
	var stopped := -1.0
	var start: Vector2i = bot.cell()
	var t0 := Time.get_ticks_msec() + (int(SWING_LEAD * 1000.0) if clips else 0)  # the first click's time
	while Time.get_ticks_msec() - t0 < (16000 if gait == "walk" else 8000):
		var ms := Time.get_ticks_msec() - t0
		var s := ms / 1000.0
		if stopped >= 0.0 and s > stopped + (SWING_TAIL if clips else 0.3) and taken >= all:
			break
		if s >= 0.0 and stopped < 0.0 and ms - last_click >= 300:
			last_click = ms
			await _click_on(bot, dir)
		if taken < all:
			var sides := SIDE_AT.size()
			var others := sides + OTHER_AT.size()
			var when: float = SIDE_AT[taken] if taken < sides else OTHER_AT[taken - sides] if taken < others else FRONT_AT[taken - others]
			if s >= when:
				var still := "%s_%s%d" % [name, "side" if taken < sides else "other" if taken < others else "front",
					taken + 1 if taken < sides else taken - sides + 1 if taken < others else taken - others + 1]
				if taken == sides or taken == others:
					_yaw(bot, other if taken == sides else front)
					await bot.frames(2)
				var img := await _grab(bot)
				stills.append([still, img, _crop_of(bot, img), "%.2f s, %s" % [(Time.get_ticks_msec() - t0) / 1000.0, _state(bot)]])
				taken += 1
				if taken == all:
					_yaw(bot, side)  # the clip goes on side on
		# The walk's clip: its start (to WALK_CLIP_START) and its end (from the cell before RUN_TO), not its 8 s between.
		var in_clip := gait != "walk" or s < WALK_CLIP_START or absi(bot.cell().x - RUN_TO.x) <= 1 or stopped >= 0.0
		if clips and in_clip and Time.get_ticks_msec() - t0 - last_grab >= 40 and (taken == 0 or taken >= all or taken < SIDE_AT.size()):
			last_grab = Time.get_ticks_msec() - t0
			clip_at.append("%03d %.3f" % [clip.size(), last_grab / 1000.0])
			clip.append(await _clip_frame(bot))
		else:
			await bot.get_tree().process_frame
		var now := (Time.get_ticks_msec() - t0) / 1000.0
		if moved < 0.0 and bot.cell() != start:
			moved = now
		if at_two < 0.0 and absi(bot.cell().x - start.x) >= 2:
			at_two = now
		if at_seven < 0.0 and absi(bot.cell().x - start.x) >= 7:
			at_seven = now
		if moved >= 0.0 and stopped < 0.0 and rig.base_clip() == Client3D.CLIP_IDLE:
			stopped = now
		bases[rig.base_clip()] = true
		if rig.base_clip() in [Client3D.CLIP_WALK, "Jog_Short", "Sprint_Short"] and moved >= 0.0 and stopped < 0.0:
			most = maxf(most, rig.carry_amount())
			least = minf(least, rig.carry_amount())
		lines.append("%.3f %s" % [now, _state(bot)])
	var cells := absi(bot.cell().x - start.x)
	var steady := 5.0 / maxf(at_seven - at_two, 0.001) if at_two >= 0.0 and at_seven > at_two else 0.0
	var pace := "%d cells %.2f s: %.2f tiles/s; steady (the 2nd cell to the 7th) %.2f tiles/s; the sprint takes over above %.2f" % [
		cells, stopped - moved, cells / maxf(stopped - moved, 0.001), steady, _sprint_from(bot)]
	var file := FileAccess.open((bot.own_dir() as String).path_join(name + "_frames.txt"), FileAccess.WRITE)
	if file != null:
		file.store_line("# %s: %s; worn: %s; buffs %s; camera %.2f m from the runner at the start; first step at %.2f s, the stop at %.2f s (%s); seconds after the first click%s, base clip, carry clip and amount, upper clip, bow_state, cell" % [
			name, _hands(bot), _worn(bot), str(bot.me().get("buffs")), camera, moved, stopped, pace, " (negative: standing before it)" if clips else ""])
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for still: Array in stills:
		var ok: bool = _save(bot, still[1], still[0]) and _save_crop(bot, still[2], still[0])
		bot.log_line("%s still %s %s (and %s_crop, 3x): %s" % [TAG, still[0], "saved" if ok else "FAILED", still[0], still[3]])
		await bot.frames(1)
	for i in clip.size():
		_save(bot, clip[i], "clip_%s/%03d" % [name, i])
		if i % 4 == 3:
			await bot.frames(1)
	if not clip_at.is_empty():
		var times := FileAccess.open((bot.own_dir() as String).path_join("clip_%s/times.txt" % name), FileAccess.WRITE)
		if times != null:
			times.store_string("# frame, seconds after the first click (frames.txt has every frame's state); first step %.2f s, the stop %.2f s" % [moved, stopped]
				+ "\n" + "\n".join(clip_at) + "\n")
			times.close()
	bot.log_line("%s run %s: %.1f s to %s, the stop at %.2f s; %s; clips %s; carry while running %.2f..%.2f; %d stills, %d clip frames; camera %.2f m" % [TAG, name,
		(Time.get_ticks_msec() - t0) / 1000.0, bot.cell(), stopped, pace, ",".join(bases.keys()), least if most > 0.0 or least < 1.0 else 0.0, most, taken, clip.size(), camera])
	_cameras[name] = camera
	if gait == "sprint":
		bot.expect("Sprint_Short" in bases, "%s: Sprint_Short reached (the console's quick, +%.2f)" % [name, QUICK_SHARE], pace)
	if carry:
		var was := name.replace("_after", "_before")
		bot.expect(_cameras.has(was) and absf(float(_cameras[was]) - camera) <= 0.1, "%s: the camera as far as its before's" % name,
			"before %s m, after %.2f m" % [str(_cameras.get(was, "none")), camera])
	if gait == "walk":
		bot.expect(Client3D.CLIP_WALK in bases and not "Jog_Short" in bases, "%s walked, never jogged (the console's quick, %+.2f)" % [name, Main.QUICK_LEAST],
			",".join(bases.keys()) + "; " + pace)
	else:
		bot.expect("Jog_Short" in bases, "%s ran in Jog_Short" % name, ",".join(bases.keys()))
	if gait == "jog":
		bot.expect(steady >= PLAIN_PACE[0] and steady <= PLAIN_PACE[1], "%s: a plain jog's steady pace %.1f to %.1f tiles a second" % [name, PLAIN_PACE[0], PLAIN_PACE[1]], pace)
	bot.expect(stopped >= 0.0, "%s: stood at the run's end" % name, "at %s" % bot.cell())
	if carry:
		bot.expect(most > 0.9, "%s: the carry on while moving" % name, "most %.2f" % most)
	else:
		bot.expect(most == 0.0, "%s: no carry (main's arms)" % name, "most %.2f" % most)


var _cameras := {}  # run name: the camera's settled distance (m), for its after's check


## Before each sprint run: the console's quick (test-only) sets the speed buff to QUICK_SHARE for QUICK_SECONDS, an
## admin-set speed and said so (a stamina potion's +0.25 stays under the man's sprint change); logged with the buffs the
## client then shows.
func _quick(bot: Node, row: Array) -> void:
	var said := str(await bot.admin("quick Tourbot %.2f %d" % [QUICK_SHARE, QUICK_SECONDS])).strip_edges()
	await bot.until(func() -> bool: return float((bot.me().get("buffs") as Dictionary).get("speed", [0.0])[0]) >= QUICK_SHARE - 0.001, 3.0)
	bot.log_line("%s %s sprint: the speed admin-set (console quick, test-only): %s; buffs %s" % [TAG, row[0], said, str(bot.me().get("buffs"))])


## Before the walk runs: the console's quick slows the player to the walk's pace (Main.QUICK_LEAST), admin-set and logged
## with the buffs the client then shows; after them, quick 0 takes it off.
func _slow(bot: Node, row: Array, on: bool) -> void:
	var said := str(await bot.admin("quick Tourbot %.2f %d" % [Main.QUICK_LEAST if on else 0.0, QUICK_SECONDS * 5])).strip_edges()
	await bot.until(func() -> bool: return (float((bot.me().get("buffs") as Dictionary).get("speed", [0.0])[0]) < 0.0) == on, 3.0)
	bot.log_line("%s %s walk: the speed admin-set %s (console quick, test-only): %s; buffs %s" % [TAG, row[0], "on" if on else "off", said, str(bot.me().get("buffs"))])


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
	for gait: String in ["walk", "jog", "sprint"]:
		for row: Array in order:
			if joined != row[0]:
				if not await _join(bot, row):
					return
				joined = row[0]
			if gait == "walk":
				for weapon: String in WALK_RUNS:
					if not await _hold(bot, weapon):
						continue
					await _clear(bot)
					await _slow(bot, row, true)
					for carry: bool in [false, true]:
						await _run(bot, row, weapon, gait, carry)
					await _slow(bot, row, false)
				continue
			for weapon: String in ((row[3] + row[4]) if gait == "jog" else row[3]):
				if not await _hold(bot, weapon):
					continue
				if gait == "jog":
					await _lay(bot)
					await _stand(bot, row, weapon)
				await _clear(bot)
				for carry: bool in [false, true]:
					if gait == "sprint":
						await _quick(bot, row)
					await _run(bot, row, weapon, gait, carry)
				if gait == "jog" and weapon in (SWING_RUNS.get(row[0], []) as Array):
					for carry: bool in [false, true]:
						await _swing_run(bot, row, weapon, carry)
		order.reverse()
	for row: Array in ARMOURED:
		if not await _join(bot, row):
			return
		if not await _wear(bot, str(row[3])) or not await _hold(bot, "giant_axe"):
			continue
		await _lay(bot)
		await _stand(bot, row, "giant_axe")
		await _clear(bot)
		for carry: bool in [false, true]:
			await _quick(bot, row)
			await _run(bot, row, "giant_axe", "sprint", carry)
	bot.log_line("%s done: server script errors %d" % [TAG, bot.server_lines("SCRIPT ERROR").size()])
