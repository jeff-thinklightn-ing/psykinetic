extends Node
## Hollowfell, the hills' mine (decision 790, 769's phases 2-3): its
## template and the mine generator (sim/level_gen/mine.gd) over six
## generations: the anchors kept verbatim, the rest laid again, the same
## generation the same map; every generation parses cleanly, keeps the width
## rule, has its relief's ledges, and every cell walks back to the start by
## World's step rule (783: no pit is a trap); seams in recesses, track by
## physics' 794 rules with its cart, every lamp lit, the monsters laid and
## none near the mouth. Then keep_ground: what lay outside the anchors
## gathered at the mouth, none of it lost.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const LEVEL := "hollowfell"
const GENERATIONS := 6

var _failures := 0


func _ready() -> void:
	World.set_process(false)

	_test_template()
	_test_generations()
	_test_keep_ground()
	_test_other_generators()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_template() -> void:
	print("\n== Hollowfell's template: three anchors, marked to regenerate by the mine generator ==")
	var level := Level.load_level(LEVEL)
	_check(not level.is_empty() and level["warnings"].is_empty(), "it loads cleanly (%s)" % [level.get("warnings", "no level")])
	var config := Regen.config_of(LEVEL)
	var names: Array = (config.get("anchors", []) as Array).map(func(anchor: Dictionary) -> String: return str(anchor["name"]))
	_check(Regen.marked(LEVEL) and config.get("generator") == "mine" and config.get("entrance") == "mouth" and config.get("keep_ground") == "entrance"
			and names == ["mouth", "chamber_east", "chamber_south"] and int(config["every_days"]) == 3,
			"the mine generator, every 3 days, entrance the mouth, ground kept there; anchors %s" % [names])
	var respawn: Dictionary = Level.template_config(LEVEL).get("respawn_s", {})
	var seconds := {}
	for kind: Variant in respawn:
		seconds[kind] = int(respawn[kind])
	_check(config.get("monsters") == {"imp": 4, "sneak": 3, "brute": 1} and seconds == {"imp": 600, "sneak": 600, "brute": 900},
			"imps 4, sneaks 3, a brute; respawned 600, 600 and 900 s (enemy-ai)")
	_check(Level.template_config(LEVEL).get("mass") == "rock" and is_equal_approx(float(level["terrain"]["ambient"]), 0.03),
			"the rock mass round it, ambient 0.03 (terrain's mass, environment's light)")
	_check(Regen.keep_cell(LEVEL) == Vector2i(4, 35) and Regen.keep_cell("castle_halls") == null,
			"the ground is gathered on the mouth's start (4, 35); the halls keep 465's rule (%s)" % [Regen.keep_cell(LEVEL)])


func _test_generations() -> void:
	print("\n== six generations: anchors kept, the rest laid again, each sound ==")
	var template := Level.template(LEVEL)
	var base := LevelMap.from_image(template["layout"], template["config"])
	var anchors: Array = Regen.config_of(LEVEL)["anchors"]
	var config := Regen.config_of(LEVEL)
	var layouts: Array[PackedByteArray] = []
	for generation in range(1, GENERATIONS + 1):
		var made := Regen.generate(LEVEL, generation)
		_check(not made.is_empty(), "generation %d is made (%d tries)" % [generation, made.get("tries", 0)])
		if made.is_empty():
			continue
		var layout: Image = made["layout"]
		layouts.append(layout.get_data())
		var map := LevelMap.from_image(layout, made["config"])
		var changed: Array[Vector2i] = []
		for anchor: Dictionary in anchors:
			for cell in Level.rect_cells(anchor["rect"]):
				if map.cell(cell) != base.cell(cell):
					changed.append(cell)
		_check(changed.is_empty(), "generation %d: the anchors' cells are the template's (changed: %s)" % [generation, changed.slice(0, 6)])
		var level := Level.parse(layout, made["height"], made["config"])
		_check(level["warnings"].is_empty(), "generation %d parses cleanly (%s)" % [generation, level["warnings"].slice(0, 4)])
		var terrain: Dictionary = level["terrain"]
		var narrow := Level.narrow_runs(terrain)
		_check(narrow.is_empty(), "generation %d: no passage one cell wide (%s)" % [generation, narrow.slice(0, 6)])
		_check(JSON.stringify(made["config"].get("ledges", [])) == JSON.stringify(Level.ledges_of(terrain)) and not (made["config"].get("ledges", []) as Array).is_empty(),
				"generation %d: its %d ledges are its relief's (585)" % [generation, (made["config"].get("ledges", []) as Array).size()])
		_check_walks(generation, level)
		_check_seams(generation, level, config)
		_check_track(generation, level)
		_check_lamps(generation, level)
		_check_monsters(generation, level, config)
	var differ := true
	for i in layouts.size():
		for j in range(i + 1, layouts.size()):
			if layouts[i] == layouts[j]:
				differ = false
	_check(layouts.size() == GENERATIONS and differ, "the %d generations all differ" % layouts.size())
	var again := Regen.generate(LEVEL, 2)
	_check(not again.is_empty() and (again["layout"] as Image).get_data() == layouts[1] and JSON.stringify(again["config"]) == JSON.stringify(Regen.generate(LEVEL, 2)["config"]),
			"generation 2 laid twice is the same map, decor and all")


