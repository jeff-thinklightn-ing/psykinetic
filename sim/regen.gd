class_name Regen
extends RefCounted
## Regenerating levels (decision 465): a level whose level.json carries
## "regenerate" (Level.regenerate_from) is laid again by its generator
## every few days. Its template (the authored files: Level.template) is
## what each generation starts from; the anchors' cells are copied
## verbatim and the generator makes the rest; the result is registered in
## memory and written to the server's level overlay, so Level reads it
## from then on and clients are sent it as a "terrain" message. Main says
## when (the slow world tick, or travel into a due level, never while the
## zone is awake) and rebuilds the zone; this does the making.

## Tries at a generation before the last good map is kept.
const TRIES := 8
## Seeds tried for a level held to layout rules (806): the first with no
## fault of them, else the fewest.
const HELD_TRIES := 16
const LAYOUT_SENSE := preload("res://sim/layout_sense.gd")
## How a thing lost outside the anchors is ended in the ItemBook.
const LOST := "in the shifting halls"
## How a thing moved into the keep_ground pile is noted in the ItemBook
## (790: the mine's ground is never lost, only gathered by the mouth).
const MOVED := "gathered at the way in"
const GENERATORS := "res://sim/level_gen/"
## The depth bands of a generated level (a share of the farthest reach from
## the "entrance" anchor): where the shallow band ends and where the middle
## one does. The labyrinth's barrow style lays its tombs by them (541) and
## graves_of names each grave's band by them (542 amended).
const BANDS: Array[float] = [0.34, 0.67]


## The levels that regenerate and each one's block (config_of), read once
## from the level folders and the registry (perf's reading, 2026-10-19:
## reading them on every world tick cost the server milliseconds); null
## until asked, and again after forget().
static var _marked: Variant = null


## Whether level [param level_name] regenerates (its template says so).
static func marked(level_name: String) -> bool:
	return _marked_configs().has(level_name)


## Every level that regenerates, sorted.
static func marked_levels() -> Array[String]:
	var out: Array[String] = []
	out.assign(_marked_configs().keys())
	return out


## Level [param level_name]'s "regenerate" block as Level.regenerate_from
## reads it from its template; {} for a level that does not regenerate.
static func config_of(level_name: String) -> Dictionary:
	return _marked_configs().get(level_name, {})


## Whether this is a test run (tests/run.sh passes --run-marker to every
## scene): with the shared overlay (Level.OVERLAY) a test never writes a
## generation there (decision 542; CLAUDE.md: tests never write levels to
## user://). A test that wants generations points Level.overlay_dir at its
## own scratch folder, as regen_test does. A scene under tests/ is one with
## or without the marker (199 amended: a solo level_test without it wrote a
## barrow into the shared overlay, and every tree's level_test failed on it),
## and without it says so once, an ERROR, so the run that left it off fails.
static func in_test_run() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-marker="):
			return true
	if is_test_scene(OS.get_cmdline_args()):
		if not _unmarked_said:
			_unmarked_said = true
			push_error("[regen] a scene under tests/ runs without --run-marker: the shared overlay is not written (199 amended); launch it as tests/run.sh does")
		return true
	return false


## Whether [param args] (a command line's) launch a scene under tests/.
static func is_test_scene(args: PackedStringArray) -> bool:
	for arg in args:
		var path := arg.replace("\\", "/").trim_prefix("res://")
		if path.begins_with("tests/") and path.ends_with(".tscn"):
			return true
	return false


## Whether in_test_run has said its ERROR for a tests/ scene with no marker.
static var _unmarked_said := false


## Whether this run may write the overlay it reads: no test run (tests/run.sh's
## --run-marker) ever writes the shared one (CLAUDE.md); a test with its own
## overlay may.
static func overlay_safe() -> bool:
	return not in_test_run() or Level.overlay_dir != Level.OVERLAY


## [param path] as an overlay folder (541 amended (3), --overlay-dir): forward
## slashes, one trailing slash, as Level.overlay_dir is read.
static func overlay_path(path: String) -> String:
	var out := path.strip_edges().replace("\\", "/")
	return out if out.ends_with("/") else out + "/"


## Whether a generation may be laid when due: the server was started with
## --regenerate or the console switched it on (Net.regenerate, as raid
## groups with --raids, 328), and this is no test run on the shared
## overlay. Off, a marked level stays as it is (the console's "regenerate
## now <level>" lays one regardless, 541 amended).
static func may_write() -> bool:
	return Net.regenerate and overlay_safe()


## The levels and their blocks are read again on the next ask: a level
## registered, unregistered or kept as a template (Level does this), or
## reloaded from edited files (Main.reload_zone).
static func forget() -> void:
	_marked = null
	_template_marks.clear()
	_laid_marks.clear()


## A generation remembers the template it was laid from (465 amended (4);
## the coordinator's rule, from the full circle's switch-on, whose links
## would have stayed on the box up to every_days after the deploy): write
## stamps its level.json "laid_from" with template_mark, and a laid
## generation whose template has changed since (template_changed) is laid
## again the next time nobody is in it, by the same path as one due. One
## laid before this has no mark: it counts as changed, once.
static var _template_marks: Dictionary[String, String] = {}
static var _laid_marks: Dictionary[String, String] = {}


## Level [param level_name]'s template, as one mark: an MD5 of its
## level.json (sorted) and its images' pixels (so a PNG saved again the
## same is no change). Cached until forget().
static func template_mark(level_name: String) -> String:
	if not _template_marks.has(level_name):
		var made := Level.template(level_name)
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_MD5)
		hashing.update(JSON.stringify(made.get("config", {}), "", true).to_utf8_buffer())
		for key: String in ["layout", "height", "relief"]:
			var image: Variant = made.get(key)
			if image is Image:
				var pixels: Image = image
				if pixels.get_format() in [Image.FORMAT_L8, Image.FORMAT_LA8, Image.FORMAT_RGB8]:
					pixels = pixels.duplicate()
					pixels.convert(Image.FORMAT_RGBA8)  # A PNG saved again as RGB or RGBA: the same pixels, the same mark.
				hashing.update(("%s %dx%d %d" % [key, pixels.get_width(), pixels.get_height(), pixels.get_format()]).to_utf8_buffer())
				hashing.update(pixels.get_data())
		_template_marks[level_name] = hashing.finish().hex_encode()
	return _template_marks[level_name]


