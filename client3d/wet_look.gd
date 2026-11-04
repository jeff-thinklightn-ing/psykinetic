extends RefCounted
## A body wet (decision 775; Jeff: wading the hills' streams "makes character get wet"): every
## humanoid's (players, companions, townsfolk) wetness worked out on the client from what it
## already draws, nothing on the wire. Standing in water (a ford, a stream's shallows: Client3D's
## _wet and _bed_levels) it is wet up to the line the water reached (its depth and a splash),
## kept at the highest; out in the rain (the weather's rain, not walled in) it wets all over by the
## rain's strength. It dries over DRY_SECONDS (FIRE_DRY times faster within FIRE_REACH of a fire;
## not at all in the rain), the shine going before the dark. Drawn by wet.gdshader as an overlay
## on the body's meshes, a material of its own while wet (instance uniforms don't reach an overlay),
## dropped once dry; a wet body near the camera drips. Preloaded by Client3D (no class_name).

## Real seconds to dry from soaked (the coordinator: about 1.5 real minutes, some 25 game minutes
## of the 90-minute day; DayNight's game minutes would be too quick to see).
const DRY_SECONDS := 90.0
## Drying by a fire (a terrain fire cell, or a camp's fire ring (777, Level.camp_fire), within
## FIRE_REACH cells, Chebyshev: the reach of the camp's warmed rest) this many times faster.
const FIRE_DRY := 4.0
const FIRE_REACH := 2
## Seconds of full rain to soak a body through; rain under this strength wets nothing.
const RAIN_SOAK_SECONDS := 40.0
const RAIN_WETS := 0.05
## How far above the water's surface the line goes (splashed while wading), and the least depth
## that counts as standing in water (m).
const SPLASH := 0.12
const IN_WATER := 0.03
## How often each body's wetness is worked out (s); the shader's line follows every frame.
const STEP := 0.2
## Drips: from bodies this wet, this near the camera (m).
const DRIPS_FROM := 0.4
const DRIPS_NEAR := 14.0
const SHADER := preload("res://client3d/wet.gdshader")

static var _clock := 0.0
## Left out (map_bench's --off=wet, to time what it costs): no body worked out or drawn wet.
static var off := false
static var _drop_mesh: QuadMesh
## The camps' fire cells of the buildings drawn, and the terrain and building count they were read from.
static var _camp_fires: Array[Vector2i] = []
static var _camps_terrain: Dictionary = {}
static var _camps_count := -1


## [param puppet]'s own wet overlay (meta "wet_material"), made the first time it is asked for.
static func material_of(puppet: Node3D) -> ShaderMaterial:
	if puppet.has_meta("wet_material"):
		return puppet.get_meta("wet_material")
	var material := ShaderMaterial.new()
	material.shader = SHADER
	puppet.set_meta("wet_material", material)
	return material


## What [param puppet]'s meshes' overlay is with [param outline] (null for none) and wet or not:
## the outline, or its wet overlay passing on to the outline. Dry, its wet overlay is dropped.
static func overlay(puppet: Node3D, outline: Material, wet: bool) -> Material:
	if not wet:
		puppet.remove_meta("wet_material")
		return outline
	var material := material_of(puppet)
	material.next_pass = outline
	return material


## How deep the water is at [param puppet]'s feet (m; 0 out of water), as [param client] draws it.
static func depth_at(client, puppet: Node3D) -> float:
	var cell := Vector2i(roundi(puppet.position.x), roundi(puppet.position.z))
	if not client._wet.has(cell) and not client._bed_levels.has(cell):
		return 0.0
	var surface: float = client._bed_levels.get(cell, client._elevation(cell))
	return maxf(surface - puppet.position.y, 0.0)


## Whether [param cell] is within FIRE_REACH of one of [param client]'s fires.
static func near_fire(client, cell: Vector2i) -> bool:
	for fire: Vector2i in client._terrain.get("fire", []) + camp_fires(client):
		if maxi(absi(fire.x - cell.x), absi(fire.y - cell.y)) <= FIRE_REACH:
			return true
	return false


## The fire rings of the camps among [param client]'s drawn buildings (Level.camp_fire), read
## again only when its terrain or its count of buildings changes.
static func camp_fires(client) -> Array[Vector2i]:
	var terrain: Dictionary = client._terrain
	var count: int = terrain.get("buildings", []).size() + terrain.get("plot_buildings", []).size()
	if not is_same(terrain, _camps_terrain) or count != _camps_count:
		_camps_terrain = terrain
		_camps_count = count
		var buildings: Array = client._drawn_buildings()
		_camp_fires.clear()
		for building: Dictionary in buildings:
			var fire := Level.camp_fire(building)
			if fire != Vector2i(-1, -1):
				_camp_fires.append(fire)
	return _camp_fires


## The rain falling on [param cell] (0..1): the weather's, outdoors, not walled in.
static func rain_on(client, cell: Vector2i) -> float:
	var weather = client._weather_view  # WeatherView
	if weather == null or not weather.outdoor or client._enclosed.has(cell):
		return 0.0
	return float(weather.weather.get("rain", 0.0))


## Each frame (Client3D._process): every humanoid body's wetness worked out and drawn every STEP;
## between, a wet body's line only follows it up and down (benched: per-frame work for every wet
## body in a storm cost 0.6 ms a frame).
static func update(client, delta: float) -> void:
	if off:
		return
	_clock += delta
	var dt := 0.0
	if _clock >= STEP:
		dt = _clock
		_clock = 0.0
	for puppet: Node3D in client._puppets.values():
		if not is_instance_valid(puppet) or not puppet.has_meta("rig") or puppet.has_meta("creature_view"):
			continue
		if dt > 0.0:
			soak(client, puppet, dt)
			show(client, puppet)
		elif puppet.has_meta("wet_material"):
			_follow(puppet)


