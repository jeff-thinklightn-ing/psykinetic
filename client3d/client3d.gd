class_name Client3D
extends Node3D
## The 3D view of the game. Instanced by Main under the same tree as the 2D
## view unless the client runs with renderer 2d (see Net.renderer), so all the net code, the
## entity specs, the settings file and the map data are the ones the 2D
## client uses; the 2D nodes are simply hidden and go on being the
## replicated state. One tile is one unit: grid (x, y) is 3D (x, 0, y). The
## sim is the physics: there are no physics bodies here, only meshes and,
## for picking, Area3Ds.
##
## The room is built once from the parsed map (Terrain) out of the Kenney
## Castle Kit (1-unit modules, KIT_WALL_HEIGHT tall), at the kit's own
## proportions and scaled only in height to WALL_HEIGHT: the ground piece
## per floor cell; the narrow wall segment per wall edge, centred on the
## boundary line; the narrow corner post at every vertex where walls meet
## at an angle or end; the doorway piece with the gate leaf hinged at the
## edge's start for a door, turning with the Door node. Fire is an emissive
## quad with a small light. Flat-colour boxes in the kit's stone (_box,
## _stone) stay available for interior walls later (BOX_WALLS).
##
## Near and far, as in 2D: a wall whose camera-facing side has walkable
## floor behind it is near and drawn at NEAR_ALPHA, so what stands there
## shows through; the rest are opaque. A post is near when all its walls
## are. Recomputed whenever the camera yaw changes.
##
## Entities get a puppet each: a primitive at the scale table's size,
## coloured as the 2D sprite is, with a Label3D name and a speech line on
## creatures, a warm light on players and companions, and an Area3D of the
## same shape for picking. Puppets follow the 2D nodes every frame.
##
## Camera: orthographic, tilted CAMERA_PITCH from horizontal, yawed by
## `yaw` about the local player: 0 matches the 2D diamond (+x down-right,
## +y down-left). Q/E step the yaw by ORBIT_STEP, tweened; a middle-button
## drag nudges it up to ORBIT_STEP either way and it springs back on
## release. The step persists in settings.cfg (Net.camera_yaw).
##
## Picking is by ray from the camera through the cursor: an entity or door
## Area3D first, else the floor plane, which Main snaps to the nearest
## walkable cell. The hover ring and the click ripple are flat ring meshes
## on the floor. All input is Main's; this view only answers its picks and
## draws what it is told.

const KIT := "res://art/kenney-castle/Models/GLB format/"
const WALL_HEIGHT := 3.0
const KIT_WALL_HEIGHT := 1.31
## The kit's walls are this thick and occupy x in [-0.5, 0] of their
## module; they are shifted to straddle the edge.
const WALL_THICKNESS := 0.5
const POST_SIZE := 0.5
## The kit's gate leaf, in kit units: thickness x, height y, width z. It
## fits the kit's doorway as is.
const GATE_SIZE := Vector3(0.1516, 0.910339, 0.662151)
## Flat-colour walls instead of the kit pieces (for interiors later).
const BOX_WALLS := false
## The kit's stone, sampled from its colormap at the wall mesh's UVs.
const STONE := Color("ebb48e")
## The 2D floor tile's colour (the box floor).
const FLOOR := Color("4b7164")
const NEAR_ALPHA := 0.3
const CAMERA_PITCH := 50.0
const CAMERA_DISTANCE := 40.0
## Orthographic height in units: a 1.5-unit character, foreshortened by
## cos(CAMERA_PITCH), is about a twelfth of it.
const CAMERA_SIZE := 12.0
const CAMERA_FOLLOW_RATE := 6.0
const ORBIT_STEP := 45.0
const ORBIT_SECONDS := 0.25
const NUDGE_DRAG_PX := 400.0
const NUDGE_RETURN_SECONDS := 0.2
const PLAYER_LIGHT_RANGE := 6.0
const PLAYER_LIGHT := Color(1.0, 0.82, 0.6)
const FIRE := Color(1.0, 0.45, 0.1)
const AMBIENT := Color(0.05, 0.05, 0.07)
const BACKGROUND := Color(0.02, 0.02, 0.025)
const SUN := Color(0.6, 0.7, 1.0)
const SUN_ENERGY := 0.1
## Label3D: units per font pixel, with the font size, for a name about a
## quarter unit tall.
const LABEL_SIZE := 0.004
const LABEL_FONT_SIZE := 64
const SPEECH := Color(1, 0.95, 0.6)
const HOVER := Color(1, 1, 1, 0.35)
const RIPPLE := Color(0.58, 0.76, 0.69)
const RIPPLE_SECONDS := 0.25
const RING_SEGMENTS := 40
## Just above the floor, so the rings never z-fight with it.
const ON_FLOOR := 0.02

