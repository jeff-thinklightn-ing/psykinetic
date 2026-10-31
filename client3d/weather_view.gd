class_name WeatherView
extends Node3D
## What the weather looks like outdoors (decision 309): rain (and in the
## cold snow, decision 362), fog drifting
## over the ground, the shadows of clouds, and the wind, which the fire,
## torch flames and scatter lean in (the `wind` global shader uniform,
## project.godot's shader_globals; and the season's `season` uniform:
## x green, y turn, z snow cover, for terrain and scatter). Visual only: what the weather does in
## play is the sim's (Weather, Fields, decision 308). Client3D keeps one,
## eases it toward the zone's weather (World.fields.weather) every frame and
## moves it with the view; it is hidden indoors, and the rain stops on
## roofs (a heightfield the drops hide on).
## Under a forest's canopy (decision 477, set_canopy) the crowns take the
## rain and snow: what falls is thinned by the cover round the view, the
## canopy drips instead (Weather.drip_at), the low fog lies thicker and
## the clouds' shadows fade.

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
## Snow: flakes at most, their fall (m/s), how far the wind carries them.
const SNOW_FLAKES := 1800
const SNOW_SPEED := 2.2
const SNOW_DRIFT := 1.6
const SNOW_COLOUR := Color(0.95, 0.97, 1.0, 0.85)
## Under a canopy: the snow its crowns let through at full cover, how much
## thicker the low fog lies there, and the drips (drops at most, the box
## they fall from, centred DRIP_HEIGHT up, their fall in m/s).
const CANOPY_SNOW := 0.3
const CANOPY_FOG := 0.6
const DRIPS := 260
const DRIP_BOX := Vector3(24.0, 4.0, 24.0)
const DRIP_HEIGHT := 4.5
const DRIP_SPEED := 8.0
const DRIP_COLOUR := Color(0.78, 0.84, 0.9, 0.5)
## The visual layer the rain is on, so the roof heightfield leaves it out.
const RAIN_LAYER := 1 << 19
## The fog's layers over the ground: their heights, and how much fog their
## noise needs to show (full fog fills them).
const FOG_LAYERS: Array[float] = [0.35, 1.0, 1.9]
const FOG_SIZE := 72.0
## The clouds' shadow: the noise's period (m), the periods its decal spans
## (odd, so the view stays a period from its edge), how dark at most (0.55
## until decision 534), and how fast it drifts at full wind (m/s).
const CLOUD_PERIOD := 36.0
const CLOUD_TILES := 3
const CLOUD_DARK := 0.3
const CLOUD_DRIFT := 3.0
## Under the low camera (623, environment's side; set_view): the rain and
## snow fall in a LOW_BOX (across, -, deep) from the camera out along the
## view, their drops LOW_DROPS times as many at most; the fog's layers
## LOW_FOG_WIDE times as wide, centred LOW_FOG_AHEAD of FOG_SIZE ahead of
## the aim and faded to their rims; the clouds' decal LOW_CLOUD_TILES
## periods wide, its edge out where the haze has the land (not Decal's
## distance fade: it dims the whole decal by its centre's distance, so every
## cloud shadow near the view would fade with it).
const LOW_BOX := Vector3(34.0, 0.0, 70.0)
const LOW_DROPS := 1.5
const LOW_FOG_WIDE := 3.0
const LOW_FOG_AHEAD := 0.75
const LOW_CLOUD_TILES := 9
## Under the low camera zoomed in (623 amended (2), environment's side) the
## eye is barely over the fog's layers (1.7 m at 8 off and 12 degrees): a
## layer fades out as the eye comes within FOG_EYE_CLEAR (m) above it and is
## gone at or over the eye, so the fog lies under the camera, never a
## ceiling over it or a stripe seen edge on.
const FOG_EYE_CLEAR := 1.0
## What drifts fog and clouds even in still air (m/s).
const CALM_DRIFT := 0.4

const FOG_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 colour : source_color = vec3(0.7);
uniform float amount = 0.0;
uniform vec2 drift = vec2(0.0);
uniform float layer = 0.0;
// Faded to the rim under the low camera (rim 1), whole in ortho (0).
uniform float rim = 0.0;
uniform float half_size = 36.0;
// How much of the layer shows for the eye's height over it (fog_eye_fade).
uniform float shown = 1.0;

