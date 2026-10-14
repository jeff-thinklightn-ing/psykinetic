extends Node
## How big a map can be: makes a square dungeon of rooms SIZE cells across
## (8x8 rooms, a door in each wall, a torch, a crate and MONSTERS monsters
## per room, the grounds mixed), plays it as a host, and prints what it
## costs: reading it, opening its zone, painting it, the client's 3D build,
## the server's tick, long paths, nodes and memory, and, with a window,
## frames. One size per run, so each starts clean (tools/map_bench.ps1
## runs a series). With --players=N, N - 1 more players join (as peers of
## their own) and stand spread over the map on a grid, so more monsters are
## near someone and fighting; every player is then too tough to die, so
## nobody is away respawning for part of the run.
## With --cells-per-monster=N, each room's monster spots are kept at the
## rate that gives about N floor cells a monster (the castle has 42; the
## default, every spot, 32).
##   godot --path . --scene res://tools/map_bench.tscn -- --size=128 [--monsters=2] [--cells-per-monster=42] [--players=1] [--ticks=200] [--seconds=8]

const NAME := "bench"
const ROOM := 8

var size := 64
var monsters := 2
var players := 1
var cells_per_monster := 0.0
var ticks := 200
var seconds := 8.0
var _main: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() != 2:
			continue
		match pair[0]:
			"size": size = pair[1].to_int()
			"monsters": monsters = pair[1].to_int()
			"players": players = maxi(1, pair[1].to_int())
			"cells-per-monster": cells_per_monster = pair[1].to_float()
			"ticks": ticks = pair[1].to_int()
			"seconds": seconds = pair[1].to_float()
	var windowed := DisplayServer.get_name() != "headless"
	print("BENCH size=%d cells (%d floor), monsters/room=%d, cells/monster=%s, players=%d, %s" % [size, size * size,
		monsters, "every spot" if cells_per_monster <= 0.0 else str(cells_per_monster), players,
		"windowed" if windowed else "headless"])
	var memory_before := OS.get_static_memory_usage()

	var started := Time.get_ticks_usec()
	var layout := _layout()
	_report("make layout.png", started)
	Level.register(NAME, layout, null, {"name": "Bench"})
	started = Time.get_ticks_usec()
	var level := Level.load_level(NAME)
	_report("Level.load_level (parse)", started)
	print("BENCH entities in level: %d" % level["entities"].size())

	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17890)
	Net.companions = false
	Net.state_path = ""
	Net.map_name = NAME
	started = Time.get_ticks_usec()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_report("main ready (load, 2D paint, zone open, spawns, 3D build if windowed)", started)
	started = Time.get_ticks_usec()
	_main._paint_level()
	_report("  2D _paint_level again", started)
	if _main._client3d != null:
		started = Time.get_ticks_usec()
		_main._client3d.rebuild(_main._terrain, _main.level_centre)
		_report("  3D client rebuild again", started)

	if players > 1:
		_spread_players()
	World.step()
	var worst := 0
	var total := 0
	for i in ticks:
		started = Time.get_ticks_usec()
		World.step()
		var took := Time.get_ticks_usec() - started
		total += took
		worst = maxi(worst, took)
	print("BENCH tick: avg %.2f ms, worst %.2f ms over %d ticks (%d entities in the zone)" % [
		total / 1000.0 / ticks, worst / 1000.0, ticks, World.get_entities().size()])

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var path_total := 0
	var path_worst := 0
	var found := 0
	var tries := 20
	for i in tries:
		var from := Vector2i(rng.randi_range(0, size / 4), rng.randi_range(0, size / 4))
		var to := Vector2i(rng.randi_range(size * 3 / 4, size - 2), rng.randi_range(size * 3 / 4, size - 2))
		started = Time.get_ticks_usec()
		var path := World.find_path(from, to, true)
		var took := Time.get_ticks_usec() - started
		path_total += took
		path_worst = maxi(path_worst, took)
		if not path.is_empty():
			found += 1
	print("BENCH find_path corner to corner: avg %.2f ms, worst %.2f ms (%d/%d found)" % [
		path_total / 1000.0 / tries, path_worst / 1000.0, found, tries])

	# A door opened and shut, and the light and heat it lets through worked
	# out again, as a monster walking through does it.
	var doors := World.get_doors()
	var door_total := 0
	var door_worst := 0
	var flips := mini(40, doors.size())
	for i in flips:
		var door: Door = doors[rng.randi_range(0, doors.size() - 1)]
		for open: bool in [not door.open, door.open]:
			started = Time.get_ticks_usec()
			door.open = open
			World.light_at(Terrain.edge_cells(door.key)[0], false)
			var took := Time.get_ticks_usec() - started
			door_total += took
			door_worst = maxi(door_worst, took)
	if flips > 0:
		print("BENCH door flip (light and heat again): avg %.2f ms, worst %.2f ms (%d doors)" % [
			door_total / 1000.0 / (flips * 2), door_worst / 1000.0, doors.size()])
	# And the 3D view's ground shaded again for it: the cells it changed,
	# their corners rewritten and each chunk touched sent once.
	if flips > 0 and _main._client3d != null:
		_main._client3d._shade_floor()
		var shade_total := 0
		var shade_worst := 0
		for i in flips:
			var door: Door = doors[rng.randi_range(0, doors.size() - 1)]
			for open: bool in [not door.open, door.open]:
				door.open = open
				World.light_at(Terrain.edge_cells(door.key)[0], false)
				started = Time.get_ticks_usec()
				_main._client3d._shade_floor()
				var took := Time.get_ticks_usec() - started
				shade_total += took
				shade_worst = maxi(shade_worst, took)
		print("BENCH door flip, the 3D ground shaded again: avg %.2f ms, worst %.2f ms" % [
			shade_total / 1000.0 / (flips * 2), shade_worst / 1000.0])

	# The world tick at its worst: every monster on its way back after a
	# fight at once, each first put up to 8 tiles from its post (into the
	# next room, often), those far from the player walking back; the slice a
	# step does, and all of it in one go (which no step does).
	var away := func() -> void:
		for monster: Monster in World.monsters():
			for attempt in 8:
				var to := monster.tile + Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
				if World.is_free(to):
					World._relocate(monster, to)
					break
			monster._returning = true
	away.call()
	World.world_tick(0)
	var queued := World._world_due.size()
	var drains := 0
	var drain_worst := 0
	while not World._world_due.is_empty():
		started = Time.get_ticks_usec()
		World._world_tick_due(World.WORLD_TICK_BUDGET_USEC)
		drain_worst = maxi(drain_worst, Time.get_ticks_usec() - started)
		drains += 1
	away.call()
	started = Time.get_ticks_usec()
	World.world_tick()
	print("BENCH world tick, every monster walking back: a slice of %d queued, gone through in %d steps of %.2f ms at most; all at once (no step does it) %.2f ms" % [
		queued, drains, drain_worst / 1000.0, (Time.get_ticks_usec() - started) / 1000.0])

	print("BENCH nodes: %d, objects: %d, static memory: +%.1f MB" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		(OS.get_static_memory_usage() - memory_before) / 1048576.0])

	if windowed:
		await _frames()
	print("BENCH done")
	get_tree().quit()