## Whether level [param level_name]'s laid generation (a level.json with
## "generation", never a level edited in the game) was laid from another
## template than its own now. Cached until forget().
static func template_changed(level_name: String) -> bool:
	if not _laid_marks.has(level_name):
		var laid: Dictionary = Level.source(level_name).get("config", {})
		_laid_marks[level_name] = str(laid.get("laid_from", "")) if laid.has("generation") and laid.get("regenerate") is Dictionary else "-"
	return _laid_marks[level_name] != "-" and _laid_marks[level_name] != template_mark(level_name)


## Name -> block of every level that regenerates, in name order.
static func _marked_configs() -> Dictionary:
	if _marked is Dictionary:
		return _marked
	var found := {}
	var names := Level.names()
	for level_name in Level.registered_names():
		if level_name not in names:
			names.append(level_name)  # A test's, made in code.
	names.sort()
	for level_name in names:
		if Level.regenerates(level_name):
			var warnings: Array[String] = []
			found[level_name] = Level.regenerate_from(Level.template_config(level_name), warnings)
	_marked = found
	return found


## The seed of [param area]'s generation [param generation], attempt
## [param attempt]: the same every time, on any machine.
static func seed_for(area: String, generation: int, attempt := 0) -> int:
	return ("%s#%d#%d" % [area, generation, attempt]).hash()


## Whether a level in [param state] ({generation, at_step}) with
## [param config] (config_of) is due at world step [param steps]: never
## tried yet, or every_days of the world's days gone by since the last
## generation (or the last try that made no map).
static func due(state: Dictionary, config: Dictionary, steps: int) -> bool:
	if config.is_empty():
		return false
	if int(state.get("generation", 0)) <= 0 and int(state.get("at_step", 0)) <= 0:
		return true
	return steps - int(state.get("at_step", 0)) >= int(config["every_days"]) * DayNight.day_steps


## The saved "regen" section ({area: {generation, at_step, robbers_down
## if latched, robbers_fallen: the band's ids fallen this generation,
## band_slain: who felled each of them}}) read back;
## entries that make no sense are dropped.
static func states_from(saved: Variant) -> Dictionary:
	var out := {}
	if saved is Dictionary:
		for area: Variant in saved:
			var entry: Variant = saved[area]
			if entry is Dictionary:
				out[str(area)] = {"generation": maxi(int(entry.get("generation", 0)), 0), "at_step": maxi(int(entry.get("at_step", 0)), 0)}
				if bool(entry.get("robbers_down", false)):
					out[str(area)]["robbers_down"] = true  # 714: the robbers' clear, latched for the generation.
				if entry.get("robbers_fallen") is Array:
					out[str(area)]["robbers_fallen"] = (entry["robbers_fallen"] as Array).map(func(id: Variant) -> String: return str(id))
				# The co-op tombs opened this generation, and who was given
				# its deed (crypt landing 2).
				for key: String in ["solved", "solved_rewarded"]:
					if entry.get(key) is Array:
						out[str(area)][key] = (entry[key] as Array).map(func(id: Variant) -> String: return str(id))
				# 747 amended (8): who felled each of the band this generation
				# (named id -> player ids), so a restart keeps the kills made
				# before the taking.
				if entry.get("band_slain") is Dictionary:
					var by := {}
					for named: Variant in entry["band_slain"]:
						if entry["band_slain"][named] is Array:
							by[str(named)] = (entry["band_slain"][named] as Array).map(func(id: Variant) -> String: return str(id))
					out[str(area)]["band_slain"] = by
				# 896's switch-on: the knight's remains laid on the bier this
				# generation, so a restart keeps them (a level entity's props
				# come from its spawn table at load, not the save).
				if bool(entry.get("remains_laid", false)):
					out[str(area)]["remains_laid"] = true
	return out


## Generation [param generation] of level [param level_name]: {layout,
## height, config, seed, tries, anchors}, the map the generator made from
## the template with the first seed (seed_for) whose anchors all reach
## each other, TRIES seeds tried; {} when none did, or the level has no
## template or generator (said in a warning): the caller keeps the last map.
static func generate(level_name: String, generation: int) -> Dictionary:
	return generate_prepared(prepare(level_name), generation)


## The regenerate block's named band (714, dungeon's side (4); enemy-ai's
## mound-breakers, 716): {kind: [named id, ...]}; each kind's monster
## markers on [param map], in cell order, given the next id as a level
## entity entry {at, named} (Level.parse puts it on the spawn), the rest
## left plain. [] without a band.
## [param rows] with every two rows on one cell made one (806 amended (5):
## a band's "named" row and the generator's "idle" row for the same
## marker; Level keeps one row a cell, the last).
static func merged_rows(rows: Array) -> Array:
	var out: Array = []
	var by_cell := {}
	for row: Variant in rows:
		if not row is Dictionary or not (row as Dictionary).get("at") is Array:
			out.append(row)
			continue
		var at: Array = row["at"]
		var key := Vector2i(int(at[0]), int(at[1]))
		if by_cell.has(key):
			(by_cell[key] as Dictionary).merge(row)
			continue
		var copy := (row as Dictionary).duplicate()
		by_cell[key] = copy
		out.append(copy)
	return out


static func band_of(map: LevelMap, config: Dictionary) -> Array:
	var out: Array = []
	var band: Variant = config.get("band", {})
	if not band is Dictionary:
		return out
	for kind: Variant in band:
		var ids: Variant = band[kind]
		if not ids is Array or str(kind).begins_with("_"):
			continue
		var cells: Array = map.cells.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
		var at := 0
		for cell: Vector2i in cells:
			if at >= (ids as Array).size():
				break
			if map.cells[cell] == "monster_" + str(kind):
				out.append({"at": [cell.x, cell.y], "named": str(ids[at])})
				at += 1
	return out


