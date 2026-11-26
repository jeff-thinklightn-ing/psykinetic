extends RefCounted
## axecarry (TASK 16, 451 amended (13)): the strip for a person running with a reached two-hander. After: Axe_Carry on the
## arms in Jog_Short and Sprint_Short (Client3D._carry_two). Before: the same run with "carry_two" taken out of the player's
## puppet's moves, main's arms (the key is absent on main; nothing else differs). Out of doors in the wilds at (210, 211),
## Jeff's goblin (the held imp, laid by the console's foes) beside the place, the low camera at its nearest zoom (zoom_min) on
## the player standing in the place, pan zero, never a panned lens. Run it with a window for the stills:
##   TOUR_SERVER_ARGS="--test-hp --no-companions --test-foe=imp,,1,held" sh tools/tour.sh axecarry --offscreen
## A section alone (_sections), minutes: TOUR_ONLY=wrists (the giant axe's jog with its wrist stills), TOUR_ONLY=pace (two
## sprints, no still), TOUR_ONLY=wrists_pace both; on a laptop remote_shot.sh's --tour-only wrists (or pace, wrists_pace).
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
## (<row>_<weapon>_jog_swing_<before|after>, SWING_RUNS), each at a goblin laid fresh and held on its cell from its laying
## (the console's root, test-only), the same cell before and after. The speed (the walk's slowing, the sprint's quick) is
## set after each run's move (a move joins the player anew, without its buffs) and read at the first step. The giant
## axe's jog runs also render two stills at WRIST_SCALE (<still>_wrist). Last, the giant axe at
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
## The other side's stills wait, up to OTHER_WAIT s, for the body in view (Client3D._body_hidden, the client's own test
## of what stands between the camera and the chest): at 969f33fa7 the first stood behind the square's stall on most
## weapons, the runner a see-through silhouette. The front quarter's follow by as much.
const OTHER_WAIT := 0.8
## The wrists (the coordinator's 11-25 (2)): the giant axe at the jog, man and woman, before and after, one still side
## on (the runner's left) and one from the front quarter rendered again at WRIST_SCALE times the window's pixels from
## the same camera (its place, lens and zoom: a SubViewport on the same world), cut round the chest at its own pixels
## (<still>_wrist): the 3x crop is the window's pixels enlarged, a hand about 20 px in it.
const WRIST_SCALE := 4
const WRIST_CROP := 0.3  # the cut's side, a share of the render's height
## The cut, shrunk to the window's pixels, against the window's own pixels of the same rect: their mean difference, each
## channel 0..1, at most this (the same frame drawn twice; a wrong lens, ground and sky for the runner, is far over it).
const WRIST_SAME := 0.08
const ROOT_SECONDS := 120  # the laid goblin held on its cell (the console's root) this long
## The swing runs (the coordinator's (2)): at the jog, before and after, one clip from standing to standing. A swing
## "where you stand" (Shift and a click) is not a player's mid-run: a free body's walk drops a swing order at once
## (World._free_drop_order, any intent of WIND_UP_LEAVE_INTENT; at a426bca29 the Shift click came 1.4 s in and never
## struck), so the swing out of a run is the one a player makes: a click on the goblin from RUN_FROM, the jog at it and
## the blow on arrival.
const SWING_RUNS := {"man": ["rot_hammer", "giant_axe"]}
const SWING_LEAD := 0.4  # s of standing clipped before the first click
const SWING_TAIL := 1.2  # s clipped after the stop (a swing run: after its first blow, SWING_TAIL twice)
## Each run logs its frames past the stop until the carry is out and the ready in (the upper layer's share READY_SHARE),
## then READY_TAIL s more, STOP_MOST s after the stop at most: at e05f0de48 the runs with no clip ended 0.3 s after
## the stop, mid-ease, and their ready was not logged.
const READY_SHARE := 0.99
const READY_TAIL := 0.3
const STOP_MOST := 3.0
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
	return "%s carry '%s' %.2f upper '%s' %.2f%s bow_state '%s' cam %.2f m zoom %.2f at %s" % [rig.base_clip(), rig.carry_clip(), rig.carry_amount(),
		rig.upper_clip(), rig.upper_share(), " striking" if rig.striking() else "", str(pup.get_meta("bow_state", "")),
		_cam(bot).global_position.distance_to(pup.global_position), float(_view(bot).get("zoom")), bot.cell()]


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


