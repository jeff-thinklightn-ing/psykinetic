class_name Door
extends Node2D
## A door on an edge: a wall that can be open or closed, and that breaks if
## it is wood and takes enough impact. Spawned by the server through the
## MultiplayerSpawner like an entity, so every client has one; open and hp
## replicate. It is not a GridEntity: it occupies no cell, it is a property
## of the edge, and World consults it through its registry.
##
## Drawn here as a thin tall face on the edge that swings about one end.
## World changes open and hp; nothing else does.

const REPLICATED := ["open", "hp"]
const SWING_SECONDS := 0.25
const FACE := Color(0.62, 0.45, 0.28)
const FACE_EDGE := Color(0.25, 0.17, 0.1, 0.9)
const POST := Color(0.3, 0.3, 0.38)
const HIDING_ALPHA := 0.3

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


## The face as drawn now, in local space: hinge end, free end, and the two
## above them.
func face_polygon() -> PackedVector2Array:
	var ends := WallEdge.endpoints(key)
	var hinge: Vector2 = ends[0]
	var along: Vector2 = ends[1] - hinge
	# Swinging about the hinge toward the perpendicular, which on this grid is
	# the other axis's screen vector.
	var across := Vector2(along.x, -along.y)  # The other cell axis, same length.
	var angle := _swing * PI * 0.5
	var free := hinge + along * cos(angle) + across * sin(angle)
	var up := Vector2(0, -Iso.height_px("wall"))
	return PackedVector2Array([hinge, free, free + up, hinge + up])


func _draw() -> void:
	var ends := WallEdge.endpoints(key)
	var up := Vector2(0, -Iso.height_px("wall"))
	for end: Vector2 in ends:
		WallEdge.draw_post(self, end, up, POST)
	if is_broken():
		return
	var face := face_polygon()
	draw_colored_polygon(face, FACE)
	draw_polyline(PackedVector2Array([face[0], face[1], face[2], face[3], face[0]]), FACE_EDGE)
