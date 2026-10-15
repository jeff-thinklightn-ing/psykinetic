class_name WeatherView
extends Node3D
## What the weather looks like outdoors (decision 309): rain, fog drifting
## over the ground, the shadows of clouds, and the wind, which the fire,
## torch flames and scatter lean in (the `wind` global shader uniform,
## project.godot's shader_globals). Visual only: what the weather does in
## play is the sim's (Weather, Fields, decision 308). Client3D keeps one,
## eases it toward the zone's weather (World.fields.weather) every frame and
## moves it with the view; it is hidden indoors, and the rain stops on
## roofs (a heightfield the drops hide on).

## How fast the drawn weather follows the sim's (per second): the sim's
## already changes gradually; this only smooths its ticks.
const EASE := 2.0
## The rain: drops at most, the box they fall in round the view (x, z
## across, y high), their fall (m/s) and how far the wind slants it.
const RAIN_DROPS := 2400
const RAIN_BOX := Vector3(34.0, 0.0, 34.0)
const RAIN_HEIGHT := 16.0
const RAIN_SPEED := 22.0
const RAIN_SLANT := 0.45
const RAIN_COLOUR := Color(0.75, 0.8, 0.88, 0.35)
## The visual layer the rain is on, so the roof heightfield leaves it out.
const RAIN_LAYER := 1 << 19
## The fog's layers over the ground: their heights, and how much fog their
## noise needs to show (full fog fills them).
const FOG_LAYERS: Array[float] = [0.35, 1.0, 1.9]
const FOG_SIZE := 72.0
## The clouds' shadow: the noise's period (m), how dark at most, and how fast
## it drifts at full wind (m/s).
const CLOUD_PERIOD := 36.0
const CLOUD_DARK := 0.55
const CLOUD_DRIFT := 3.0
## What drifts fog and clouds even in still air (m/s).
const CALM_DRIFT := 0.4

const FOG_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 colour : source_color = vec3(0.7);
uniform float amount = 0.0;
uniform vec2 drift = vec2(0.0);
uniform float layer = 0.0;

varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 4; i++) {
		total += weight * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		weight *= 0.5;
	}
	return total;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (world.xz - drift) * 0.09 + vec2(layer * 3.7, layer * 1.3);
	float wisp = fbm(p + vec2(TIME * 0.02, -TIME * 0.015));
	// Thin fog shows as wisps; thick fills the layer.
	float edge = mix(0.85, 0.15, amount);
	ALBEDO = colour;
	ALPHA = smoothstep(edge, edge + 0.25, wisp) * amount * 0.45;
}
"""

const DROP_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.75, 0.8, 0.88, 0.35);

void fragment() {
	ALBEDO = colour.rgb;
	ALPHA = colour.a * (1.0 - abs(UV.x * 2.0 - 1.0));
}
"""

## The weather drawn now, eased (Weather.at's keys), and whether it is drawn.
var weather := {"cloud": 0.0, "rain": 0.0, "fog": 0.0, "wind": 0.0, "wind_dir": Vector2.RIGHT}
var outdoor := false
## How far fog and clouds have drifted (m, world xz).
var _drift := Vector2.ZERO
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _roofs: GPUParticlesCollisionHeightField3D
var _fog: Array[MeshInstance3D] = []
var _fog_material: Array[ShaderMaterial] = []
var _clouds: Decal


func _ready() -> void:
	name = "Weather"
	_build_rain()
	_build_fog()
	_build_clouds()
	set_outdoor(false)


## Shown outdoors only; indoors the wind is still.
func set_outdoor(value: bool) -> void:
	outdoor = value
	visible = value
	if _rain != null:
		_rain.emitting = false
	if not value:
		weather = {"cloud": 0.0, "rain": 0.0, "fog": 0.0, "wind": 0.0, "wind_dir": Vector2.RIGHT}
		RenderingServer.global_shader_parameter_set("wind", Vector4.ZERO)


## Eases toward [param target] (Weather.at's, or {} for none) over
## [param delta] seconds; true if anything drawn changed.
func ease_toward(target: Dictionary, delta: float) -> bool:
	if not outdoor:
		return false
	var changed := false
	var weight := 1.0 - exp(-EASE * delta)
	for key: String in ["cloud", "rain", "fog", "wind"]:
		var to := float(target.get(key, 0.0))
		var now: float = weather[key]
		var next := to if absf(to - now) < 0.001 else lerpf(now, to, weight)
		if next != now:
			weather[key] = next
			changed = true
	var way: Vector2 = target.get("wind_dir", weather["wind_dir"])
	weather["wind_dir"] = Vector2.from_angle(lerp_angle(weather["wind_dir"].angle(), way.angle(), weight))
	return changed