## What generate needs that only the main thread may make (decision 684):
## the template (Level's caches), its "regenerate" block and the generator
## script loaded; {} (said in a warning) when the level can't be generated.
static func prepare(level_name: String) -> Dictionary:
	var made := Level.template(level_name)
	var layout: Image = made["layout"]
	if layout == null:
		push_warning("[regen] %s has no template to generate from" % level_name)
		return {}
	var warnings: Array[String] = []
	var config := Level.regenerate_from(made["config"], warnings)
	for warning in warnings:
		push_warning("[regen] %s: %s" % [level_name, warning])
	if config.is_empty():
		push_warning("[regen] %s is not marked \"regenerate\"" % level_name)
		return {}
	var generator_path := GENERATORS + str(config["generator"]) + ".gd"
	if not ResourceLoader.exists(generator_path):
		push_warning("[regen] %s names a generator there is not: %s" % [level_name, generator_path])
		return {}
	var generator: GDScript = load(generator_path)
	# The first hall's niches (608): the template's list goes to the
	# generator, which re-rolls them and moves the hidden door.
	config["niches"] = made["config"].get("niches", [])
	# The arrivals (832): the template's spawn points and starts, for a
	# generator that lays its monsters clear of them when the block holds
	# that rule.
	var arrivals: Dictionary = (made["config"].get("spawn_points", {}) as Dictionary).duplicate(true)
	var starts: Array = made["config"].get("starts", [])
	for index in starts.size():
		arrivals["start %d" % (index + 1)] = starts[index]
	# The quest givers (747 amended (8)): the monsters are laid clear of
	# them too, so the walk to one from the way in is clear by shape.
	if "arrival" in (config.get("held", []) as Array):
		for spec: Dictionary in Level.parse(layout, made["height"], made["config"]).get("entities", []):
			if str(spec.get("kind", "")) in LAYOUT_SENSE.GIVER_KINDS and spec.get("tile") is Vector2i:
				arrivals["giver %s" % spec["tile"]] = [spec["tile"].x, spec["tile"].y]
	config["arrivals"] = arrivals
	# The worker's own copies: Level keeps the template's dictionaries, which
	# the main thread goes on reading (the images are only read, by both).
	return {"level_name": level_name, "made": {"layout": layout, "height": made["height"], "config": made["config"].duplicate(true)},
		"config": config.duplicate(true), "generator": generator}


## Generation [param generation] made from [param prepared] (prepare's):
## generate's tries, touching no node, autoload or cache, so Main runs it on
## a worker thread (decision 684); {} for an empty [param prepared].
static func generate_prepared(prepared: Dictionary, generation: int) -> Dictionary:
	if prepared.is_empty():
		return {}
	var level_name: String = prepared["level_name"]
	var made: Dictionary = prepared["made"]
	var config: Dictionary = prepared["config"]
	var generator: GDScript = prepared["generator"]
	var layout: Image = made["layout"]
	var template := LevelMap.from_image(layout, made["config"])
	template.read_heights(made["height"])
	var anchors: Array = config["anchors"]
	var best := {}
	var held: Array = config.get("held", [])
	for attempt in (HELD_TRIES if not held.is_empty() else TRIES):
		var seed := seed_for(level_name, generation, attempt)
		var map: LevelMap = generator.generate(template, config, seed)
		if map == null:
			continue
		if not connected(map, anchors):
			continue
		var height: Image = map.to_height_image() if made["height"] != null or not map.heights.is_empty() else null
		var generated := generated_config(made["config"], anchors, generation)
		# The barrow's first layer (580) holds the robbers' halls, no dead and
		# no tombs: it lists no graves; its niches are the first hall's with
		# the hidden door among them (608), the Ossuary's are cut along its
		# galleries, the dark below has none.
		var layer := int(config.get("layer", 2))
		var barrow := str(config.get("style", "")) == "barrow"
		generated["niches"] = []
		if barrow and layer == 1 and generator.has_method("niche_plan"):
			_lay_hidden(generated, generator.niche_plan(config, seed))
		elif barrow and layer == 2:
			generated["niches"] = niches_of(map, anchors, seed)
		generated["graves"] = graves_of(map, config, generated["niches"] if layer == 2 else []) if layer != 1 else []
		generated["entities"] = (generated.get("entities", []) as Array) + band_of(map, config)
		# Moss and webs (647): the template's own kept inside the anchors
		# (generated_config), the rest rolled over the generation.
		if barrow:
			generated["decor"].append_array(decor_of(map, anchors, config, generated, seed, bool(made["config"].get("damp", false))))
		elif str(config.get("style", "")) == "tower":
			generated["decor"].append_array(runes_of(map, anchors, generated, seed))
		# A generator that lays its own decor, entities and relief (790, the
		# mine): its rows added to the anchors' kept ones, and the ledges of
		# the relief it made (585) in place of the template's.
		if generator.has_method("decor_of"):
			generated["decor"].append_array(generator.decor_of(map))
		if generator.has_method("entities_of"):
			generated["entities"].append_array(generator.entities_of(map))
		if generator.has_method("ledges_of"):
			generated["ledges"] = generator.ledges_of(map)
		# A generator that names what it lays by section (806 amended, the
		# crypt): each section's rows added to the anchors' kept ones (decor,
		# entities, buildings, niches), or set where the template has none
		# (its "laid_rooms" for layout_sense, its "carvings").
		if generator.has_method("rows_of"):
			var rows: Dictionary = generator.rows_of(map)
			for section: String in rows:
				if generated.get(section) is Array:
					(generated[section] as Array).append_array(rows[section])
				else:
					generated[section] = rows[section]
		if generated.get("entities") is Array:
			generated["entities"] = merged_rows(generated["entities"])
		var result := {"layout": map.to_image(), "height": height, "config": generated, "seed": seed, "tries": attempt + 1, "anchors": anchors}
		# 806: a level whose block lists "held" rules takes the first try
		# with none of those faults, else the try with the fewest.
		if held.is_empty():
			return result
		# 806 (c): the block's "prefer" rules (castle_halls' spine and wrap)
		# break ties: the first try with none held and none preferred, else
		# the fewest held, then the fewest preferred. Only "held" fails a test.
		var prefer: Array = config.get("prefer", [])
		var found := layout_faults(result, config)
		# 806 amended (11): a try with an arrival fault is never laid, not
		# even as the best (the crypt lays clear of arrivals, so none should
		# come; with none clear, the level's last laid copy stands).
		if "arrival" in held and found.any(func(fault: Dictionary) -> bool: return fault["rule"] == "arrival"):
			continue
		result["faults"] = found.filter(func(fault: Dictionary) -> bool: return fault["rule"] in held).size()
		# 806 amended (15): a kept chest fault ranks worse than any other held
		# fault, so a try with a wrap wins over one with an unguarded chest.
		result["chests"] = found.filter(func(fault: Dictionary) -> bool: return fault["rule"] == "chest" and "chest" in held).size()
		result["preferred"] = found.filter(func(fault: Dictionary) -> bool: return fault["rule"] in prefer).size()
		result["nearest"] = found.filter(func(fault: Dictionary) -> bool: return fault.has("near")).map(func(fault: Dictionary) -> int: return int(fault["near"]))
		if result["faults"] == 0 and result["preferred"] == 0:
			return result
		if best.is_empty() or [int(result["chests"]), int(result["faults"]), int(result["preferred"])] < [int(best["chests"]), int(best["faults"]), int(best["preferred"])]:
			best = result
	if not best.is_empty():
		if int(best["faults"]) > 0:
			print("[regen] %s: the best of %d tries keeps %d layout faults (806)" % [level_name, HELD_TRIES, best["faults"]])
		elif int(best["preferred"]) > 0:
			# 870: a preferred rule given up on (the Ossuary's packs nearer than
			# their "apart"): the nearest they came, numbers only.
			print("[regen] %s: the best of %d tries keeps %d preferred faults (870), nearest %s" % [level_name, HELD_TRIES, best["preferred"], best.get("nearest", "")])
		return best
	push_warning("[regen] %s: no map of %d tries joined every anchor (or kept its arrivals clear); the last one stands" % [level_name,
		HELD_TRIES if not held.is_empty() else TRIES])
	return {}


