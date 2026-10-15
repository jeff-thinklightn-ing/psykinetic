extends RefCounted
## --test-smooth: how smoothly a client draws things, frame by frame, for
## tools/net_smooth.sh. Every frame it takes where the local player is
## drawn, where everything else near it is drawn, and where the camera
## looks, and counts the frames one of them moved farther than anything
## moves smoothly in a frame (a jump: a snap, a slide cut short, a backlog
## popping at once), the worst of them, and the frames it went back the way
## it came (a rubber band). Main reports it at the end with the client's
## corrections (NetStats).

## Farther than this in a frame is a jump: the fastest slide (a push, half a
## tile a tick) moves a twelfth of a tile in a frame at 60 fps.
const JUMP_TILES := 0.4
## A frame longer than this is the machine's hitch, not the network's: the
## frame's movement is not counted.
const HITCH_SECONDS := 0.1
## This far or more in a frame is a teleport (a respawn, a change of zone),
## counted apart: it is meant to be instant.
const TELEPORT_TILES := 8.0
## Others are watched this near the local player (about the screen).
const NEAR_TILES := 12
## A back step: this far (tiles) back along the way it was going over the
## last BACK_WINDOW frames.
const BACK_TILES := 0.15
const BACK_WINDOW := 6

var _started := 0
## The first TELL_JUMPS jumps are each logged, to see what made them.
const TELL_JUMPS := 40
var _told := 0
var _frames := 0
## Per instance id: [the last drawn position, its way over the last frames].
var _last: Dictionary[int, Array] = {}
## "self", "others", "camera": {jumps, worst, backs}.
var _kinds := {}


func _init() -> void:
	_started = Time.get_ticks_msec()
	for kind in ["self", "others", "camera"]:
		_kinds[kind] = {"jumps": 0, "worst": 0.0, "backs": 0, "teleports": 0}


## One frame: [param camera] is where the camera looks, in tiles.
func sample(player: Player, camera: Vector2, delta: float) -> void:
	_frames += 1
	var counted := delta <= HITCH_SECONDS
	var seen: Dictionary[int, bool] = {}
	_take("self", -1, String(player.name), Iso.local_to_grid(player.position), counted, seen)
	_take("camera", -2, "camera", camera, counted, seen)
	for entity in World.get_entities():
		if entity == player or not entity.spawned or World.distance(entity.tile, player.tile) > NEAR_TILES:
			continue
		_take("others", entity.get_instance_id(), String(entity.name), Iso.local_to_grid(entity.position), counted, seen)
	for id: int in _last.keys():
		if not seen.has(id):
			_last.erase(id)  # Gone or out of sight: a fresh start when back.


func _take(kind: String, id: int, label: String, at: Vector2, counted: bool, seen: Dictionary[int, bool]) -> void:
	seen[id] = true
	if not _last.has(id):
		_last[id] = [at, PackedVector2Array()]
		return
	var last: Array = _last[id]
	var moved: Vector2 = at - (last[0] as Vector2)
	var trail: PackedVector2Array = last[1]
	if counted:
		var stats: Dictionary = _kinds[kind]
		if moved.length() >= TELEPORT_TILES:
			stats["teleports"] += 1  # A respawn or a change of zone: meant.
		elif moved.length() > JUMP_TILES:
			stats["jumps"] += 1
			stats["worst"] = maxf(stats["worst"], moved.length())
			if _told < TELL_JUMPS:
				_told += 1
				print("[smooth] jump: %s %s %.2f tiles, %s to %s, tick %d + %.2f" % [kind, label, moved.length(),
					last[0], at, World.tick, World.tick_alpha])
		# The way it was going: the sum of the last frames' moves.
		var way := Vector2.ZERO
		for step in trail:
			way += step
		if way.length() > 0.05 and moved.dot(way.normalized()) < -BACK_TILES / BACK_WINDOW:
			stats["backs"] += 1
	trail.append(moved)
	if trail.size() > BACK_WINDOW:
		trail.remove_at(0)
	_last[id] = [at, trail]


## "[smooth] 60.0 s, 3600 frames; self: 2 jumps (2.0/min), worst 1.40 tiles, 5 back; ..."
func report() -> String:
	var minutes := maxf((Time.get_ticks_msec() - _started) / 60000.0, 0.001)
	var parts: Array[String] = []
	for kind in ["self", "others", "camera"]:
		var stats: Dictionary = _kinds[kind]
		parts.append("%s: %d jumps (%.1f/min), worst %.2f tiles, %d back (%.1f/min), %d teleports" % [kind, stats["jumps"],
			stats["jumps"] / minutes, stats["worst"], stats["backs"], stats["backs"] / minutes, stats["teleports"]])
	return "[smooth] %.1f s, %d frames; %s" % [minutes * 60.0, _frames, "; ".join(parts)]
