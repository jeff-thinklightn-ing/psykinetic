extends SceneTree
## A sheet of models in poses: a row a model, a column a clip, each caught
## the given way through it, seen from in front and a little to one side
## with an orthographic camera, saved as a PNG. For checking a rig (does
## every clip pose it sensibly?) and showing bodies side by side.
##
## Needs a window (it renders): not --headless.
##   godot --path . -s res://tools/body_sheet.gd -- <out.png>[@<pixels>[@<cell>]] <clips.res> \
##       <model.glb>[@<blend>[@<yaw>]] [<model.glb>... ...] [-- <clip>[@<t>] ...]
## <clips.res> "self" plays each model's own clips. A model may be given as
## <model.glb>@<blend>@<yaw degrees> to turn it (e.g. a creature side on:
## model.glb@@90); a fourth field "srgb" reads its vertex colours as sRGB (glTF's
## are linear: a file that wrote sRGB values as they are). <blend> sets a model's "lean"/"heavy" shape keys (-1 lean .. 1 heavy),
## or is a look, <name>=<value> joined by "+": any shape key by name (0..1), "scale"
## (the whole model's, a stature), and a built body's part colours by name (skin, hair,
## tunic, trousers; hex without "#"), and "parts", the generator's parts it wears joined by
## "," (tools/body_gen.py's WEARABLES; the rest hidden, "parts=" for none), e.g.
## heavy=0.6+old=1+scale=0.94+hair=b0b0b0+parts=Hair_Cropped,Beard_Full; "paint" a painted
## body's material (decision 529, a res:// path) and "mark" one of its marks
## (0 scar, 1 stripes, 2 hand), e.g. paint=res://art/models/characters/orc_body.tres+mark=2;
## <t> is how far through the clip (0..1, default 0.3); <pixels> a cell's
## width (default PIXELS); <cell> the metres between models (default CELL; 0.5 for a rabbit). "rest" is the rest pose. Clips default to: rest Idle Walk@0.25 Jog_Fwd@0.25 Sprint@0.3
## Sword_Attack@0.45 Hit_Chest@0.3 Death01@1.

const DEFAULT_CLIPS := ["rest", "Idle", "Walk@0.25", "Jog_Fwd@0.25", "Sprint@0.3", "Sword_Attack@0.45",
	"Hit_Chest@0.3", "Death01@1"]
const CELL := 2.2  # Metres between models in a row and between rows, by default.
const PIXELS := 220  # A cell's width in the image, by default.

var _out := ""
var _cell := CELL
var _frames := 0
## Drawn here, at the sheet's own size (a window may not be as big).
var _view: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var split := args.find("--")
	var models: Array = args.slice(2, split if split >= 0 else args.size())
	var clips: Array = args.slice(split + 1) if split >= 0 else DEFAULT_CLIPS
	if args.size() < 3 or models.is_empty():
		print("usage: -s res://tools/body_sheet.gd -- <out.png> <clips.res> <model.glb>[@blend] ... [-- <clip>[@t] ...]")
		quit(1)
		return
	var out := str(args[0]).split("@")
	_out = out[0]
	var pixels := int(out[1]) if out.size() > 1 and out[1] != "" else PIXELS
	_cell = float(out[2]) if out.size() > 2 else CELL
	# "self": each model plays its own clips (a creature's, from its .glb).
	var library := load(args[1]) as AnimationLibrary if args[1] != "self" else null
	_view = SubViewport.new()
	_view.size = Vector2i(pixels * clips.size(), pixels * models.size())
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var tallest := 0.0
	for row in models.size():
		var spec := str(models[row]).split("@")
		for column in clips.size():
			var model := (load(spec[0]) as PackedScene).instantiate() as Node3D
			model.position = Vector3(column * _cell, -row * _cell, 0.0)
			_view.add_child(model)
			var look := spec.size() > 1 and spec[1].contains("=")
			if spec.size() > 1 and spec[1] != "" and not look:
				_blend(model, float(spec[1]))
			if spec.size() > 2:
				model.rotation.y = deg_to_rad(float(spec[2]))
			_palette(model, spec.size() > 3 and spec[3] == "srgb")
			if look:
				_look(model, spec[1])
			var clip := str(clips[column]).split("@")
			if clip[0] != "rest":
				var animator: AnimationPlayer
				if library == null:
					animator = model.find_children("*", "AnimationPlayer", true, false)[0]
				else:
					animator = AnimationPlayer.new()
					model.add_child(animator)
					animator.root_node = NodePath("..")
					animator.add_animation_library("", library)
				animator.play(clip[0])
				var length := animator.get_animation(clip[0]).length
				animator.seek(length * (float(clip[1]) if clip.size() > 1 else 0.3), true)
				animator.pause()
			tallest = maxf(tallest, _height(model))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _cell * models.size()
	var middle := Vector3((clips.size() - 1) * _cell * 0.5, -(models.size() - 1) * _cell * 0.5 + tallest * 0.5, 0.0)
	_view.add_child(camera)
	camera.look_at_from_position(middle + Vector3(3.0, 1.5, 8.0) * _cell / CELL, middle)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	_view.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.78, 0.76, 0.72)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.55)
	_view.add_child(environment)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:  # A few frames, so the poses and shadows have settled.
		_view.get_texture().get_image().save_png(_out)
		print("wrote %s" % _out)
		quit()
	return false