## 806: a made generation's faults (sim/layout_sense.gd) under the rules
## [param held] its "regenerate" block holds it to ("held"), checked with
## the block's "ways" and "pillars" and its anchors.
static func held_faults(made: Dictionary, config: Dictionary, held: Array) -> Array:
	return layout_faults(made, config).filter(func(fault: Dictionary) -> bool: return fault["rule"] in held)


## 806: every layout fault of a made generation, by its "regenerate" block
## [param config] (its "ways", default 3, "pillars", default 0, anchors).
static func layout_faults(made: Dictionary, config: Dictionary) -> Array:
	var level := Level.parse(made["layout"], made["height"], made["config"])
	return LAYOUT_SENSE.check(level, made["config"].get("laid_rooms", []), layout_options(config))


## 806: the checker's options for a "regenerate" block [param config]: its
## "ways" (default 3) and "pillars" (0), a dungeon, and the anchors the
## spine's heart is sought in: the block's "heart" anchor when it names one
## (the crypt's: the robbers' camp), else every anchor (the farthest);
## "arrival" when the block holds that rule (806 amended (11)); its
## "foes_door" (747 amended (8)), the arrival the giver walk is not asked of.
static func layout_options(config: Dictionary) -> Dictionary:
	var anchors: Array = config.get("anchors", [])
	var heart := str(config.get("heart", ""))
	if not heart.is_empty():
		anchors = anchors.filter(func(anchor: Variant) -> bool: return anchor is Dictionary and str(anchor.get("name", "")) == heart)
	return {"ways": int(config.get("ways", 3)), "anchors": anchors, "dungeon": true, "pillars": int(config.get("pillars", 0)),
		"arrival": "arrival" in (config.get("held", []) as Array), "foes_door": str(config.get("foes_door", "")),
		"packs_apart": packs_apart(config), "first_alone": first_alone(config),
		"band": (config.get("band", {}) as Dictionary).keys().filter(func(kind: Variant) -> bool: return not str(kind).begins_with("_")) if config.get("band") is Dictionary else []}


## The first-alone rule's reach (870): the band's own rally, [seen, heard]
## (Monster.RALLY_SEE, RALLY_HEAR, 806 amended (17): a mate answers a fight
## he sees or hears), when the block holds or prefers "first"; else [] (the
## rule off). Read from the AI's constants, never a copy in level.json, so
## the layout's promise and the rally stay one measure.
static func first_alone(config: Dictionary) -> Array:
	var rules: Array = (config.get("held", []) as Array) + (config.get("prefer", []) as Array)
	return [Monster.RALLY_SEE, Monster.RALLY_HEAR] if "first" in rules else []


## The packs rule's reach (870): the largest clear "apart" of the block's
## "packs" given as [clear, walled], when the block prefers "packs"; else 0.
static func packs_apart(config: Dictionary) -> int:
	if "packs" not in (config.get("prefer", []) as Array) or not config.get("packs") is Dictionary:
		return 0
	var most := 0
	for lead: String in config["packs"]:
		var gap: Variant = (config["packs"][lead] as Dictionary).get("apart", 0)
		if gap is Array:
			most = maxi(most, int(gap[0]))
	return most


## The graves of a generated [param map] (542 amended, enemy-ai's crypt
## design: a walking skeleton is given a grave of its own in a shallower
## band): [[x, y, band], ...], one per dead-end floor cell outside the
## anchors (one walkable neighbour: a blind way's end) and, since the
## two-cell rule left no lone cells (725), one per wall niche in
## [param niches] (niches_of's, [x, y, dx, dy, kind, variant]: the floor
## cell before it), none with a chest on it, in cell order; the band 0, 1 or 2
## by the cell's distance from the "entrance" anchor's centre (the first
## anchor unless [param config] names one) over the farthest the map
## reaches from it (BANDS). Written into the generated level.json as
## "graves".
static func graves_of(map: LevelMap, config: Dictionary, niches: Array = []) -> Array:
	var out: Array = []
	var anchors: Array = config.get("anchors", [])
	if anchors.is_empty():
		return out
	var before := {}
	for niche: Variant in niches:
		if niche is Array and (niche as Array).size() >= 2:
			before[Vector2i(int(niche[0]), int(niche[1]))] = true
	var entrance: Dictionary = anchors[0]
	for anchor: Dictionary in anchors:
		if str(anchor.get("name", "")) == str(config.get("entrance", "")):
			entrance = anchor
	var frame := depth_frame(map, entrance)
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if not map.walkable(cell) or map.cell(cell) == "chest" or Level.in_anchors(anchors, cell):
				continue
			var open := 0
			for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next := cell + direction
				if map.in_bounds(next) and map.walkable(next) and map.edge(Terrain.edge_key(cell, direction)) != "wall":
					open += 1
			if open != 1 and not before.has(cell):
				continue
			out.append([x, y, band_at(frame, cell)])
	return out