## Shape -> mesh factory; sizes from the scale table.
var _shapes := {
	"capsule": func() -> Mesh:
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.3
		mesh.height = Iso.HEIGHTS["capsule"]
		return mesh,
	"cube": func() -> Mesh:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * Iso.HEIGHTS["cube"]
		return mesh,
	"barrel": func() -> Mesh:
		var mesh := CylinderMesh.new()
		mesh.height = Iso.HEIGHTS["barrel"]
		mesh.top_radius = 0.35
		mesh.bottom_radius = 0.35
		return mesh,
	"sphere": func() -> Mesh:
		var mesh := SphereMesh.new()
		mesh.radius = Iso.HEIGHTS["sphere"] * 0.5
		mesh.height = Iso.HEIGHTS["sphere"]
		return mesh,
	"slab": func() -> Mesh:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, Iso.HEIGHTS["slab"], 0.9)
		return mesh,
	"flat": func() -> Mesh:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, Iso.HEIGHTS["flat"], 0.9)
		return mesh,
}

var _camera: Camera3D
var _camera_target := Vector3.ZERO
## The camera's yaw now, and the step it rests at (a multiple of ORBIT_STEP).
var yaw := 0.0
var _yaw_step := 0.0
var _yaw_tween: Tween
## Middle button held: the screen x it went down at, or NAN when not.
var _nudge_from := NAN
var _room: Node3D
## The kit's own material and a see-through copy of it; the flat stone
## pair likewise.
var _kit_opaque: Material
var _kit_near: Material
var _stone_opaque: StandardMaterial3D
var _stone_near: StandardMaterial3D
## Wall edge key -> its piece; vertex -> its post.
var _walls: Dictionary[Vector3i, Node3D] = {}
var _posts: Dictionary[Vector2i, Node3D] = {}
## Door edge key -> the doorway node (jambs, lintel, hinge).
var _doorways: Dictionary[Vector3i, Node3D] = {}
## Entity instance id -> its puppet.
var _puppets: Dictionary[int, Node3D] = {}
var _hover: MeshInstance3D
var _ring_mesh: ArrayMesh
var _terrain: Dictionary = {}


## Builds the room and the rig. [param terrain] is Terrain.parse's result,
## the same the 2D view paints from.
func setup(terrain: Dictionary) -> void:
	_terrain = terrain
	_ring_mesh = _make_ring(0.42, 0.5)
	_build_environment()
	_build_camera()
	_build_room()
	_hover = _make_ring_instance(HOVER)
	_hover.visible = false
	add_child(_hover)
	_yaw_step = roundf(Net.camera_yaw / ORBIT_STEP) * ORBIT_STEP
	yaw = _yaw_step
	_place_camera()
	_classify_walls()


func _process(delta: float) -> void:
	_sync_puppets()
	_sync_doors()
	_nudge()
	_follow(delta)


# --- Rig ---------------------------------------------------------------------

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, 160.0, 0.0)
	add_child(sun)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = CAMERA_DISTANCE * 3.0
	add_child(_camera)
	_camera_target = _tile_position(Main.CHAMBER_CENTRE)
	_place_camera()
	_camera.current = true


## The camera's offset from its target: CAMERA_PITCH above the ground on
## the +x +z side (grid +x toward the viewer down-right, +y down-left, as
## in the 2D view), turned about the vertical by the yaw.
func _camera_offset() -> Vector3:
	var pitch := deg_to_rad(CAMERA_PITCH)
	var horizontal := CAMERA_DISTANCE * cos(pitch)
	var offset := Vector3(horizontal / sqrt(2.0), CAMERA_DISTANCE * sin(pitch), horizontal / sqrt(2.0))
	return offset.rotated(Vector3.UP, deg_to_rad(yaw))


func _place_camera() -> void:
	_camera.position = _camera_target + _camera_offset()
	_camera.look_at(_camera_target, Vector3.UP)


