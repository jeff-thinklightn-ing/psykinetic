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
## Fish rising (805 amended (10), "fish rise"): on each body of water that
## fishes (World.fish_waters_of the room's terrain) a ring spreads now and
## then where a fish rises, more often the keener they feed
## (Weather.fish_feeding: dawn, dusk, rain), the same measure that brings
## the bite sooner, so the water says when to cast. Wider and slower than a
## bite's ring, never near a float, a fleck of spray when they feed hard.

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
## The bite read without sound (the coordinator after animation's take 2 at
## Jeff's pond: a 3.5 cm float was four pixels behind the reeds and nothing on
## screen changed at the bite). The float, stylized: FLOAT_RADIUS (m), its
## upper half a red cap. At the bite it is tugged right under twice, at
## BITE_TUGS seconds (the splashes), TUG_DOWN seconds down and TUG_BACK back,
## UNDER metres deep; between, it rides DIP low. Its ring spreads to
## BITE_RING_WIDEST (2 m across). The line hangs slack while it waits, sagging SAG of its
## length at the middle (SAG_LEAST to SAG_MOST metres), and is drawn straight
## and taut through the bite: the change that reads at any zoom.
const FLOAT_RADIUS := 0.12
const FLOAT_WHITE := Color("eee6d2")
const FLOAT_RED := Color("d42a1a")
const BITE_TUGS: Array[float] = [0.0, 1.2]
const TUG_DOWN := 0.25
const TUG_BACK := 0.35
const UNDER := 0.35
const BITE_RING_WIDEST := 1.0
## The bite's ring at its start, as opaque as this, fading as it spreads; a
## band BITE_RING_BAND of its radius wide (take 3: the thin pale ring didn't
## show at the usual zoom).
const BITE_RING_ALPHA := 0.95
const BITE_RING_BAND := 0.22
const SAG := 0.3
const SAG_LEAST := 0.35
const SAG_MOST := 1.4
const SAG_STEPS := 10
## The bite's ring again, every this many seconds while the float is down,
## and its splash once more this far in (805 amended (11): a bite of 3 s).
const BITE_RING_EVERY := 1.0
const BITE_SPLASH_AGAIN := 1.2
## The rod's tip from the angler's feet: up, and out ahead.
const TIP_UP := 1.6
const TIP_OUT := 1.2
## Seconds a landed or missed float takes to come back to the tip.
const PULL_SECONDS := 0.4

## Seconds between rises on a body: RISE_SLOW while fish hardly feed,
## RISE_FAST at their keenest (each gap drawn half to half again of it).
const RISE_SLOW := 9.0
const RISE_FAST := 1.5
## A rise's ring: its widest radius (m) and its seconds.
const RISE_WIDEST := 0.9
const RISE_SECONDS := 1.2
## A rise ring's whiteness at its start, fading to nothing as it spreads.
const RISE_ALPHA := 0.6
## In the dark a ring and its fleck dim to RISE_DARK of that (they are drawn
## unlit, and would glow), full again from daylight 0.5.
const RISE_DARK := 0.35
## No rise within this many metres of a float (it would read as a bite),
## nor farther than RISE_NEAR from the camera (unseen).
const RISE_CLEAR := 2.0
const RISE_NEAR := 45.0
## Feeding above this throws a fleck of spray as the ring starts.
const RISE_SPLASH := 0.6
const SPLASH_SECONDS := 0.3

## The view (Client3D): its puppets and water surface are read.
var view: Node = null
## The angler's name -> {float, line, state, since, ring}.
var casts: Dictionary[String, Dictionary] = {}
## Each state seen begin, for tests: [key, state].
var seen: Array[Array] = []

var _clock := 0.0
## Fishing water read from the view's terrain: body key -> its cells.
var bodies: Dictionary[String, Array] = {}
var _read_from: Variant = null
## Body key -> when it next rises (_clock).
var _next_rise: Dictionary[String, float] = {}
## Rises showing: {ring, splash, since, at, splashing}; spent ones kept for
## the next.
var rises: Array[Dictionary] = []
## Each rise begun, for tests: [body, cell, feeding].
var rose: Array[Array] = []
## For tests: feeding taken as this (0..1) instead of the clock's.
var feeding_override := -1.0
var _roll := RandomNumberGenerator.new()


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
	step_rises(view.get("_terrain") if view.get("_terrain") is Dictionary else {})


## How keenly fish feed now, here (Weather.fish_feeding for the live zone's
## region, or the tests' override).
func feeding() -> float:
	if feeding_override >= 0.0:
		return feeding_override
	return Weather.fish_feeding(World.fields.region, DayNight.now())