## The depth measure the graves and the decor share: {centre: the
## [param entrance] anchor's centre, far: the farthest a corner of
## [param map] lies from it, in cells}.
static func depth_frame(map: LevelMap, entrance: Dictionary) -> Dictionary:
	var rect: Rect2i = entrance["rect"]
	var centre := rect.position + rect.size / 2
	var far := 1
	for corner: Vector2i in [Vector2i.ZERO, Vector2i(map.size.x - 1, 0), Vector2i(0, map.size.y - 1), map.size - Vector2i.ONE]:
		far = maxi(far, absi(centre.x - corner.x) + absi(centre.y - corner.y))
	return {"centre": centre, "far": far}


## The band, 0, 1 or 2 (BANDS), [param cell] lies in by [param frame]
## (depth_frame).
static func band_at(frame: Dictionary, cell: Vector2i) -> int:
	var centre: Vector2i = frame["centre"]
	var depth := clampf(float(absi(centre.x - cell.x) + absi(centre.y - cell.y)) / float(frame["far"]), 0.0, 1.0)
	return 0 if depth < BANDS[0] else (1 if depth < BANDS[1] else 2)


## The entrance anchor of [param config]: the one named "entrance", else
## the first; {} with none.
static func entrance_of(config: Dictionary) -> Dictionary:
	var anchors: Array = config.get("anchors", [])
	if anchors.is_empty():
		return {}
	var entrance: Dictionary = anchors[0]
	for anchor: Dictionary in anchors:
		if str(anchor.get("name", "")) == str(config.get("entrance", "")):
			entrance = anchor
	return entrance


## The first hall's niches and its hidden door laid into [param generated]
## (608) as [param plan] (Labyrinth.niche_plan) says: "niches" the
## re-rolled list, the link that stood in the template's alcove moved to
## the pick's (and marked "hidden"), "from_below" to the hall cell before
## it.
static func _lay_hidden(generated: Dictionary, plan: Dictionary) -> void:
	if plan.is_empty():
		return
	generated["niches"] = plan["niches"]
	var alcove: Vector2i = plan["alcove"]
	var before: Vector2i = plan["before"]
	if plan.has("was_alcove") and generated.get("links") is Array:
		for link: Variant in generated["links"]:
			if link is Dictionary and Level._tile(link.get("at")) == plan["was_alcove"]:
				link["at"] = [alcove.x, alcove.y]
				link["hidden"] = true
	if generated.get("spawn_points") is Dictionary and generated["spawn_points"].has("from_below"):
		generated["spawn_points"]["from_below"] = [before.x, before.y]


## 608: the niche roll's seed salt (Labyrinth.NICHE_SALT, the same), the
## share of the Ossuary's wall cells that get a niche, and of those the
## share that are hollows ("c") among the shelves ("b") and the columbarium
## cells ("d").
const NICHE_SALT := 0x6e1c4e
const NICHE_SHARE := 0.17
const NICHE_HOLLOW := 0.17

