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
## How a thing lost outside the anchors is ended in the ItemBook.
const LOST := "in the shifting halls"
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
## own scratch folder, as regen_test does.
static func in_test_run() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-marker="):
			return true
	return false


## Whether this run may write the overlay it reads: no test run (tests/run.sh's
## --run-marker) ever writes the shared one (CLAUDE.md); a test with its own
## overlay may.
static func overlay_safe() -> bool:
	return not in_test_run() or Level.overlay_dir != Level.OVERLAY


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
## if latched, robbers_fallen: the band's ids fallen this generation}}) read back;
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
	for attempt in TRIES:
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
		return {"layout": map.to_image(), "height": height, "config": generated, "seed": seed, "tries": attempt + 1, "anchors": anchors}
	push_warning("[regen] %s: no map of %d tries joined every anchor; the last one stands" % [level_name, TRIES])
	return {}


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
## generation. Variants by the roll. Written into the generated level.json
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
static func keep_section(section: Dictionary, anchors: Array) -> Dictionary:
	var lost: Array[int] = []
	var kept := {"tick": int(section.get("tick", 0)), "entities": [], "respawns": [], "ground": [], "records": []}
	for entry: Dictionary in section.get("entities", []):
		if _keeps(anchors, entry["spec"]):
			kept["entities"].append(entry)
		else:
			_uids_of(entry.get("items", []), lost)
	for respawn: Dictionary in section.get("respawns", []):
		var at: Variant = _key_cell(str(respawn.get("spawn_key", "")))
		if at != null and Level.in_anchors(anchors, at):
			kept["respawns"].append(respawn)
	for pile: Dictionary in section.get("ground", []):
		if Level.in_anchors(anchors, pile["cell"]):
			kept["ground"].append(pile)
		else:
			_uids_of(pile.get("items", []), lost)
	for record: Dictionary in section.get("records", []):
		var entry: Variant = record.get("entry", {})
		var spec: Variant = Snapshot.parse_entry(entry).get("spec", {})
		if spec is Dictionary and not spec.is_empty() and _keeps(anchors, spec):
			kept["records"].append(record)
		elif entry is Dictionary:
			_uids_of(entry.get("items", []), lost)
	return {"kept": kept, "lost": lost}


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
