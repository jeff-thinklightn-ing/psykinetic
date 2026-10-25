class_name CharacterLab
extends Node3D
## The Character Lab (decision 674; Jeff: "i also need to work on the player
## model and run animations separately"): the player's body alone on a grid,
## under a camera like the game's, to look at the model and its clips
## without a world. Local only: it never goes online, starts no World zone
## and writes no file in the project (art/, levels/) or in user://.
##
## A body is made as Client3D makes a person's (Client3D._make_model, its
## held things by Client3D._hold), from one of BUILDS and a look's words
## (PersonLook), holding what the pickers say and wearing an armour.
## Its clip loops at a speed, paused, scrubbed or stepped a frame; on the
## treadmill the floor runs under it at the clip's gait pace (Client3D's
## HUMAN_GAITS, times the speed over feel.json's gait rate), so a foot that
## slides on it says the pace is wrong. Keys: 1, 2, 3 the game's views
## (normal, low, overhead); drag to orbit, wheel to zoom; Space pauses, "."
## steps a frame.
##
## Jeff's own exports (674 step 2): a body or clips dropped in the drop folder
## are imported through the gate and shown here in the game's place (LabDrop,
## client3d/lab_drop.gd; R takes the folder again); the line under the panel
## says what it is doing.
##
## Compared and measured (674 step 3): "Compare" puts a second body (B) beside
## the first (A), SPACING apart across its way, its own build, look words and
## source (the game's body and clips, or Jeff's drop export); the clip, speed,
## pause, scrub, treadmill and held things are both's, started together. Under
## the panel, each one's feet measured as it plays (LabFeet,
## client3d/lab_feet.gd: the pace that keeps its planted foot still, and how
## fast it slides at the table's pace), and its planted toe marked on the
## floor, the marks riding the treadmill: a slide smears them, a good pace
## stacks them. "Use measured" sets the gait's pace (feel.json's
## client3d.gait.<clip>, gait_f for a woman, Client3D.paced) to the measured
## one for this run: the lab writes no file, keeping it is feel.json's edit.

## The five builds the hand and rest tests check (anim_rig_test): a name,
## its body, its shape keys over the look's.
const BUILDS: Array[Array] = [
	["man", "male", {}],
	["man heavy", "male", {"heavy": 1.0}],
	["man broad", "male", {"heavy": 0.6, "broad": 1.0}],
	["man lean", "male", {"lean": 1.0, "narrow": 1.0}],
	["woman", "female", {}]]
## The game's views: [pitch in degrees, orthographic size or 0 for the low
## camera's perspective, its field of view].
const VIEWS: Array[Array] = [[Client3D.CAMERA_PITCH, 4.0, 0.0], [Client3D.LOW_PITCH, 0.0, Client3D.LOW_FOV],
	[Client3D.OVERHEAD_PITCH, 4.0, 0.0]]
## The camera's distance off the body, its aim's height, its zoom's bounds.
const DISTANCE := 12.0
const AIM := 0.9
const ZOOM_MIN := 1.5
const ZOOM_MAX := 12.0
## Degrees a pixel of drag turns the camera.
const ORBIT_RATE := 0.3
## A step ("."), the clips' frame.
const FRAME := 1.0 / 30.0
## The floor: its size and its grid's cell, in metres (a tile is a metre).
const FLOOR_SIZE := 40.0
const FLOOR_CELL := 1.0
## Clips listed first, the gaits and idles (any clip can be picked).
const FIRST: Array[String] = [Client3D.CLIP_WALK, "Jog_Short", "Sprint_Short", "Idle", "Idle_Tired"]
## What a hand can hold, and what is worn: the items tagged so.
const HOLDS: Array[String] = ["weapon", "shield", "tool"]

var body := 0
var words := "seed=1"
var clip := "Idle"
var upper := ""
var speed := 1.0
var paused := false
var treadmill := false
var held: Array[String] = ["", ""]
var worn := ""
var view := 0
## The clip's time while paused or scrubbed (seconds).
var at := 0.0
## How far the floor has run (metres, along the body's back).
var run := 0.0

