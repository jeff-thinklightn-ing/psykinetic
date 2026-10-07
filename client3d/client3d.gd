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
## creatures, a warm-white light on players and companions, and an Area3D
## of the same shape for picking. Puppets follow the 2D nodes every frame,
## so they move as those do: at a steady speed along the walk. A creature
## has a nose that turns with its shown facing, and lunges when it swings.
## Speech comes from the speech message (say) and shows for
## SPEECH_SECONDS.
##
## Camera: orthographic, tilted `pitch` from horizontal (it rests at
## `rest_pitch`, between PITCH_MIN and PITCH_MAX), yawed by `yaw` about
## the local player: 0 matches the 2D diamond (+x down-right, +y
## down-left). It rests only on the four diamond views: yaw 0 and each
## ORBIT_STEP (90°) from it. The ortho size grows with the tilt above
## CAMERA_PITCH, up to PEEK_PULL_BACK times at PITCH_MAX (size_for), so a
## steeper view also shows more round the player.
##
## Click scheme, by keys (Main drives them): W/S tilt the resting pitch at
## TILT_RATE while held, slowing into either end, and it stays where it is
## left; Q/E step from one diamond to the next in one ease of
## ORBIT_SECONDS; A/D turn the yaw at TURN_RATE while held and, let go, it
## carries on to the next diamond the way it was turning if it was more
## than TURN_COMMIT past the last one it passed, or goes back to that one,
## the settle starting at the turning speed so the release flows into it;
## a middle click levels the pitch back to CAMERA_PITCH. WASD scheme: a sideways middle drag turns
## the yaw freely and, let go, settles on the nearest diamond; a vertical
## one is a pitch peek, tilting from the resting pitch toward PEEK_PITCH in
## proportion to the drag (full over PEEK_DRAG_PX, eased) and springing
## back over PEEK_RETURN_SECONDS. The diamond and the resting pitch persist
## in settings.cfg (Net.camera_yaw, Net.camera_pitch); a peek saves
## nothing. The near/far rule reads only the yaw, so the near walls stay
## see-through through any tilt.
## While a movement key is held (frozen, set by Main) the yaw does not
## move at all; a drag meanwhile applies when the keys are let go. It
## follows the player; in WASD it leans toward the cursor as the 2D camera
## does (Main.camera_lean).
##
## Picking is by ray from the camera through the cursor: an entity or door
## Area3D first, else the floor plane, which Main snaps to the nearest
## walkable cell. The hover is a square outline of the cell, the click
## ripple a ring, the toss aim an arrow, all flat on the floor. All input
## is Main's; this view only answers its picks and draws what it is told.

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
## The resting yaws are multiples of this: the diamond views.
const ORBIT_STEP := 90.0
## A WASD middle drag let go: on to the nearest diamond, eased out.
const SETTLE_SECONDS := 0.25
## Q/E: one diamond to the next, eased in and out.
const ORBIT_SECONDS := 0.4
## A/D let go: past the last diamond by more than this, on to the next.
const TURN_COMMIT := 10.0
## A/D let go back to the diamond it came from: the settle takes the time
## a stop from the turning speed would, plus this, for the turn back.
const TURN_RETURN_EXTRA := 0.15
## Click scheme keys: A/D turn this fast (degrees a second); W/S tilt this
## fast between PITCH_MIN and PITCH_MAX, slowing over the last
## TILT_EASE_DEGREES at either end; a middle click levels the pitch to
## CAMERA_PITCH over LEVEL_SECONDS.
const TURN_RATE := 180.0
const TILT_RATE := 60.0
const PITCH_MIN := 40.0
const PITCH_MAX := 85.0
const TILT_EASE_DEGREES := 8.0
const LEVEL_SECONDS := 0.25
## The pitch peek: the tilt it goes to, the drag for all of it (screen
## px), how far it pulls back (ortho size), and the spring back.
const PEEK_PITCH := 85.0
const PEEK_DRAG_PX := 300.0
const PEEK_PULL_BACK := 1.2
const PEEK_RETURN_SECONDS := 0.25
const PLAYER_LIGHT_RANGE := 6.0
## Warm white, whatever the body's colour.
const PLAYER_LIGHT := Color(1.0, 0.93, 0.82)
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
## The hover outline: a square this far from the cell's centre, this thick.
const HOVER_HALF := 0.47
const HOVER_LINE := 0.05
const TOSS := Color(1.0, 0.85, 0.4, 0.85)
const TOSS_LENGTH := 1.3
const SPEECH_SECONDS := 4.0
## A swing pushes the body this far out toward the blow, and back.
const LUNGE := 0.3
const LUNGE_SECONDS := 0.16
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
## The camera's yaw now, and the diamond it rests at (a multiple of
## ORBIT_STEP).
var yaw := 0.0
var _yaw_step := 0.0
## The yaw easing toward a step: from, to, and how far along (1: at rest).
## Driven from _process, not a Tween, so it moves before Main's pick.
var _ease_from := 0.0
var _ease_to := 0.0
var _ease_t := 1.0
## How the ease runs: its length, and its curve (SINE_OUT for a settle,
## IN_OUT for Q/E, FLOW for an A/D release: a cubic that starts at
## _ease_velocity degrees a second and stops on the target).
enum Ease { SINE_OUT, IN_OUT, FLOW }
var _ease_seconds := SETTLE_SECONDS
var _ease_curve := Ease.SINE_OUT
var _ease_velocity := 0.0
## A/D: the way it is turning (0: not), for the release.
var _turning := 0.0
## WASD's middle drag: the yaw it started from, how far it has gone, and
## whether a release came while frozen (it settles when they unfreeze).
var _dragging := false
var _drag_base := 0.0
var _drag_offset := 0.0
var _settle_pending := false
## Held still by Main while a movement key is down.
var frozen := false
## The camera's tilt from horizontal now, in degrees, and where it rests:
## `pitch` is `rest_pitch` but during a pitch peek.
var pitch := CAMERA_PITCH
var rest_pitch := CAMERA_PITCH
## A middle click's levelling: from, and how far along (1: not levelling).
var _level_from := CAMERA_PITCH
var _level_t := 1.0
## The pitch peek: held, how far in (0 at rest .. 1 full), and the spring
## back's start and progress (1: not springing).
var _peeking := false
var _peek := 0.0
var _peek_from := 0.0
var _peek_t := 1.0
## WASD: the camera's lean toward the cursor, in grid units (Main.camera_lean).
var _lead := Vector2.ZERO
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
var _toss: MeshInstance3D
var _ring_mesh: ArrayMesh
## Entity instance id -> when its speech line goes (msec).
var _speech_until: Dictionary[int, int] = {}
var _terrain: Dictionary = {}