## The view now rendered again at WRIST_SCALE times the window's pixels from a copy of the camera (its place, lens,
## near and far) on the same world, cut round the runner's chest (as _crop_of, WRIST_CROP of the height) at its own
## pixels. A SubViewport rendered once and freed, in the frame of [param seen] (the window's still, _grab's, no frame
## between): [cut, its mean difference from the window's pixels of the same rect, each channel 0..1]. At e05f0de48 all
## eight were flat ground under a sky band, no runner: the eye's global transform was set after it entered the tree,
## and a transform set so reaches the renderer only at the tree's next flush of its changes, after the forced draw, so
## the eye drew from the world's origin. It is now set before it enters the tree and pushed at once
## (force_update_transform), and the cut checked against the window's own pixels (WRIST_SAME).
func _wrist_grab(bot: Node, seen: Image) -> Array:
	var cam := _cam(bot)
	var vp := cam.get_viewport()
	var sub := SubViewport.new()
	sub.size = vp.get_texture().get_size() * WRIST_SCALE
	sub.world_3d = cam.get_world_3d()
	sub.msaa_3d = vp.msaa_3d
	sub.screen_space_aa = vp.screen_space_aa
	sub.use_taa = vp.use_taa
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	var eye := Camera3D.new()
	for key: String in ["projection", "fov", "size", "near", "far", "keep_aspect", "cull_mask", "environment", "attributes", "h_offset", "v_offset"]:
		eye.set(key, cam.get(key))
	eye.transform = cam.global_transform  # the SubViewport is no Node3D: in it the local transform is the global one
	eye.current = true
	sub.add_child(eye)
	bot.add_child(sub)
	eye.global_transform = cam.global_transform
	eye.force_update_transform()
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var p := eye.unproject_position(_pup(bot, bot.me()).global_position + Vector3.UP * 1.2)
	sub.queue_free()
	var w := int(img.get_height() * WRIST_CROP)
	var rect := Rect2i(int(p.x) - w / 2, int(p.y) - w / 2, w, w).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if not rect.has_area():
		return [null, 1.0]
	var cut := img.get_region(rect)
	var diff := 1.0
	if seen == null or seen.is_empty():
		return [cut, diff]
	var f := Vector2(seen.get_size()) / Vector2(img.get_size())  # the window's pixels to the render's, about 1 / WRIST_SCALE
	var small := Rect2i(Vector2i(Vector2(rect.position) * f), Vector2i(Vector2(rect.size) * f)).intersection(Rect2i(Vector2i.ZERO, seen.get_size()))
	if small.has_area():
		var down := cut.duplicate() as Image
		down.resize(small.size.x, small.size.y, Image.INTERPOLATE_BILINEAR)
		var win := seen.get_region(small)
		var total := 0.0
		for y in small.size.y:
			for x in small.size.x:
				var a := down.get_pixel(x, y)
				var b := win.get_pixel(x, y)
				total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		diff = total / (3.0 * small.size.x * small.size.y)
	return [cut, diff]


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
	var laid := str(await bot.admin("foes Tourbot")).strip_edges().left(80)
	# Held on its cell (the console's root, test-only): laid, every temper moved within half a second, unrepeatably
	# (at 969f33fa7 the rot hammer's goblin went to (214, 214) before the click, the giant axe's from (212, 212) to
	# (208, 208)).
	var held := str(await bot.admin("root Tourbot the imp %d" % ROOT_SECONDS)).strip_edges()
	bot.log_line("%s goblin laid: %s; %s" % [TAG, laid, held])
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
		if said.begins_with("strike: no monster"):
			return  # what is left near is the wilds' own, not the laid imp
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
	await _clear(bot)
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
	var clip_at: PackedStringArray = []
	var at_click := Vector2i(-1, -1)
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
				at_click = gob.tile
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
			clip_at.append("%03d %.3f" % [clip.size(), last_grab / 1000.0])
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
	_times(bot, name, clip_at, "the goblin at %s, clicked on %s; the first blow %.2f s" % [from, at_click, struck])
	var end := gob.tile if is_instance_valid(gob) else Vector2i(-1, -1)
	bot.log_line("%s run %s: the first blow at %.2f s; clips %s; %d clip frames; camera %.2f m; the goblin at %s, at the click %s, at the end %s" % [
		TAG, name, struck, ",".join(bases.keys()), clip.size(), camera, from, at_click, str(end) if end.x >= 0 else "gone"])
	_cameras[name] = camera
	_foe_at[name] = from
	# Held to the click: after it the blow may knock the goblin back (at e05f0de48 the rot hammer's did), so its end cell
	# is logged, not checked.
	bot.expect(at_click == from, "%s: the goblin held on its cell to the click (the console's root)" % name,
		"at %s, at the click %s, at the end %s" % [from, at_click, end])
	if carry:
		var was_at: Variant = _foe_at.get(name.replace("_after", "_before"))
		bot.expect(was_at == from, "%s: the goblin on its before's cell" % name, "before %s, after %s" % [str(was_at), from])
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
	var name := "%s_%s_%s_%s" % [row[0], weapon, gait, "after" if carry else "before"]
	var share := await _speed(bot, name, gait)
	_mode(bot, carry)
	_near(bot)
	var dir := Vector2i(signi(RUN_TO.x - RUN_FROM.x), signi(RUN_TO.y - RUN_FROM.y))
	var side := _yaw_for(Vector2(-dir.y, dir.x))
	var other := _yaw_for(Vector2(dir.y, -dir.x))
	var front := _yaw_for(Vector2(-dir.x - dir.y, dir.x - dir.y).normalized())
	_yaw(bot, side)
	await bot.frames(3)
	var camera := await _settle(bot, name)
	var all := 0 if _quiet else SIDE_AT.size() + OTHER_AT.size() + FRONT_AT.size()
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
	var clips := _only == "" and (weapon == CLIP_WEAPON or gait == "walk")
	var clip_at: PackedStringArray = []  # each clip frame's time
	var moved := -1.0
	var at_two := -1.0  # the times the runner's cell is 2 and 7 cells on: the steady pace between
	var at_seven := -1.0
	var stopped := -1.0
	var ready_in := -1.0  # after the stop, the first frame the carry is out and the ready in (upper_share READY_SHARE)
	var buff_at_step := "none"  # the client's speed buff at the first moving frame
	var shift := 0.0  # s the other side's first still waited for the body in view: the later stills follow by as much
	var facing := side
	var wrist := gait == "jog" and weapon == CLIP_WEAPON
	var wrists: Array[Array] = []  # [name, image, state]
	var start: Vector2i = bot.cell()
	var t0 := Time.get_ticks_msec() + (int(SWING_LEAD * 1000.0) if clips else 0)  # the first click's time
	while Time.get_ticks_msec() - t0 < (16000 if gait == "walk" else 8000):
		var ms := Time.get_ticks_msec() - t0
		var s := ms / 1000.0
		var settled := ready_in >= 0.0 and s > ready_in + READY_TAIL or s > stopped + STOP_MOST
		if stopped >= 0.0 and s > stopped + (SWING_TAIL if clips else 0.3) and taken >= all and settled:
			break
		if s >= 0.0 and stopped < 0.0 and ms - last_click >= 300:
			last_click = ms
			await _click_on(bot, dir)
		if taken < all:
			var sides := SIDE_AT.size()
			var others := sides + OTHER_AT.size()
			var when: float = SIDE_AT[taken] if taken < sides else OTHER_AT[taken - sides] + shift if taken < others else FRONT_AT[taken - others] + shift
			var look := side if taken < sides else other if taken < others else front
			if s >= when and facing != look:
				facing = look
				_yaw(bot, look)
				await bot.frames(2)
			var hidden := s >= when and bool(_view(bot).call("_body_hidden", _pup(bot, bot.me())))
			if s >= when and hidden and taken == sides and s < when + OTHER_WAIT and stopped < 0.0:
				pass  # the other side's first: the body hidden, wait for it in view
			elif s >= when:
				if taken == sides:
					shift = s - OTHER_AT[0]
				var still := "%s_%s%d" % [name, "side" if taken < sides else "other" if taken < others else "front",
					taken + 1 if taken < sides else taken - sides + 1 if taken < others else taken - others + 1]
				var img := await _grab(bot)
				var said := "%.2f s, %s%s" % [(Time.get_ticks_msec() - t0) / 1000.0, _state(bot), "; the body HIDDEN from the camera" if hidden else ""]
				stills.append([still, img, _crop_of(bot, img), said])
				if wrist and (taken == 1 or taken == others):
					var got: Array = await _wrist_grab(bot, img)
					wrists.append([still + "_wrist", got[0], said, got[1]])
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
			buff_at_step = _buff_said(bot)
			bot.log_line("%s %s: first step at %.2f s, the client's speed buff %s" % [TAG, name, now, buff_at_step])
		if at_two < 0.0 and absi(bot.cell().x - start.x) >= 2:
			at_two = now
		if at_seven < 0.0 and absi(bot.cell().x - start.x) >= 7:
			at_seven = now
		if moved >= 0.0 and stopped < 0.0 and rig.base_clip() == Client3D.CLIP_IDLE:
			stopped = now
		if stopped >= 0.0 and ready_in < 0.0 and rig.carry_amount() <= 0.01 and rig.upper_share() >= READY_SHARE:
			ready_in = now
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
		file.store_line("# %s: %s; worn: %s; buffs %s; the speed buff at the first step %s (set %+.2f); camera %.2f m from the runner at the start; first step at %.2f s, the stop at %.2f s, the ready in at %.2f s (%s); the other side's stills %.2f s late (the body hidden); seconds after the first click%s, base clip, carry clip and amount, upper clip and its share (the ready's ease-in, upper_in), bow_state, camera distance and zoom, cell" % [
			name, _hands(bot), _worn(bot), str(bot.me().get("buffs")), buff_at_step, share, camera, moved, stopped, ready_in, pace, shift, " (negative: standing before it)" if clips else ""])
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for still: Array in stills:
		var ok: bool = _save(bot, still[1], still[0]) and _save_crop(bot, still[2], still[0])
		bot.log_line("%s still %s %s (and %s_crop, 3x): %s" % [TAG, still[0], "saved" if ok else "FAILED", still[0], still[3]])
		await bot.frames(1)
	for still: Array in wrists:
		var ok: bool = _save(bot, still[1], still[0])
		bot.log_line("%s still %s %s (%dx the window's pixels, cut %s; %.3f from the window's own pixels): %s" % [TAG, still[0], "saved" if ok else "FAILED",
			WRIST_SCALE, str((still[1] as Image).get_size()) if still[1] != null else "none", float(still[3]), still[2]])
		await bot.frames(1)
	for i in clip.size():
		_save(bot, clip[i], "clip_%s/%03d" % [name, i])
		if i % 4 == 3:
			await bot.frames(1)
	_times(bot, name, clip_at, "first step %.2f s, the stop %.2f s" % [moved, stopped])
	bot.log_line("%s run %s: %.1f s to %s, the stop at %.2f s; %s; clips %s; carry while running %.2f..%.2f; %d stills, %d clip frames; camera %.2f m" % [TAG, name,
		(Time.get_ticks_msec() - t0) / 1000.0, bot.cell(), stopped, pace, ",".join(bases.keys()), least if most > 0.0 or least < 1.0 else 0.0, most, taken, clip.size(), camera])
	_cameras[name] = camera
	var buff := _buff(bot, buff_at_step)
	if gait == "jog":
		bot.expect(buff == 0.0, "%s: no speed buff at the first step (a plain jog)" % name, buff_at_step)
	else:
		bot.expect(absf(buff - share) < 0.005, "%s: the speed buff %+.2f at the first step (the console's quick)" % [name, share], buff_at_step)
	if wrist:
		bot.expect(wrists.size() == 2 and wrists.all(func(w: Array) -> bool: return w[1] != null and float(w[3]) <= WRIST_SAME),
			"%s: the wrists rendered side on and from the front quarter, each the window's still at %dx (within %.2f of its pixels)" % [name, WRIST_SCALE, WRIST_SAME],
			", ".join(wrists.map(func(w: Array) -> String: return "%s %.3f" % [w[0], float(w[3])])) + " (%d of 2)" % wrists.size())
	if gait == "sprint":
		bot.expect("Sprint_Short" in bases, "%s: Sprint_Short reached (the console's quick, +%.2f)" % [name, QUICK_SHARE], pace)
	if carry:
		var was := name.replace("_after", "_before")
		bot.expect(_cameras.has(was) and absf(float(_cameras[was]) - camera) <= 0.1, "%s: the camera as far as its before's" % name,
			"before %s m, after %.2f m" % [str(_cameras.get(was, "none")), camera])
	if gait == "walk":
		bot.expect(Client3D.CLIP_WALK in bases and not "Jog_Short" in bases, "%s walked, never jogged (the console's quick, %+.2f)" % [name, Main.QUICK_LEAST],
			",".join(bases.keys()) + "; " + pace)
	elif gait == "jog":
		bot.expect("Jog_Short" in bases, "%s ran in Jog_Short" % name, ",".join(bases.keys()))
	if gait == "jog":
		bot.expect(steady >= PLAIN_PACE[0] and steady <= PLAIN_PACE[1], "%s: a plain jog's steady pace %.1f to %.1f tiles a second" % [name, PLAIN_PACE[0], PLAIN_PACE[1]], pace)
	bot.expect(stopped >= 0.0, "%s: stood at the run's end" % name, "at %s" % bot.cell())
	if carry:
		bot.expect(ready_in >= 0.0, "%s: the ready eased in after the stop, logged" % name, "the stop %.2f s, frames to %.2f s" % [stopped, (Time.get_ticks_msec() - t0) / 1000.0])
	if carry:
		bot.expect(most > 0.9, "%s: the carry on while moving" % name, "most %.2f" % most)
	else:
		bot.expect(most == 0.0, "%s: no carry (main's arms)" % name, "most %.2f" % most)


