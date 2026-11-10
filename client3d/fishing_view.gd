extends Node
## Fishing seen and heard (805 amended (3); the coordinator: "seeing yourself
## and Wren cast, wait and pull one in"): for each player or companion whose
## GridEntity.fishing is set, a quill float on the water cell it names and a
## line from the rod's tip to it. The cast flies the float out in an arc
## (sfx.fish_cast, the whip) and lands (sfx.fish_plop); it sits bobbing while it waits; at the bite it dips and a
## ring spreads (sfx.fish_bite); landed, it is pulled in (sfx.fish_landed),
## missed, it lifts out (sfx.fish_missed). While it waits, the water laps and
## ticks at it (sfx.fish_wait, held from the plop to the bite or the pull;
## 805 amended (9)). Client only: it reads what is replicated each frame.
## A sound slot sound has no takes for yet is skipped quietly (SoundKit.has).

## Seconds the cast's flight takes (World.FISH_CAST_TICKS at its tick rate).
const CAST_SECONDS := 1.5
## The float's bob while it waits: metres, and cycles a second.
const BOB := 0.012
const BOB_RATE := 0.6
## How deep the float dips at the bite, and the bite's ring: its widest
## radius and its seconds.
const DIP := 0.06
const RING_WIDEST := 0.6
const RING_SECONDS := 0.7
## The rod's tip from the angler's feet: up, and out ahead.
const TIP_UP := 1.6
const TIP_OUT := 1.2
## Seconds a landed or missed float takes to come back to the tip.
const PULL_SECONDS := 0.4

## The view (Client3D): its puppets and water surface are read.
var view: Node = null
## The angler's name -> {float, line, state, since, ring}.
var casts: Dictionary[String, Dictionary] = {}
## Each state seen begin, for tests: [key, state].
var seen: Array[Array] = []

var _clock := 0.0


func _process(delta: float) -> void:
	if view == null:
		return
	_clock += delta
	var live: Dictionary[String, bool] = {}
	for entity: GridEntity in World.sought():
		if entity.fishing.is_empty():
			continue
		var key := String(entity.name)
		live[key] = true
		show_cast(key, entity)
	for key: String in casts.keys():
		if not live.has(key):
			_drop(key)


## [param entity]'s cast drawn (made the first time), by its state.
func show_cast(key: String, entity: GridEntity) -> void:
	var state := str(entity.fishing.get("state", ""))
	var at: Variant = entity.fishing.get("at", Vector2i.ZERO)
	var cell: Vector2i = at if at is Vector2i else Vector2i.ZERO
	if not casts.has(key):
		casts[key] = _make()
	var cast: Dictionary = casts[key]
	if cast["state"] != state:
		_begin(key, cast, state, cell)
	var tip := _tip(entity)
	var water := Vector3(cell.x, _surface(cell), cell.y)
	var since := _clock - float(cast["since"])
	var bob := sin(_clock * TAU * BOB_RATE) * BOB
	var spot := water + Vector3(0, bob, 0)
	match state:
		"cast":
			var t := clampf(since / CAST_SECONDS, 0.0, 1.0)
			spot = tip.lerp(water, t) + Vector3(0, sin(t * PI) * 1.2, 0)
		"bite":
			spot = water + Vector3(0, -DIP * (0.6 + 0.4 * sin(since * 30.0)), 0)
		"landed", "missed":
			spot = water.lerp(tip, clampf(since / PULL_SECONDS, 0.0, 1.0))
	var bobber: Node3D = cast["float"]
	bobber.position = spot
	var lap: Variant = cast.get("lap")
	if lap != null and is_instance_valid(lap):
		view.sfx.steer(lap, spot)
	_line(cast["line"], tip, spot)
	var ring: MeshInstance3D = cast["ring"]
	ring.visible = state == "bite" and since < RING_SECONDS
	if ring.visible:
		var grown := since / RING_SECONDS
		ring.position = water + Vector3(0, 0.01, 0)
		ring.scale = Vector3.ONE * lerpf(0.1, RING_WIDEST, grown)
		(ring.material_override as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - grown)


## A state begun: its sound, and noted.
func _begin(key: String, cast: Dictionary, state: String, cell: Vector2i) -> void:
	cast["state"] = state
	cast["since"] = _clock
	seen.append([key, state])
	var slot: String = {"cast": "sfx.fish_cast", "wait": "sfx.fish_plop", "bite": "sfx.fish_bite", "landed": "sfx.fish_landed",
		"missed": "sfx.fish_missed"}.get(state, "")
	var water := Vector3(cell.x, _surface(cell), cell.y)
	if not slot.is_empty() and SoundKit.has(slot) and view.get("sfx") != null:
		view.sfx.play(slot, water)
	# The line in water: its lap held only while it waits.
	_quiet(cast)
	if state == "wait" and view.get("sfx") != null:
		cast["lap"] = view.sfx.hold("sfx.fish_wait", water)


## A float, its line and its ring, under the view.
func _make() -> Dictionary:
	var bobber := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.035
	ball.height = 0.12
	bobber.mesh = ball
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("e8e0c8")  # A quill's pale shaft.
	bobber.material_override = paint
	view.add_child(bobber)
	var line := MeshInstance3D.new()
	line.mesh = ImmediateMesh.new()
	var thread := StandardMaterial3D.new()
	thread.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	thread.albedo_color = Color(0.85, 0.85, 0.8, 0.7)
	thread.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.material_override = thread
	view.add_child(line)
	var ring := MeshInstance3D.new()
	var disc := TorusMesh.new()
	disc.inner_radius = 0.9
	disc.outer_radius = 1.0
	ring.mesh = disc
	var foam := StandardMaterial3D.new()
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.albedo_color = Color(1, 1, 1, 0.6)
	ring.material_override = foam
	ring.visible = false
	view.add_child(ring)
	return {"float": bobber, "line": line, "ring": ring, "state": "", "since": _clock}


## The line drawn from [param from] to [param to].
func _line(line: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var mesh: ImmediateMesh = line.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()


## The rod's tip: the held rod's own tip (pc-character's Client3D.rod_tip,
## art-kit's "tip" socket); with no rod drawn, up from the angler's drawn
## place and out along its facing.
func _tip(entity: GridEntity) -> Vector3:
	var puppet: Node3D = view._puppets.get(entity.get_instance_id())
	var held: Variant = Client3D.rod_tip(puppet)
	if held is Vector3:
		return held
	var feet: Vector3 = puppet.position if puppet != null else view._tile_position(entity.tile)
	var ahead := Vector2(entity.facing).normalized() if entity.facing != Vector2i.ZERO else Vector2(0, 1)
	return feet + Vector3(ahead.x * TIP_OUT, TIP_UP, ahead.y * TIP_OUT)


## The water's top at [param cell].
func _surface(cell: Vector2i) -> float:
	return view._water_surface(Vector2(cell))


## [param cast]'s held lap, if any, stopped.
func _quiet(cast: Dictionary) -> void:
	var lap: Variant = cast.get("lap")
	if lap != null and is_instance_valid(lap):
		lap.queue_free()
	cast["lap"] = null


## [param key]'s float, line and ring gone.
func _drop(key: String) -> void:
	_quiet(casts[key])
	for part: String in ["float", "line", "ring"]:
		var node: Node = casts[key][part]
		if is_instance_valid(node):
			node.queue_free()
	casts.erase(key)


func _exit_tree() -> void:
	for key: String in casts.keys():
		_drop(key)