## A wet body's line kept at its height in the world as it rises and sinks (only when it moved).
static func _follow(puppet: Node3D) -> void:
	var y := puppet.global_position.y
	if absf(y - float(puppet.get_meta("wet_y", y))) < 0.005:
		return
	puppet.set_meta("wet_y", y)
	(puppet.get_meta("wet_material") as ShaderMaterial).set_shader_parameter("wet_line", y + float(puppet.get_meta("wet_line", 0.0)))


## [param puppet]'s wetness after [param dt] seconds where it stands: metas "wet" (below the
## line, 0..1), "wet_line" (the line, m above its feet) and "wet_all" (all over, 0..1).
static func soak(client, puppet: Node3D, dt: float) -> void:
	var cell := Vector2i(roundi(puppet.position.x), roundi(puppet.position.z))
	var wet := float(puppet.get_meta("wet", 0.0))
	var line := float(puppet.get_meta("wet_line", 0.0))
	var all := float(puppet.get_meta("wet_all", 0.0))
	var depth := depth_at(client, puppet)
	var rain := rain_on(client, cell)
	if depth > IN_WATER:
		line = maxf(line if wet > 0.0 else 0.0, depth + SPLASH)
		wet = 1.0
	if rain >= RAIN_WETS:
		all = minf(all + dt * rain / RAIN_SOAK_SECONDS, maxf(all, rain))
	else:
		var rate := dt / DRY_SECONDS * (FIRE_DRY if near_fire(client, cell) else 1.0)
		if depth <= IN_WATER:
			wet = maxf(wet - rate, 0.0)
		all = maxf(all - rate, 0.0)
	if wet <= 0.0:
		line = 0.0
	puppet.set_meta("wet", wet)
	puppet.set_meta("wet_line", line)
	puppet.set_meta("wet_all", all)


## [param puppet] drawn as wet as it is: the overlay on its meshes (off once dry), their instance
## uniforms, and its drips.
static func show(client, puppet: Node3D) -> void:
	var wet := float(puppet.get_meta("wet", 0.0))
	var all := float(puppet.get_meta("wet_all", 0.0))
	var on := wet > 0.0 or all > 0.0
	var was: bool = puppet.get_meta("wet_on", false)
	if not on and not was:
		return
	var meshes := meshes_of(puppet)
	if on != was or puppet.get_meta("wet_meshes", 0) != meshes.size():
		puppet.set_meta("wet_on", on)
		puppet.set_meta("wet_meshes", meshes.size())
		var outline: Material = puppet.get_meta("outline") if puppet.has_meta("outline") else null
		for mesh: MeshInstance3D in meshes:
			mesh.material_overlay = overlay(puppet, outline, on)
	if not on:
		_drip(client, puppet, 0.0, 0.0)
		return
	var material := material_of(puppet)
	puppet.set_meta("wet_y", puppet.global_position.y)
	material.set_shader_parameter("wet_line", puppet.global_position.y + float(puppet.get_meta("wet_line", 0.0)))
	material.set_shader_parameter("wet_amount", wet)
	material.set_shader_parameter("wet_all", all)
	_drip(client, puppet, maxf(wet, all), minf(float(puppet.get_meta("wet_line", 0.0)), 1.0) if wet >= all else 1.0)


## The meshes a body draws with (Client3D's "Body": its model and worn pieces; not what its hands
## hold, the sockets' "Held": nobody looks for a wet sword, and the overlay costs a draw a mesh).
static func meshes_of(puppet: Node3D) -> Array:
	var body := puppet.get_node_or_null("Body") as Node3D
	if body == null:
		return []
	var meshes := body.find_children("*", "MeshInstance3D", true, false).filter(
		func(mesh: Node) -> bool: return not str(mesh.get_path()).contains("/Held"))
	if body is MeshInstance3D:
		meshes.append(body)
	return meshes


## Drops falling from a body [param wet] (0..1) from about [param from] metres up (its hem), if
## it is wet enough and near the camera; none else.
static func _drip(client, puppet: Node3D, wet: float, from: float) -> void:
	var drips := puppet.get_node_or_null("WetDrips") as CPUParticles3D
	var camera: Camera3D = client._camera
	var near := camera != null and camera.global_position.distance_to(puppet.global_position) <= DRIPS_NEAR
	var dripping := wet >= DRIPS_FROM and near
	if drips == null:
		if not dripping:
			return
		drips = _make_drips()
		puppet.add_child(drips)
	drips.emitting = dripping
	if dripping:
		drips.amount_ratio = clampf((wet - DRIPS_FROM) / (1.0 - DRIPS_FROM), 0.15, 1.0)
		drips.position.y = maxf(from * 0.85, 0.25)


static func _make_drips() -> CPUParticles3D:
	if _drop_mesh == null:
		_drop_mesh = QuadMesh.new()
		_drop_mesh.size = Vector2(0.018, 0.04)
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.albedo_color = Color(0.82, 0.9, 1.0, 0.7)
		_drop_mesh.material = look
	var drips := CPUParticles3D.new()
	drips.name = "WetDrips"
	drips.mesh = _drop_mesh
	drips.amount = 8
	drips.lifetime = 0.5
	drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drips.emission_box_extents = Vector3(0.2, 0.03, 0.2)
	drips.direction = Vector3.DOWN
	drips.spread = 8.0
	drips.initial_velocity_min = 0.1
	drips.initial_velocity_max = 0.4
	drips.gravity = Vector3(0.0, -9.8, 0.0)
	drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return drips