var _cameras := {}  # run name: the camera's settled distance (m), for its after's check


## The section run (TOUR_ONLY, tour.sh's and remote_shot.sh's --tour-only; "" the whole tour), and whether a run takes no
## stills (the pace section's).
var _only := ""
var _quiet := false


## The coordinator's 11-25 sections, each minutes, not the whole tour's 25: TOUR_ONLY "wrists", the man's and the woman's
## giant axe at the jog, before and after, with their stills and the two wrist stills (side2_wrist, front1_wrist), no
## clip; "pace", the woman's giant axe and the man's battle axe at the sprint, before and after, no still and no clip,
## each run's steady pace in its log line (at e05f0de48 those after runs paced under their befores, 3.95 against 6.23 and
## 5.54 against 6.20, the latest other-side stills on the slowest). A name holding both (wrists_pace) runs both.
func _sections(bot: Node) -> void:
	for row: Array in ROWS:
		if not await _join(bot, row):
			return
		if _only.contains("wrists") and await _hold(bot, CLIP_WEAPON):
			await _clear(bot)
			for carry: bool in [false, true]:
				await _run(bot, row, CLIP_WEAPON, "jog", carry)
		var paced := "giant_axe" if row[0] == "woman" else "battle_axe"
		if _only.contains("pace") and await _hold(bot, paced):
			await _clear(bot)
			_quiet = true
			for carry: bool in [false, true]:
				await _run(bot, row, paced, "sprint", carry)
			_quiet = false