varying vec3 world;
varying vec2 local;

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
	local = VERTEX.xz;
}

void fragment() {
	vec2 p = (world.xz - drift) * 0.09 + vec2(layer * 3.7, layer * 1.3);
	float wisp = fbm(p + vec2(TIME * 0.02, -TIME * 0.015));
	// Thin fog shows as wisps; thick fills the layer.
	float edge = mix(0.85, 0.15, amount);
	ALBEDO = colour;
	ALPHA = smoothstep(edge, edge + 0.25, wisp) * amount * 0.45;
	ALPHA *= (1.0 - rim * smoothstep(0.6, 1.0, length(local) / half_size)) * shown;
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

const FLAKE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.95, 0.97, 1.0, 0.85);

void fragment() {
	float round_ = 1.0 - smoothstep(0.25, 0.5, length(UV - 0.5));
	ALBEDO = colour.rgb;
	ALPHA = colour.a * round_;
}
"""

## The weather drawn now, eased (Weather.at's keys), and whether it is drawn.
var weather := {"cloud": 0.0, "rain": 0.0, "snow": 0.0, "fog": 0.0, "wind": 0.0, "wind_dir": Vector2.RIGHT}
var outdoor := false
## The canopy's cover round the view (0..1) and its drips now (set_canopy).
var canopy := 0.0
var drip := 0.0
## How far fog and clouds have drifted (m, world xz).
var _drift := Vector2.ZERO
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _snow: GPUParticles3D
var _snow_process: ParticleProcessMaterial
var _drips: GPUParticles3D
var _roofs: GPUParticlesCollisionHeightField3D
var _fog: Array[MeshInstance3D] = []
var _fog_material: Array[ShaderMaterial] = []
var _clouds: Decal
## The low camera's view (set_view): on, the camera's place, and the way it
## looks along the ground (unit, world xz).
var low := false
var _camera_at := Vector3.ZERO
var _ahead := Vector2(0.0, -1.0)
## The fog's planes, ortho's and the low camera's; the clouds' one tile
## and its decal textures by tiles across.
var _fog_planes: Array[PlaneMesh] = []
var _cloud_tile: Image
var _cloud_textures: Dictionary[int, ImageTexture] = {}
## The sky's clouds' noise (sky_noise), built once.
var _sky_noise: ImageTexture


func _ready() -> void:
	name = "Weather"
	_build_rain()
	_build_snow()
	_build_drips()
	_build_fog()
	_build_clouds()
	set_outdoor(false)


## Shown outdoors only; indoors the wind is still.
func set_outdoor(value: bool) -> void:
	outdoor = value
	visible = value
	if _rain != null:
		_rain.emitting = false
		_snow.emitting = false
		_drips.emitting = false
	if not value:
		canopy = 0.0
		drip = 0.0
		weather = {"cloud": 0.0, "rain": 0.0, "snow": 0.0, "fog": 0.0, "wind": 0.0, "wind_dir": Vector2.RIGHT}
		RenderingServer.global_shader_parameter_set("wind", Vector4.ZERO)
		RenderingServer.global_shader_parameter_set("season", Vector4(1.0, 0.0, 0.0, 0.0))


## The view the weather is drawn for (623, environment's side): the low
## camera [param is_low] or ortho, the [param camera]'s place and the way
## it looks along the ground ([param ahead], world xz). Turning the low
## camera on or off sizes the rain, snow, fog and clouds for it; off, all is
## as ortho always drew it.
func set_view(is_low: bool, camera: Vector3, ahead: Vector2) -> void:
	_camera_at = camera
	if ahead.length_squared() > 0.0001:
		_ahead = ahead.normalized()
	if is_low == low:
		return
	low = is_low
	var box := LOW_BOX if low else RAIN_BOX
	var drops := LOW_DROPS if low else 1.0
	_rain.amount = roundi(RAIN_DROPS * drops)
	_snow.amount = roundi(SNOW_FLAKES * drops)
	_rain_process.emission_box_extents = box * 0.5
	_snow_process.emission_box_extents = box * 0.5
	_rain.visibility_aabb = AABB(Vector3(-box.x, -RAIN_HEIGHT - 6.0, -box.z), Vector3(box.x * 2.0, RAIN_HEIGHT + 8.0, box.z * 2.0))
	_snow.visibility_aabb = AABB(Vector3(-box.x, -RAIN_HEIGHT, -box.z), Vector3(box.x * 2.0, RAIN_HEIGHT + 4.0, box.z * 2.0))
	# The roofs round the box, turned any way along the view, not the camera.
	_roofs.follow_camera_enabled = not low
	_roofs.size = Vector3(LOW_BOX.z + 8.0, 40.0, LOW_BOX.z + 8.0) if low else Vector3(RAIN_BOX.x + 8.0, 40.0, RAIN_BOX.z + 8.0)
	_roofs.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512 if low else GPUParticlesCollisionHeightField3D.RESOLUTION_256
	var plane := _fog_planes[1 if low else 0]
	for i in _fog.size():
		_fog[i].mesh = plane
		_fog_material[i].set_shader_parameter("rim", 1.0 if low else 0.0)
		_fog_material[i].set_shader_parameter("half_size", plane.size.x * 0.5)
	var tiles := LOW_CLOUD_TILES if low else CLOUD_TILES
	_clouds.texture_albedo = _cloud_texture(tiles)
	_clouds.size = Vector3(CLOUD_PERIOD * tiles, 40.0, CLOUD_PERIOD * tiles)


## How much of a fog layer shows with the eye [param clearance] (m) over it
## under the low camera: none at or under it, all from FOG_EYE_CLEAR up.
static func fog_eye_fade(clearance: float) -> float:
	return smoothstep(0.0, FOG_EYE_CLEAR, clearance)


## The season's land for terrain and scatter (Season.at's green, turn and
## snow), outdoors only.
func set_season(season: Dictionary) -> void:
	if outdoor:
		RenderingServer.global_shader_parameter_set("season",
				Vector4(season.get("green", 1.0), season.get("turn", 0.0), season.get("snow", 0.0), 0.0))


## The canopy's [param cover] round the view and its [param drips]
## (Weather.drip_at), both 0..1; drawn by place.
func set_canopy(cover: float, drips: float) -> void:
	canopy = clampf(cover, 0.0, 1.0)
	drip = clampf(drips, 0.0, 1.0)


## Eases toward [param target] (Weather.at's, or {} for none) over
## [param delta] seconds; true if anything drawn changed.
func ease_toward(target: Dictionary, delta: float) -> bool:
	if not outdoor:
		return false
	var changed := false
	var weight := 1.0 - exp(-EASE * delta)
	for key: String in ["cloud", "rain", "snow", "fog", "wind"]:
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
	# Under the low camera the rain's and snow's box runs from the camera out
	# along the view (its z), the roofs' heightfield over it; in ortho, over
	# the aim.
	var frame := Basis.IDENTITY
	var over := target
	if low:
		frame = Basis(Vector3.UP, atan2(_ahead.x, _ahead.y))
		over = Vector3(_camera_at.x + _ahead.x * LOW_BOX.z * 0.5, target.y, _camera_at.z + _ahead.y * LOW_BOX.z * 0.5)
		_roofs.global_position = over
	# Rain: the box over the view, the drops slanted downwind.
	var rain: float = weather["rain"]
	var through := rain * (1.0 - canopy)
	_rain.emitting = through > 0.02
	_rain.amount_ratio = clampf(through, 0.0, 1.0)
	_rain.global_transform = Transform3D(frame, over + Vector3(0.0, RAIN_HEIGHT, 0.0))
	_rain_process.direction = frame.inverse() * Vector3(way.x * RAIN_SLANT * wind, -1.0, way.y * RAIN_SLANT * wind).normalized()
	# Snow: slow flakes, carried by the wind.
	var snow: float = weather["snow"]
	snow *= lerpf(1.0, CANOPY_SNOW, canopy)
	_snow.emitting = snow > 0.02
	_snow.amount_ratio = clampf(snow, 0.0, 1.0)
	_snow.global_transform = Transform3D(frame, over + Vector3(0.0, RAIN_HEIGHT * 0.6, 0.0))
	_snow_process.gravity = Vector3(way.x * SNOW_DRIFT * wind, -0.3, way.y * SNOW_DRIFT * wind)
	# Drips: big slow drops from under the crowns, straight down.
	_drips.emitting = drip > 0.02
	_drips.amount_ratio = drip
	_drips.global_position = target + Vector3(0.0, DRIP_HEIGHT, 0.0)
	# Fog: layers centred on the view (under the low camera, ahead of the
	# aim), their noise drifting.
	var fog: float = minf(weather["fog"] * (1.0 + CANOPY_FOG * canopy), 1.0)
	var middle_at := target
	if low:
		middle_at += Vector3(_ahead.x, 0.0, _ahead.y) * FOG_SIZE * LOW_FOG_AHEAD
	for i in _fog.size():
		var height := target.y + FOG_LAYERS[i]
		var shown := fog_eye_fade(_camera_at.y - height) if low else 1.0
		_fog[i].visible = fog > 0.02 and shown > 0.01
		_fog[i].global_position = Vector3(middle_at.x, height, middle_at.z)
		_fog_material[i].set_shader_parameter("shown", shown)
		_fog_material[i].set_shader_parameter("amount", fog)
		_fog_material[i].set_shader_parameter("drift", _drift)
		_fog_material[i].set_shader_parameter("colour", fog_colour)
	# Clouds: strongest broken, none overcast or in fog, by day only. The
	# decal is CLOUD_TILES periods wide, its texture tiled, and drifts with
	# the wind; it jumps a whole period at a time to keep the view within
	# half a period of its middle, so its edge is never on screen and the
	# jump never shows.
	var cloud: float = weather["cloud"]
	var shade := cloud * (1.0 - smoothstep(0.75, 1.0, cloud)) * (1.0 - fog) * daylight * (1.0 - canopy)
	_clouds.visible = shade > 0.01
	_clouds.modulate = Color(1.0, 1.0, 1.0, minf(1.0, shade * 2.0) * CLOUD_DARK)
	var middle := cloud_middle(Vector2(target.x, target.z), _drift)
	_clouds.global_position = Vector3(middle.x, target.y + 12.0, middle.y)


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


func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = SNOW_FLAKES
	_snow.lifetime = (RAIN_HEIGHT * 0.6 + 3.0) / SNOW_SPEED
	_snow.preprocess = _snow.lifetime
	_snow.visibility_aabb = AABB(Vector3(-RAIN_BOX.x, -RAIN_HEIGHT, -RAIN_BOX.z), Vector3(RAIN_BOX.x * 2.0, RAIN_HEIGHT + 4.0, RAIN_BOX.z * 2.0))
	_snow.local_coords = false
	_snow.layers = RAIN_LAYER
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	_snow_process = ParticleProcessMaterial.new()
	_snow_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_process.emission_box_extents = RAIN_BOX * 0.5
	_snow_process.direction = Vector3.DOWN
	_snow_process.spread = 10.0
	_snow_process.initial_velocity_min = SNOW_SPEED * 0.8
	_snow_process.initial_velocity_max = SNOW_SPEED * 1.2
	_snow_process.gravity = Vector3(0.0, -0.3, 0.0)
	_snow_process.turbulence_enabled = true
	_snow_process.turbulence_noise_strength = 0.6
	_snow_process.turbulence_noise_scale = 4.0
	_snow_process.scale_min = 0.6
	_snow_process.scale_max = 1.3
	_snow_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = _snow_process
	var flake := QuadMesh.new()
	flake.size = Vector2(0.07, 0.07)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FLAKE_SHADER
	material.shader = shader
	material.set_shader_parameter("colour", SNOW_COLOUR)
	flake.material = material
	_snow.draw_pass_1 = flake
	_snow.emitting = false
	add_child(_snow)


## The canopy's drips: a few big drops falling from under the crowns,
## in the box over the view; they start under the crowns (the rain's
## heightfield would hide them at once), so they pass through nothing and
## live just long enough to reach the ground.
func _build_drips() -> void:
	_drips = GPUParticles3D.new()
	_drips.name = "Drips"
	_drips.amount = DRIPS
	_drips.lifetime = (DRIP_HEIGHT + DRIP_BOX.y * 0.5) / (DRIP_SPEED * 0.6)
	_drips.preprocess = _drips.lifetime
	_drips.visibility_aabb = AABB(Vector3(-DRIP_BOX.x, -DRIP_HEIGHT - 4.0, -DRIP_BOX.z), Vector3(DRIP_BOX.x * 2.0, DRIP_HEIGHT + 8.0, DRIP_BOX.z * 2.0))
	_drips.local_coords = false
	_drips.layers = RAIN_LAYER
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drips.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = DRIP_BOX * 0.5
	process.direction = Vector3.DOWN
	process.spread = 0.0
	process.initial_velocity_min = DRIP_SPEED * 0.6
	process.initial_velocity_max = DRIP_SPEED
	process.gravity = Vector3(0.0, -4.0, 0.0)
	_drips.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(0.04, 0.22)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = DROP_SHADER
	material.shader = shader
	material.set_shader_parameter("colour", DRIP_COLOUR)
	drop.material = material
	_drips.draw_pass_1 = drop
	_drips.emitting = false
	add_child(_drips)


func _build_fog() -> void:
	var shader := Shader.new()
	shader.code = FOG_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(FOG_SIZE, FOG_SIZE)
	var wide := PlaneMesh.new()
	wide.size = plane.size * LOW_FOG_WIDE
	_fog_planes = [plane, wide]
	for i in FOG_LAYERS.size():
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("layer", float(i))
		material.set_shader_parameter("half_size", FOG_SIZE * 0.5)
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


## The clouds' decal texture [param tiles] periods across (made once a
## size): the tile repeated tiles by tiles, so the decal can jump a period
## and look the same.
func _cloud_texture(tiles: int) -> ImageTexture:
	if not _cloud_textures.has(tiles):
		var size := _cloud_tile.get_width()
		var image := Image.create(size * tiles, size * tiles, false, Image.FORMAT_RGBA8)
		for ty in tiles:
			for tx in tiles:
				image.blit_rect(_cloud_tile, Rect2i(0, 0, size, size), Vector2i(size * tx, size * ty))
		_cloud_textures[tiles] = ImageTexture.create_from_image(image)
	return _cloud_textures[tiles]


## The clouds' noise for the sky's cloud layer (decision 744): the shadows'
## own (_build_clouds' seamless Perlin, same seed and frequency), its value
## in R before the shadows' cut, so the sky cuts it by the cover; mipmapped,
## as the layer is seen far off and flat near the horizon.
func sky_noise() -> ImageTexture:
	if _sky_noise == null:
		var image := _cloud_noise().get_seamless_image(128, 128)
		image.convert(Image.FORMAT_RGBA8)
		image.generate_mipmaps()
		_sky_noise = ImageTexture.create_from_image(image)
	return _sky_noise


## How far the clouds and fog have drifted (m, world xz), the shadows'.
func drift() -> Vector2:
	return _drift


static func _cloud_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	noise.seed = 7
	return noise


## Where the cloud decal's middle goes for the view's [param target]
## (world xz) with the clouds [param drift]ed (m): on the drift's own grid
## of CLOUD_PERIOD, the grid point nearest the target, so the target is
## never more than half a period from it.
static func cloud_middle(target: Vector2, drift: Vector2) -> Vector2:
	var offset := Vector2(fposmod(drift.x, CLOUD_PERIOD), fposmod(drift.y, CLOUD_PERIOD))
	return offset + Vector2(snappedf(target.x - offset.x, CLOUD_PERIOD), snappedf(target.y - offset.y, CLOUD_PERIOD))


func _build_clouds() -> void:
	var size := 128
	var tile := _cloud_noise().get_seamless_image(size, size)
	_cloud_tile = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			_cloud_tile.set_pixel(x, y, Color(0.0, 0.0, 0.0, smoothstep(0.45, 0.62, tile.get_pixel(x, y).r)))
	_clouds = Decal.new()
	_clouds.name = "CloudShadow"
	_clouds.size = Vector3(CLOUD_PERIOD * CLOUD_TILES, 40.0, CLOUD_PERIOD * CLOUD_TILES)
	_clouds.texture_albedo = _cloud_texture(CLOUD_TILES)
	_clouds.albedo_mix = 1.0
	_clouds.upper_fade = 0.0
	_clouds.lower_fade = 0.0
	_clouds.visible = false
	add_child(_clouds)
