class_name Client3D
extends Node3D
## The 3D view of the game: step 1, the room. Instanced by Main under the
## same tree as the 2D view when the client runs with --renderer=3d, so all
## the net code, the entity specs, the settings file and the map data are
## the ones the 2D client uses; the 2D nodes are simply hidden. One tile is
## one unit: grid (x, y) is 3D (x, 0, y). The sim is the physics: there are
## no physics bodies here, only meshes.
##
## The room is built once from the parsed map (Terrain), out of the Kenney
## Castle Kit (art/kenney-castle, 1-unit modules): ground pieces for floor
## cells, the narrow wall segment for every wall edge, scaled to WALL_HEIGHT
## and thinned to the edge, a corner post at every vertex where walls meet
## at an angle or end, a doorway with a swinging leaf for every door. Fire
## is an emissive quad with a small light. Entities get a puppet each: a
## primitive at the scale table's size, tinted as the 2D sprite is, with a
## Label3D name; players and companions carry a warm light. The puppets
## follow the 2D entity nodes (the replicated state) every frame.
##
## The camera is orthographic, tilted CAMERA_PITCH from horizontal and
## yawed so that grid +x runs down-right and +y down-left as in the 2D
## diamond view, following the local player. Fixed for this step: no orbit,
## no picking, no movement input.

const KIT := "res://art/kenney-castle/Models/GLB format/"
const WALL_HEIGHT := 3.0
const KIT_WALL_HEIGHT := 1.31
## The narrow wall is 0.5 thick; an edge has none, so thin it to this.
const WALL_THICKNESS := 0.15
const POST_SIZE := 0.25
## Kit door leaf: 0.36 wide, 0.6 tall, in kit units.
const DOOR_LEAF_WIDTH := 0.359374
const CAMERA_PITCH := 50.0
const CAMERA_DISTANCE := 40.0
## Orthographic height in units: a 1.5-unit character, foreshortened by
## cos(CAMERA_PITCH), is about a twelfth of it.
const CAMERA_SIZE := 12.0
const CAMERA_FOLLOW_RATE := 6.0
const PLAYER_LIGHT_RANGE := 6.0
const PLAYER_LIGHT := Color(1.0, 0.82, 0.6)
const FIRE := Color(1.0, 0.45, 0.1)
const AMBIENT := Color(0.05, 0.05, 0.07)
const BACKGROUND := Color(0.02, 0.02, 0.025)
const SUN := Color(0.6, 0.7, 1.0)
const SUN_ENERGY := 0.25
## Label3D: units per font pixel, with the font size, for a name about a
## quarter unit tall.
const LABEL_SIZE := 0.004
const LABEL_FONT_SIZE := 64

## Shape -> [mesh factory, height in units].
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
var _room: Node3D
## Entity instance id -> its puppet.
var _puppets: Dictionary[int, Node3D] = {}
## Door instance id -> its leaf hinge.
var _door_leaves: Dictionary[int, Node3D] = {}
var _terrain: Dictionary = {}


## Builds the room and the fixed rig. [param terrain] is Terrain.parse's
## result, the same the 2D view paints from.
func setup(terrain: Dictionary) -> void:
	_terrain = terrain
	_build_environment()
	_build_camera()
	_build_room()


func _process(delta: float) -> void:
	_sync_puppets()
	_sync_doors()
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


## From the +x +z side, so grid +x comes toward the viewer down-right and
## +y down-left, as in the 2D view; CAMERA_PITCH above the ground plane.
func _place_camera() -> void:
	var pitch := deg_to_rad(CAMERA_PITCH)
	var horizontal := CAMERA_DISTANCE * cos(pitch)
	var offset := Vector3(horizontal / sqrt(2.0), CAMERA_DISTANCE * sin(pitch), horizontal / sqrt(2.0))
	_camera.position = _camera_target + offset
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


# --- Room ----------------------------------------------------------------------

static func _tile_position(tile: Vector2i) -> Vector3:
	return Vector3(tile.x, 0.0, tile.y)


func _kit(piece: String) -> Node3D:
	var scene: PackedScene = load(KIT + piece + ".glb")
	return scene.instantiate() as Node3D


func _build_room() -> void:
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	var fire: Array[Vector2i] = _terrain["fire"]
	for cell: Vector2i in _terrain["floor"]:
		var ground := _kit("ground")
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


