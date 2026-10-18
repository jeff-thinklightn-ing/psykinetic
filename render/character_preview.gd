class_name CharacterPreview
extends Panel
## The options panel's Character section's live look at the player's body
## (decision 439): their body as their look makes it (Client3D's human
## bodies, PersonLook), standing in its idle, turning slowly, in a
## SubViewport of its own world, framed as a slot box ("Inset"). It is drawn
## only while the panel shows (a SubViewport hidden is not rendered).

## Its size in the HUD's 3840 x 2160 units (ui: a face must read at 1080p).
const SIZE := Vector2(440, 640)
## How fast it turns (radians a second).
const TURN_SPEED := 0.5
## The camera: this far off, looking at this height, framing this many metres.
const CAMERA_DISTANCE := 4.0
const LOOK_AT := 0.95
const FRAME_HEIGHT := 2.2

var _view: SubViewport
var _turntable: Node3D
var _model: Node3D
var _body := &""


func _ready() -> void:
	theme_type_variation = &"Inset"
	custom_minimum_size = SIZE
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	container.add_child(_view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = FRAME_HEIGHT
	camera.position = Vector3(0.0, LOOK_AT, CAMERA_DISTANCE)
	_view.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	_view.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	_view.add_child(environment)
	_turntable = Node3D.new()
	_view.add_child(_turntable)


## Drawn as [param look] (PersonLook) on the [param body]'s model.
func show_look(look: PersonLook) -> void:
	if _model == null or look.body != _body:
		if _model != null:
			_model.queue_free()
		var model := Client3D.HUMAN_F if look.body == &"female" else Client3D.HUMAN
		_model = (load(model["scene"]) as PackedScene).instantiate() as Node3D
		_turntable.add_child(_model)
		_body = look.body
		var animator := AnimationPlayer.new()
		_model.add_child(animator)
		animator.root_node = NodePath("..")
		animator.add_animation_library("", load(model["clips"]) as AnimationLibrary)
		animator.play(Client3D.CLIP_IDLE)
		Client3D._dress(_model, Color.WHITE)
	look.apply(_model)
	_model.scale = Vector3.ONE * look.scale


func _process(delta: float) -> void:
	if is_visible_in_tree() and _turntable != null:
		_turntable.rotation.y += TURN_SPEED * delta
