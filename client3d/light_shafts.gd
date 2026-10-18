extends Node3D
## Shafts of sunlight down through a forest's canopy (decision 477): a few
## cheap fakes, each a quad glowing additively turned about its length to
## face the camera, hung from the
## crowns over the clearings and the gaps between them, leaning toward the
## sun, their feet kept where the light reaches the floor. Only by day,
## with the sun up and the sky clear; light haze shows them best, rain and
## night none. Client3D makes one per map with a canopy (setup) and moves
## it every frame (place); at most SHOWN at once, those nearest the view.

## How high the crowns are over the floor (m): where a shaft starts.
const TOP := 9.0
## Shafts at most at once, and how far from the view one shows (m).
const SHOWN := 8
const REACH := 40.0
## Shafts a clearing holds at most, and a clearing's shaft's width as a
## share of its radius; a gap's width (m).
const PER_CLEARING := 3
const CLEARING_WIDTH := 0.3
const GAP_WIDTH := 0.9
## A gap: a cell under GAP_COVER inside the canopy (every neighbour under
## some cover), GAP_SPACING cells at least from another gap or a clearing.
const GAP_COVER := 0.5
const GAP_SPACING := 6
## The sun's height (degrees) under which there are none, and over which
## they are full.
const SUN_LOW := 15.0
const SUN_HIGH := 35.0
## How bright at most, and their colour.
const STRENGTH := 0.2
const COLOUR := Color(1.0, 0.95, 0.8)

const SHADER := """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.95, 0.8);
uniform float strength = 0.0;
uniform float seed = 0.0;

float hash(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

float noise(float p) {
	float i = floor(p);
	float f = fract(p);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	// UV.y 0 at the crowns, 1 on the floor: brightest under the crowns,
	// faded at both ends; soft across, with slow streaks of dust.
	float along = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.45, 1.0, UV.y) * 0.85);
	float across = pow(max(1.0 - abs(UV.x * 2.0 - 1.0), 0.0), 1.6);
	float streaks = 0.65 + 0.35 * noise(UV.x * 9.0 + seed * 13.0 + TIME * 0.05);
	// Gone close to the eye, so walking through one never flashes.
	float near = smoothstep(1.5, 6.0, length(VERTEX));
	ALBEDO = colour * strength * along * across * streaks * near;
}
"""

## Where shafts can hang: [{foot: Vector3 on the floor, width}].
var _spots: Array[Dictionary] = []
var _shafts: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	name = "LightShafts"
	var shader := Shader.new()
	shader.code = SHADER
	for i in SHOWN:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("colour", COLOUR)
		material.set_shader_parameter("seed", float(i))
		var shaft := MeshInstance3D.new()
		shaft.name = "Shaft%d" % i
		shaft.mesh = _quad()
		shaft.material_override = material
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.layers = WeatherView.RAIN_LAYER
		shaft.visible = false
		add_child(shaft)
		_shafts.append(shaft)
		_materials.append(material)


## Finds where shafts hang on a map: [param clearings] (Fields.clearings),
## each with up to PER_CLEARING; and the gaps in [param canopy] (cell ->
## cover, Fields.canopy). [param floor_at] gives a cell's floor in the
## view (Vector2i -> Vector3).
func setup(clearings: Array, canopy: Dictionary, floor_at: Callable) -> void:
	_spots = []
	var taken: Array[Vector2] = []
	for clearing: Dictionary in clearings:
		var centre: Vector2 = clearing["centre"]
		var radius := float(clearing["radius"])
		taken.append(centre)
		var count := clampi(roundi(radius / 2.0), 1, PER_CLEARING)
		for i in count:
			var offset := Vector2.ZERO if count == 1 else Vector2.from_angle(TAU * i / count + centre.x) * radius * 0.4
			var cell := Vector2i((centre + offset).round())
			_spots.append({"foot": floor_at.call(cell), "width": clampf(radius * CLEARING_WIDTH, GAP_WIDTH, 2.5)})
	for cell: Vector2i in canopy:
		if canopy[cell] >= GAP_COVER or not _inside(cell, canopy) or not _least(cell, canopy):
			continue
		var near := false
		for other in taken:
			if Vector2(cell).distance_to(other) < GAP_SPACING:
				near = true
				break
		if near:
			continue
		taken.append(Vector2(cell))
		_spots.append({"foot": floor_at.call(cell), "width": GAP_WIDTH})