## Builds the room and the rig. [param terrain] is Terrain.parse's result,
## the same the 2D view paints from.
func setup(terrain: Dictionary) -> void:
	_terrain = terrain
	_ring_mesh = _make_ring(0.42, 0.5)
	_build_environment()
	_build_camera()
	_build_room()
	_hover = _make_flat(_make_square_outline(HOVER_HALF, HOVER_LINE), HOVER)
	_hover.visible = false
	add_child(_hover)
	_toss = _make_flat(_make_arrow(TOSS_LENGTH), TOSS)
	_toss.visible = false
	add_child(_toss)
	# Net has the saved yaw rounded to a diamond already; --test-yaw is
	# taken exactly, for screenshots, and rests on its nearest diamond.
	_yaw_step = nearest_diamond(Net.camera_yaw)
	yaw = Net.camera_yaw
	rest_pitch = clampf(Net.camera_pitch, PITCH_MIN, PITCH_MAX)
	pitch = rest_pitch
	_camera.size = size_for(pitch)
	_place_camera()
	_classify_walls()


func _process(delta: float) -> void:
	_sync_puppets()
	_sync_doors()
	_ease_yaw(delta)
	_ease_peek(delta)
	_ease_level(delta)
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


## The camera's offset from its target: `pitch` above the ground on the
## +x +z side (grid +x toward the viewer down-right, +y down-left, as in
## the 2D view), turned about the vertical by the yaw.
func _camera_offset() -> Vector3:
	var tilt := deg_to_rad(pitch)
	var horizontal := CAMERA_DISTANCE * cos(tilt)
	var offset := Vector3(horizontal / sqrt(2.0), CAMERA_DISTANCE * sin(tilt), horizontal / sqrt(2.0))
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
	_lead = Main.camera_lean(_lead, get_viewport(), yaw, delta)
	var rate := 1.0 - exp(-CAMERA_FOLLOW_RATE * delta)
	_camera_target = _camera_target.lerp(puppet.position + Vector3(_lead.x, 0.0, _lead.y), rate)
	_place_camera()


func _local_player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.owner_peer == Net.local_id and entity.spawned:
			return entity
	return null


# --- Orbit ---------------------------------------------------------------------

## The ortho size at [param degrees] of tilt: CAMERA_SIZE up to
## CAMERA_PITCH, growing to PEEK_PULL_BACK times it at PITCH_MAX.
static func size_for(degrees: float) -> float:
	var share := clampf(inverse_lerp(CAMERA_PITCH, PITCH_MAX, degrees), 0.0, 1.0)
	return CAMERA_SIZE * lerpf(1.0, PEEK_PULL_BACK, share)