var _foe_at := {}  # swing run name: the goblin's cell, for its after's check


## The weight's section (451 amended (14), TASK 16 step 2; TOUR_ONLY=sway, remote_shot.sh's --tour-only sway): the
## carry's three columns side by side, today's rigid carry (Client3D.carry_sway off, the shipped placing), the weight on
## the shipped placing and the weight on J2 (Client3D.carry_placing "j2", Axe_Carry_J2), SWAY_COLUMNS, for the man's
## battle axe and the woman's giant axe (SWAY_ROWS). Gait by gait, each column in turn: the walk, the jog and the sprint
## from RUN_FROM west to RUN_TO, standing to standing (the start and the stop in each), then a jog with a 90-degree turn
## (west, then at SWAY_CORNER north or south, whichever way SWAY_LEG cells are walkable). Each run is one clip (each
## 40 ms, cropped round the runner) from SWING_LEAD s standing before the first click to SWING_TAIL s after the stop (the
## walk's 8 s between kept out, as _run's), and at the jog and the sprint two stills side on, the first at a footfall's
## low (the Hips' lowest in a stride, SWAY_STILL_AFTER s after the gait is reached; grabbed the frame after it) and the
## second at the stride's high after it. <run>_frames.txt logs each frame: the state, the Hips' height (m), the body's
## yaw (deg), and the sway's give (lean, turn, clavicle in deg, the hand up and ahead in cm, its yaw in deg; "off" when
## none runs). The column's switches are the client's own statics, set before each run and put back after the section.
const SWAY_COLUMNS: Array[Array] = [["rigid", false, "shipped"], ["shipped", true, "shipped"], ["j2", true, "j2"]]
const SWAY_ROWS := {"man": "battle_axe", "woman": "giant_axe"}
const SWAY_CORNER := Vector2i(200, 211)
const SWAY_LEG := 5
const SWAY_STILL_AFTER := 1.0
func _sway_section(bot: Node) -> void:
	var was_sway := Client3D.carry_sway
	var was_placing := Client3D.carry_placing
	var turn_dir := Vector2i.ZERO
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1)]:
		var clear := true
		for k in range(0, SWAY_LEG + 1):
			clear = clear and World.is_walkable(SWAY_CORNER + d * k)
		if clear:
			turn_dir = d
			break
	bot.log_line("%s sway: the turn at %s goes %s" % [TAG, SWAY_CORNER, str(turn_dir) if turn_dir != Vector2i.ZERO else "nowhere (no clear leg north or south)"])
	for row: Array in ROWS:
		var weapon: String = SWAY_ROWS.get(row[0], "")
		if weapon == "" or not await _join(bot, row):
			continue
		if not await _hold(bot, weapon):
			continue
		await _clear(bot)
		for gait: String in ["walk", "jog", "sprint", "turn"]:
			if gait == "turn" and turn_dir == Vector2i.ZERO:
				continue
			for col: Array in SWAY_COLUMNS:
				Client3D.carry_sway = bool(col[1])
				Client3D.carry_placing = str(col[2])
				await _sway_run(bot, row, weapon, gait, col, turn_dir)
	Client3D.carry_sway = was_sway
	Client3D.carry_placing = was_placing


