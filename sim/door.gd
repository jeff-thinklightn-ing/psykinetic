class_name Door
extends Node2D
## A door on an edge: a wall that can be open or closed, and that breaks if
## it is wood and takes enough impact. Spawned by the server through the
## MultiplayerSpawner like an entity, so every client has one; open and hp
## replicate. It is not a GridEntity: it occupies no cell, it is a property
## of the edge, and World consults it through its registry.
##
## Drawn here as a wall-height object: a jamb post at each end of the edge,
## full wall height whatever the walls beside it do, and a panel between
## them that swings about the hinge post. World changes open and hp;
## nothing else does.

const REPLICATED := ["open", "hp"]
const SWING_SECONDS := 0.25
const PANEL := Color(0.62, 0.45, 0.28)
const PANEL_EDGE := Color(0.25, 0.17, 0.1, 0.9)
const PANEL_TOP := Color(0.6, 0.625, 0.72)
const POST := Color(0.36, 0.3, 0.26)
const POST_TOP := Color(0.5, 0.43, 0.37)
const POST_WIDTH := 3.0

var key := Vector3i.ZERO
var open := false
var hp := 20
var max_hp := 20
var body_material := GridEntity.BodyMaterial.WOOD
## 0 closed .. 1 fully open, eased toward the state each frame.
var _swing := 0.0


func _init() -> void:
	var config := SceneReplicationConfig.new()
	for property in REPLICATED:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	synchronizer.replication_config = config
	add_child(synchronizer)


## Builds one from a spawn spec: {script, name, edge: [x, y, side], props}.
static func build(spec: Dictionary) -> Door:
	var door := Door.new()
	door.name = str(spec.get("name", "Door"))
	var edge: Array = spec.get("edge", [0, 0, 0])
	door.key = Vector3i(int(edge[0]), int(edge[1]), int(edge[2]))
	var props: Dictionary = spec.get("props", {})
	for property: String in props:
		door.set(property, props[property])
	door.hp = door.max_hp
	# Drawn with its -x / -y cell, a hair nearer the camera than what stands
	# on that cell, so the face is in front of it and behind the next cell.
	door.position = Iso.tile_to_local(Vector2i(door.key.x, door.key.y)) + Vector2(0, 0.5)
	return door


func _ready() -> void:
	World.register_door(self)
	_swing = 1.0 if is_open() else 0.0


func _exit_tree() -> void:
	World.unregister_door(self)


func is_broken() -> bool:
	return max_hp > 0 and hp <= 0


## Open, or broken: either way the edge is passable and see-through.
func is_open() -> bool:
	return open or is_broken()


func _process(delta: float) -> void:
	var target := 1.0 if is_open() else 0.0
	if not is_equal_approx(_swing, target):
		_swing = move_toward(_swing, target, delta / SWING_SECONDS)
		queue_redraw()


## The panel as drawn now, in local space: hinge end, free end, and the two
## above them. It swings in the ground plane about the hinge, from along
## the edge toward across it, so its screen shape follows the grid.
func face_polygon() -> PackedVector2Array:
	var ends := WallEdge.endpoints(key)
	var hinge: Vector2 = ends[0]
	var angle := _swing * PI * 0.5
	var free := hinge + WallEdge.screen(_panel_grid(angle))
	var up := Vector2(0, -WallEdge.full_height())
	return PackedVector2Array([hinge, free, free + up, hinge + up])


## The panel's direction in grid units at [param angle] from the edge.
func _panel_grid(angle: float) -> Vector2:
	return WallEdge.along_grid(key) * cos(angle) + WallEdge.across_grid(key) * sin(angle)


func _draw() -> void:
	var ends := WallEdge.endpoints(key)
	var up := Vector2(0, -WallEdge.full_height())
	if not is_broken():
		var angle := _swing * PI * 0.5
		var face := face_polygon()
		# The panel's thickness turns with it: across the edge when shut,
		# along it when open.
		var thickness := WallEdge.screen(
				WallEdge.across_grid(key) * cos(angle) - WallEdge.along_grid(key) * sin(angle)).normalized() * WallEdge.STRIP
		WallEdge.draw_wall(self, face[0], face[1], WallEdge.full_height(), thickness, PANEL, PANEL_TOP)
		draw_polyline(PackedVector2Array([face[0], face[1], face[2], face[3], face[0]]), PANEL_EDGE)
	var half := Vector2(POST_WIDTH * 0.5, 0)
	for end: Vector2 in ends:
		draw_colored_polygon(PackedVector2Array([end - half, end + half, end + half + up, end - half + up]), POST)
		draw_line(end - half + up, end + half + up, POST_TOP, 1.5)