## The gap between rises on a body at [param keen] feeding (its middle).
static func rise_gap(keen: float) -> float:
	return lerpf(RISE_SLOW, RISE_FAST, clampf(keen, 0.0, 1.0))


## The fishing water of [param terrain] read as bodies (once per terrain).
func read_waters(terrain: Dictionary) -> void:
	if is_same(terrain, _read_from):
		return
	_read_from = terrain
	bodies.clear()
	_next_rise.clear()
	var waters := World.fish_waters_of(terrain)
	for cell: Vector2i in waters:
		var key: String = waters[cell]
		if not bodies.has(key):
			bodies[key] = []
		bodies[key].append(cell)


## The rises on [param terrain]'s fishing water, now (_clock): each body
## rises when due, then the next is drawn; the showing rings spread and fade.
func step_rises(terrain: Dictionary) -> void:
	read_waters(terrain)
	var keen := feeding()
	var dim := lerpf(RISE_DARK, 1.0, smoothstep(DayNight.NIGHT, 0.5, DayNight.daylight(DayNight.now())))
	for key: String in bodies:
		if not _next_rise.has(key):
			_next_rise[key] = _clock + rise_gap(keen) * _roll.randf()
		elif _clock >= _next_rise[key]:
			_next_rise[key] = _clock + rise_gap(keen) * _roll.randf_range(0.5, 1.5)
			var cells: Array = bodies[key]
			_rise(key, cells[_roll.randi() % cells.size()], keen)
	for rise: Dictionary in rises:
		var ring: MeshInstance3D = rise["ring"]
		if not ring.visible:
			continue
		var since := _clock - float(rise["since"])
		var grown := since / RISE_SECONDS
		ring.visible = grown < 1.0
		ring.scale = Vector3.ONE * lerpf(0.15, RISE_WIDEST, sqrt(clampf(grown, 0.0, 1.0)))
		(ring.material_override as StandardMaterial3D).albedo_color.a = RISE_ALPHA * dim * (1.0 - grown)
		var splash: MeshInstance3D = rise["splash"]
		var flick := since / SPLASH_SECONDS
		splash.visible = bool(rise["splashing"]) and flick < 1.0
		if splash.visible:
			splash.position = rise["at"] + Vector3(0, sin(flick * PI) * 0.12, 0)
			splash.scale = Vector3.ONE * (1.0 - flick)
			(splash.material_override as StandardMaterial3D).albedo_color.a = dim


## A fish rises at [param cell] of [param key]'s water, unless a float is
## near or the camera far.
func _rise(key: String, cell: Vector2i, keen: float) -> void:
	for cast: Dictionary in casts.values():
		var bobber: Node3D = cast["float"]
		if Vector2(bobber.position.x, bobber.position.z).distance_to(Vector2(cell)) < RISE_CLEAR:
			return
	var at := Vector3(cell.x, _surface(cell), cell.y)
	var camera := view.get_viewport().get_camera_3d() if view.is_inside_tree() else null
	if camera != null and Vector2(camera.global_position.x, camera.global_position.z).distance_to(
			Vector2(view.to_global(at).x, view.to_global(at).z)) > RISE_NEAR:
		return
	var rise: Dictionary = {}
	for spent: Dictionary in rises:
		if not (spent["ring"] as MeshInstance3D).visible:
			rise = spent
			break
	if rise.is_empty():
		rise = {"ring": _ring_mesh(), "splash": _splash_mesh()}
		rises.append(rise)
	rise["since"] = _clock
	rise["at"] = at
	rise["splashing"] = keen > RISE_SPLASH
	var ring: MeshInstance3D = rise["ring"]
	ring.position = at + Vector3(0, 0.01, 0)
	ring.scale = Vector3.ONE * 0.15
	ring.visible = true
	rose.append([key, cell, keen])


## A ring as a bite's (a thin torus, pale and fading), under the view.
func _ring_mesh() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var disc := TorusMesh.new()
	disc.inner_radius = 0.8  # A band a fifth of its radius: read from the low camera.
	disc.outer_radius = 1.0
	ring.mesh = disc
	var foam := StandardMaterial3D.new()
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.albedo_color = Color(1, 1, 1, RISE_ALPHA)
	ring.material_override = foam
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	view.add_child(ring)
	return ring