## Every walkable cell of [param level] walks to its start by World's step
## rule (the walk the other way: a cell is reached when a step from it onto
## a reached one is open), so no cell below the floor is a trap (783), and
## every anchor reaches the mouth; at least two pits' worth of cells lie
## below the floor, with stairs.
func _check_walks(generation: int, level: Dictionary) -> void:
	World.reset()
	World.load_terrain(level["terrain"])
	var start: Vector2i = level["starts"][0]
	var floor_level := int(level["terrain"]["heights"].get(start, 0))
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for way: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			if not reached.has(cell + way) and not World._terrain_blocks_step(cell + way, -way, true):
				reached[cell + way] = true
				queue.append(cell + way)
	var stranded: Array[Vector2i] = []
	var below := 0
	for cell: Vector2i in level["terrain"]["floor"]:
		if not reached.has(cell):
			stranded.append(cell)
		if int(level["terrain"]["heights"].get(cell, 0)) < floor_level:
			below += 1
	_check(stranded.is_empty() and below >= 16 and not level["terrain"]["stairs"].is_empty(),
			"generation %d: every cell walks back to the start, the %d below the floor by their stairs (stranded: %s)" % [generation, below, stranded.slice(0, 6)])


func _check_seams(generation: int, level: Dictionary, config: Dictionary) -> void:
	var seams := 0
	var recessed := 0
	for spec: Dictionary in level["entities"]:
		if spec.get("script") == Level.SEAM_SCRIPT:
			seams += 1
			recessed += 1 if World.in_recess(spec["tile"]) else 0
	var span: Array = config["seams"]
	# 806 amended: besides, one in each gallery's end and in any bay holding nothing.
	var most := int(span[1]) + 2 + int(config.get("galleries", [0, 5])[1]) + int(config.get("bays", [0, 6])[1])
	_check(seams >= int(span[0]) + 2 and seams <= most and recessed == seams,
			"generation %d: %d seams (the chamber's 2, %s laid, and the galleries' and empty bays'; at most %d), all in a recess" % [generation, seams, span, most])


## Physics' 794 rules: no track cell with three track neighbours, every end
## a buffer, no track on a stair; the generated cart on a track cell, drawn
## as prop.mine_cart along it.
func _check_track(generation: int, level: Dictionary) -> void:
	var track := {}
	var ends := 0
	for piece: Dictionary in level["terrain"].get("decor", []):
		if piece["kind"] == "mine_track":
			track[piece["cell"]] = piece
	var faults: Array = []
	for cell: Vector2i in track:
		var near := 0
		for way: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			near += 1 if track.has(cell + way) else 0
		if near >= 3 or level["terrain"]["stairs"].has(cell) or (near <= 1 and int(track[cell]["variant"]) != 3):
			faults.append(cell)
		ends += 1 if near <= 1 else 0
	var carts: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec.get("art") == "prop.mine_cart")
	var on_track := carts.all(func(spec: Dictionary) -> bool: return track.has(spec["tile"]))
	_check(track.size() >= 8 + 6 and faults.is_empty() and ends >= 4 and carts.size() >= 2 and on_track,
			"generation %d: %d track cells, %d ends, %d carts on it (faults: %s)" % [generation, track.size(), ends, carts.size(), faults.slice(0, 4)])