## Click scheme, Q/E: the next diamond round, in one ease in and out;
## saved.
func orbit(direction: int) -> void:
	_settle_on(_yaw_step + ORBIT_STEP * signf(direction))
	_ease_seconds = ORBIT_SECONDS
	_ease_curve = Ease.IN_OUT


## Click scheme, A/D held: turn [param direction] (-1 or 1) for
## [param delta] seconds at TURN_RATE, through any angle.
func turn(direction: float, delta: float) -> void:
	_ease_t = 1.0
	_turning = signf(direction)
	_set_yaw(yaw + TURN_RATE * _turning * delta)


## Click scheme, A/D let go: on to the next diamond the way it was
## turning if it is more than TURN_COMMIT past the last one it passed, or
## back to that one (settle_target), saved. The settle starts at the
## turning speed and slows to a stop on the diamond: going on, in the
## time that stop takes (twice the distance over the speed); going back,
## it runs on a little, turns and comes back, TURN_RETURN_EXTRA longer.
func end_turn() -> void:
	var direction := _turning
	_turning = 0.0
	if direction == 0.0:
		return
	var target := settle_target(yaw, direction)
	var distance := (target - yaw) * direction
	_settle_on(target)
	_ease_curve = Ease.FLOW
	_ease_velocity = TURN_RATE * direction
	if distance > 0.0:
		_ease_seconds = 2.0 * distance / TURN_RATE
	else:
		_ease_seconds = 2.0 * absf(distance) / TURN_RATE + TURN_RETURN_EXTRA
	if _ease_seconds <= 0.0:
		_ease_t = 1.0


## Where an A/D turn let go at [param degrees], going [param direction],
## settles: the last diamond it passed (or is on), or the next one along
## if it is more than TURN_COMMIT past it.
static func settle_target(degrees: float, direction: float) -> float:
	var passed := floorf(degrees / ORBIT_STEP) * ORBIT_STEP if direction > 0.0 \
			else ceilf(degrees / ORBIT_STEP) * ORBIT_STEP
	if (degrees - passed) * direction > TURN_COMMIT:
		return passed + ORBIT_STEP * direction
	return passed


## Click scheme, W/S held: tilt the resting pitch [param direction] (1 up
## toward top-down, -1 down) for [param delta] seconds at TILT_RATE,
## slowing over the last TILT_EASE_DEGREES before either end. It stays
## where it is left.
func tilt(direction: float, delta: float) -> void:
	if _peeking or direction == 0.0:
		return
	_level_t = 1.0
	var limit := PITCH_MAX if direction > 0.0 else PITCH_MIN
	var left := absf(limit - rest_pitch)
	var speed := TILT_RATE * clampf(left / TILT_EASE_DEGREES, 0.1, 1.0)
	_set_rest_pitch(move_toward(rest_pitch, limit, speed * delta))


## Click scheme, W/S let go: the pitch is kept in the settings file.
func end_tilt() -> void:
	Net.camera_pitch = rest_pitch
	Net.save_view_settings()


## Click scheme, a middle click: level the pitch back to CAMERA_PITCH over
## LEVEL_SECONDS; saved.
func level_pitch() -> void:
	if _peeking:
		return
	_level_from = rest_pitch
	_level_t = 0.0
	Net.camera_pitch = CAMERA_PITCH
	Net.save_view_settings()


func _ease_level(delta: float) -> void:
	if _level_t >= 1.0:
		return
	_level_t = minf(_level_t + delta / LEVEL_SECONDS, 1.0)
	_set_rest_pitch(lerpf(_level_from, CAMERA_PITCH, sin(_level_t * PI * 0.5)))


func _set_rest_pitch(degrees: float) -> void:
	rest_pitch = degrees
	if not _peeking and _peek_t >= 1.0:
		_set_pitch(degrees)


func _set_pitch(degrees: float) -> void:
	pitch = degrees
	_camera.size = size_for(degrees)
	_place_camera()


## The middle button went down on a vertical drag: a pitch peek from
## wherever the camera is now (a spring back under way stops there).
func begin_pitch_peek() -> void:
	_peeking = true
	_peek_t = 1.0


## The peek is [param pixels] of vertical drag, either way: that share of
## PEEK_DRAG_PX of the full tilt and pull back.
func pitch_peek(pixels: float) -> void:
	if _peeking:
		_set_peek(clampf(absf(pixels) / PEEK_DRAG_PX, 0.0, 1.0))