var puppet: Node3D
var rig: AnimRig
var look: PersonLook
## The second body, compared (674 step 3): its build, words, whether it is
## Jeff's export (A always is when there is one), and it as made.
const SPACING := 1.2
var compare := false
var body_b := 0
var words_b := "seed=1"
var own_b := false
var puppet_b: Node3D
var rig_b: AnimRig
var look_b: PersonLook
## Each side's foot meter (LabFeet), A's then B's (null without B).
const LabFeet := preload("res://client3d/lab_feet.gd")
var feet: Array = [null, null]
## The planted toes' marks on the floor: one every MARK_SECONDS a foot is
## planted, gone after MARK_LIFE.
const MARK_SECONDS := 0.05
const MARK_LIFE := 1.5
var _marks: Array[Array] = []
var _mark_at := 0.0
var _mark_mesh: CylinderMesh
var _read_at := 0
var camera: Camera3D
var floor_material: StandardMaterial3D
var status: Label
## Jeff's exports, watched (674 step 2); its folders set before the lab is in the tree.
const LabDrop := preload("res://client3d/lab_drop.gd")
var drop := LabDrop.new()
var drop_line: Label
var _drop_at := 0
var _drop_loaded := 0
var _yaw := 45.0
var _pitch := Client3D.CAMERA_PITCH
var _zoom := 4.0
var _dragging := false
var _ui: Dictionary = {}


func _ready() -> void:
	_make_stage()
	_make_ui()
	make_body()


## The light, the sky and the floor.
func _make_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	add_child(env)
	var ground := MeshInstance3D.new()
	ground.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	ground.mesh = plane
	floor_material = StandardMaterial3D.new()
	floor_material.albedo_texture = _grid_texture()
	floor_material.uv1_scale = Vector3(FLOOR_SIZE / FLOOR_CELL, FLOOR_SIZE / FLOOR_CELL, 1.0)
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = floor_material
	add_child(ground)
	camera = Camera3D.new()
	add_child(camera)
	set_view(0)


static func _grid_texture() -> ImageTexture:
	var image := Image.create(64, 64, true, Image.FORMAT_RGB8)
	image.fill(Color(0.46, 0.45, 0.42))
	for i in 64:
		for line in [0, 1, 32]:
			var shade := Color(0.3, 0.3, 0.28) if line != 32 else Color(0.4, 0.39, 0.37)
			image.set_pixel(i, line, shade)
			image.set_pixel(line, i, shade)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The body again, as body, words, held and worn say; and B beside it when
## comparing.
func make_body() -> void:
	for old: Node3D in [puppet, puppet_b]:
		if old != null:
			remove_child(old)
			old.queue_free()
	puppet_b = null
	rig_b = null
	look_b = null
	puppet = _made(body, words, true, "Person")
	rig = puppet.get_meta("rig") as AnimRig
	look = puppet.get_meta("look") as PersonLook
	if compare:
		puppet_b = _made(body_b, words_b, own_b, "PersonB")
		rig_b = puppet_b.get_meta("rig") as AnimRig
		look_b = puppet_b.get_meta("look") as PersonLook
		puppet.position.z = -SPACING * 0.5
		puppet_b.position.z = SPACING * 0.5
		_tag(puppet, "A", body, true)
		_tag(puppet_b, "B", body_b, own_b)
	feet = [LabFeet.new(puppet), LabFeet.new(puppet_b) if puppet_b != null else null]
	play()
	_say("%s, %s" % [BUILDS[body][0], words] + ("; B %s, %s" % [BUILDS[body_b][0], words_b] if compare else ""))


## One body: BUILDS' [param index] in [param said] look words, Jeff's export
## when [param own] and there is one, holding and wearing what the pickers say.
func _made(index: int, said: String, own: bool, named: String) -> Node3D:
	var build: Array = BUILDS[index]
	var made_look := PersonLook.make(("body=%s " % build[1]) + said)
	for key: String in build[2]:
		made_look.keys[key] = build[2][key]
	var model: Dictionary = (Client3D.HUMAN_F if made_look.body == &"female" else Client3D.HUMAN).duplicate()
	if own and drop.bodies.has(String(made_look.body)):
		model["scene"] = drop.bodies[String(made_look.body)]
	if own and not drop.clip_names.is_empty():
		model["clips"] = drop.clips_path()
	var made := Node3D.new()
	made.name = named
	made.set_meta("look", made_look)
	made.set_meta("model_scale", made_look.scale)
	add_child(made)
	made.add_child(Client3D._make_model(model, made))
	var scene := made.get_node("Body/Model") as Node3D
	if not worn.is_empty():
		made_look.wear(scene, worn)
	var sockets: Dictionary = made.get_meta("sockets", {})
	for hand in 2:
		Client3D._hold(sockets, hand, held[hand], {})
	if made.has_meta("reach"):
		Client3D._sync_reach(made.get_meta("reach") as HandReach, sockets, held)
	return made


