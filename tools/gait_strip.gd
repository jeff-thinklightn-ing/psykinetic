extends SceneTree
## A gait seen side on as the game moves it: one row a gait, the model drawn
## at moments through one cycle, each where the game would have moved it by
## then (the speed given) and posed where its clip is at that moment (played
## at speed over pace, as Client3D does), over a ground marked every half
## metre. A planted foot stays on one spot from copy to copy; one that slides
## smears along the ground. For judging a gait's pace (tools/gait_pace.gd)
## and stride by eye, and for showing them.
##
## Needs a window (it renders): not --headless.
##   godot --path . -s res://tools/gait_strip.gd -- <out.png> <clips.res> <model.glb> \
##       <clip>@<pace>@<speed> [...]
## e.g. Jog_Short@2.66@4: the clip Jog_Short, whose pace is 2.66 m/s, moved
## at 4 m/s (a player's 4 tiles a second).

const COPIES := 9
const ROW := 2.4  # Metres between rows.
const PIXELS_PER_M := 160

var _out := ""
var _frames := 0
var _view: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -s res://tools/gait_strip.gd -- <out.png> <clips.res> <model.glb> <clip>@<pace>@<speed> ...")
		quit(1)
		return
	_out = args[0]
	var library := load(args[1]) as AnimationLibrary
	var scene := load(args[2]) as PackedScene
	var gaits := args.slice(3)
	_view = SubViewport.new()
	var widest := 0.0
	var rows: Array = []
	for row in gaits.size():
		var spec := str(gaits[row]).split("@")
		var clip := library.get_animation(spec[0])
		var pace := float(spec[1])
		var speed := float(spec[2])
		var rate := speed / pace
		var cycle := clip.length / rate  # Seconds of play a cycle takes at that speed.
		rows.append([spec[0], clip, rate, cycle, speed])
		widest = maxf(widest, speed * cycle + 1.0)
	_view.size = Vector2i(int((widest + 1.0) * PIXELS_PER_M), int(gaits.size() * ROW * PIXELS_PER_M))
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	for row in rows.size():
		var clip_name: String = rows[row][0]
		var rate: float = rows[row][2]
		var cycle: float = rows[row][3]
		var speed: float = rows[row][4]
		var y := -row * ROW
		_ground(y, widest)
		for i in COPIES:
			var t := cycle * i / (COPIES - 1)
			var model := scene.instantiate() as Node3D
			model.position = Vector3(speed * t, y, 0.0)
			model.rotation.y = PI * 0.5  # Its front (+z as modelled) toward +x: walking right.
			_view.add_child(model)
			_dress(model)
			var animator := AnimationPlayer.new()
			model.add_child(animator)
			animator.root_node = NodePath("..")
			animator.add_animation_library("", library)
			animator.play(clip_name)
			animator.seek(fmod(t * rate, (rows[row][1] as Animation).length), true)
			animator.pause()
			# Copies fade from first to last, so one can tell them apart.
			_fade(model, 0.35 + 0.65 * float(i) / (COPIES - 1))
		print("%s: plays at %.2fx, a cycle %.2f s, %.2f m, a step %.2f m" % [clip_name, rate, cycle, speed * cycle, speed * cycle * 0.5])
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = rows.size() * ROW
	var middle := Vector3((widest - 1.0) * 0.5, -(rows.size() - 1) * ROW * 0.5 + 0.9, 0.0)
	_view.add_child(camera)
	camera.look_at_from_position(middle + Vector3(0.0, 0.0, 10.0), middle)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	_view.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.86, 0.85, 0.82)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.55)
	_view.add_child(environment)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_view.get_texture().get_image().save_png(_out)
		print("wrote %s" % _out)
		quit()
	return false


## The ground: a strip at the feet, marked dark every half metre.
func _ground(y: float, length: float) -> void:
	for i in int(length / 0.5) + 2:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.03, 0.05)
		mark.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.25, 0.25) if i % 2 == 0 else Color(0.6, 0.6, 0.6)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark.material_override = material
		mark.position = Vector3(i * 0.5 - 0.25, y - 0.015, 0.4)
		_view.add_child(mark)


## A human body (tools/body_build.py's "human" material) drawn as the game draws it.
func _dress(model: Node3D) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var own := mesh.mesh.surface_get_material(0)
		if own != null and own.resource_name == "human":
			mesh.material_override = load("res://art/models/characters/human_body.tres")
			var parts: Dictionary = mesh.get_meta("extras", {})
			for part: String in parts:
				mesh.set_instance_shader_parameter(part, Color(str(parts[part])))


func _fade(model: Node3D, alpha: float) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.transparency = 1.0 - alpha
