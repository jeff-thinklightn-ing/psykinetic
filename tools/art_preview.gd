extends Node3D
## A slot on its own, as the game's camera sees it, kept up to date as its
## art is saved: the slot's art (its own, else its fill, else its grey box)
## on a 1 m grid, the slot's box outlined round it, the goblin (1.2 m)
## beside it for scale, its moving parts swinging through their range and
## its states shown in turn, and what ArtCheck says of it on screen. Saving
## the slot's .glb shows it again at once (read from disk, ArtKit.live);
## saving its .blend exports it through Blender first (BLENDER_PATH, else
## Steam's), then shows it.
##   godot --path . tools/art_preview.tscn -- --slot=door.single [--shot=<file.png>] [--shot-after=<seconds>]
## (--shot: save the window as a PNG --shot-after seconds after it opens,
## 1.2 by default, and quit.)
## Keys: Left/Right the slot before or after (every mesh slot, by name);
## Q/E turn the view a quarter; the wheel zooms (out no farther than the
## game's widest, Client3D.ZOOM_MAX); G the grey box or the art; Space
## stops or starts the parts; L day or torchlight.

const GOBLIN := "res://art/models/characters/goblin.glb"
const EXPORT_SCRIPT := "res://tools/blender/export_slot.py"
const STEAM_BLENDER := "C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe"
## Seconds a part takes to swing out and back; a state is shown this long.
const SWING_SECONDS := 3.0
const STATE_SECONDS := 2.0
## How often the slot's files are looked at for a change.
const WATCH_SECONDS := 0.5
const OUTLINE := Color(1.0, 0.8, 0.2)
const ERROR := Color(1.0, 0.45, 0.4)
const WARNING := Color(1.0, 0.85, 0.5)
const FITS := Color(0.6, 1.0, 0.6)

var _slots: Array[String] = []
var _index := 0
var _yaw := 45.0
var _zoom := 1.0
var _swinging := true
var _clock := 0.0
var _watch_clock := 0.0
var _stamps := {}
var _exporting := -1
var _piece: Node3D
## Each moving part's transform as made, to move it from.
var _rest := {}
var _outline: MeshInstance3D
var _goblin: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _torch: OmniLight3D
var _environment: Environment
var _text: RichTextLabel
var _shot := ""
var _shot_after := 1.2
var _alive := 0.0


func _ready() -> void:
	ArtKit.live = true
	for slot: String in ArtKit.slots():
		if str(ArtKit.spec(slot).get("type", "mesh")) == "mesh":
			_slots.append(slot)
	_slots.sort()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-after="):
			_shot_after = float(arg.trim_prefix("--shot-after="))
		if arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		if arg.begins_with("--slot="):
			var wanted := arg.trim_prefix("--slot=")
			if wanted in _slots:
				_index = _slots.find(wanted)
			else:
				push_error("art_preview: %s is not a mesh slot (%s)" % [wanted, ", ".join(_slots)])
	_build_world()
	_show()


func _build_world() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Client3D.SKY_HORIZON
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Client3D.DAY_AMBIENT
	_environment.ambient_light_energy = Client3D.DAY_AMBIENT_ENERGY
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Client3D.DAY_SUN
	_sun.light_energy = Client3D.DAY_SUN_ENERGY
	_sun.shadow_enabled = true
	_sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	add_child(_sun)
	_torch = OmniLight3D.new()
	_torch.light_color = Client3D.TORCH
	_torch.omni_range = 8.0
	_torch.light_energy = 2.0
	_torch.shadow_enabled = true
	_torch.position = Vector3(1.5, 1.6, 1.5)
	_torch.visible = false
	add_child(_torch)
	add_child(_grid())
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = Client3D.CAMERA_DISTANCE * 3.0
	add_child(_camera)
	_camera.current = true
	_goblin = (load(GOBLIN) as PackedScene).instantiate() as Node3D
	_goblin.rotation.y = PI * 0.5
	add_child(_goblin)
	_outline = MeshInstance3D.new()
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.albedo_color = OUTLINE
	lines.no_depth_test = true
	_outline.material_override = lines
	add_child(_outline)
	var hud := CanvasLayer.new()
	add_child(hud)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.position = Vector2(16, 12)
	_text.size = Vector2(2200, 0)
	_text.add_theme_font_size_override("normal_font_size", 36)
	_text.add_theme_font_size_override("bold_font_size", 44)
	_text.add_theme_constant_override("outline_size", 6)
	_text.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(_text)