## Which body is which, over its head.
func _tag(person: Node3D, side: String, index: int, own: bool) -> void:
	var tag := Label3D.new()
	tag.name = "Tag"
	var of := person.get_meta("look") as PersonLook
	var is_own := own and (drop.bodies.has(String(of.body)) or not drop.clip_names.is_empty())
	tag.text = "%s: %s, %s" % [side, "yours" if is_own else "game", BUILDS[index][0]]
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.1
	tag.pixel_size = 0.004
	person.add_child(tag)


## The rigs playing, A's and B's.
func rigs() -> Array[AnimRig]:
	var all: Array[AnimRig] = []
	for each: AnimRig in [rig, rig_b]:
		if each != null:
			all.append(each)
	return all


## The clips the body has, the gaits and idles first.
func clips() -> PackedStringArray:
	var listed := PackedStringArray()
	for each in FIRST:
		if rig != null and rig.has(each):
			listed.append(each)
	if rig != null:
		var rest := Array(rig.clips())
		rest.sort()
		for each: String in rest:
			if not each in listed:
				listed.append(each)
	return listed


## The clip from its start (or held at [member at] while paused), the upper
## layer's over it.
func play() -> void:
	for each in rigs():
		if upper.is_empty():
			each.upper_off()
		else:
			each.upper(upper, speed, true)
		if paused:
			each.base_at(clip, at)
		else:
			each.loop(clip, speed, 0.0, true)
	_reset_feet()


func set_speed(value: float) -> void:
	speed = value
	if not paused:
		for each in rigs():
			each.set_speed(speed)
	_reset_feet()


func set_paused(value: bool) -> void:
	paused = value
	if rig == null:
		return
	if paused:
		at = rig.position()
	for each in rigs():
		if paused:
			each.base_at(clip, at)
		else:
			each.set_speed(speed)  # From where it was held.


## The clip held at [param seconds] (paused).
func scrub(seconds: float) -> void:
	paused = true
	at = fposmod(seconds, maxf(rig.length(clip), FRAME))
	for each in rigs():
		each.base_at(clip, at)


func step() -> void:
	scrub(at + FRAME)


## The treadmill's pace (metres a second): the clip's gait pace at this
## speed, as Client3D plays a gait (speed / (pace * scale) * gait rate; the
## pace as feel.json has it, Client3D.paced), or 0 for a clip that isn't a
## gait; A's, or B's ([param which] 1). The floor runs at A's.
func pace(which := 0) -> float:
	var of := look if which == 0 else look_b
	if of == null:
		return 0.0
	var gaits := Client3D.paced(Client3D.HUMAN_F_GAITS if of.body == &"female" else Client3D.HUMAN_GAITS)
	for gait: Array in gaits:
		if gait[0] == clip:
			var rate := ArtKit.feel("client3d.gait_rate", Client3D.GAIT_RATE)
			return float(gait[1]) * of.scale * speed / maxf(rate, 0.01)
	return 0.0


## The feel key of the clip's pace for side [param which]'s body, "" for a
## clip that isn't a gait.
func gait_key(which := 0) -> String:
	var of := look if which == 0 else look_b
	if of == null or is_zero_approx(pace(which)):
		return ""
	return ("client3d.gait_f." if of.body == &"female" else "client3d.gait.") + clip


