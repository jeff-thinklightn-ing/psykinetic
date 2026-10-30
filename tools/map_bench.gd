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
## nobody is away respawning for part of the run. With --party=1 they stand
## round the host instead, in view: a party's bodies (decision 243) drawn
## together.
## With --cells-per-monster=N, each room's monster spots are kept at the
## rate that gives about N floor cells a monster (the castle has 42; the
## default, every spot, 32). With --repeat=N, the ticks are timed in N
## blocks, and the median block and the spread are printed too: compare
## medians (a single run's average moves by several ms on a shared machine).
## With --settle=N the map runs N ticks with the host alone before the
## other players come and the timing starts.
## --map=NAME plays a level from levels/ instead of the dungeon (run it with
## APPDATA set to a temp folder, so no edited overlay is read). In the
## frames, --spin=D turns the camera D degrees a second, as A or D held does,
## and --walk=N steps the host one tile every WALK_STEP seconds, N tiles
## either way along its row and back; the turn's own cost (the camera
## placed and what it hides worked out again) is timed. --fade=0 leaves
## nothing to fade, to compare. --look=X,Y pans the view to that cell
## (wherever the host is), and --shot=PATH saves the last frame as a PNG;
## --zoom=Z sets the view's zoom (past ZOOM_MAX too, for an overview) and
## --yaw=D turns it to D degrees; a shot leaves out the hints.
## --stand-in=1 draws the border's pine stands with PineStands' stand-in
## while their slot has no art (shots, to tune the packing).
## --low=1 turns the low camera on (decision 623) and --scatter-reach=N sets
## its scatter's reach (decision 653); the frames start with the scatter
## round the view built.
## --season=NAME starts the year in that season (Season.NAMES).
## --hour=H starts the clock at that hour (0..24: 12 noon).
## --weather-at=KIND@S turns every region's weather to KIND S seconds into
## the frames, to time the ease (the sky's radiance, decision 744); run
## --seconds long enough for the change (Weather's change, about a tenth of
## a spell).
## --weather=KIND starts every region in that weather (Weather; rain's
## drops and fog's layers drawn, outdoors).
## --off=shadows,border,glimpse,minimap leaves those pieces of the view out
## of the frames, to see what each costs (with --fade=0, no --weather).
## --bench-state=PATH starts the host from that saved world (a copy: the
## host writes it back), e.g. tools/town_state's wilds town with its
## residents; with the game's --test-herds=N after "--", N sets of herds.
##   godot --path . --scene res://tools/map_bench.tscn -- --size=128 [--monsters=2] [--cells-per-monster=42] [--players=1] [--ticks=200] [--repeat=1] [--seconds=8]

const NAME := "bench"
const ROOM := 8

var size := 64
var monsters := 2
var players := 1
## --party=1: the other players round the host, not spread over the map.
var party := false
var cells_per_monster := 0.0
## --outdoor=1: the dungeon outdoors, a forest round its outline (its trees,
## saplings and forest floor in the 3D build and the frames).
var outdoor := false
var repeat := 1
var settle := 0
var ticks := 200
var seconds := 8.0
var map := ""
var spin := 0.0
var walk := 0
var fade := true
var look := Vector2i(-1, -1)
var shot := ""
var shot_zoom := 0.0
var shot_yaw := NAN
var low := false
var scatter_reach := 0.0
## --weather-at: the kind, and when in the frames ("" once done).
var weather_at := ""
var weather_at_s := 0.0
const WALK_STEP := 0.3
var _main: Node