## Lines a metre apart over the ground, ground plane under them.
func _grid() -> Node3D:
	var holder := Node3D.new()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Client3D.GROUND_COLOURS["stone"]
	earth.roughness = 1.0
	ground.material_override = earth
	ground.position.y = -0.005
	holder.add_child(ground)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-20, 21):
		mesh.surface_add_vertex(Vector3(i, 0, -20))
		mesh.surface_add_vertex(Vector3(i, 0, 20))
		mesh.surface_add_vertex(Vector3(-20, 0, i))
		mesh.surface_add_vertex(Vector3(20, 0, i))
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = mesh
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(0, 0, 0, 0.25)
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.material_override = ink
	holder.add_child(lines)
	return holder


## The selected slot again: its piece, outline, the goblin beside it, the
## camera on it, and what ArtCheck says.
func _show() -> void:
	var slot := _slots[_index]
	if _piece != null:
		_piece.free()
	_piece = ArtKit.instance(slot)
	add_child(_piece)
	_rest.clear()
	for part: Dictionary in ArtKit.spec(slot).get("parts", []):
		var node := _piece.get_node_or_null(NodePath(str(part["name"]))) as Node3D
		if node != null:
			_rest[node] = node.transform
	var size := ArtKit.size(slot)
	var kind := str(ArtKit.spec(slot).get("kind", "cell"))
	var low := Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	if kind == "floor":
		low.y = -size.y
	elif kind == "held":
		low = Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	_outline.mesh = _box_lines(AABB(low, size))
	_goblin.position = Vector3(-(size.x * 0.5 + 0.8), 0.0, size.z * 0.5 + 0.3)
	_stamps = _stamp(slot)
	_clock = 0.0
	_place_camera()
	_describe()


func _describe() -> void:
	var slot := _slots[_index]
	var entry := ArtKit.spec(slot)
	var drawn := {"own": "its own art", "fill": "its fill (%s)" % entry.get("fill", {}).get("from", "?"), "placeholder": "a grey box"}
	var lines: Array[String] = ["[b]%s[/b]  %d of %d   drawn from %s%s" % [
		slot, _index + 1, _slots.size(), "a grey box (G)" if ArtKit.show_placeholders else drawn[ArtKit.filled_by(slot)],
		"   [color=#%s]exporting the .blend...[/color]" % WARNING.to_html(false) if _exporting >= 0 else ""]]
	var size := ArtKit.size(slot)
	lines.append("%s piece, %.2f x %.2f x %.2f m, budget %s triangles. %s" % [
		entry.get("kind", "?"), size.x, size.y, size.z, int(entry.get("budget", 0)), str(entry.get("uses", ""))])
	if ArtKit.filled_by(slot) == "own":
		var problems := ArtCheck.check(slot)
		if problems.is_empty():
			lines.append("[color=#%s]fits its slot[/color]" % FITS.to_html(false))
		for problem in problems:
			lines.append("[color=#%s]%s[/color]" % [(ERROR if problem.begins_with("error") else WARNING).to_html(false), problem])
	else:
		lines.append("No art of its own yet: save it as %s%s.blend and run tools\\art_drop.ps1 on it; it shows here as it is saved." % [
			ProjectSettings.globalize_path(ArtKit.folder(slot)), slot])
	lines.append("[color=#bbbbbb]Left/Right slot   Q/E turn   wheel zoom   G grey box   Space parts   L torchlight[/color]")
	_text.text = "\n".join(lines)


func _process(delta: float) -> void:
	_clock += delta
	_alive += delta
	if _swinging:
		_move_parts()
	_show_state()
	if _shot != "" and _alive > _shot_after:
		var error := get_viewport().get_texture().get_image().save_png(_shot)
		print("art_preview: %s %s" % [_shot, "saved" if error == OK else error_string(error)])
		get_tree().quit()
		_shot = ""
	_watch_clock += delta
	if _watch_clock >= WATCH_SECONDS:
		_watch_clock = 0.0
		_watch()


## Each part through its range and back over SWING_SECONDS.
func _move_parts() -> void:
	var slot := _slots[_index]
	var share := 0.5 - 0.5 * cos(_clock / SWING_SECONDS * TAU)
	for part: Dictionary in ArtKit.spec(slot).get("parts", []):
		var node := _piece.get_node_or_null(NodePath(str(part["name"]))) as Node3D
		if node == null or not _rest.has(node):
			continue
		var rest: Transform3D = _rest[node]
		var reach: Array = part.get("range", [0, 90])
		var amount := lerpf(float(reach[0]), float(reach[1]), share)
		var axis := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}.get(str(part.get("axis", "y")), Vector3.UP) as Vector3
		if part.get("motion") == "slide":
			node.transform = rest.translated(axis * amount)
		else:
			node.transform = Transform3D(Basis(axis, deg_to_rad(amount)) * rest.basis, rest.origin)