func _sway_run(bot: Node, row: Array, weapon: String, gait: String, col: Array, turn_dir: Vector2i) -> void:
	await _home(bot, RUN_FROM)
	var name := "%s_%s_%s_%s" % [row[0], weapon, gait, col[0]]
	await _speed(bot, name, "jog" if gait == "turn" else gait)
	_mode(bot, true)
	_near(bot)
	var west := Vector2i(signi(RUN_TO.x - RUN_FROM.x), 0)
	_yaw(bot, _yaw_for(Vector2(-west.y, west.x)))
	await bot.frames(3)
	var camera := await _settle(bot, name)
	var rig := _rig(bot)
	var pup := _pup(bot, bot.me())
	var sk := pup.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips := sk.find_bone("Hips")
	var body := pup.get_node("Body") as Node3D
	var lines: PackedStringArray = []
	var clip: Array[Image] = []
	var clip_at: PackedStringArray = []
	var stills: Array[Array] = []
	var bases := {}
	var carries := {}
	var last_click := -1000
	var last_grab := -1000
	var start: Vector2i = bot.cell()
	var moved := -1.0
	var stopped := -1.0
	var gait_at := -1.0
	var turned := false
	var yaw0 := INF
	var yaw_most := 0.0
	var gave := 0  # frames the sway gave (any part not zero)
	var h := [INF, INF]  # the Hips' height the two frames before
	var still_want := "low"
	var target := RUN_TO
	var t0 := Time.get_ticks_msec() + int(SWING_LEAD * 1000.0)
	while Time.get_ticks_msec() - t0 < (16000 if gait == "walk" else 9000):
		var s := (Time.get_ticks_msec() - t0) / 1000.0
		if stopped >= 0.0 and s > stopped + SWING_TAIL:
			break
		if s >= 0.0 and stopped < 0.0 and (Time.get_ticks_msec() - t0) - last_click >= 300:
			last_click = Time.get_ticks_msec() - t0
			if gait == "turn" and not turned and bot.cell().x <= SWAY_CORNER.x:
				turned = true
				target = SWAY_CORNER + turn_dir * SWAY_LEG
				bot.log_line("%s %s: at %s, clicked on toward %s, %.2f s" % [TAG, name, bot.cell(), target, s])
			if gait == "turn" and not turned:
				await bot.click(SWAY_CORNER + west * 3)
			elif gait == "turn":
				for k in range(SWAY_LEG, 1, -1):
					var to: Vector2i = SWAY_CORNER + turn_dir * k
					if not is_nan((bot.screen_point(to) as Vector2).x):
						await bot.click(to)
						break
			else:
				await _click_on(bot, west)
		var in_clip := gait != "walk" or s < WALK_CLIP_START or absi(bot.cell().x - RUN_TO.x) <= 1 or stopped >= 0.0
		var grabbed := false
		var y := (sk.global_transform * sk.get_bone_global_pose(hips).origin).y
		var fast := rig.base_clip() in ["Jog_Short", "Sprint_Short"]
		if fast and gait_at < 0.0:
			gait_at = s
		if gait != "walk" and gait != "turn" and fast and gait_at >= 0.0 and s >= gait_at + SWAY_STILL_AFTER and still_want != "":
			var at_low: bool = still_want == "low" and h[0] < h[1] and h[0] <= y
			var at_high: bool = still_want == "high" and h[0] > h[1] and h[0] >= y
			if at_low or at_high:
				var img := await _grab(bot)
				grabbed = true
				stills.append(["%s_%s" % [name, still_want], img, _crop_of(bot, img), "%.2f s, the Hips %.3f m (the %s %.3f the frame before), %s" % [s, y, still_want, h[0], _state(bot)]])
				still_want = "high" if still_want == "low" else ""
		if not grabbed and in_clip and (Time.get_ticks_msec() - t0) - last_grab >= 40:
			last_grab = Time.get_ticks_msec() - t0
			clip_at.append("%03d %.3f" % [clip.size(), last_grab / 1000.0])
			clip.append(await _clip_frame(bot))
		elif not grabbed:
			await bot.get_tree().process_frame
		h = [y, h[0]]
		var now := (Time.get_ticks_msec() - t0) / 1000.0
		if moved < 0.0 and bot.cell() != start:
			moved = now
		if moved >= 0.0 and stopped < 0.0 and rig.base_clip() == Client3D.CLIP_IDLE:
			stopped = now
		var yaw := rad_to_deg(body.rotation.y)
		if moved >= 0.0 and yaw0 == INF:
			yaw0 = yaw
		if yaw0 != INF:
			yaw_most = maxf(yaw_most, absf(wrapf(yaw - yaw0, -180.0, 180.0)))
		bases[rig.base_clip()] = true
		if rig.carry_clip() != "":
			carries[rig.carry_clip()] = true
		var sway: Node = pup.get_meta("sway") if pup.has_meta("sway") else null
		var give := "off"
		if sway != null and sway.get("active"):
			var off: Vector3 = sway.get("hand_off")
			give = "lean %+.2f turn %+.2f clav %.2f hand up %+.2f ahead %+.2f yaw %+.2f" % [sway.get("lean"), sway.get("turn"), sway.get("clav"), off.y * 100.0, off.z * 100.0, sway.get("yaw")]
			if absf(float(sway.get("lean"))) + absf(float(sway.get("turn"))) + off.length() > 0.0001:
				gave += 1
		lines.append("%.3f %s hips %.3f yaw %.1f %s" % [now, _state(bot), y, yaw, give])
	var file := FileAccess.open((bot.own_dir() as String).path_join(name + "_frames.txt"), FileAccess.WRITE)
	if file != null:
		file.store_line("# %s: %s; worn: %s; the column %s (carry_sway %s, placing %s); camera %.2f m; first step %.2f s, the stop %.2f s, the gait reached %.2f s; the body's yaw turned %.1f deg at most; seconds after the first click (negative: standing before it), state, the Hips' height, the body's yaw, the sway's give" % [
			name, _hands(bot), _worn(bot), col[0], col[1], col[2], camera, moved, stopped, gait_at, yaw_most])
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
	_times(bot, name, clip_at, "first step %.2f s, the stop %.2f s; the column %s" % [moved, stopped, col[0]])
	bot.log_line("%s run %s: the stop at %.2f s at %s; clips %s; carry %s; the sway gave on %d frames; yaw turned %.1f deg; %d stills, %d clip frames; camera %.2f m" % [
		TAG, name, stopped, bot.cell(), ",".join(bases.keys()), ",".join(carries.keys()), gave, yaw_most, stills.size(), clip.size(), camera])
	var placed := str(Client3D.CARRY_PLACINGS[col[2]])
	bot.expect(carries.has(placed) and carries.size() == 1, "%s: carried as %s" % [name, placed], ",".join(carries.keys()))
	bot.expect((gave > 0) == bool(col[1]), "%s: the sway %s" % [name, "gave" if col[1] else "off (the rigid carry)"], "%d frames gave" % gave)
	bot.expect(stopped >= 0.0, "%s: stood at the run's end" % name, "at %s" % bot.cell())
	if gait == "turn":
		bot.expect(turned and yaw_most >= 80.0, "%s: turned about 90 degrees" % name, "%.1f deg" % yaw_most)
	elif gait != "walk":
		bot.expect(stills.size() == 2, "%s: the footfall's low and the stride's high stills" % name, "%d" % stills.size())