## The middle button came up: back to the resting pitch and size over
## PEEK_RETURN_SECONDS.
func end_pitch_peek() -> void:
	if not _peeking:
		return
	_peeking = false
	_peek_from = _peek
	_peek_t = 0.0


## The spring back, a sine out.
func _ease_peek(delta: float) -> void:
	if _peek_t >= 1.0:
		return
	_peek_t = minf(_peek_t + delta / PEEK_RETURN_SECONDS, 1.0)
	_set_peek(lerpf(_peek_from, 0.0, sin(_peek_t * PI * 0.5)))


## How far in the peek is, 0..1: the pitch and size it gives, eased in
## and out (smoothstep), so the tilt starts and ends gently.
func _set_peek(amount: float) -> void:
	_peek = amount
	var eased := smoothstep(0.0, 1.0, amount)
	_set_pitch(lerpf(rest_pitch, PEEK_PITCH, eased))


## WASD: the middle button went down; the drag turns from the yaw now.
func begin_drag() -> void:
	_dragging = true
	_settle_pending = false
	_drag_base = yaw
	_drag_offset = 0.0
	_ease_t = 1.0


## WASD: the drag is [param degrees] from where it began. Followed at once,
## unless frozen (then it waits) or easing back in after a freeze (then it
## is where the ease is going).
func drag(degrees: float) -> void:
	if not _dragging:
		return
	_drag_offset = degrees
	if frozen:
		return
	if _ease_t < 1.0:
		_ease_to = _drag_base + degrees
	else:
		_set_yaw(_drag_base + degrees)


## WASD: the middle button came up: settle on the nearest step, now or,
## if frozen, when the keys are let go.
func end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	if frozen:
		_settle_pending = true
	else:
		_settle_on(nearest_diamond(_drag_base + _drag_offset))


## Main: a movement key is (not) held. Held, the yaw stops where it is;
## let go, what the middle button did meanwhile applies.
func set_frozen(on: bool) -> void:
	if frozen == on:
		return
	frozen = on
	if on:
		return
	if _dragging:
		_ease_toward(_drag_base + _drag_offset)
	elif _settle_pending:
		_settle_pending = false
		_settle_on(nearest_diamond(_drag_base + _drag_offset))


## The diamond view nearest [param degrees]; half way between two (an
## axis view), the higher.
static func nearest_diamond(degrees: float) -> float:
	return snappedf(degrees, ORBIT_STEP)


## Eases to the diamond [param step], which the yaw then rests on and the
## settings file keeps.
func _settle_on(step: float) -> void:
	_yaw_step = step
	Net.camera_yaw = fposmod(step, 360.0)
	Net.save_view_settings()
	_ease_toward(step)


func _ease_toward(degrees: float) -> void:
	_ease_from = yaw
	_ease_to = degrees
	_ease_t = 0.0
	_ease_seconds = SETTLE_SECONDS
	_ease_curve = Ease.SINE_OUT


## One frame of the ease; nothing while frozen.
func _ease_yaw(delta: float) -> void:
	if frozen or _ease_t >= 1.0:
		return
	_ease_t = minf(_ease_t + delta / _ease_seconds, 1.0)
	var s := _ease_t
	match _ease_curve:
		Ease.IN_OUT:
			_set_yaw(lerpf(_ease_from, _ease_to, 0.5 - 0.5 * cos(s * PI)))
		Ease.FLOW:
			# Cubic Hermite: from _ease_from at _ease_velocity to _ease_to at rest.
			var along := (-2.0 * s * s * s + 3.0 * s * s) * (_ease_to - _ease_from)
			var carried := (s * s * s - 2.0 * s * s + s) * _ease_seconds * _ease_velocity
			_set_yaw(_ease_from + along + carried)
		_:
			_set_yaw(lerpf(_ease_from, _ease_to, sin(s * PI * 0.5)))


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


## Flat quads in the ground plane, each [a, b, c, d] corner order.
static func _flat_mesh(quads: Array[PackedVector2Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in quads:
		for i: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(quad[i].x, 0.0, quad[i].y))
	return surface.commit()


## A square outline round the cell's centre: the inner edge [param half]
## minus [param line] out, the outer [param half].
static func _make_square_outline(half: float, line: float) -> ArrayMesh:
	var inner := half - line
	var quads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, -inner), Vector2(-half, -inner)]),
		PackedVector2Array([Vector2(-half, inner), Vector2(half, inner), Vector2(half, half), Vector2(-half, half)]),
		PackedVector2Array([Vector2(-half, -inner), Vector2(-inner, -inner), Vector2(-inner, inner), Vector2(-half, inner)]),
		PackedVector2Array([Vector2(inner, -inner), Vector2(half, -inner), Vector2(half, inner), Vector2(inner, inner)]),
	]
	return _flat_mesh(quads)