## The slot's states in turn (none first), each STATE_SECONDS: a state's
## "state_<name>" nodes shown only in it.
func _show_state() -> void:
	var states: Array = ArtKit.spec(_slots[_index]).get("states", [])
	if states.is_empty():
		return
	var showing := int(_clock / STATE_SECONDS) % (states.size() + 1) - 1
	for node in _piece.find_children("state_*", "", true, false):
		(node as Node3D).visible = showing >= 0 and str(node.name) == "state_" + str(states[showing])


## The slot's files as they stand now: each file's time.
func _stamp(slot: String) -> Dictionary:
	var out := {}
	var folder := ArtKit.folder(slot)
	if DirAccess.dir_exists_absolute(folder):
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() in ["glb", "blend", "png"]:
				out[file] = FileAccess.get_modified_time(folder + file)
	return out


## A saved .blend is exported (once at a time); a changed .glb or .png is
## shown again.
func _watch() -> void:
	var slot := _slots[_index]
	if _exporting >= 0 and not OS.is_process_running(_exporting):
		_exporting = -1
		_describe()
	var now := _stamp(slot)
	if now == _stamps:
		return
	var folder := ArtKit.folder(slot)
	var shown := now.size() != _stamps.size()
	for file: String in now:
		if now[file] == _stamps.get(file, -1):
			continue
		if file.get_extension() == "blend":
			var glb := folder + file.get_basename() + ".glb"
			if FileAccess.get_modified_time(glb) < now[file]:
				_export(folder + file, glb)
		else:
			shown = true
	_stamps = now
	if shown:
		ArtKit.forget(slot)
		_show()


func _export(blend: String, glb: String) -> void:
	if _exporting >= 0:
		return
	var blender := OS.get_environment("BLENDER_PATH")
	if blender == "":
		blender = STEAM_BLENDER
	if not FileAccess.file_exists(blender):
		_text.text += "\n[color=#%s]no Blender at %s: set BLENDER_PATH[/color]" % [ERROR.to_html(false), blender]
		return
	_exporting = OS.create_process(blender, ["-b", ProjectSettings.globalize_path(blend), "--python",
		ProjectSettings.globalize_path(EXPORT_SCRIPT), "--", ProjectSettings.globalize_path(glb)])
	_describe()


func _place_camera() -> void:
	var slot := _slots[_index]
	var target := Vector3(0.0, ArtKit.size(slot).y * 0.4, 0.0)
	var tilt := deg_to_rad(Client3D.CAMERA_PITCH)
	var offset := Vector3(0.0, sin(tilt), cos(tilt)) * Client3D.CAMERA_DISTANCE
	_camera.position = target + offset.rotated(Vector3.UP, deg_to_rad(_yaw))
	_camera.look_at(target)
	_camera.size = Client3D.CAMERA_SIZE * _zoom


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_RIGHT:
				_index = (_index + 1) % _slots.size()
				_show()
			KEY_LEFT:
				_index = (_index - 1 + _slots.size()) % _slots.size()
				_show()
			KEY_Q:
				_yaw -= Client3D.ORBIT_STEP
				_place_camera()
			KEY_E:
				_yaw += Client3D.ORBIT_STEP
				_place_camera()
			KEY_G:
				ArtKit.show_placeholders = not ArtKit.show_placeholders
				_show()
			KEY_SPACE:
				_swinging = not _swinging
			KEY_L:
				_torch.visible = not _torch.visible
				_sun.visible = not _torch.visible
				_environment.ambient_light_color = Client3D.AMBIENT if _torch.visible else Client3D.DAY_AMBIENT
				_environment.background_color = Client3D.BACKGROUND if _torch.visible else Client3D.SKY_HORIZON
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom / Client3D.ZOOM_STEP, 0.2)
			_place_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * Client3D.ZOOM_STEP, Client3D.ZOOM_MAX)
			_place_camera()


func _box_lines(box: AABB) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 12:
		var edge := _edge(box, i)
		mesh.surface_add_vertex(edge[0])
		mesh.surface_add_vertex(edge[1])
	mesh.surface_end()
	return mesh


func _edge(box: AABB, i: int) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for c in 8:
		corners.append(box.position + box.size * Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1))
	var pairs := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	return [corners[pairs[i][0]], corners[pairs[i][1]]]