## The speed for [param gait], set after the run's move: the console's quick (test-only) at Main.QUICK_LEAST for the walk,
## QUICK_SHARE for the sprint (a stamina potion's +0.25 stays under the man's sprint change), none for the jog; logged
## with the buffs the client then shows. At 969f33fa7 it was set before the runs and never reached one: the console's
## move (each run's _home) goes by travel, which takes the player out and joins a new one from its record, and a record
## keeps no buffs ({"speed": [0.6, 600]} after quick, ticks and hp; {} after move, measured on the host).
func _speed(bot: Node, name: String, gait: String) -> float:
	if gait == "jog":
		return 0.0
	var share := Main.QUICK_LEAST if gait == "walk" else QUICK_SHARE
	var said := str(await bot.admin("quick Tourbot %.2f %d" % [share, QUICK_SECONDS])).strip_edges()
	await bot.until(func() -> bool: return absf(_buff(bot) - share) < 0.005, 3.0)
	bot.log_line("%s %s: the speed admin-set (console quick, test-only): %s; buffs %s" % [TAG, name, said, str(bot.me().get("buffs"))])
	return share


## The client's speed buff now as a share (0 when none), or as [param said] (_buff_said's) reads it.
func _buff(bot: Node, said := "") -> float:
	if said != "":
		return float(said.get_slice(" ", 0)) if said != "none" else 0.0
	var b: Variant = (bot.me().get("buffs") as Dictionary).get("speed", null)
	return float(b[0]) if b is Array and not (b as Array).is_empty() else 0.0


