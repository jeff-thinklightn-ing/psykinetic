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
## Per body (678's companion question): "name (Class)" -> {"backs": frames
## gone back, "events": runs of them, "tile_backs": its tile back to the one
## before (A, B, A: the server's own), "near_swap": events within
## SWAP_FRAMES after a swap}.
var _bodies := {}
## Per id: [the tile before, the tile now].
var _tiles: Dictionary[int, Array] = {}
## Per id: whether it was going back last frame (an event is a run of them).
var _backing: Dictionary[int, bool] = {}
## Swaps seen: the player and a body trading tiles in one frame (679).
var _swaps := 0
var _since_swap := 1000000
const SWAP_FRAMES := 30


func _init() -> void:
	_started = Time.get_ticks_msec()
	for kind in ["self", "others", "camera"]:
		_kinds[kind] = {"jumps": 0, "worst": 0.0, "backs": 0, "teleports": 0}


## One frame: [param camera] is where the camera looks, in tiles.
func sample(player: Player, camera: Vector2, delta: float) -> void:
	_frames += 1
	var counted := delta <= HITCH_SECONDS
	var seen: Dictionary[int, bool] = {}
	_since_swap += 1
	var player_was: Array = _tiles.get(-1, [player.tile, player.tile])
	var player_moved: bool = player.tile != player_was[1]
	_take("self", -1, _label(player), Iso.local_to_grid(player.position), counted, seen, player.tile)
	_take("camera", -2, "camera", camera, counted, seen)
	for entity in World.get_entities():
		if entity == player or not entity.spawned or World.distance(entity.tile, player.tile) > NEAR_TILES:
			continue
		var id := entity.get_instance_id()
		var was: Array = _tiles.get(id, [entity.tile, entity.tile])
		if player_moved and entity.tile == player_was[1] and player.tile == was[1] and entity.tile != was[1]:
			_swaps += 1
			_since_swap = 0
		_take("others", id, _label(entity), Iso.local_to_grid(entity.position), counted, seen, entity.tile)
	for id: int in _last.keys():
		if not seen.has(id):
			_last.erase(id)  # Gone or out of sight: a fresh start when back.
			_tiles.erase(id)
			_backing.erase(id)


static func _label(entity: GridEntity) -> String:
	var script: Script = entity.get_script()
	var kind: String = script.get_global_name() if script != null else ""
	return "%s (%s)" % [entity.name, kind] if not kind.is_empty() else String(entity.name)


func _take(kind: String, id: int, label: String, at: Vector2, counted: bool, seen: Dictionary[int, bool], tile := Vector2i(-99999, -99999)) -> void:
	seen[id] = true
	var body: Dictionary = _bodies.get(label, {"backs": 0, "events": 0, "tile_backs": 0, "near_swap": 0})
	if kind != "camera":
		_bodies[label] = body
	if tile.x != -99999:
		var tiles: Array = _tiles.get(id, [tile, tile])
		if tile != tiles[1]:
			if tile == tiles[0]:
				body["tile_backs"] += 1
			tiles = [tiles[1], tile]
		_tiles[id] = tiles
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
		var back := way.length() > 0.05 and moved.dot(way.normalized()) < -BACK_TILES / BACK_WINDOW
		if back:
			stats["backs"] += 1
			if kind != "camera":
				body["backs"] += 1
				if not _backing.get(id, false):
					body["events"] += 1
					if _since_swap <= SWAP_FRAMES:
						body["near_swap"] += 1
		_backing[id] = back
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


## "[smooth] by body: Pip (Companion) 12 back in 3 runs, 1 tile back, 2 after a swap; ...; swaps 4": the
## bodies that went back, most first (678's companion question).
func bodies_report() -> String:
	var names: Array = _bodies.keys().filter(func(name: String) -> bool: return _bodies[name]["backs"] > 0 or _bodies[name]["tile_backs"] > 0)
	names.sort_custom(func(a: String, b: String) -> bool: return _bodies[a]["backs"] > _bodies[b]["backs"])
	var parts: Array[String] = []
	for name: String in names:
		var body: Dictionary = _bodies[name]
		parts.append("%s %d back in %d runs, %d tile back, %d after a swap" % [name, body["backs"], body["events"], body["tile_backs"], body["near_swap"]])
	return "[smooth] by body: %s; swaps %d" % ["; ".join(parts) if not parts.is_empty() else "none", _swaps]