## Side [param which]'s gait pace set, for this run, to what its feet
## measure (the table's value that gives the measured pace at this speed and
## stature); the value set, or 0 with nothing to set.
func use_measured(which := 0) -> float:
	var key := gait_key(which)
	var meter: Variant = feet[which]
	if key.is_empty() or meter == null:
		return 0.0
	var measured: Dictionary = meter.measure(pace(which))
	if measured.is_empty():
		return 0.0
	var of := look if which == 0 else look_b
	var rate := ArtKit.feel("client3d.gait_rate", Client3D.GAIT_RATE)
	var table := snappedf(float(measured["pace"]) * rate / maxf(of.scale * speed, 0.01), 0.01)
	ArtKit.set_feel_value("feel." + key, table)
	_reset_feet()
	return table


## Side [param which]'s readout line, and whether it shows red.
func readout(which := 0) -> Array:
	var meter: Variant = feet[which]
	var side := "A" if which == 0 else "B"
	if meter == null or (meter.toes as Array).is_empty():
		return ["%s: no toes to measure" % side, false]
	var at_pace := pace(which)
	var measured: Dictionary = meter.measure(at_pace)
	if measured.is_empty():
		return ["%s: no planted foot yet" % side, false]
	var shown := ""
	if at_pace > 0.0:
		shown = "%s: measured pace %.2f m/s, table %.2f; slide %.2f m/s (%d%%), 90th %.2f" % [side, measured["pace"], at_pace,
			measured["slide"], roundi(100.0 * float(measured["slide"]) / at_pace), measured["slide_90"]]
	else:
		shown = "%s: standing; the planted foot moves %.2f m/s, 90th %.2f" % [side, measured["slide"], measured["slide_90"]]
	return [shown, LabFeet.red(measured, at_pace)]


## The feet's samples dropped (the clip, speed or body changed).
func _reset_feet() -> void:
	for meter: Variant in feet:
		if meter != null:
			meter.reset()


## Each side's feet sampled [param delta] on, over the clip's last loop, and
## its planted toe marked on the floor.
func sample_feet(delta: float) -> void:
	var window := (rig.length(clip) if rig != null else 1.0) / maxf(speed, 0.05)
	_mark_at += delta
	var marking := _mark_at >= MARK_SECONDS
	if marking:
		_mark_at = 0.0
	for meter: Variant in feet:
		if meter == null:
			continue
		meter.sample(delta, window)
		if marking:
			var toe: Variant = meter.planted_toe()
			if toe != null:
				_mark(toe)


## A mark at [param toe], on the floor.
func _mark(toe: Vector3) -> void:
	if _mark_mesh == null:
		_mark_mesh = CylinderMesh.new()
		_mark_mesh.top_radius = 0.025
		_mark_mesh.bottom_radius = 0.025
		_mark_mesh.height = 0.004
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.95, 0.75, 0.2)
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mark_mesh.material = paint
	var mark := MeshInstance3D.new()
	mark.name = "Mark"
	mark.mesh = _mark_mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.position = Vector3(toe.x, 0.003, toe.z)
	add_child(mark)
	_marks.append([mark, 0.0])


## The marks aged [param delta], riding the floor [param ran] metres back.
func _age_marks(delta: float, ran: float) -> void:
	for each: Array in _marks:
		each[1] = float(each[1]) + delta
		(each[0] as Node3D).position.x -= ran
	while not _marks.is_empty() and float(_marks[0][1]) > MARK_LIFE:
		(_marks[0][0] as Node3D).queue_free()
		_marks.pop_front()


func set_view(index: int) -> void:
	view = index
	_pitch = float(VIEWS[index][0])
	if float(VIEWS[index][1]) > 0.0:
		_zoom = float(VIEWS[index][1])
	_place_camera()


func _place_camera() -> void:
	var low := float(VIEWS[view][1]) <= 0.0
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if low else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = float(VIEWS[view][2]) if low else camera.fov
	camera.size = _zoom
	var distance := _zoom * 1.2 if low else DISTANCE
	var pitch := deg_to_rad(_pitch)
	var yaw := deg_to_rad(_yaw)
	var aim := Vector3(0.0, AIM, 0.0)
	var off := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
	camera.look_at_from_position(aim + off, aim, Vector3.UP if _pitch < 89.0 else Vector3.FORWARD)