## --bench-state=PATH: the host starts from that world (Net.state_path).
var bench_state := ""
## --off=a,b: in the frames, pieces of the view left out, to see what each
## costs: shadows (the near lights' shadows), border (terrain's band round
## an outdoor map), glimpse (the level past a way out), minimap.
var off: Array[String] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() != 2:
			continue
		match pair[0]:
			"size": size = pair[1].to_int()
			"monsters": monsters = pair[1].to_int()
			"players": players = maxi(1, pair[1].to_int())
			"party": party = pair[1] == "1"
			"cells-per-monster": cells_per_monster = pair[1].to_float()
			"outdoor": outdoor = pair[1] != "0"
			"repeat": repeat = maxi(1, pair[1].to_int())
			"settle": settle = maxi(0, pair[1].to_int())
			"ticks": ticks = pair[1].to_int()
			"seconds": seconds = pair[1].to_float()
			"map": map = pair[1]
			"spin": spin = pair[1].to_float()
			"walk": walk = maxi(0, pair[1].to_int())
			"fade": fade = pair[1] != "0"
			"look": look = Vector2i(pair[1].get_slice(",", 0).to_int(), pair[1].get_slice(",", 1).to_int())
			"shot": shot = pair[1]
			"zoom": shot_zoom = pair[1].to_float()
			"yaw": shot_yaw = pair[1].to_float()
			"weather": Net.start_weather = pair[1].to_lower() if Weather.KINDS.has(pair[1].to_lower()) else ""
			"bench-state": bench_state = pair[1]
			"off": off.assign(pair[1].split(","))
			"stand-in": PineStands.stand_in = pair[1] != "0"
			"season": Net.start_season = pair[1].to_lower() if Season.NAMES.has(pair[1].to_lower()) else ""
			"low": low = pair[1] != "0"
			"scatter-reach": scatter_reach = pair[1].to_float()
			"hour": Net.start_hour = fposmod(pair[1].to_float(), 24.0)
			"weather-at":
				weather_at = pair[1].get_slice("@", 0).to_lower()
				weather_at_s = pair[1].get_slice("@", 1).to_float()
	if low:
		Net.set_camera_low(true, false)
	var windowed := DisplayServer.get_name() != "headless"
	print("BENCH size=%d cells (%d floor), monsters/room=%d, cells/monster=%s, players=%d, %s" % [size, size * size,
		monsters, "every spot" if cells_per_monster <= 0.0 else str(cells_per_monster), players,
		"windowed" if windowed else "headless"])
	var memory_before := OS.get_static_memory_usage()

	var started := Time.get_ticks_usec()
	if map == "":
		var layout := _layout()
		_report("make layout.png", started)
		Level.register(NAME, layout, null, {"name": "Bench", "outdoor": outdoor})
	started = Time.get_ticks_usec()
	var level := Level.load_level(NAME if map == "" else map)
	if map != "":
		size = level["size"].x
		print("BENCH map %s, %d x %d" % [map, level["size"].x, level["size"].y])
	_report("Level.load_level (parse)", started)
	print("BENCH entities in level: %d" % level["entities"].size())

	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17890)
	Net.companions = false
	# A world to start from (--bench-state: a copy, as the host writes it
	# back every 30 ticks): a town with its residents (tools/town_state).
	Net.state_path = bench_state
	Net.map_name = NAME if map == "" else map
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

	# --settle=N: the map runs N ticks with the host alone in its corner
	# before the others come, as a server's zone has run before players
	# arrive somewhere (what was worked out ahead is ready).
	for i in settle:
		World.step()
	if players > 1:
		_spread_players()
	World.step()
	var worst := 0
	var total := 0
	# --repeat=N: N blocks of [member ticks], one after another; each
	# block's average is a sample, and their median and spread are what to
	# compare (one run's average moves by several ms on a shared machine).
	var averages: Array[float] = []
	for block in repeat:
		var block_total := 0
		for i in ticks:
			started = Time.get_ticks_usec()
			World.step()
			var took := Time.get_ticks_usec() - started
			block_total += took
			worst = maxi(worst, took)
		total += block_total
		averages.append(block_total / 1000.0 / ticks)
	print("BENCH tick: avg %.2f ms, worst %.2f ms over %d ticks (%d entities in the zone)" % [
		total / 1000.0 / (ticks * repeat), worst / 1000.0, ticks * repeat, World.get_entities().size()])
	if repeat > 1:
		var sorted := averages.duplicate()
		sorted.sort()
		print("BENCH tick median: %.2f ms over %d blocks of %d ticks (blocks %.2f to %.2f: %s)" % [
			sorted[sorted.size() / 2], repeat, ticks, sorted[0], sorted[-1],
			", ".join(averages.map(func(a: float) -> String: return "%.1f" % a))])

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
	# The 3D view's scatter, made as the view comes near, a step a frame:
	# what a chunk costs in all, and its dearest step.
	if _main._client3d != null and "_scatter_chunks" in _main._client3d:
		var view: Node = _main._client3d
		var scatter_total := 0
		var scatter_worst := 0
		var scattered := 0
		for chunk: Vector2i in view._scatter_chunks:
			if view._scattered.has(chunk):
				continue
			# A frame does one step: the chunk's plan, or one kind's build.
			view._scattered[chunk] = true
			started = Time.get_ticks_usec()
			var placed: Dictionary = view._scatter_plan(chunk)
			var spent := Time.get_ticks_usec() - started
			scatter_total += spent
			scatter_worst = maxi(scatter_worst, spent)
			for kind: String in placed:
				started = Time.get_ticks_usec()
				view._scatter_build(chunk, kind, placed[kind])
				spent = Time.get_ticks_usec() - started
				scatter_total += spent
				scatter_worst = maxi(scatter_worst, spent)
			scattered += 1
			if scattered >= 40:
				break
		if scattered > 0:
			print("BENCH scatter a chunk (made as the view comes near, a step a frame): avg %.2f ms a chunk, worst step %.2f ms (%d chunks)" % [
				scatter_total / 1000.0 / scattered, scatter_worst / 1000.0, scattered])

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

	# A frame or two first, so what was freed this run (queue_free) is gone.
	await get_tree().process_frame
	await get_tree().process_frame
	print("BENCH nodes: %d, objects: %d, static memory: +%.1f MB" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		(OS.get_static_memory_usage() - memory_before) / 1048576.0])

	if windowed:
		await _frames()
	print("BENCH done")
	get_tree().quit()