## The Ossuary's burial niches (608; 542 amended's alcoves before): cut
## into the galleries' walls, as [[x, y, dx, dy, kind, variant], ...]:
## (x, y) a floor cell of [param map] outside the [param anchors] (no
## link's), (dx, dy) the step onto a wall with rock behind it (never a
## door), kind "b" (shelves) or "d" (columbarium cells), "c" (a hollow)
## NICHE_HOLLOW of the time, variant 1 or 2; about NICHE_SHARE of the
## cells by a wall, one niche a cell at most, by an rng of [param seed] and
## NICHE_SALT, the cells in a set order. Written into the generated
## level.json as "niches" (Level.niches_from); the client draws art-kit's
## wall.crypt pieces on the edges.
static func niches_of(map: LevelMap, anchors: Array, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ NICHE_SALT
	var out: Array = []
	var cells: Array = map.cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	for cell: Vector2i in cells:
		if not map.walkable(cell) or map.cell(cell) == "link" or Level.in_anchors(anchors, cell):
			continue
		var sides: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var far := cell + direction
			if map.in_bounds(far) and not map.walkable(far) and map.edge(Terrain.edge_key(cell, direction)) != "door":
				sides.append(direction)
		if sides.is_empty() or rng.randf() >= NICHE_SHARE:
			continue
		var side: Vector2i = sides[rng.randi_range(0, sides.size() - 1)]
		var kind := "c" if rng.randf() < NICHE_HOLLOW else ("b" if rng.randf() < 0.5 else "d")
		out.append([cell.x, cell.y, side.x, side.y, kind, 1 if rng.randf() < 0.5 else 2])
	return out


## 647: the decor roll's seed salt; the share of the wall-foot edges that
## get moss in a damp level ("damp": true, the Hall of Fallen Souls), on
## the barrow's second layer (the Ossuary) and its first (the town's
## tombs); the deep band's share is MOSS_DEEP times that (the low rooms);
## the share of eligible floor cells that get a moss patch, of the moss
## share; the share of corners that get a web, and of open niche mouths.
const DECOR_SALT := 0x6d055
const MOSS_DAMP := 0.35
const MOSS_DEEP_LAYER := 0.15
const MOSS_FIRST_LAYER := 0.05
const MOSS_DEEP := 1.5
const MOSS_PATCH := 0.4
## The share of the dark tower's wall feet with a line of runes (659
## amended; a light roll, Jeff tunes).
const RUNE_SHARE := 0.12
const WEB_CORNER := 0.3
const WEB_NICHE := 0.25

## The barrow's moss and webs for a generation (647; Jeff: "moss and
## spiderwebs for decor, no live plants"): [[x, y, dx, dy, kind, variant],
## ...] (Level.decor_from's shape) rolled by an rng of [param seed] and
## DECOR_SALT over [param map]'s floor cells outside [param anchors] in a
## set order, never a cell the ways run through (the map's extras "paths"),
## a link's, a marker's or a spawn point's cell, nor one [param generated]
## already decorates: "moss_strip" along a wall edge with rock behind it
## (never a door) with the moss share (MOSS_DAMP when [param damp], else
## MOSS_FIRST_LAYER on layer 1 and MOSS_DEEP_LAYER on layer 2, MOSS_DEEP
## times that in the deep band), one a cell; "web_corner" in a corner where
## two such walls meet, WEB_CORNER of them, one a cell; "moss_patch" on a
## floor cell with no wall beside it, MOSS_PATCH of the moss share; and
## "web_niche" across WEB_NICHE of [param generated]'s open niches of kind
## "a" or "c" (variant 1; never the hidden one, never a sealed slab),
## inside the anchors too, since the first hall's niches are re-rolled each
## generation. Variants by the roll. The block's "hidden_tell" (608
## amended (3)) on the hidden niche. Written into the generated level.json
## as "decor" after the template's own.
static func decor_of(map: LevelMap, anchors: Array, config: Dictionary, generated: Dictionary, seed: int, damp: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ DECOR_SALT
	var out: Array = []
	var layer := int(config.get("layer", 2))
	var moss := MOSS_DAMP if damp else (MOSS_FIRST_LAYER if layer == 1 else MOSS_DEEP_LAYER)
	var entrance := entrance_of(config)
	var frame := depth_frame(map, entrance) if not entrance.is_empty() else {}
	var paths: Dictionary = map.extras.get("paths", {})
	var kept := {}
	var taken := {}
	for entry: Variant in generated.get("decor", []):
		if entry is Array and (entry as Array).size() == 6:
			kept[Vector2i(int(entry[0]), int(entry[1]))] = true
	for value: Variant in generated.get("spawn_points", {}).values():
		var at: Variant = Level._tile(value)
		if at != null:
			taken[at] = true
	var cells: Array = map.cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	for cell: Vector2i in cells:
		if not map.walkable(cell) or map.cell(cell) not in Level.GROUNDS or Level.in_anchors(anchors, cell) \
				or paths.has(cell) or taken.has(cell) or kept.has(cell):
			continue
		var share := moss
		if not frame.is_empty() and band_at(frame, cell) == 2:
			share = minf(moss * MOSS_DEEP, 1.0)
		var sides: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var far := cell + direction
			if map.in_bounds(far) and not map.walkable(far) and map.edge(Terrain.edge_key(cell, direction)) != "door":
				sides.append(direction)
		if sides.is_empty():
			if rng.randf() < share * MOSS_PATCH:
				out.append([cell.x, cell.y, 0, 0, "moss_patch", rng.randi_range(1, int(Level.DECOR_KINDS["moss_patch"]["variants"]))])
			continue
		var corners: Array[Vector2i] = []
		for side in sides:
			for other in sides:
				if side.x != 0 and other.y != 0:
					corners.append(side + other)
		if not corners.is_empty() and rng.randf() < WEB_CORNER:
			var corner: Vector2i = corners[rng.randi_range(0, corners.size() - 1)]
			out.append([cell.x, cell.y, corner.x, corner.y, "web_corner", rng.randi_range(1, int(Level.DECOR_KINDS["web_corner"]["variants"]))])
		if rng.randf() < share:
			var side: Vector2i = sides[rng.randi_range(0, sides.size() - 1)]
			out.append([cell.x, cell.y, side.x, side.y, "moss_strip", rng.randi_range(1, int(Level.DECOR_KINDS["moss_strip"]["variants"]))])
	for niche: Variant in generated.get("niches", []):
		if not niche is Array or (niche as Array).size() != 6 or str(niche[4]) not in ["a", "c"] or int(niche[5]) != 1:
			continue
		var cell := Vector2i(int(niche[0]), int(niche[1]))
		if kept.has(cell) or rng.randf() >= WEB_NICHE:
			continue
		out.append([cell.x, cell.y, int(niche[2]), int(niche[3]), "web_niche", rng.randi_range(1, int(Level.DECOR_KINDS["web_niche"]["variants"]))])
	# 608 amended (3): the block's "hidden_tell", a decor kind sat on the
	# hidden niche ("on": "hidden"), laid at it every generation; after the
	# rolls, so the rest of the decor stays as it was.
	var tell := str(config.get("hidden_tell", ""))
	if Level.DECOR_KINDS.has(tell) and Level.DECOR_KINDS[tell].get("on") == "hidden":
		for niche: Variant in generated.get("niches", []):
			if niche is Array and (niche as Array).size() == 6 and str(niche[4]) == "hidden":
				out.append([int(niche[0]), int(niche[1]), int(niche[2]), int(niche[3]), tell, 1])
	return out


## The dark tower's runes for a generation (659 amended): [[x, y, dx, dy,
## "rune_strip", variant], ...] (Level.decor_from's shape), a strip along
## RUNE_SHARE of the wall feet (a wall edge with rock behind it, never a
## door) of [param map]'s floor outside [param anchors], one a cell, never a
## cell the ways run through, a marker's, a spawn point's or one
## [param generated] already decorates; rolled by an rng of [param seed]
## and DECOR_SALT in a set order, variants by the roll. The chamber's own
## are the template's, kept (generated_config).
static func runes_of(map: LevelMap, anchors: Array, generated: Dictionary, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ DECOR_SALT
	var out: Array = []
	var paths: Dictionary = map.extras.get("paths", {})
	var taken := {}
	for entry: Variant in generated.get("decor", []):
		if entry is Array and (entry as Array).size() == 6:
			taken[Vector2i(int(entry[0]), int(entry[1]))] = true
	for value: Variant in generated.get("spawn_points", {}).values():
		var at: Variant = Level._tile(value)
		if at != null:
			taken[at] = true
	var cells: Array = map.cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	for cell: Vector2i in cells:
		if not map.walkable(cell) or map.cell(cell) not in Level.GROUNDS or Level.in_anchors(anchors, cell) \
				or paths.has(cell) or taken.has(cell):
			continue
		var sides: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var far := cell + direction
			if map.in_bounds(far) and not map.walkable(far) and map.edge(Terrain.edge_key(cell, direction)) != "door":
				sides.append(direction)
		if sides.is_empty() or rng.randf() >= RUNE_SHARE:
			continue
		var side: Vector2i = sides[rng.randi_range(0, sides.size() - 1)]
		out.append([cell.x, cell.y, side.x, side.y, "rune_strip", rng.randi_range(1, int(Level.DECOR_KINDS["rune_strip"]["variants"]))])
	return out


## Whether every anchor's floor reaches every other's on [param map], on
## foot through open and door edges (an anchor with no floor is let be).
static func connected(map: LevelMap, anchors: Array) -> bool:
	var starts: Array[Vector2i] = []
	for anchor: Dictionary in anchors:
		for cell in Level.rect_cells(anchor["rect"]):
			if map.walkable(cell):
				starts.append(cell)
				break
	if starts.size() < 2:
		return true
	var seen: Dictionary[Vector2i, bool] = {starts[0]: true}
	var queue: Array[Vector2i] = [starts[0]]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := here + direction
			if seen.has(next) or not map.in_bounds(next) or not map.walkable(next):
				continue
			if map.edge(Terrain.edge_key(here, direction)) == "wall":
				continue
			seen[next] = true
			queue.append(next)
	for start in starts:
		if not seen.has(start):
			return false
	return true


## The generated level's level.json: [param template_config] with what
## lies outside [param anchors] left out (entities, starts, places,
## buildings, decor, town walls, roofs; links and spawn points are kept, as
## Level warns of any outside), and "generation" written in for the record.
static func generated_config(template_config: Dictionary, anchors: Array, generation: int) -> Dictionary:
	var config := template_config.duplicate(true)
	var inside := func(value: Variant) -> bool:
		var at: Variant = Level._tile(value)
		return at != null and Level.in_anchors(anchors, at)
	if config.get("entities") is Array:
		config["entities"] = config["entities"].filter(func(entry: Variant) -> bool:
			return entry is Dictionary and inside.call(entry.get("at")))
	if config.get("starts") is Array:
		config["starts"] = config["starts"].filter(inside)
	if config.get("places") is Dictionary:
		var places := {}
		for key: Variant in config["places"]:
			var entry: Variant = config["places"][key]
			if entry is Dictionary and inside.call(entry.get("at")):
				places[key] = entry
		config["places"] = places
	if config.get("buildings") is Array:
		config["buildings"] = config["buildings"].filter(func(entry: Variant) -> bool:
			return entry is Dictionary and inside.call(entry.get("at")))
	if config.get("spots") is Array:
		# Where people stand and sit (Level.spots_from): kept in the anchors, with the rest laid there.
		config["spots"] = config["spots"].filter(func(entry: Variant) -> bool:
			return entry is Dictionary and inside.call(entry.get("cell")))
	# The template's moss and webs (647) inside the anchors; a web on a
	# niche goes too, since the niches are re-rolled (Level.decor_from would
	# say so otherwise): the roll hangs the generation's own.
	var decor: Array = []
	if config.get("decor") is Array:
		decor = config["decor"].filter(func(entry: Variant) -> bool:
			return entry is Array and entry.size() == 6 and str(entry[4]) != "web_niche" and inside.call([entry[0], entry[1]]))
	config["decor"] = decor
	# The named rooms (666, ui's 665 cards): kept where their rect lies in an
	# anchor, the one place a room keeps its walls through the generations.
	if config.get("rooms") is Dictionary:
		var rooms := {}
		for key: Variant in config["rooms"]:
			var entry: Variant = config["rooms"][key]
			var rect: Variant = Level.town_wall_rect(entry) if entry is Dictionary and entry.get("rect") is Array else null
			if rect != null and Level.in_anchors(anchors, rect.position) and Level.in_anchors(anchors, rect.end - Vector2i.ONE):
				rooms[key] = entry
		config["rooms"] = rooms
	for key: String in ["town_walls", "roofs"]:
		if config.get(key) is Array:
			config[key] = config[key].filter(func(entry: Variant) -> bool:
				var rect: Variant = Level.town_wall_rect(entry)
				return rect != null and Level.in_anchors(anchors, rect.position) and Level.in_anchors(anchors, rect.end - Vector2i.ONE))
	config["generation"] = generation
	return config


## Puts [param made] (generate) in place as level [param level_name]:
## registered in memory (Level.register, so it is read at once, a test's
## template kept aside first) and written to the overlay (Level.overlay_dir:
## a restart reads it, and Level.overlaid makes clients be sent it).
## Refused, with a warning, when the overlay holds that level without
## "regenerate" in its level.json: a level edited in the game (builder
## mode) is never written over. False when nothing was written.
static func write(level_name: String, made: Dictionary) -> bool:
	var folder := Level.overlay_dir + level_name + "/"
	if Level.overlaid(level_name):
		var there: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "level.json")) \
				if FileAccess.file_exists(folder + "level.json") else null
		if not (there is Dictionary and there.get("regenerate") is Dictionary):
			push_warning("[regen] %s is in the overlay without \"regenerate\" (edited in the game): not written over" % level_name)
			return false
	if not Level._templates.has(level_name):
		Level.keep_template(level_name, Level.template(level_name))
	made["config"]["laid_from"] = template_mark(level_name)  # 465 amended (4): what it was laid from.
	var absolute := ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(absolute):
		DirAccess.make_dir_recursive_absolute(absolute)
	var layout: Image = made["layout"]
	var error := layout.save_png(absolute.path_join("layout.png"))
	if error != OK:
		push_warning("[regen] could not write %slayout.png (%s)" % [folder, error_string(error)])
		return false
	var height: Image = made["height"]
	if height != null:
		error = height.save_png(absolute.path_join("height.png"))
		if error != OK:
			push_warning("[regen] could not write %sheight.png (%s)" % [folder, error_string(error)])
			return false
	elif FileAccess.file_exists(folder + "height.png"):
		DirAccess.remove_absolute(absolute.path_join("height.png"))
	var json := FileAccess.open(folder + "level.json", FileAccess.WRITE)
	if json == null:
		push_warning("[regen] could not write %slevel.json" % folder)
		return false
	json.store_string(JSON.stringify(made["config"], "\t", false) + "\n")
	json.close()
	Level.register(level_name, layout, height, made["config"])
	return true


## What of a zone's saved section (Snapshot's {tick, entities, respawns,
## ground, records}) survives a generation: {kept: the section with only
## what sits inside [param anchors] (an entity, respawn timer or record by
## its marker-cell key, decision 433, else its cell; a ground pile by its
## cell), lost: the ItemBook uids of everything else, to be ended}.
##
## With [param keep_to] a cell (790: the regenerate block's "keep_ground",
## keep_cell), nothing on the ground is lost: every pile outside the anchors,
## and the load of a cart outside them (a Cargo entity; the new map brings
## its own cart), go into one pile on that cell, their uids listed in
## "moved" (Main places them there and notes it, MOVED); [param id_of]
## (uid -> item id) names a cart's things for the pile.
static func keep_section(section: Dictionary, anchors: Array, keep_to: Variant = null, id_of := Callable()) -> Dictionary:
	var lost: Array[int] = []
	var moved: Array[int] = []
	var kept := {"tick": int(section.get("tick", 0)), "entities": [], "respawns": [], "ground": [], "records": []}
	var keeping := keep_to is Vector2i
	var heap := {"cell": keep_to, "ids": [], "items": [], "gold": 0}
	for entry: Dictionary in section.get("entities", []):
		if _keeps(anchors, entry["spec"]):
			kept["entities"].append(entry)
		elif keeping and str(entry["spec"].get("script", "")) == Level.CARGO and id_of.is_valid():
			var cargo: Array[int] = []
			_uids_of(entry.get("items", []), cargo)
			for uid in cargo:
				var id := str(id_of.call(uid))
				if id.is_empty():
					lost.append(uid)
					continue
				heap["ids"].append(id)
				heap["items"].append(uid)
				moved.append(uid)
		else:
			_uids_of(entry.get("items", []), lost)
	for respawn: Dictionary in section.get("respawns", []):
		var at: Variant = _key_cell(str(respawn.get("spawn_key", "")))
		if at != null and Level.in_anchors(anchors, at):
			kept["respawns"].append(respawn)
	for pile: Dictionary in section.get("ground", []):
		if keeping and pile["cell"] == keep_to:
			heap["ids"].append_array(pile.get("ids", []))
			heap["items"].append_array(pile.get("items", []))
			heap["gold"] = int(heap["gold"]) + int(pile.get("gold", 0))
		elif Level.in_anchors(anchors, pile["cell"]):
			kept["ground"].append(pile)
		elif keeping:
			heap["ids"].append_array(pile.get("ids", []))
			heap["items"].append_array(pile.get("items", []))
			heap["gold"] = int(heap["gold"]) + int(pile.get("gold", 0))
			_uids_of(pile.get("items", []), moved)
		else:
			_uids_of(pile.get("items", []), lost)
	if keeping and (not (heap["ids"] as Array).is_empty() or int(heap["gold"]) > 0):
		kept["ground"].append(heap)
	for record: Dictionary in section.get("records", []):
		var entry: Variant = record.get("entry", {})
		var spec: Variant = Snapshot.parse_entry(entry).get("spec", {})
		if spec is Dictionary and not spec.is_empty() and _keeps(anchors, spec):
			kept["records"].append(record)
		elif entry is Dictionary:
			_uids_of(entry.get("items", []), lost)
	return {"kept": kept, "lost": lost, "moved": moved}


## Where level [param level_name]'s ground is gathered when it is laid again
## (790, keep_section's keep_to): its regenerate block's "keep_ground" names
## an anchor ("entrance": the entrance anchor, entrance_of), and the pile
## lies on the template's first start inside it, else the anchor's centre;
## null when the block says no "keep_ground" (465: what lies outside the
## anchors is lost).
static func keep_cell(level_name: String) -> Variant:
	var config := config_of(level_name)
	var named := str(config.get("keep_ground", ""))
	if named.is_empty():
		return null
	var anchor := entrance_of(config) if named == "entrance" else {}
	for each: Dictionary in config.get("anchors", []):
		if str(each.get("name", "")) == named:
			anchor = each
	if anchor.is_empty():
		return null
	var rect: Rect2i = anchor["rect"]
	for start: Variant in Level.template_config(level_name).get("starts", []):
		var at: Variant = Level._tile(start)
		if at is Vector2i and rect.has_point(at):
			return at
	return rect.position + rect.size / 2


## Whether a saved entity's [param spec] sits in [param anchors]: by its
## marker-cell key when it has one, else by its tile.
static func _keeps(anchors: Array, spec: Dictionary) -> bool:
	var at: Variant = _key_cell(str(spec.get("spawn_key", "")))
	if at == null:
		at = spec.get("tile")
	return at is Vector2i and Level.in_anchors(anchors, at)


## A spawn key "x,y" as a cell; null for none or one that is no pair.
static func _key_cell(key: String) -> Variant:
	var parts := key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(parts[0].to_int(), parts[1].to_int())


static func _uids_of(values: Variant, into: Array[int]) -> void:
	if not values is Array:
		return
	for value: Variant in values:
		if (value is int or value is float) and int(value) != 0:
			into.append(int(value))


## The spawn point inside an anchor of [param level] nearest [param cell]
## (where a player saved in what is now rock comes back); null if the level
## has none in an anchor.
static func anchor_spawn_near(level: Dictionary, cell: Vector2i) -> Variant:
	var anchors: Array = level.get("regenerate", {}).get("anchors", [])
	var best: Variant = null
	var best_distance := 0
	var spawn_points: Dictionary = level.get("spawn_points", {})
	var names: Array = spawn_points.keys()
	names.sort()
	for spawn_name: String in names:
		var at: Vector2i = spawn_points[spawn_name]
		if not Level.in_anchors(anchors, at):
			continue
		var d := absi(at.x - cell.x) + absi(at.y - cell.y)
		if best == null or d < best_distance:
			best = at
			best_distance = d
	return best