func _process(delta: float) -> void:
	var ran := pace() * delta if treadmill and not paused else 0.0
	run += ran
	if not paused:
		sample_feet(delta)
	_age_marks(0.0 if paused else delta, ran)
	if _ui.has("feet_a") and Time.get_ticks_msec() >= _read_at:
		_read_at = Time.get_ticks_msec() + 250
		for which in 2:
			var label := _ui["feet_a" if which == 0 else "feet_b"] as Label
			var line: Array = readout(which) if which == 0 or compare else ["", false]
			label.text = str(line[0])
			label.modulate = Color(1.0, 0.45, 0.4) if bool(line[1]) else Color.WHITE
	# The floor runs under the body from its front (+X, as Body faces) to its back.
	floor_material.uv1_offset = Vector3(fposmod(-run / FLOOR_CELL, 1.0), 0.0, 0.0) if treadmill else Vector3.ZERO
	if _ui.has("scrub") and rig != null and not paused:
		(_ui["scrub"] as HSlider).set_value_no_signal(rig.position() / maxf(rig.length(clip), FRAME))
	if _ui.has("pace"):
		(_ui["pace"] as Label).text = "treadmill %.2f m/s" % pace() if treadmill else ""
	var now := Time.get_ticks_msec()
	if now >= _drop_at:
		_drop_at = now + 1000
		drop.poll(now)
		if drop_line != null:
			drop_line.text = drop.status
			drop_line.modulate = Color(1.0, 0.45, 0.4) if drop.bad else Color.WHITE
		if drop.loaded != _drop_loaded:
			_drop_loaded = drop.loaded
			make_body()
			_fill_clips()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom / 1.1, ZOOM_MIN)
			_place_camera()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.1, ZOOM_MAX)
			_place_camera()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * ORBIT_RATE
		_pitch = clampf(_pitch + motion.relative.y * ORBIT_RATE, 5.0, 89.5)
		_place_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_1: set_view(0)
			KEY_2: set_view(1)
			KEY_3: set_view(2)
			KEY_SPACE: set_paused(not paused)
			KEY_PERIOD: step()
			KEY_R: drop.force()


func _say(words_said: String) -> void:
	if status != null:
		status.text = words_said