## A surface whose material is named "palette" drawn with art-kit's palette, as the
## game's drop-in does; one named "human" with the bodies' material, as the game
## draws them; one named "VertexColour" by its vertex colours.
func _palette(model: Node3D, srgb := false) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(i)
			if material != null and material.resource_name == "palette":
				mesh.set_surface_override_material(i, load("res://art/kit/palette.tres"))
			elif material != null and material.resource_name == "human":
				# A built body (tools/body_build.py): the game's one material, its own colours.
				mesh.material_override = load("res://art/models/characters/human_body.tres")
				var own: Dictionary = mesh.get_meta("extras", {})
				for part: String in own:
					mesh.set_instance_shader_parameter(part, Color(str(own[part])))
			elif material != null and material.resource_name == "VertexColour":
				# The mesh's own colours (tools/body_build.py --vertex-colours), matte.
				var own := StandardMaterial3D.new()
				own.vertex_color_use_as_albedo = true
				own.vertex_color_is_srgb = srgb  # glTF's are linear; "@srgb" for a file that wrote sRGB.
				own.roughness = 1.0
				mesh.set_surface_override_material(i, own)


func _blend(model: Node3D, value: float) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var shapes := mesh.mesh as ArrayMesh
		for i in shapes.get_blend_shape_count():
			match shapes.get_blend_shape_name(i):
				&"lean":
					mesh.set_blend_shape_value(i, maxf(-value, 0.0))
				&"heavy":
					mesh.set_blend_shape_value(i, maxf(value, 0.0))


## A look ("name=value+..."; see the usage): shape keys, scale, part colours.
func _look(model: Node3D, look: String) -> void:
	for pair in look.split("+"):
		var field := pair.split("=")
		if field[0] == "scale":
			model.scale = Vector3.ONE * float(field[1])
			continue
		if field[0] == "paint":
			# A painted body's material (decision 529: e.g. orc_body.tres), unvaried, on its skin as
			# the game draws it (parts on art-kit's palette in the palette).
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				# (Client3D._paint_skin's way: this script runs without the game's autoloads.)
				for surface in mesh.mesh.get_surface_count():
					var own := mesh.mesh.surface_get_material(surface)
					var palette := own != null and own.resource_name == "palette"
					mesh.set_surface_override_material(surface, load("res://art/kit/palette.tres") if palette else load(field[1]) as Material)
				mesh.set_instance_shader_parameter("skin", Vector3(0.0, 1.0, 1.0))
				mesh.set_instance_shader_parameter("gear", Color(1.0, 1.0, 1.0, 0.0))
				mesh.set_instance_shader_parameter("mark", Vector3.ZERO)
			continue
		if field[0] == "mark":
			# Its mark (0 the scar, 1 the stripes, 2 the hand; after "paint").
			var mark := Vector3.ZERO
			mark[int(field[1])] = 1.0
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				mesh.set_instance_shader_parameter("mark", mark)
			continue
		if field[0] == "parts":
			var worn := field[1].split(",", false)
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				mesh.visible = mesh.name == "Body" or mesh.name in worn
			continue
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if field[0] in ["skin", "hair", "tunic", "trousers"]:
				mesh.set_instance_shader_parameter(field[0], Color(field[1]))
				continue
			var shapes := mesh.mesh as ArrayMesh
			for i in shapes.get_blend_shape_count():
				if shapes.get_blend_shape_name(i) == StringName(field[0]):
					mesh.set_blend_shape_value(i, float(field[1]))


func _height(model: Node3D) -> float:
	var top := 0.0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, mesh.get_aabb().end.y)
	return top