## A rise's fleck of spray, under the view.
func _splash_mesh() -> MeshInstance3D:
	var splash := MeshInstance3D.new()
	var drop := SphereMesh.new()
	drop.radius = 0.05
	drop.height = 0.1
	drop.radial_segments = 6
	drop.rings = 3
	splash.mesh = drop
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.92, 0.96, 1.0)
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash.material_override = white
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splash.visible = false
	view.add_child(splash)
	return splash


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
			spot = water + Vector3(0, -DIP - (UNDER - DIP) * tug(since), 0)
		"landed", "missed":
			spot = water.lerp(tip, clampf(since / PULL_SECONDS, 0.0, 1.0))
	var bobber: Node3D = cast["float"]
	bobber.position = spot
	var lap: Variant = cast.get("lap")
	if lap != null and is_instance_valid(lap):
		view.sfx.steer(lap, spot)
	_line(cast["line"], tip, spot, sag_of(tip, spot) if state == "wait" else 0.0)
	var ring: MeshInstance3D = cast["ring"]
	# 805 amended (11): the bite lasts long enough to answer (World.FISH_BITE_TICKS),
	# so its ring spreads again every BITE_RING_EVERY while the float is down,
	# and its splash sounds again once (BITE_SPLASH_AGAIN), so it is seen and heard.
	var ring_since := fmod(since, BITE_RING_EVERY)
	ring.visible = state == "bite" and ring_since < RING_SECONDS
	if state == "bite" and since >= BITE_SPLASH_AGAIN and not cast.get("splashed_again", false):
		cast["splashed_again"] = true
		if SoundKit.has("sfx.fish_bite") and view.get("sfx") != null:
			view.sfx.play("sfx.fish_bite", water)
	if ring.visible:
		var grown := ring_since / RING_SECONDS
		ring.position = water + Vector3(0, 0.01, 0)
		ring.scale = Vector3.ONE * lerpf(0.1, BITE_RING_WIDEST, grown)
		(ring.material_override as StandardMaterial3D).albedo_color.a = BITE_RING_ALPHA * (1.0 - grown)


## A state begun: its sound, and noted.
func _begin(key: String, cast: Dictionary, state: String, cell: Vector2i) -> void:
	cast["state"] = state
	cast["since"] = _clock
	cast["splashed_again"] = false
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
	ball.radius = FLOAT_RADIUS
	ball.height = FLOAT_RADIUS * 2.0
	bobber.mesh = ball
	var paint := StandardMaterial3D.new()
	paint.albedo_color = FLOAT_WHITE
	bobber.material_override = paint
	var cap := MeshInstance3D.new()  # Its upper half red, a hair proud of the white.
	var dome := SphereMesh.new()
	dome.radius = FLOAT_RADIUS * 1.02
	dome.height = FLOAT_RADIUS * 1.02
	dome.is_hemisphere = true
	cap.mesh = dome
	var red := StandardMaterial3D.new()
	red.albedo_color = FLOAT_RED
	cap.material_override = red
	bobber.add_child(cap)
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
	disc.inner_radius = 1.0 - BITE_RING_BAND
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


## How deep in the bite [param since] (seconds into it) the float is tugged,
## 0 to 1: 1 at the bottom of each of BITE_TUGS (TUG_DOWN down, TUG_BACK
## back), 0 between.
static func tug(since: float) -> float:
	var most := 0.0
	for at: float in BITE_TUGS:
		var t := since - at
		if t < 0.0:
			continue
		if t < TUG_DOWN:
			most = maxf(most, t / TUG_DOWN)
		elif t < TUG_DOWN + TUG_BACK:
			most = maxf(most, 1.0 - (t - TUG_DOWN) / TUG_BACK)
	return most


## How far a waiting line from [param from] to [param to] sags at its middle.
static func sag_of(from: Vector3, to: Vector3) -> float:
	return clampf(from.distance_to(to) * SAG, SAG_LEAST, SAG_MOST)


## The line drawn from [param from] to [param to], hanging [param sag]
## metres low at its middle (a parabola; 0: straight and taut), never below
## [param to]'s height short of it.
func _line(line: MeshInstance3D, from: Vector3, to: Vector3, sag := 0.0) -> void:
	var mesh: ImmediateMesh = line.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps := SAG_STEPS if sag > 0.0 else 1
	for i in steps + 1:
		var t := float(i) / steps
		var point := from.lerp(to, t)
		point.y = maxf(point.y - sag * 4.0 * t * (1.0 - t), to.y)
		mesh.surface_add_vertex(point)
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
	for rise: Dictionary in rises:
		for part: String in ["ring", "splash"]:
			var node: Node = rise[part]
			if is_instance_valid(node):
				node.queue_free()
	rises.clear()