## Frames for [member seconds] with the world ticking as in play: the
## average and worst frame, draw calls and video memory.
func _frames() -> void:
	World.set_process(true)
	for i in 30:
		await get_tree().process_frame
	var frames := 0
	var worst := 0.0
	var draws := 0.0
	var started := Time.get_ticks_usec()
	var last := started
	while Time.get_ticks_usec() - started < seconds * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		draws = maxf(draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	print("BENCH frames: %.1f fps avg, worst frame %.1f ms, draw calls up to %d, objects in frame %d, video memory %.0f MB" % [
		frames / elapsed, worst, draws,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


## players - 1 more players, each at the free tile nearest a point of a grid
## over the map (the host keeps its corner), and every player too tough to
## die.
func _spread_players() -> void:
	var across := ceili(sqrt(players))
	var joined := 0
	for i in across * across:
		if joined >= players - 1:
			break
		var point := Vector2i((i % across * 2 + 1) * size / (across * 2), (i / across * 2 + 1) * size / (across * 2))
		if point.x < size / (across * 2) + 1 and point.y < size / (across * 2) + 1 and i == 0 and across > 1:
			continue  # The host's corner.
		var peer := 1000 + joined
		_main._admit(peer, "be0c0000-0000-4000-8000-%012d" % peer, "Bench%d" % joined)
		var player: Player = _main._players.get(peer)
		var spot := _free_near(point)
		if player != null and spot != Vector2i(-1, -1):
			World._relocate(player, spot)
		joined += 1
	for entity in World.sought():
		entity.max_hp = 1000000
		entity.hp = entity.max_hp
	print("BENCH players: %d, spread over a %dx%d grid" % [World.sought().size(), across, across])


## The free tile nearest [param point], looking out ring by ring.
func _free_near(point: Vector2i) -> Vector2i:
	for reach in 12:
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if maxi(absi(dx), absi(dy)) == reach and World.is_free(point + Vector2i(dx, dy)):
					return point + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func _report(what: String, started: int) -> void:
	print("BENCH %s: %.1f ms" % [what, (Time.get_ticks_usec() - started) / 1000.0])


## The dungeon, at double resolution (docs/levels.md).
func _layout() -> Image:
	var pixels := size * 2 + 1
	var image := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	image.fill(colour.call("void"))
	var wall: Color = colour.call("wall")
	var door: Color = colour.call("door")
	var kinds := ["monster_imp", "monster_brute", "monster_sneak"]
	for y in size:
		for x in size:
			var room := Vector2i(x / ROOM, y / ROOM)
			var ground: String = Level.GROUNDS[absi(hash(room)) % Level.GROUNDS.size()]
			var at := Vector2i(x % ROOM, y % ROOM)
			var meaning := ground
			if at == Vector2i(2, 2):
				meaning = "torch"
			elif at == Vector2i(5, 2):
				meaning = "crate"
			elif x == 1 and y == 1:
				meaning = "start"
			else:
				# The share of spots kept for cells_per_monster (all of them by default).
				var keep := 1.0 if cells_per_monster <= 0.0 else ROOM * ROOM / cells_per_monster / monsters
				for m in monsters:
					if at == Vector2i(1 + (m * 3) % 6, 5 + m / 2 % 2) 							and absi(hash(Vector3i(x, y, m + 100))) % 1000 < keep * 1000.0:
						meaning = kinds[absi(hash(Vector3i(x, y, m))) % kinds.size()]
			image.set_pixel(x * 2, y * 2, colour.call(meaning))
			# Ground-coloured filler east and south, so the picture reads.
			if x + 1 < size:
				var east: Color = colour.call(ground)
				if at.x == ROOM - 1:
					east = door if at.y == ROOM / 2 else wall
				image.set_pixel(x * 2 + 1, y * 2, east)
			if y + 1 < size:
				var south: Color = colour.call(ground)
				if at.y == ROOM - 1:
					south = door if at.x == ROOM / 2 else wall
				image.set_pixel(x * 2, y * 2 + 1, south)
	return image