func _check_lamps(generation: int, level: Dictionary) -> void:
	var lamps := {}
	for piece: Dictionary in level["terrain"].get("decor", []):
		if piece["kind"] == "mine_lamp":
			lamps[piece["cell"]] = true
	var lights := {}
	for cell: Vector2i in level["terrain"]["lanterns"]:
		lights[cell] = true
	var unpaired := lamps.keys().filter(func(cell: Vector2i) -> bool: return not lights.has(cell)) \
			+ lights.keys().filter(func(cell: Vector2i) -> bool: return not lamps.has(cell))
	_check(lamps.size() >= 20 and unpaired.is_empty(), "generation %d: %d lamps, each a lantern (unpaired: %s)" % [generation, lamps.size(), unpaired.slice(0, 4)])


func _check_monsters(generation: int, level: Dictionary, config: Dictionary) -> void:
	var counts := {}
	var near: Array = []
	var mouth: Rect2i = Regen.entrance_of(config)["rect"]
	for spec: Dictionary in level["entities"]:
		var kind := str(spec.get("kind", ""))
		if kind.is_empty():
			continue
		# The chambers' own (790 amended (3)): each chief and his two,
		# marked in the template's anchors, beside the block's "monsters".
		if Level.in_anchors(config.get("anchors", []), spec["tile"]):
			continue
		counts[kind] = int(counts.get(kind, 0)) + 1
		if mouth.grow(6).has_point(spec["tile"]):
			near.append(spec["tile"])
	_check(counts == config["monsters"] and near.is_empty(), "generation %d: monsters %s, none within 6 of the mouth (%s)" % [generation, counts, near])


func _test_keep_ground() -> void:
	print("\n== keep_ground: what lay outside the anchors gathered at the mouth, none lost ==")
	var anchors: Array = Regen.config_of(LEVEL)["anchors"]
	var keep_to: Vector2i = Regen.keep_cell(LEVEL)
	var cart_spec := {"script": Level.CARGO, "name": "Cart", "tile": Vector2i(40, 40), "spawn_key": "40,40"}
	var section := {"tick": 5, "entities": [{"spec": cart_spec, "items": [7, 8]}], "respawns": [],
		"ground": [{"cell": Vector2i(30, 30), "ids": ["ore"], "items": [3], "gold": 2},
			{"cell": keep_to, "ids": ["torch"], "items": [4], "gold": 0},
			{"cell": Vector2i(85, 24), "ids": ["rope"], "items": [5], "gold": 0}], "records": []}
	var names := {7: "ore", 8: "pick"}
	var sifted := Regen.keep_section(section, anchors, keep_to, func(uid: int) -> String: return names.get(uid, ""))
	var ground: Array = sifted["kept"]["ground"]
	var heap: Array = ground.filter(func(pile: Dictionary) -> bool: return pile["cell"] == keep_to)
	var stays: Array = ground.filter(func(pile: Dictionary) -> bool: return pile["cell"] == Vector2i(85, 24))
	_check(sifted["lost"].is_empty() and heap.size() == 1 and stays.size() == 1 and ground.size() == 2,
			"nothing lost; one pile at the mouth, the chamber's pile left where it lies (%s)" % [ground])
	if heap.size() == 1:
		var ids: Array = heap[0]["ids"].duplicate()
		ids.sort()
		_check(ids == ["ore", "ore", "pick", "torch"] and int(heap[0]["gold"]) == 2 and (sifted["moved"] as Array) == [7, 8, 3],
				"the pile holds the loose ore, the cart's load and what lay there already, the gold too; moved %s" % [sifted["moved"]])
	_check(sifted["kept"]["entities"].is_empty(), "the old cart is not kept (the new map brings its own)")
	var plain := Regen.keep_section(section, anchors)
	_check((plain["lost"] as Array) == [7, 8, 3] and plain["moved"].is_empty(), "without keep_ground, 465's rule: the rest is lost (%s)" % [plain["lost"]])
	_check(Regen.MOVED == "gathered at the way in" and Regen.LOST == "in the shifting halls", "the history says gathered, not lost (voice's line)")


func _test_other_generators() -> void:
	print("\n== the hook: a generator without decor_of adds no mine decor ==")
	var made := Regen.generate("castle_halls", 1)
	var mine_kinds: Array = (made.get("config", {}).get("decor", []) as Array).filter(func(row: Array) -> bool: return str(row[4]).begins_with("mine_"))
	_check(not made.is_empty() and mine_kinds.is_empty(), "castle_halls' generation lays no mine pieces (%d)" % mine_kinds.size())


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: " + what)
	else:
		_failures += 1
		print("FAIL: " + what)