## The items that fit [param tags]' first match, sorted.
static func items_tagged(tags: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var all := Items.all()
	for id: String in all:
		var has: Array = (all[id] as Dictionary).get("tags", [])
		if tags.any(func(tag: String) -> bool: return tag in has):
			found.append(id)
	found.sort()
	return found


static func items_worn() -> Array[String]:
	var found: Array[String] = []
	var all := Items.all()
	for id: String in all:
		if not Items.armour_of(id).is_empty():
			found.append(id)
	found.sort()
	return found


## The panel on the left: each picker sets its value and makes the body or
## plays the clip again.
func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(32, 32)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(760, 0)  # In the HUD's 3840 x 2160 units.
	panel.add_child(column)
	var title := Label.new()
	title.text = "Character Lab"
	column.add_child(title)
	_ui["build"] = _picker(column, "Build", BUILDS.map(func(b: Array) -> String: return str(b[0])), func(i: int) -> void:
		body = i
		make_body())
	var line := LineEdit.new()
	line.text = words
	line.placeholder_text = "look words: seed=1 hair=long ..."
	line.text_submitted.connect(func(text: String) -> void:
		words = text
		make_body())
	column.add_child(line)
	var none: Array = ["(none)"]
	var holdable := items_tagged(HOLDS)
	_ui["right"] = _picker(column, "Right hand", none + holdable, func(i: int) -> void:
		held[0] = "" if i == 0 else holdable[i - 1]
		make_body())
	_ui["left"] = _picker(column, "Left hand", none + holdable, func(i: int) -> void:
		held[1] = "" if i == 0 else holdable[i - 1]
		make_body())
	var wearable := items_worn()
	_ui["worn"] = _picker(column, "Worn", none + wearable, func(i: int) -> void:
		worn = "" if i == 0 else wearable[i - 1]
		make_body())
	_ui["clip"] = _picker(column, "Clip", [], func(i: int) -> void:
		clip = str((_ui["clip"] as OptionButton).get_item_metadata(i))
		at = 0.0
		play())
	_ui["upper"] = _picker(column, "Upper body", [], func(i: int) -> void:
		upper = "" if i == 0 else str((_ui["upper"] as OptionButton).get_item_metadata(i))
		play())
	var speed_row := HBoxContainer.new()
	var speed_label := Label.new()
	speed_label.text = "Speed 1.00"
	speed_row.add_child(speed_label)
	var speed_slider := HSlider.new()
	speed_slider.min_value = 0.1
	speed_slider.max_value = 2.5
	speed_slider.step = 0.05
	speed_slider.value = 1.0
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_slider.value_changed.connect(func(value: float) -> void:
		speed_label.text = "Speed %.2f" % value
		set_speed(value))
	speed_row.add_child(speed_slider)
	column.add_child(speed_row)
	var scrubber := HSlider.new()
	scrubber.max_value = 1.0
	scrubber.step = 0.001
	scrubber.value_changed.connect(func(value: float) -> void: scrub(value * rig.length(clip)))
	column.add_child(scrubber)
	_ui["scrub"] = scrubber
	var buttons := HBoxContainer.new()
	var pause := Button.new()
	pause.text = "Pause (Space)"
	pause.pressed.connect(func() -> void: set_paused(not paused))
	buttons.add_child(pause)
	var frame := Button.new()
	frame.text = "Step (.)"
	frame.pressed.connect(step)
	buttons.add_child(frame)
	column.add_child(buttons)
	var mill := CheckBox.new()
	mill.text = "Treadmill"
	mill.toggled.connect(func(on: bool) -> void:
		treadmill = on
		run = 0.0)
	column.add_child(mill)
	var pace_label := Label.new()
	column.add_child(pace_label)
	_ui["pace"] = pace_label
	for which in 2:
		var row := HBoxContainer.new()
		var meter := Label.new()
		meter.autowrap_mode = TextServer.AUTOWRAP_WORD
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(meter)
		var use := Button.new()
		use.text = "Use measured"
		use.pressed.connect(func() -> void:
			var set_to := use_measured(which)
			_say("%s set to %.2f for this run (keep it in art/kit/feel.json)" % [gait_key(which), set_to] if set_to > 0.0
				else "nothing to set: not a gait, or no planted foot yet"))
		row.add_child(use)
		column.add_child(row)
		_ui["feet_a" if which == 0 else "feet_b"] = meter
	var versus := CheckBox.new()
	versus.text = "Compare (B beside A)"
	versus.toggled.connect(func(on: bool) -> void:
		compare = on
		make_body())
	column.add_child(versus)
	_ui["build_b"] = _picker(column, "B build", BUILDS.map(func(b: Array) -> String: return str(b[0])), func(i: int) -> void:
		body_b = i
		if compare:
			make_body())
	var line_b := LineEdit.new()
	line_b.text = words_b
	line_b.placeholder_text = "B's look words"
	line_b.text_submitted.connect(func(text: String) -> void:
		words_b = text
		if compare:
			make_body())
	column.add_child(line_b)
	_ui["source_b"] = _picker(column, "B is", ["the game's", "yours (the drop)"], func(i: int) -> void:
		own_b = i == 1
		if compare:
			make_body())
	var views := Label.new()
	views.text = "1 normal, 2 low, 3 overhead; drag orbits, wheel zooms"
	views.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(views)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(status)
	drop_line = Label.new()
	drop_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(drop_line)
	_fill_clips.call_deferred()


## The clip pickers filled once the first body's rig says what it has.
func _fill_clips() -> void:
	var clip_picker := _ui["clip"] as OptionButton
	var upper_picker := _ui["upper"] as OptionButton
	clip_picker.clear()
	upper_picker.clear()
	upper_picker.add_item("(none)")
	for each in clips():
		var shown: String = each + " (yours)" if each in drop.clip_names else each
		clip_picker.add_item(shown)
		clip_picker.set_item_metadata(clip_picker.item_count - 1, each)
		upper_picker.add_item(shown)
		upper_picker.set_item_metadata(upper_picker.item_count - 1, each)
		if each == clip:
			clip_picker.select(clip_picker.item_count - 1)


static func _picker(column: Container, label: String, items: Array, chosen: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	for item: String in items:
		picker.add_item(item)
	picker.item_selected.connect(chosen)
	row.add_child(picker)
	column.add_child(row)
	return picker