## An arrow along +x from the origin, [param length] long.
static func _make_arrow(length: float) -> ArrayMesh:
	var shaft := 0.07
	var head := 0.3
	var neck := length - head
	var quads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(0.25, -shaft), Vector2(neck, -shaft), Vector2(neck, shaft), Vector2(0.25, shaft)]),
		# The head as a quad with two corners at the tip.
		PackedVector2Array([Vector2(neck, -head * 0.7), Vector2(length, 0.0), Vector2(length, 0.0), Vector2(neck, head * 0.7)]),
	]
	return _flat_mesh(quads)


func _make_ring_instance(color: Color) -> MeshInstance3D:
	return _make_flat(_ring_mesh, color)


func _make_flat(mesh: Mesh, color: Color) -> MeshInstance3D:
	var flat := MeshInstance3D.new()
	flat.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	flat.material_override = material
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return flat


## The hover outline on [param tile], or hidden.
func hover(tile: Vector2i, show: bool) -> void:
	_hover.visible = show
	if show:
		_hover.position = _tile_position(tile) + Vector3(0.0, ON_FLOOR, 0.0)


## The toss aim during a right drag: an arrow on the floor from
## [param target] the way it will go; hidden for ZERO or no target.
func toss_aim(target: GridEntity, direction: Vector2i) -> void:
	_toss.visible = direction != Vector2i.ZERO and is_instance_valid(target)
	if not _toss.visible:
		return
	var puppet: Node3D = _puppets.get(target.get_instance_id())
	var at := puppet.position if puppet != null else _tile_position(target.tile)
	_toss.position = Vector3(at.x, ON_FLOOR * 3.0, at.z)
	_toss.rotation.y = -Vector2(direction).angle()


## A line of speech over [param entity]'s puppet for SPEECH_SECONDS.
func say(entity: GridEntity, text: String) -> void:
	var puppet: Node3D = _puppets.get(entity.get_instance_id())
	if puppet == null:
		puppet = _make_puppet(entity)
		_puppets[entity.get_instance_id()] = puppet
	var speech := puppet.get_node_or_null("Speech") as Label3D
	if speech == null:
		return
	speech.text = text
	speech.visible = not text.is_empty()
	_speech_until[entity.get_instance_id()] = Time.get_ticks_msec() + roundi(SPEECH_SECONDS * 1000.0)


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
## position under the azimuth-0 projection), turned to its shown facing,
## removed when it goes. A speech line goes when its time is up.
func _sync_puppets() -> void:
	var seen: Dictionary[int, bool] = {}
	var now := Time.get_ticks_msec()
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
		var facing := puppet.get_node_or_null("Facing") as Node3D
		if facing != null:
			facing.rotation.y = -entity.shown_facing().angle()
		if _speech_until.has(id) and now >= _speech_until[id]:
			_speech_until.erase(id)
			var speech := puppet.get_node_or_null("Speech") as Label3D
			if speech != null:
				speech.visible = false
	for id in _puppets.keys():
		if not seen.has(id):
			_puppets[id].queue_free()
			_puppets.erase(id)
			_speech_until.erase(id)


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
		# The nose: which way it faces, turned each frame (see _sync_puppets).
		var pivot := Node3D.new()
		pivot.name = "Facing"
		var nose := MeshInstance3D.new()
		var nose_mesh := BoxMesh.new()
		nose_mesh.size = Vector3(0.18, 0.1, 0.14)
		nose.mesh = nose_mesh
		nose.material_override = material
		nose.position = Vector3(0.3, height * 0.72, 0.0)
		pivot.add_child(nose)
		puppet.add_child(pivot)
		entity.swung.connect(_on_swung.bind(entity.get_instance_id()))
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


## A swing: the body goes out toward the blow and back.
func _on_swung(direction: Vector2i, id: int) -> void:
	var puppet: Node3D = _puppets.get(id)
	if puppet == null:
		return
	var body := puppet.get_node("Body") as Node3D
	var rest := Vector3(0.0, body.position.y, 0.0)
	var out := rest + Vector3(direction.x, 0.0, direction.y).normalized() * LUNGE
	var tween := create_tween()
	tween.tween_property(body, "position", out, LUNGE_SECONDS * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position", rest, LUNGE_SECONDS * 0.6).set_ease(Tween.EASE_IN)


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