## An edge on the ground: its midpoint and whether it runs along x (a
## south edge) or along y (an east edge).
static func _edge_midpoint(key: Vector3i) -> Vector3:
	if key.z == Terrain.EAST:
		return Vector3(key.x + 0.5, 0.0, key.y)
	return Vector3(key.x, 0.0, key.y + 0.5)


static func _edge_yaw(key: Vector3i) -> float:
	# The narrow wall runs along z; a south edge runs along x.
	return 0.0 if key.z == Terrain.EAST else PI * 0.5


## The kit's narrow wall occupies x in [-0.5, 0]: shifted to straddle the
## line, thinned, and stretched to WALL_HEIGHT.
func _wall_piece(piece: String) -> Node3D:
	var holder := Node3D.new()
	var mesh := _kit(piece)
	mesh.position = Vector3(0.25, 0.0, 0.0)
	var thin := WALL_THICKNESS / 0.5
	holder.scale = Vector3(thin, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	holder.add_child(mesh)
	return holder


func _add_wall(key: Vector3i) -> void:
	var wall := Node3D.new()
	wall.name = "Wall_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	wall.position = _edge_midpoint(key)
	wall.rotation.y = _edge_yaw(key)
	wall.add_child(_wall_piece("wall-narrow"))
	_room.add_child(wall)


## A doorway wall on the edge and a leaf hinged at its start end, found by
## the Door node's key when it syncs (see _sync_doors).
func _add_doorway(key: Vector3i) -> void:
	var doorway := Node3D.new()
	doorway.name = "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	doorway.position = _edge_midpoint(key)
	doorway.rotation.y = _edge_yaw(key)
	doorway.add_child(_wall_piece("wall-doorway"))
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	var leaf_scale := WALL_HEIGHT / KIT_WALL_HEIGHT
	var half_width := DOOR_LEAF_WIDTH * leaf_scale * 0.5
	hinge.position = Vector3(0.0, 0.0, -half_width)
	var leaf := _kit("door")
	leaf.scale = Vector3.ONE * leaf_scale
	leaf.position = Vector3(0.0, 0.0, half_width)
	hinge.add_child(leaf)
	doorway.add_child(hinge)
	_room.add_child(doorway)
	doorway.set_meta("key", key)


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
	var post := _kit("wall-narrow-corner")
	post.position = Vector3(vertex.x - 0.5, 0.0, vertex.y - 0.5)
	post.scale = Vector3(POST_SIZE / 0.5, WALL_HEIGHT / KIT_WALL_HEIGHT, POST_SIZE / 0.5)
	_room.add_child(post)


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
	quad.position = _tile_position(cell) + Vector3(0.0, 0.02, 0.0)
	_room.add_child(quad)
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.5
	light.omni_range = 2.5
	light.position = _tile_position(cell) + Vector3(0.0, 0.5, 0.0)
	_room.add_child(light)


# --- Entities ----------------------------------------------------------------

## One puppet per spawned entity, placed where its 2D node is (the grid
## position under the azimuth-0 projection), removed when it goes.
func _sync_puppets() -> void:
	var seen: Dictionary[int, bool] = {}
	for entity in World.get_entities():
		if not entity.spawned:
			continue
		var id := entity.get_instance_id()
		seen[id] = true
		if not _puppets.has(id):
			_puppets[id] = _make_puppet(entity)
		var grid := Iso.local_to_grid(entity.position)
		_puppets[id].position = Vector3(grid.x, 0.0, grid.y)
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
	var caption: String = entity.label if not entity.label.is_empty() else entity.name
	if entity.is_creature():
		var label := Label3D.new()
		label.name = "Name"
		label.text = caption
		label.pixel_size = LABEL_SIZE
		label.font_size = LABEL_FONT_SIZE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 12
		label.position.y = height + 0.35
		puppet.add_child(label)
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


## The leaf of each door follows its Door node's open state.
func _sync_doors() -> void:
	for door in World.get_doors():
		var id := door.get_instance_id()
		if not _door_leaves.has(id):
			for child in _room.get_children():
				if child.has_meta("key") and child.get_meta("key") == door.key:
					_door_leaves[id] = child.get_node("Hinge")
					break
		var hinge: Node3D = _door_leaves.get(id)
		if hinge == null:
			continue
		hinge.visible = not door.is_broken()
		var target: float = PI * 0.5 if door.is_open() else 0.0
		hinge.rotation.y = move_toward(hinge.rotation.y, target, get_process_delta_time() / Door.SWING_SECONDS * PI * 0.5)