func _follow(delta: float) -> void:
	var player := _local_player()
	if player == null:
		return
	var puppet: Node3D = _puppets.get(player.get_instance_id())
	if puppet == null:
		return
	var rate := 1.0 - exp(-CAMERA_FOLLOW_RATE * delta)
	_camera_target = _camera_target.lerp(puppet.position, rate)
	_place_camera()


func _local_player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.owner_peer == Net.local_id and entity.spawned:
			return entity
	return null


# --- Orbit ---------------------------------------------------------------------

## Q/E: the next step round, tweened; kept in the settings file.
func orbit(direction: int) -> void:
	_yaw_step += ORBIT_STEP * signf(direction)
	Net.camera_yaw = _yaw_step
	Net.save_view_settings()
	_tween_yaw(_yaw_step, ORBIT_SECONDS)


## Middle button down: the drag nudges the yaw from here; up: it springs
## back to the step.
func nudge_button(pressed: bool) -> void:
	if pressed:
		if _yaw_tween != null:
			_yaw_tween.kill()
			_yaw_tween = null
		_nudge_from = DisplayServer.mouse_get_position().x
		return
	_nudge_from = NAN
	_tween_yaw(_yaw_step, NUDGE_RETURN_SECONDS)


func _nudge() -> void:
	if is_nan(_nudge_from):
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		nudge_button(false)
		return
	var drag := (DisplayServer.mouse_get_position().x - _nudge_from) / (NUDGE_DRAG_PX * 0.5)
	_set_yaw(_yaw_step + ORBIT_STEP * sin(clampf(drag, -1.0, 1.0) * PI * 0.5))


func _tween_yaw(to: float, seconds: float) -> void:
	if _yaw_tween != null:
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.tween_method(_set_yaw, yaw, to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_yaw(degrees: float) -> void:
	if is_equal_approx(degrees, yaw):
		return
	yaw = degrees
	_place_camera()
	_classify_walls()


# --- Picking --------------------------------------------------------------------

func _mouse_ray() -> Array[Vector3]:
	var mouse := get_viewport().get_mouse_position()
	return [_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse)]


## Where the cursor's ray meets the ground plane, in grid units; NaN when
## it does not.
func mouse_grid() -> Vector2:
	var ray := _mouse_ray()
	if absf(ray[1].y) < 0.0001:
		return Vector2(NAN, NAN)
	var t := -ray[0].y / ray[1].y
	if t < 0.0:
		return Vector2(NAN, NAN)
	var hit := ray[0] + ray[1] * t
	return Vector2(hit.x, hit.z)


## The first pick Area3D the cursor's ray hits, with its "entity" or
## "door" meta, or {}.
func _pick() -> Dictionary:
	var ray := _mouse_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * CAMERA_DISTANCE * 3.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return get_world_3d().direct_space_state.intersect_ray(query)


## The entity whose puppet is under the cursor, or null. The local player
## is skipped so clicks pass through to what is behind it.
func entity_under_mouse() -> GridEntity:
	var hit := _pick()
	if hit.is_empty():
		return null
	var area: Area3D = hit["collider"]
	if not area.has_meta("entity"):
		return null
	var entity := instance_from_id(area.get_meta("entity")) as GridEntity
	if entity == null or not entity.spawned or entity == _local_player():
		return null
	return entity


## The door whose leaf or frame is under the cursor, or null.
func door_under_mouse() -> Door:
	var hit := _pick()
	if hit.is_empty():
		return null
	var area: Area3D = hit["collider"]
	if not area.has_meta("door"):
		return null
	var key: Vector3i = area.get_meta("door")
	for door in World.get_doors():
		if door.key == key:
			return door
	return null


## Where a grid direction points on screen (for the toss drag).
func screen_vector(direction: Vector2i) -> Vector2:
	return _camera.unproject_position(Vector3(direction.x, 0.0, direction.y)) \
			- _camera.unproject_position(Vector3.ZERO)


## A tile's centre in viewport coordinates (for --test-hover).
func screen_of_tile(tile: Vector2i) -> Vector2:
	return _camera.unproject_position(_tile_position(tile))


# --- Rings ------------------------------------------------------------------------

