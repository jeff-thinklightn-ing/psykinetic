class_name Flames
extends RefCounted
## Fire drawn (decision 523): a flame of three crossed quads (flame.gdshader:
## its shape from scrolling noise, art-kit's row 7 from the bone core out
## to the deep red tips, embers rising out of it, leaning downwind) with a
## faint smoke over it (smoke.gdshader); and the flicker and the daylight
## fade of fire's drawn light. Visual only: World's light (Fields) stays
## steady, as Senses reads it.

## Each slot's flame, its height (m): a hand for a torch, about a cell wide
## for a campfire (art-kit's sizes).
const SIZES := {"prop.torch_post": 0.4, "prop.torch": 0.3, "prop.campfire": 0.9, "prop.forge": 0.45}
const DEFAULT_SIZE := 0.3
## How far a flame's drawn light swings (a share of its energy): a torch's
## calmer than an open fire's.
const TORCH_FLICKER := 0.08
const FIRE_FLICKER := 0.14
## By day under the open sky a fire's light fades to this share (it still
## glints at noon); indoors, in dungeons, it burns full.
const DAY_SHARE := 0.3
## The quads stand this many flame heights tall: the flame fills the lower
## part, its embers rise through the rest.
const REACH := 1.6

static var _mesh: ArrayMesh
static var _flame_material: ShaderMaterial
static var _smoke_mesh: QuadMesh


## A flame [param size] m tall standing at [param at] in [param parent],
## its noise offset by [param seed], and its smoke; returns its node.
static func light(parent: Node3D, at: Vector3, size: float, seed := 0) -> Node3D:
	var flame := Node3D.new()
	flame.name = "Flame"
	flame.position = at
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _crossed()
	body.material_override = _material()
	body.scale = Vector3.ONE * size
	body.rotation.y = float(posmod(seed, 360)) * PI / 180.0
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.set_instance_shader_parameter("seed", float(posmod(seed, 997)))
	flame.add_child(body)
	var smoke := MeshInstance3D.new()
	smoke.name = "Smoke"
	smoke.mesh = _smoke()
	smoke.scale = Vector3.ONE * size
	smoke.position.y = size * REACH * 0.55
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.set_instance_shader_parameter("seed", float(posmod(seed * 7, 997)))
	flame.add_child(smoke)
	parent.add_child(flame)
	return flame


## A flame at [param instance]'s "flame" socket, [param slot]'s (art-kit's
## convention: prop.torch, prop.torch_post, prop.campfire, prop.forge), sized
## by the slot; null when the slot has no such socket.
static func at_socket(instance: Node3D, slot: String, seed := 0) -> Node3D:
	var at: Variant = socket_of(slot)
	if at == null:
		return null
	return light(instance, at, size_of(slot), seed)


## [param slot]'s flame socket (its own units), or null.
static func socket_of(slot: String) -> Variant:
	var sockets: Variant = ArtKit.spec(slot).get("sockets", {}) if ArtKit.has(slot) else {}
	if not sockets is Dictionary or not (sockets as Dictionary).has("flame"):
		return null
	var at: Array = sockets["flame"]
	return Vector3(float(at[0]), float(at[1]), float(at[2]))


static func size_of(slot: String) -> float:
	return float(SIZES.get(slot, DEFAULT_SIZE))


## A fire's drawn light, as a share of its energy, at [param time] (s, the
## view's own: accumulated frame time, so a fixed-fps capture flickers as
## play does), on its own [param phase], swinging [param swing] either way
## at most: a slow sway (about 1.5 Hz) and a smaller flutter (about 7 Hz).
static func flicker(time: float, phase: float, swing: float) -> float:
	var sway := sin(TAU * 1.5 * time + phase) * 0.6 + sin(TAU * 0.9 * time + phase * 1.7) * 0.4
	var flutter := sin(TAU * 7.0 * time + phase * 3.1) * 0.5 + sin(TAU * 11.3 * time + phase * 5.3) * 0.5
	return 1.0 + swing * (0.7 * sway + 0.3 * flutter)


## The share of its light a fire keeps by day: outdoors, faded toward
## DAY_SHARE by [param daylight] (0 night .. 1 day) where the sky reaches
## (less under [param canopy], the forest's shade); indoors, all of it.
static func day_share(daylight: float, outdoor: bool, canopy: float) -> float:
	if not outdoor:
		return 1.0
	return lerpf(1.0, DAY_SHARE, clampf(daylight, 0.0, 1.0) * (1.0 - clampf(canopy, 0.0, 1.0)))


## Three quads a unit tall (REACH of them drawn), crossed at 60 degrees,
## their feet at the origin; UV x across, y up from the foot.
static func _crossed() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.4
	for i in 3:
		var turn := i * PI / 3.0
		var across := Vector3(cos(turn), 0.0, sin(turn)) * half
		var corners := [-across, across, across + Vector3.UP * REACH, -across + Vector3.UP * REACH]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			surface.set_uv(uvs[k])
			surface.add_vertex(corners[k])
	_mesh = surface.commit()
	return _mesh


static func _material() -> ShaderMaterial:
	if _flame_material == null:
		_flame_material = ShaderMaterial.new()
		_flame_material.shader = preload("res://client3d/flame.gdshader")
	return _flame_material


static func _smoke() -> QuadMesh:
	if _smoke_mesh == null:
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(1.2, 1.6)
		var material := ShaderMaterial.new()
		material.shader = preload("res://client3d/smoke.gdshader")
		_smoke_mesh.material = material
	return _smoke_mesh