## Moves the weather with the view's [param target] (the ground point the
## camera looks at), lit by [param fog_colour] and [param daylight] (0..1:
## clouds cast shadows by day only); [param to_world] turns the level's
## directions into the view's.
func place(target: Vector3, delta: float, fog_colour: Color, daylight: float, to_world: Callable) -> void:
	if not outdoor:
		return
	var way3: Vector3 = to_world.call(Vector3(weather["wind_dir"].x, 0.0, weather["wind_dir"].y))
	var way := Vector2(way3.x, way3.z).normalized()
	var wind: float = weather["wind"]
	RenderingServer.global_shader_parameter_set("wind", Vector4(way.x, way.y, wind, 0.0))
	_drift += way * (CALM_DRIFT + CLOUD_DRIFT * wind) * delta
	# Rain: the box over the view, the drops slanted downwind.
	var rain: float = weather["rain"]
	_rain.emitting = rain > 0.02
	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	_rain.global_position = target + Vector3(0.0, RAIN_HEIGHT, 0.0)
	_rain_process.direction = Vector3(way.x * RAIN_SLANT * wind, -1.0, way.y * RAIN_SLANT * wind).normalized()
	# Fog: layers centred on the view, their noise drifting.
	var fog: float = weather["fog"]
	for i in _fog.size():
		_fog[i].visible = fog > 0.02
		_fog[i].global_position = Vector3(target.x, target.y + FOG_LAYERS[i], target.z)
		_fog_material[i].set_shader_parameter("amount", fog)
		_fog_material[i].set_shader_parameter("drift", _drift)
		_fog_material[i].set_shader_parameter("colour", fog_colour)
	# Clouds: strongest broken, none overcast or in fog, by day only. The
	# decal is two periods wide and jumps a period at a time, its texture
	# tiled, so the jump never shows.
	var cloud: float = weather["cloud"]
	var shade := cloud * (1.0 - smoothstep(0.75, 1.0, cloud)) * (1.0 - fog) * daylight
	_clouds.visible = shade > 0.01
	_clouds.modulate = Color(1.0, 1.0, 1.0, minf(1.0, shade * 2.0) * CLOUD_DARK)
	var offset := Vector2(fposmod(_drift.x, CLOUD_PERIOD), fposmod(_drift.y, CLOUD_PERIOD))
	var snap := Vector2(snappedf(target.x, CLOUD_PERIOD), snappedf(target.z, CLOUD_PERIOD))
	_clouds.global_position = Vector3(snap.x + offset.x, target.y + 12.0, snap.y + offset.y)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = RAIN_DROPS
	_rain.lifetime = (RAIN_HEIGHT + 4.0) / RAIN_SPEED
	_rain.preprocess = _rain.lifetime
	_rain.visibility_aabb = AABB(Vector3(-RAIN_BOX.x, -RAIN_HEIGHT - 6.0, -RAIN_BOX.z), Vector3(RAIN_BOX.x * 2.0, RAIN_HEIGHT + 8.0, RAIN_BOX.z * 2.0))
	_rain.local_coords = false
	_rain.layers = RAIN_LAYER
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.emission_box_extents = RAIN_BOX * 0.5
	_rain_process.direction = Vector3.DOWN
	_rain_process.spread = 0.0
	_rain_process.initial_velocity_min = RAIN_SPEED
	_rain_process.initial_velocity_max = RAIN_SPEED * 1.15
	_rain_process.gravity = Vector3.ZERO
	_rain_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = _rain_process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.55)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = DROP_SHADER
	material.shader = shader
	material.set_shader_parameter("colour", RAIN_COLOUR)
	streak.material = material
	_rain.draw_pass_1 = streak
	_rain.emitting = false
	add_child(_rain)
	# The roofs (and the ground) the drops stop on, seen from above round
	# the camera; redrawn only when the view moves on.
	_roofs = GPUParticlesCollisionHeightField3D.new()
	_roofs.name = "Roofs"
	_roofs.size = Vector3(RAIN_BOX.x + 8.0, 40.0, RAIN_BOX.z + 8.0)
	_roofs.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_roofs.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_roofs.follow_camera_enabled = true
	_roofs.heightfield_mask = 0xFFFFF & ~RAIN_LAYER
	add_child(_roofs)


func _build_fog() -> void:
	var shader := Shader.new()
	shader.code = FOG_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(FOG_SIZE, FOG_SIZE)
	for i in FOG_LAYERS.size():
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("layer", float(i))
		var layer := MeshInstance3D.new()
		layer.name = "Fog%d" % i
		layer.mesh = plane
		layer.material_override = material
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.layers = RAIN_LAYER
		layer.visible = false
		add_child(layer)
		_fog.append(layer)
		_fog_material.append(material)


func _build_clouds() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	noise.seed = 7
	var size := 128
	var tile := noise.get_seamless_image(size, size)
	# Two by two, so the decal can jump a period and look the same.
	var image := Image.create(size * 2, size * 2, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var shade := smoothstep(0.45, 0.62, tile.get_pixel(x, y).r)
			var colour := Color(0.0, 0.0, 0.0, shade)
			image.set_pixel(x, y, colour)
			image.set_pixel(x + size, y, colour)
			image.set_pixel(x, y + size, colour)
			image.set_pixel(x + size, y + size, colour)
	_clouds = Decal.new()
	_clouds.name = "CloudShadow"
	_clouds.size = Vector3(CLOUD_PERIOD * 2.0, 40.0, CLOUD_PERIOD * 2.0)
	_clouds.texture_albedo = ImageTexture.create_from_image(image)
	_clouds.albedo_mix = 1.0
	_clouds.upper_fade = 0.0
	_clouds.lower_fade = 0.0
	_clouds.visible = false
	add_child(_clouds)