## A flat annulus in the ground plane, radii in units.
func _make_ring(inner: float, outer: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RING_SEGMENTS:
		var a0 := TAU * i / RING_SEGMENTS
		var a1 := TAU * (i + 1) / RING_SEGMENTS
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		for vertex in [i0, o0, o1, i0, o1, i1]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	return surface.commit()


func _make_ring_instance(color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


## The hover ring on [param tile], or hidden.
func hover(tile: Vector2i, show: bool) -> void:
	_hover.visible = show
	if show:
		_hover.position = _tile_position(tile) + Vector3(0.0, ON_FLOOR, 0.0)


## The click ripple: a ring that grows from a few px to the cell and fades
## over RIPPLE_SECONDS, then is gone.
func ripple(tile: Vector2i) -> void:
	var ring := _make_ring_instance(RIPPLE)
	ring.position = _tile_position(tile) + Vector3(0.0, ON_FLOOR * 2.0, 0.0)
	add_child(ring)
	var material := ring.material_override as StandardMaterial3D
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(1.4, 1.0, 1.4), RIPPLE_SECONDS)
	tween.tween_property(material, "albedo_color:a", 0.0, RIPPLE_SECONDS)
	tween.chain().tween_callback(ring.queue_free)


# --- Room ----------------------------------------------------------------------

static func _tile_position(tile: Vector2i) -> Vector3:
	return Vector3(tile.x, 0.0, tile.y)


func _kit(piece: String) -> Node3D:
	var scene: PackedScene = load(KIT + piece + ".glb")
	return scene.instantiate() as Node3D


func _stone(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(STONE, alpha)
	material.roughness = 0.9
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## The kit pieces share one material (a colormap); the see-through copy
## is it with alpha.
func _load_kit_materials() -> void:
	var sample := _kit("wall-narrow")
	for node in _descendants(sample):
		if node is MeshInstance3D:
			_kit_opaque = (node as MeshInstance3D).mesh.surface_get_material(0)
			break
	sample.free()
	var near := _kit_opaque.duplicate() as BaseMaterial3D
	near.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	near.albedo_color = Color(near.albedo_color, NEAR_ALPHA)
	_kit_near = near


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


func _build_room() -> void:
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_load_kit_materials()
	_stone_opaque = _stone(1.0)
	_stone_near = _stone(NEAR_ALPHA)
	var fire: Array[Vector2i] = _terrain["fire"]
	for cell: Vector2i in _terrain["floor"]:
		var ground := _kit("ground")
		ground.name = "Floor_%d_%d" % [cell.x, cell.y]
		ground.position = _tile_position(cell)
		_room.add_child(ground)
		if cell in fire:
			_add_fire(cell)
	var edges: Dictionary = _terrain["edges"]
	var kind_at := func(key: Vector3i) -> int: return edges.get(key, Terrain.Edge.OPEN)
	var vertices: Dictionary[Vector2i, bool] = {}
	for key: Vector3i in edges:
		match edges[key]:
			Terrain.Edge.WALL:
				_add_wall(key)
			Terrain.Edge.DOOR:
				_add_doorway(key)
			_:
				continue
		for end in 2:
			vertices[WallEdge.vertex_at(key, end)] = true
	for vertex in vertices:
		if _needs_post(vertex, kind_at):
			_add_post(vertex)


## An edge on the ground: its midpoint, and its yaw (a south edge runs
## along x, an east edge along z; the pieces are built along z).
static func _edge_midpoint(key: Vector3i) -> Vector3:
	if key.z == Terrain.EAST:
		return Vector3(key.x + 0.5, 0.0, key.y)
	return Vector3(key.x, 0.0, key.y + 0.5)


static func _edge_yaw(key: Vector3i) -> float:
	return 0.0 if key.z == Terrain.EAST else PI * 0.5


## A flat-colour box standing on the ground, its origin at its base.
func _box(size: Vector3, material: Material) -> Node3D:
	var holder := Node3D.new()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position.y = size.y * 0.5
	holder.add_child(box)
	return holder


## A kit wall module (narrow wall or doorway) on an edge: the piece sits
## in x [-0.5, 0] of its module, so it is shifted to straddle the line,
## and stretched in height only.
func _kit_wall(piece: String) -> Node3D:
	var holder := Node3D.new()
	var mesh := _kit(piece)
	mesh.position.x = WALL_THICKNESS * 0.5
	holder.scale = Vector3(1.0, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	holder.add_child(mesh)
	return holder


func _add_wall(key: Vector3i) -> void:
	var wall: Node3D
	if BOX_WALLS:
		wall = _box(Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0), _stone_opaque)
	else:
		wall = _kit_wall("wall-narrow")
	wall.name = "Wall_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	wall.position = _edge_midpoint(key)
	wall.rotation.y = _edge_yaw(key)
	_room.add_child(wall)
	_walls[key] = wall


## The kit's doorway on the edge with its gate leaf, hinged at the edge's
## start end and swinging with the Door node, and an Area3D over the
## module for picking.
func _add_doorway(key: Vector3i) -> void:
	var doorway := Node3D.new()
	doorway.name = "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	doorway.position = _edge_midpoint(key)
	doorway.rotation.y = _edge_yaw(key)
	var frame := _kit_wall("wall-doorway")
	frame.name = "Frame"
	doorway.add_child(frame)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position.z = -GATE_SIZE.z * 0.5
	var leaf := _kit("gate")
	leaf.scale = Vector3(1.0, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	leaf.position.z = GATE_SIZE.z * 0.5
	hinge.add_child(leaf)
	doorway.add_child(hinge)
	var area := Area3D.new()
	area.name = "Pick"
	area.set_meta("door", key)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0)
	shape.shape = box
	shape.position.y = WALL_HEIGHT * 0.5
	area.add_child(shape)
	doorway.add_child(area)
	_room.add_child(doorway)
	_doorways[key] = doorway


## A post where walls meet at an angle, or a wall ends; none along a
## straight run.
static func _needs_post(vertex: Vector2i, kind_at: Callable) -> bool:
	var directions: Array[Vector2] = []
	for entry: Array in WallEdge.edges_at_vertex(vertex):
		var kind: int = kind_at.call(entry[0])
		if kind == Terrain.Edge.OPEN:
			continue
		directions.append(WallEdge.away_from(entry[0], entry[1]))
	if directions.size() != 2:
		return true
	return directions[0].dot(directions[1]) > -0.9


func _add_post(vertex: Vector2i) -> void:
	var post: Node3D
	if BOX_WALLS:
		post = _box(Vector3(POST_SIZE, WALL_HEIGHT, POST_SIZE), _stone_opaque)
	else:
		post = _kit("wall-narrow-corner")
		post.scale = Vector3(1.0, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	post.name = "Post_%d_%d" % [vertex.x, vertex.y]
	post.position = Vector3(vertex.x - 0.5, 0.0, vertex.y - 0.5)
	_room.add_child(post)
	_posts[vertex] = post


func _add_fire(cell: Vector2i) -> void:
	var quad := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.9, 0.9)
	var material := StandardMaterial3D.new()
	material.albedo_color = FIRE
	material.emission_enabled = true
	material.emission = FIRE
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	quad.mesh = mesh
	quad.position = _tile_position(cell) + Vector3(0.0, ON_FLOOR, 0.0)
	_room.add_child(quad)
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.5
	light.omni_range = 2.5
	light.position = _tile_position(cell) + Vector3(0.0, 0.5, 0.0)
	_room.add_child(light)


# --- Near and far ----------------------------------------------------------------

## The 2D near rule for this camera: the cell behind an edge's
## camera-facing side is its -x / -y cell when the +x / +y face points
## toward the camera, else the other; the wall is near when that cell is
## walkable.
func _is_near(key: Vector3i) -> bool:
	var toward := _camera_offset()
	var toward_grid := Vector2(toward.x, toward.z)
	var normal := Vector2(1, 0) if key.z == Terrain.EAST else Vector2(0, 1)
	var behind := Vector2i(key.x, key.y)
	if normal.dot(toward_grid) < -0.0001:
		behind += Vector2i(normal)
	return behind in _terrain["floor"]


func _classify_walls() -> void:
	var near_keys: Dictionary[Vector3i, bool] = {}
	for key in _walls:
		var near := _is_near(key)
		near_keys[key] = near
		_set_stone(_walls[key], near)
	for key in _doorways:
		var near := _is_near(key)
		near_keys[key] = near
		_set_stone(_doorways[key].get_node("Frame"), near)
	var edges: Dictionary = _terrain["edges"]
	for vertex in _posts:
		var all_near := true
		for entry: Array in WallEdge.edges_at_vertex(vertex):
			if edges.get(entry[0], Terrain.Edge.OPEN) != Terrain.Edge.OPEN and not near_keys.get(entry[0], false):
				all_near = false
		_set_stone(_posts[vertex], all_near)


## A near piece is see-through and casts no shadow, so a lantern behind it
## still lights the floor in front. Every mesh under [param piece] takes
## the kit material pair, or the flat stone pair for a box.
func _set_stone(piece: Node3D, near: bool) -> void:
	for node in _descendants(piece):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var boxed := mesh.mesh is BoxMesh
		if boxed:
			mesh.material_override = _stone_near if near else _stone_opaque
		else:
			mesh.material_override = _kit_near if near else _kit_opaque
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if near \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Entities ----------------------------------------------------------------

## One puppet per spawned entity, placed where its 2D node is (the grid
## position under the azimuth-0 projection), removed when it goes; its
## speech line follows the 2D one.
func _sync_puppets() -> void:
	var seen: Dictionary[int, bool] = {}
	for entity in World.get_entities():
		if not entity.spawned:
			continue
		var id := entity.get_instance_id()
		seen[id] = true
		if not _puppets.has(id):
			_puppets[id] = _make_puppet(entity)
		var puppet := _puppets[id]
		var grid := Iso.local_to_grid(entity.position)
		puppet.position = Vector3(grid.x, 0.0, grid.y)
		var speech := puppet.get_node_or_null("Speech") as Label3D
		if speech != null:
			var line := entity.speech()
			speech.visible = not line.is_empty()
			speech.text = line
	for id in _puppets.keys():
		if not seen.has(id):
			_puppets[id].queue_free()
			_puppets.erase(id)


func _make_puppet(entity: GridEntity) -> Node3D:
	var puppet := Node3D.new()
	puppet.name = entity.name
	var shape := EntityFactory.shape_name_for(entity.spawn_spec)
	var height: float = Iso.HEIGHTS[shape]
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = (_shapes[shape] as Callable).call()
	body.position.y = height * 0.5
	var material := StandardMaterial3D.new()
	var sprite := entity.get_node_or_null("Sprite") as Sprite2D
	material.albedo_color = sprite.modulate if sprite != null else Color.WHITE
	material.roughness = 0.8
	# A touch of glow so a body reads in the dark away from any light.
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.12
	body.material_override = material
	puppet.add_child(body)
	# The pick shape: the body's own.
	var area := Area3D.new()
	area.name = "Pick"
	area.set_meta("entity", entity.get_instance_id())
	var collision := CollisionShape3D.new()
	collision.shape = _pick_shape(shape, body.mesh)
	collision.position.y = height * 0.5
	area.add_child(collision)
	puppet.add_child(area)
	if entity.is_creature():
		var caption: String = entity.label if not entity.label.is_empty() else entity.name
		puppet.add_child(_label("Name", caption, Color.WHITE, height + 0.35))
		puppet.add_child(_label("Speech", "", SPEECH, height + 0.75))
	if entity is Player or entity is Companion:
		var light := OmniLight3D.new()
		light.name = "Lantern"
		light.light_color = PLAYER_LIGHT
		light.light_energy = 1.2
		light.omni_range = PLAYER_LIGHT_RANGE
		light.shadow_enabled = true
		# Above the head: inside the body it would light the body from within
		# and leave its outside in its own shadow.
		light.position.y = height + 0.6
		puppet.add_child(light)
	add_child(puppet)
	return puppet


func _pick_shape(shape_name: String, mesh: Mesh) -> Shape3D:
	match shape_name:
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = (mesh as CapsuleMesh).radius
			capsule.height = (mesh as CapsuleMesh).height
			return capsule
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = (mesh as SphereMesh).radius
			return sphere
		"barrel":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = (mesh as CylinderMesh).top_radius
			cylinder.height = (mesh as CylinderMesh).height
			return cylinder
		_:
			var box := BoxShape3D.new()
			box.size = (mesh as BoxMesh).size
			return box


func _label(name_: String, text: String, color: Color, height: float) -> Label3D:
	var label := Label3D.new()
	label.name = name_
	label.text = text
	label.visible = not text.is_empty()
	label.pixel_size = LABEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.position.y = height
	return label


## The leaf of each door follows its Door node's open state.
func _sync_doors() -> void:
	for door in World.get_doors():
		var doorway: Node3D = _doorways.get(door.key)
		if doorway == null:
			continue
		var hinge := doorway.get_node("Hinge") as Node3D
		hinge.visible = not door.is_broken()
		var target: float = PI * 0.5 if door.is_open() else 0.0
		hinge.rotation.y = move_toward(hinge.rotation.y, target, get_process_delta_time() / Door.SWING_SECONDS * PI * 0.5)