## How many spots setup found (for tests).
func spot_count() -> int:
	return _spots.size()


## Hangs the shafts nearest [param view] (the point the camera looks at)
## toward the sun ([param toward_sun], in the view's directions, its y
## the sun's height), at [param strength] (0..1, shafts' share of full:
## the day, the sky's clearness and haze; see strength_for).
func place(view: Vector3, toward_sun: Vector3, strength: float) -> void:
	var sun := toward_sun.normalized()
	var height := smoothstep(sin(deg_to_rad(SUN_LOW)), sin(deg_to_rad(SUN_HIGH)), sun.y)
	var shown := strength * height
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := camera.global_position if camera != null else Vector3.INF
	var nearest: Array[Dictionary] = []
	if shown > 0.01:
		for spot: Dictionary in _spots:
			var d := (spot["foot"] as Vector3).distance_to(view)
			if d < REACH:
				nearest.append({"spot": spot, "d": d})
		nearest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	for i in _shafts.size():
		var shaft := _shafts[i]
		shaft.visible = i < nearest.size()
		if not shaft.visible:
			continue
		var spot: Dictionary = nearest[i]["spot"]
		var foot: Vector3 = spot["foot"]
		var length := TOP / maxf(sun.y, 0.2)
		var top := foot + sun * length
		var middle := (foot + top) * 0.5
		# Turned about its length to face the eye; one seen end on (the sun
		# behind the camera) would be a short bright blot, so it fades.
		var to_eye := (eye - middle).normalized() if eye != Vector3.INF else Vector3.UP
		var side := sun.cross(to_eye)
		if side.length() < 0.05:
			side = sun.cross(Vector3.RIGHT)
		side = side.normalized()
		var depth := side.cross(sun).normalized()
		shaft.global_transform = Transform3D(Basis(side * float(spot["width"]), sun * length, depth), middle)
		var end_on := 1.0 - smoothstep(0.9, 0.985, absf(sun.dot(to_eye)))
		# Fainter toward the edge of reach, so one never pops in.
		var fade := end_on * (1.0 - smoothstep(REACH * 0.7, REACH, float(nearest[i]["d"])))
		_materials[i].set_shader_parameter("strength", STRENGTH * shown * fade)


## The shafts' strength for [param daylight] (0..1) under [param weather]
## (Weather.at's amounts): none at night, in rain or under cloud; light
## haze shows them best, thick fog hides them.
static func strength_for(daylight: float, weather: Dictionary) -> float:
	var cloud := float(weather.get("cloud", 0.0))
	var fog := float(weather.get("fog", 0.0))
	var rain := float(weather.get("rain", 0.0)) + float(weather.get("snow", 0.0))
	var haze := (1.0 + 1.5 * fog) * (1.0 - smoothstep(0.5, 0.9, fog))
	return clampf(daylight * (1.0 - cloud) * (1.0 - clampf(rain * 3.0, 0.0, 1.0)) * haze, 0.0, 1.5)


## Whether every neighbour of [param cell] is under some cover: it is
## inside the canopy, not at its edge.
static func _inside(cell: Vector2i, canopy: Dictionary) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not canopy.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Whether [param cell] is the most open of its neighbours (a gap's middle).
static func _least(cell: Vector2i, canopy: Dictionary) -> bool:
	var here: float = canopy[cell]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and float(canopy.get(cell + Vector2i(dx, dy), 1.0)) < here:
				return false
	return true


## A shaft's shape: a unit quad across x along y (-0.5..0.5 each way),
## UV.y 0 at the top.
static func _quad() -> ArrayMesh:
	var a := Vector3.LEFT * 0.5
	var b := Vector3.RIGHT * 0.5
	var top := Vector3.UP * 0.5
	var vertices := PackedVector3Array([a + top, b + top, b - top, a + top, b - top, a - top])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