func _buff_said(bot: Node) -> String:
	var b: Variant = (bot.me().get("buffs") as Dictionary).get("speed", null)
	return "%+.2f %s" % [float(b[0]), str(b)] if b is Array and not (b as Array).is_empty() else "none"


## clip_<name>/times.txt: each clip frame's time after the first click, under a "#" line.
func _times(bot: Node, name: String, clip_at: PackedStringArray, head: String) -> void:
	if clip_at.is_empty():
		return
	var times := FileAccess.open((bot.own_dir() as String).path_join("clip_%s/times.txt" % name), FileAccess.WRITE)
	if times != null:
		times.store_string("# frame, seconds after the first click (frames.txt has every frame's state); " + head + "\n" + "\n".join(clip_at) + "\n")
		times.close()


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
	_only = OS.get_environment("TOUR_ONLY")
	if _only != "":
		bot.log_line("%s section %s" % [TAG, _only])
		if bot.expect(_only.contains("wrists") or _only.contains("pace") or _only.contains("sway"), "a section this tour has (wrists, pace, sway)", _only):
			if _only.contains("wrists") or _only.contains("pace"):
				await _sections(bot)
			if _only.contains("sway"):
				await _sway_section(bot)
		bot.log_line("%s done: server script errors %d" % [TAG, bot.server_lines("SCRIPT ERROR").size()])
		return
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
					for carry: bool in [false, true]:
						await _run(bot, row, weapon, gait, carry)
				continue
			for weapon: String in ((row[3] + row[4]) if gait == "jog" else row[3]):
				if not await _hold(bot, weapon):
					continue
				if gait == "jog":
					await _lay(bot)
					await _stand(bot, row, weapon)
				await _clear(bot)
				for carry: bool in [false, true]:
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
			await _run(bot, row, "giant_axe", "sprint", carry)
	bot.log_line("%s done: server script errors %d" % [TAG, bot.server_lines("SCRIPT ERROR").size()])