## Frames for [member seconds] with the world ticking as in play, vsync
## off: the average and worst frame, draw calls and video memory, and the
## renderer's share of a frame.
func _frames() -> void:
	World.set_process(true)
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	# Uncapped, so the frame rate shows what a frame costs, not the screen's.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 30:
		await get_tree().process_frame
	var view: Node = _main._client3d
	if view != null and off.has("shadows"):
		for light: OmniLight3D in view._shadow_lights:
			light.shadow_enabled = false
		view._shadow_lights.clear()
	if view != null and off.has("border") and view._border != null:
		view._border.visible = false
		view._border.set_process(false)
	if view != null and off.has("glimpse"):
		for glimpse: Node3D in view._glimpses:
			glimpse.visible = false
	if off.has("minimap") and _main.minimap != null:
		_main.minimap.visible = false
		_main.minimap.set_process(false)
	if not off.is_empty():
		print("BENCH left out: %s" % ", ".join(off))
	if view != null and not fade:
		view._occluders.clear()
		view._occluder_chunks.clear()
		view._occluders_built = true
	if view != null:
		print("BENCH fade: %d pieces that can fade (%d trees and saplings)%s" % [view._occluders.size(),
			view._trees.size() + view._saplings.size(), "" if fade else ", left out (--fade=0)"])
	var host: Player = _main._players.get(Net.local_id)
	if view != null and host != null and look != Vector2i(-1, -1):
		var puppet: Node3D = view._puppets.get(host.get_instance_id())
		if puppet != null:
			view.pan = Vector3(look.x, 0.0, look.y) - Vector3(puppet.position.x, 0.0, puppet.position.z)
	if view != null and shot_zoom > 0.0:
		view.zoom = shot_zoom
		view._zoom_to = shot_zoom
		view._apply_size()
	if view != null and not is_nan(shot_yaw):
		view._set_yaw(shot_yaw)
	if shot != "" and _main.hint_panel != null:
		_main.hint_panel.visible = false
	# The scatter round the view built before the frames (decision 653): how
	# long it took, and how much is drawn.
	if view != null and "_scatter_chunks" in view:
		if scatter_reach > 0.0:
			view.scatter_reach_low = scatter_reach
		await get_tree().process_frame
		var built := Time.get_ticks_usec()
		view._grow_scatter()
		while view._scatter_step():
			pass
		print("BENCH scatter round the view (reach %.0f): built in %.1f ms; %s" % [view._scatter_reach(),
			(Time.get_ticks_usec() - built) / 1000.0, _scatter_drawn(view)])
	var home := host.tile if host != null else Vector2i.ZERO
	var stepped := 0
	var turn_total := 0
	var turn_worst := 0
	var turns := 0
	var frames := 0
	var worst := 0.0
	var draws := 0.0
	# The renderer's own time a frame, on the CPU and on the GPU; the rest
	# of a frame is the scripts and the engine's own nodes.
	var render_cpu := 0.0
	var render_gpu := 0.0
	# Each frame's: the medians and the GPU's 95th, and its slowest frames
	# with when they came, to find a refresh (the sky's radiance).
	var cpu_frames: Array[float] = []
	var gpu_frames: Array[Vector2] = []
	var map_draws: int = _main.minimap.draws if _main.minimap != null else 0
	var map_usec: int = _main.minimap.draw_usec if _main.minimap != null else 0
	var started := Time.get_ticks_usec()
	var last := started
	# Every frame's length with when it came: the median, the 99th, and the
	# longest, to find what a spike is.
	var spikes: Array[Vector2] = []
	while Time.get_ticks_usec() - started < seconds * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var delta := (now - last) / 1000000.0
		worst = maxf(worst, (now - last) / 1000.0)
		spikes.append(Vector2((now - last) / 1000.0, (now - started) / 1000000.0))
		last = now
		frames += 1
		if view != null and spin != 0.0:
			var turn_started := Time.get_ticks_usec()
			view._set_yaw(view.yaw + spin * delta)
			var took := Time.get_ticks_usec() - turn_started
			turn_total += took
			turn_worst = maxi(turn_worst, took)
			turns += 1
		if host != null and walk > 0:
			var step := int((now - started) / (WALK_STEP * 1000000.0))
			if step != stepped:
				stepped = step
				# Out and back: 0, 1 ... walk, ... 0, -1 ... -walk ... 0.
				var phase := step % (walk * 4)
				var along := phase if phase <= walk else (2 * walk - phase if phase <= 3 * walk else phase - 4 * walk)
				var to := home + Vector2i(along, 0)
				if World.is_free(to):
					World._relocate(host, to)
		draws = maxf(draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport) \
				+ RenderingServer.get_frame_setup_time_cpu()
		render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		cpu_frames.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu())
		gpu_frames.append(Vector2(RenderingServer.viewport_get_measured_render_time_gpu(viewport), (now - started) / 1000000.0))
		if weather_at != "" and (now - started) / 1000000.0 >= weather_at_s:
			print("BENCH weather to %s at %.1f s" % [weather_at, (now - started) / 1000000.0])
			Weather.set_override("all", weather_at, 600.0)
			weather_at = ""
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	print("BENCH frames: %.1f fps avg, worst frame %.1f ms, draw calls up to %d, objects in frame %d, video memory %.0f MB" % [
		frames / elapsed, worst, draws,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	print("BENCH a frame: rendering %.1f ms on the CPU, %.1f ms on the GPU (averages; the rest is scripts and nodes)" % [
		render_cpu / frames, render_gpu / frames])
	if frames > 0:
		cpu_frames.sort()
		var gpu_sorted: Array[float] = []
		for each in gpu_frames:
			gpu_sorted.append(each.x)
		gpu_sorted.sort()
		gpu_frames.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
		var slowest: Array[String] = []
		for each in gpu_frames.slice(0, 5):
			slowest.append("%.2f ms at %.1f s" % [each.x, each.y])
		print("BENCH rendering a frame: median %.2f ms on the CPU, %.2f ms on the GPU, GPU 95th %.2f ms; slowest on the GPU: %s" % [
			cpu_frames[cpu_frames.size() / 2], gpu_sorted[gpu_sorted.size() / 2], gpu_sorted[int(gpu_sorted.size() * 0.95)],
			", ".join(slowest)])
		if seconds >= 30.0:
			# Over a long run (a weather's ease), the GPU's median each 10 s.
			var buckets := {}
			for each in gpu_frames:
				var bucket := int(each.y / 10.0)
				if not buckets.has(bucket):
					buckets[bucket] = []
				buckets[bucket].append(each.x)
			var medians: Array[String] = []
			for bucket: int in range(int(ceil(seconds / 10.0))):
				var times: Array = buckets.get(bucket, [])
				times.sort()
				medians.append("%.2f" % times[times.size() / 2] if not times.is_empty() else "-")
			print("BENCH GPU median each 10 s: %s" % " ".join(medians))
	if _main.minimap != null and _main.minimap.visible:
		var drawn: int = _main.minimap.draws - map_draws
		print("BENCH minimap: drawn %d times in %d frames, %.3f ms a draw, %.3f ms a frame" % [drawn, frames,
			(_main.minimap.draw_usec - map_usec) / 1000.0 / maxi(drawn, 1), (_main.minimap.draw_usec - map_usec) / 1000.0 / frames])
	if view != null and "_scatter_chunks" in view:
		print("BENCH scatter after the frames: %s" % _scatter_drawn(view))
	var times: Array[float] = []
	for spike in spikes:
		times.append(spike.x)
	times.sort()
	spikes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var listed: Array[String] = []
	for spike in spikes.slice(0, 8):
		listed.append("%.1f ms at %.1f s" % [spike.x, spike.y])
	print("BENCH frame time: median %.2f ms, 99th %.2f ms; longest: %s" % [
		times[times.size() / 2], times[mini(times.size() - 1, times.size() * 99 / 100)], ", ".join(listed)])
	if view != null:
		for plan: Dictionary in view._glimpse_plans:
			var low := Vector2i(1 << 20, 1 << 20)
			var high := -low
			for cell: Vector2i in plan["cells"]:
				low = low.min(cell)
				high = high.max(cell)
			print("BENCH glimpse of %s: %d cells, %s to %s" % [plan["to"], plan["cells"].size(), low, high])
	if view != null and view._border != null:
		print("BENCH border: %d canopy chunks, %d nodes, task %d" % [view._border.chunks.size(), view._border.get_child_count(), view._border._task])
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
		print("BENCH shot: %s" % shot)
	if turns > 0:
		print("BENCH turning %.0f degrees a second: the turn itself avg %.2f ms, worst %.2f ms a frame (%d frames)" % [
			spin, turn_total / 1000.0 / turns, turn_worst / 1000.0, turns])


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
		var host: Player = _main._players.get(Net.local_id)
		var spot := _free_near(host.tile + Vector2i(joined % 4 - 1, joined / 4 + 1) if party and host != null else point)
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
					if at == Vector2i(1 + (m * 3) % 6, 5 + m / 2 % 2) \
							and absi(hash(Vector3i(x, y, m + 100))) % 1000 < keep * 1000.0:
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


## How much scatter [param view] draws: chunks, nodes and instances.
func _scatter_drawn(view: Node) -> String:
	var nodes := 0
	var instances := 0
	for chunk: Vector2i in view._scatter_nodes:
		for drawn: Node in view._scatter_nodes[chunk]:
			if is_instance_valid(drawn) and not drawn.is_queued_for_deletion():
				nodes += 1
				instances += (drawn as MultiMeshInstance3D).multimesh.instance_count
	return "%d chunks, %d MultiMeshes, %d instances" % [view._scattered.size(), nodes, instances]
