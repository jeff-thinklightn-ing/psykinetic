extends RefCounted
## A restart keeps the world's ground (758, 40ecbfcd: Snapshot.load passes
## every saved key, so the felled clearing and the towns' plots come back):
##   TOUR_PHASES=2 sh tools/tour.sh restart
## Phase 1: a fresh world's towns fell and lay nothing for days (five fast
## days, 11-01), so the tour picks a real trunk by Umbrage and a clear 4x4 of
## its floor, from the level as Clearing reads it, and writes them as the
## server saves them to seed.json; the world saved. Between, tools/tour.sh
## stops the server, lays the seed into its local save (world.json, this run's
## own) and starts it again on it. Phase 2: a fresh client joins; the felled
## cell and the plot are told, with all phase 1 was told.

const ZONE := "wilds"
const SPEED_MINUTES := 2
const MOST_SECONDS := 60.0
const NEAR := Vector2i(212, 205)  # Umbrage's square.
const SEED_TOWN := "wilds/store"


func run(bot: Node) -> void:
	var phase := 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tour-phase="):
			phase = int(arg.trim_prefix("--tour-phase="))
	bot.log_line("restart tour, phase %d" % phase)
	var kept: String = bot.out_dir.path_join("restart_phase1.json")
	await bot.until(func() -> bool: return bot.main._clearing_told.has(ZONE), 30.0)
	if phase == 1:
		await _phase_one(bot, kept)
	else:
		await _phase_two(bot, kept)


func _told(bot: Node) -> Dictionary:
	var cells: Dictionary = bot.main._clearing_told.get(ZONE, {})
	var plots: Array = bot.main._plots_told.get(ZONE, [])
	return {"cells": cells.duplicate(), "plots": plots.map(func(p: Dictionary) -> String: return str(p.get("rect")))}


func _phase_one(bot: Node, kept: String) -> void:
	var boot := _told(bot)
	bot.log_line("phase 1, at the boot: %d felled cells, %d plots told" % [(boot["cells"] as Dictionary).size(), (boot["plots"] as Array).size()])
	await bot.seconds(MOST_SECONDS)
	var now := _told(bot)
	var clearing := Clearing.new()
	var trunk: Vector2i = clearing._nearest_edge(ZONE, NEAR, 70, NEAR)
	var base: Dictionary = clearing._base_of(ZONE)
	var plot := Rect2i()
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var rect := Rect2i(NEAR + Vector2i(dx, dy), Vector2i(4, 4))
				if plot.size == Vector2i.ZERO and Level.rect_cells(rect).all(func(c: Vector2i) -> bool:
						return base["floor"].has(c) and not base["built"].has(c) and not base["water"].has(c) and not base["links"].has(c)):
					plot = rect
	if not bot.expect(trunk != World.NO_CELL and plot.size != Vector2i.ZERO, "a trunk and a clear 4x4 by Umbrage to seed", "trunk %s, plot %s" % [trunk, plot]):
		return
	var seed := {"clearing": {ZONE: {"%d,%d" % [trunk.x, trunk.y]: [0, 1]}},
		"plots": {ZONE: [{"town": SEED_TOWN, "kind": "forge", "use": "forge", "rect": [plot.position.x, plot.position.y, 4, 4], "facing": [0, 1], "day": 1}]}}
	var file := FileAccess.open(bot.out_dir.path_join("seed.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(seed))
	file.close()
	bot.log_line("seeded: felled %s, a plot at %s" % [trunk, plot])
	bot.log_line("save: %s" % await bot.admin("save"))
	var cells_out := {"%d,%d" % [trunk.x, trunk.y]: [0, 1]}
	for cell: Vector2i in now["cells"]:
		cells_out["%d,%d" % [cell.x, cell.y]] = now["cells"][cell]
	var plots: Array = (now["plots"] as Array) + [str(plot)]
	file = FileAccess.open(kept, FileAccess.WRITE)
	file.store_string(JSON.stringify({"cells": cells_out, "plots": plots}))
	file.close()
	bot.log_line("phase 1 kept: %d cells, %d plots to see again" % [cells_out.size(), plots.size()])


func _phase_two(bot: Node, kept: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(kept))
	if not bot.expect(data is Dictionary, "phase 1's kept state is there to compare", kept):
		return
	await bot.seconds(5.0)  # The whole list told on joining.
	var now := _told(bot)
	var missing_cells: Array = (data["cells"] as Dictionary).keys().filter(func(k: String) -> bool:
		return not (now["cells"] as Dictionary).has(Vector2i(int(k.get_slice(",", 0)), int(k.get_slice(",", 1)))))
	var missing_plots: Array = (data["plots"] as Array).filter(func(r: String) -> bool: return not r in now["plots"])
	bot.log_line("phase 2, after the restart: %d felled cells, %d plots told (phase 1: %d, %d)" % [(now["cells"] as Dictionary).size(),
		(now["plots"] as Array).size(), (data["cells"] as Dictionary).size(), (data["plots"] as Array).size()])
	bot.expect(missing_cells.is_empty(), "every felled cell is still felled after the restart",
		"%d of %d missing: %s" % [missing_cells.size(), (data["cells"] as Dictionary).size(), missing_cells.slice(0, 8)])
	bot.expect(missing_plots.is_empty(), "every plot is still laid after the restart",
		"%d of %d missing: %s" % [missing_plots.size(), (data["plots"] as Array).size(), missing_plots.slice(0, 4)])
