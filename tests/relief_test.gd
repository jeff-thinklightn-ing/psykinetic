extends Node
## The ground's relief (decision 525): Relief's rules (a cliff past
## WALK_RISE, a step as World.height_step says it, whole levels, the uphill
## pace, corners per side of a cliff, a pad, relief.png's centimetres
## round trip); a level's relief.png read (its whole levels derived, a
## stair found by metres, said when it is the wrong size or beside a
## height.png); buildings only on a pad; water level, running down, under
## its shore; in the world, a gentle hill walked (slower up) and a cliff
## not, a fall off it hurt by its levels, sight over the hill's ridge
## stopped and from its top not; routes costing the climb; the "terrain"
## message carrying relief.png; the sample's gentle rise. A level with no
## relief.png walking as before is cliff_test's and the rest of the suite's.
## Run it with tests/run.ps1 or tests/run.sh.

const WIDTH := 20
const HEIGHT := 12
## The ground round the hill and the plateau.
const BASE := 1.0
## The hill: rows 0 to 6, rising RISE a cell from x 4 to its ridge at
## RIDGE and down again to x 16.
const RIDGE := 10
const RISE := 0.4
## The plateau, CLIFF over the ground, a cliff all round.
const PLATEAU := Rect2i(14, 8, 6, 4)
const CLIFF := 2.0
## A pond, POND under the ground.
const POND := Rect2i(1, 9, 2, 2)
const POND_DEPTH := 0.5

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17865)
	Monster.idling = false
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	Level.register("rl_hill", _layout(), null, {"name": "The Hill", "outdoor": true}, Relief.image(_field(), Vector2i(WIDTH, HEIGHT)))
	_test_rules()
	_test_parse()
	_test_buildings()
	_test_water()
	_test_walk()
	_test_sight()
	_test_routes()
	_test_message()
	_test_sample()
	_test_lay()
	_test_escarpment()
	_test_curves()
	_test_curves_laid()
	_test_river()
	_test_road()
	_test_hills()
	_test_wilds()
	_test_bridge_decks()
	_main.load_map(Level.DEFAULT_MAP)
	Level.unregister("rl_hill")
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Grass over WIDTH x HEIGHT, the pond's water, the start at (1, 7).
static func _layout(water := POND) -> Image:
	var rows: Array[String] = []
	for y in 2 * HEIGHT - 1:
		rows.append(".".repeat(2 * WIDTH - 1))
	var markers := {}
	for y in HEIGHT:
		for x in WIDTH:
			markers[Vector2i(x, y)] = "water" if water.has_point(Vector2i(x, y)) else "grass"
	markers[Vector2i(1, 7)] = "start"
	return Level.image_from_rows(rows, markers)


## The hill, the plateau and the pond over BASE ground.
static func _field() -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(WIDTH * HEIGHT)
	for y in HEIGHT:
		for x in WIDTH:
			var height := BASE
			if y <= 6 and absi(x - RIDGE) <= 6:
				height += RISE * (6 - absi(x - RIDGE))
			if PLATEAU.has_point(Vector2i(x, y)):
				height += CLIFF
			if POND.has_point(Vector2i(x, y)):
				height -= POND_DEPTH
			field[y * WIDTH + x] = height
	return field


func _test_rules() -> void:
	print("== Relief's rules ==")
	_check(not Relief.cliff_between(0.0, 0.45) and Relief.cliff_between(0.0, 0.46) and Relief.cliff_between(1.0, 0.5)
		and not Relief.cliff_between(0.0, 0.6, true) and Relief.cliff_between(0.0, 0.7, true),
		"a cliff past %.2f m a step (sqrt 2 times that on a diagonal)" % Relief.WALK_RISE)
	var size := Vector2i(3, 2)
	var field := PackedFloat32Array([0.0, 0.3, 1.0, 0.0, 0.3, 0.5])
	var stairs := {Vector2i(1, 1): Vector2i(1, 0)}
	_check(Relief.step(field, size, {}, Vector2i(0, 0), Vector2i(1, 0)) == 0, "a gentle step is walked")
	_check(Relief.step(field, size, {}, Vector2i(1, 0), Vector2i(1, 0)) == -1 and Relief.step(field, size, {}, Vector2i(2, 0), Vector2i(-1, 0)) == 1,
		"0.7 m up is a ledge a level up, down a drop of one")
	_check(Relief.step(field, size, stairs, Vector2i(1, 1), Vector2i(1, 0)) == 0 and Relief.step(field, size, {}, Vector2i(1, 1), Vector2i(1, 0)) == 0,
		"0.2 m up is walked, stair or none")
	var stepped := PackedFloat32Array([0.0, 0.5, 0.0, 0.0])
	_check(Relief.step(stepped, Vector2i(2, 2), {Vector2i(0, 0): Vector2i(1, 0)}, Vector2i(0, 0), Vector2i(1, 0)) == 0
		and Relief.step(stepped, Vector2i(2, 2), {}, Vector2i(0, 0), Vector2i(1, 0)) == -1
		and Relief.step(stepped, Vector2i(2, 2), {Vector2i(0, 0): Vector2i(1, 0)}, Vector2i(1, 0), Vector2i(-1, 0)) == 0,
		"a stair climbs %.1f m its own way, down too; without one it is a ledge" % Relief.STAIR_RISE)
	_check(Relief.step(stepped, Vector2i(2, 2), {}, Vector2i(0, 1), Vector2i(1, -1)) != 0, "a diagonal past a ledge is not walked")
	_check(Relief.levels(1.5) == 3 and Relief.levels(-0.2) == -1 and Relief.levels(0.9) == 2, "metres in whole levels, one at least")
	_check(is_equal_approx(Relief.pace(Relief.WALK_RISE), 1.0 + Relief.UPHILL_PACE) and Relief.pace(-0.4) == 1.0 and Relief.pace(0.0) == 1.0
		and Relief.pace(0.9) == 1.0, "uphill %.1f times as long at the steepest, down and on the flat as ever (a stair's rise too)" % (1.0 + Relief.UPHILL_PACE))
	var joined := Relief.corner_heights(PackedFloat32Array([0.0, 0.2]), Vector2i(2, 1), Vector2i(0, 0))
	_check(is_equal_approx(joined[1], 0.1) and is_equal_approx(joined[3], 0.1) and joined[0] == 0.0,
		"a corner is the mean of the cells joined at it (%s)" % [joined])
	var faced := PackedFloat32Array([0.0, 1.0])
	var low := Relief.corner_heights(faced, Vector2i(2, 1), Vector2i(0, 0))
	var high := Relief.corner_heights(faced, Vector2i(2, 1), Vector2i(1, 0))
	_check(low[1] == 0.0 and low[3] == 0.0 and high[0] == 1.0 and high[2] == 1.0, "across a cliff each side keeps its own corners (%s, %s)" % [low, high])
	# terrain's case on the sample: (1, 1) 0.59 over (0, 1) is a cliff, but
	# round the ring by (1, 0) and (0, 0) all four are joined.
	var ring := PackedFloat32Array([0.0, 0.35, 0.0, 0.59])
	var a := Relief.corner_heights(ring, Vector2i(2, 2), Vector2i(1, 1))
	var b := Relief.corner_heights(ring, Vector2i(2, 2), Vector2i(1, 0))
	_check(is_equal_approx(a[0], b[2]) and is_equal_approx(a[0], (0.0 + 0.35 + 0.0 + 0.59) / 4.0),
		"a ring cut once is one: walkably joined cells share their corner (%.3f, %.3f)" % [a[0], b[2]])
	var split := Relief.corner_heights(PackedFloat32Array([0.0, 1.0, 1.0, 0.0]), Vector2i(2, 2), Vector2i(0, 0))
	_check(split[3] == 0.0, "cut twice it splits (%.2f)" % split[3])
	_check(Relief.flat(PackedFloat32Array([1.0, 1.04, 1.02, 0.99]), Vector2i(2, 2), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])
		and not Relief.flat(PackedFloat32Array([1.0, 1.06]), Vector2i(2, 1), [Vector2i(0, 0), Vector2i(1, 0)]), "a pad is flat within %.2f m" % Relief.PAD_FLAT)
	var cm := PackedFloat32Array([1.23, 300.5, 0.0, 655.35])
	var image := Relief.image(cm, Vector2i(2, 2))
	var read := Relief.read(image, Vector2i(2, 2), [] as Array[String])
	_check(image.get_format() == Image.FORMAT_RGB8 and read.size() == 4 and is_equal_approx(read[0], 1.23) and is_equal_approx(read[1], 300.5)
		and read[2] == 0.0 and is_equal_approx(read[3], 655.35), "relief.png's centimetres round trip (%s)" % [read])
	var saved := Image.new()
	saved.load_png_from_buffer(image.save_png_to_buffer())
	_check(is_equal_approx(Relief.read(saved, Vector2i(2, 2), [] as Array[String])[1], 300.5), "and through a PNG")
	var derived := Relief.derived({Vector2i(1, 0): 2}, Vector2i(2, 1))
	_check(derived[0] == 0.0 and derived[1] == 1.0 and Relief.whole_levels(PackedFloat32Array([0.2, 1.3]), Vector2i(2, 1)) == {Vector2i(1, 0): 3},
		"whole levels to metres and back")


func _test_parse() -> void:
	print("== relief.png read ==")
	var level := Level.load_level("rl_hill")
	var terrain: Dictionary = level["terrain"]
	_check(level["warnings"].is_empty(), "the hill says nothing (%s)" % [level["warnings"]])
	_check(terrain["relief_given"] and terrain["relief_size"] == Vector2i(WIDTH, HEIGHT)
		and is_equal_approx(Relief.at(terrain["relief"], terrain["relief_size"], Vector2i(RIDGE, 3)), BASE + 6 * RISE), "the field is in the terrain")
	_check(terrain["heights"].get(Vector2i(RIDGE, 3), 0) == roundi((BASE + 6 * RISE) / Relief.LEVEL_M) and terrain["heights"].get(PLATEAU.position, 0) == roundi((BASE + CLIFF) / Relief.LEVEL_M),
		"whole levels derived for what reads them (%s)" % [terrain["heights"].get(Vector2i(RIDGE, 3), 0)])
	var wrong := Level.parse(_layout(), null, {"outdoor": true}, Image.create_empty(3, 3, false, Image.FORMAT_RGB8))
	_check(not wrong["terrain"]["relief_given"] and wrong["warnings"].any(func(w: String) -> bool: return "relief.png is" in w and "relief ignored" in w),
		"a relief.png of the wrong size is said and ignored")
	var heights := Level.height_image(_layout(), {Vector2i(5, 8): 1})
	var both := Level.parse(_layout(), heights, {"outdoor": true}, Relief.image(_field(), Vector2i(WIDTH, HEIGHT)))
	_check(both["warnings"].any(func(w: String) -> bool: return "relief.png is the ground" in w) and both["terrain"]["heights"].get(Vector2i(5, 8)) == roundi(BASE / Relief.LEVEL_M),
		"beside a height.png it wins, said (%s, %s)" % [both["warnings"], both["terrain"]["heights"].get(Vector2i(5, 8))])
	var none := Level.parse(_layout(), heights, {"outdoor": true})
	_check(not none["terrain"]["relief_given"] and Relief.at(none["terrain"]["relief"], none["terrain"]["relief_size"], Vector2i(5, 8)) == Relief.LEVEL_M,
		"with none it is derived, %.1f m a level" % Relief.LEVEL_M)
	# A stair found by metres: at the plateau's foot a slope climbs to it?
	# CLIFF is too much, so a cell half way: a stair at (13, 9) up to 0.5 m.
	var field := _field()
	field[9 * WIDTH + 13] = BASE + CLIFF - 0.5
	var layout := _layout()
	layout.set_pixelv(Vector2i(13, 9) * 2, Color(Level.LEGEND["stair"]))
	var stair := Level.parse(layout, null, {"outdoor": true}, Relief.image(field, Vector2i(WIDTH, HEIGHT)))
	_check(stair["terrain"]["stairs"].get(Vector2i(13, 9)) == Vector2i(1, 0), "a stair climbs to the cell %.1f m up (%s)" % [Relief.STAIR_RISE, stair["terrain"]["stairs"]])


func _test_buildings() -> void:
	print("== pads ==")
	var config := {"outdoor": true, "buildings": [{"slot": "building.hut", "at": [5, 8]}, {"slot": "building.hut", "at": [6, 1]}]}
	var level := Level.parse(_layout(), null, config, Relief.image(_field(), Vector2i(WIDTH, HEIGHT)))
	var cells: Array = level["buildings"].map(func(b: Dictionary) -> Vector2i: return b["cell"])
	_check(Vector2i(5, 8) in cells and not Vector2i(6, 1) in cells, "a hut on flat ground stands, one on the hill's side does not (%s)" % [cells])
	_check(level["warnings"].any(func(w: String) -> bool: return "building.hut at (6, 1) is not all on clear floor of one height" in w), "said")
	var field := _field()
	field[8 * WIDTH + 6] = BASE + 0.04
	var rough := Level.parse(_layout(), null, {"outdoor": true, "buildings": [{"slot": "building.hut", "at": [5, 8]}]}, Relief.image(field, Vector2i(WIDTH, HEIGHT)))
	_check(rough["buildings"].size() == 1, "within %.2f m is a pad" % Relief.PAD_FLAT)


func _test_water() -> void:
	print("== water ==")
	var field := _field()
	field[9 * WIDTH + 1] += 0.2
	var tilted := Level.parse(_layout(), null, {"outdoor": true}, Relief.image(field, Vector2i(WIDTH, HEIGHT)))
	_check(tilted["warnings"].any(func(w: String) -> bool: return "pond at" in w and "not level" in w), "a pond not level is said (%s)" % [tilted["warnings"]])
	field = _field()
	field[9 * WIDTH + 3] = BASE - POND_DEPTH + 0.05
	var low := Level.parse(_layout(), null, {"outdoor": true}, Relief.image(field, Vector2i(WIDTH, HEIGHT)))
	_check(low["warnings"].any(func(w: String) -> bool: return "has its shore at (3, 9) less than 0.1 m over it" in w), "a shore under %.1f m over the water is said" % Relief.SHORE_LIP)
	# A stream down x 8 to the map's edge, rising once.
	var stream := Rect2i(8, 7, 1, 5)
	field = _field()
	var path: Array = []
	for y in range(7, 12):
		field[y * WIDTH + 8] = BASE - 0.3 - 0.05 * y
		path.append([8, y])
	var down := Level.parse(_layout(stream), null, {"outdoor": true, "streams": [{"path": path}]}, Relief.image(field, Vector2i(WIDTH, HEIGHT)))
	_check(not down["warnings"].any(func(w: String) -> bool: return "stream" in w or "water" in w), "a stream stepping down says nothing (%s)" % [down["warnings"]])
	field[10 * WIDTH + 8] += 0.2
	var up := Level.parse(_layout(stream), null, {"outdoor": true, "streams": [{"path": path}]}, Relief.image(field, Vector2i(WIDTH, HEIGHT)))
	_check(up["warnings"].any(func(w: String) -> bool: return "the stream from (8, 7) rises at (8, 10)" in w), "one rising is said (%s)" % [up["warnings"]])


func _test_walk() -> void:
	print("== walked ==")
	_check(_main.load_map("rl_hill"), "the level loads")
	_check(World.has_relief() and is_equal_approx(World.elevation_at(Vector2i(RIDGE, 3)), BASE + 6 * RISE), "World holds the field")
	_check(World.height_step(Vector2i(5, 3), Vector2i(1, 0)) == 0 and World.height_step(Vector2i(6, 3), Vector2i(1, 1)) == 0,
		"up the hill, straight and diagonal, is walked")
	var path := World.find_path(Vector2i(4, 3), Vector2i(16, 3))
	_check(path.size() == 12, "over the ridge in 12 steps (%d)" % path.size())
	var player := _player()
	World._relocate(player, Vector2i(5, 3))
	var up := World.step_ticks(player, Vector2i(1, 0))
	World._relocate(player, Vector2i(11, 3))
	var down := World.step_ticks(player, Vector2i(1, 0))
	_check(is_equal_approx(up, player.move_ticks * Relief.pace(RISE)) and is_equal_approx(down, player.move_ticks),
		"a step up takes %.2f times as long, down as ever" % Relief.pace(RISE))
	# A step planned ahead is paced by its own cells (perf, 2026-10-19: a
	# client predicting from where it stands drifted from the server, the
	# wilds town's rubber banding).
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0), Vector2i(5, 3)), up), "a step from another cell is paced by that cell's slope")
	World._relocate(player, Vector2i(RIDGE - 1, 3))
	var shown := MovePrediction.new(player)
	_check(shown.step(Vector2i(1, 0)) and shown.step(Vector2i(1, 0)), "two WASD steps shown, up to the ridge and over")
	_check(is_equal_approx(shown._steps[0].duration, up) and is_equal_approx(shown._steps[1].duration, down),
		"the first paced up, the second down from the ridge, as the server will take them (%.2f, %.2f)" % [shown._steps[0].duration, shown._steps[1].duration])
	_check(World._terrain_blocks_step(Vector2i(13, 9), Vector2i(1, 0)) and World._terrain_blocks_step(Vector2i(14, 9), Vector2i(-1, 0)),
		"the plateau's cliff stops a step up and off")
	var imp: Monster = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Faller", "tile": Vector2i(14, 9), "props": {"sight_range": 0, "max_hp": 50}})
	World._relocate(player, Vector2i(15, 9))
	var hp := imp.hp
	World._push(player, imp, Vector2i(-1, 0), 3.0)
	_check(imp.tile.x < 14 and hp - imp.hp == World.FALL_IMPACT_PER_LEVEL * Relief.levels(CLIFF),
		"pushed off %.1f m it falls %d levels, hurt %d (%s, %d)" % [CLIFF, Relief.levels(CLIFF), World.FALL_IMPACT_PER_LEVEL * Relief.levels(CLIFF), imp.tile, hp - imp.hp])
	World.despawn(imp)


func _test_sight() -> void:
	print("== sight over the ridge ==")
	_main.load_map("rl_hill")
	_check(not World.has_line_of_sight(Vector2i(2, 3), Vector2i(18, 3)), "the ridge hides one foot from the other")
	_check(World.has_line_of_sight(Vector2i(2, 3), Vector2i(RIDGE, 3)), "the ridge itself is seen")
	_check(World.has_line_of_sight(Vector2i(RIDGE, 3), Vector2i(18, 3)) and World.has_line_of_sight(Vector2i(RIDGE, 3), Vector2i(2, 3)),
		"from the top, both sides")
	_check(World.has_line_of_sight(Vector2i(2, 9), Vector2i(12, 9)), "on the flat, far")
	_check(World.has_line_of_sight(Vector2i(13, 9), Vector2i(15, 9)) and not World.has_line_of_sight(Vector2i(13, 9), Vector2i(18, 9)),
		"from under the plateau its lip is seen, not what stands back from it")
	var line := World.shot_line(Vector2i(2, 3), Vector2i(18, 3), 20)
	_check(not Vector2i(18, 3) in line and not line.is_empty(), "a shot over the ridge stops on its side (%d cells)" % line.size())


func _test_routes() -> void:
	print("== routes ==")
	var area := {"relief": _field(), "relief_size": Vector2i(WIDTH, HEIGHT), "stairs": {}, "heights": {}, "edges": {}, "floor": {}, "size": Vector2i(WIDTH, HEIGHT)}
	for y in HEIGHT:
		for x in WIDTH:
			area["floor"][Vector2i(x, y)] = true
	_check(WorldRoutes.climb_cost(area, Vector2i(5, 3), Vector2i(1, 0), 2) == roundi(2 * (Relief.pace(RISE) - 1.0))
		and WorldRoutes.climb_cost(area, Vector2i(11, 3), Vector2i(1, 0), 2) == 0, "a climb costs half steps, a descent none")
	_check(WorldRoutes.can_step(area, Vector2i(5, 3), Vector2i(1, 0)) and not WorldRoutes.can_step(area, Vector2i(13, 9), Vector2i(1, 0)),
		"a group walks the hill, not the cliff")
	var over := WorldRoutes._steps_between(area, Vector2i(4, 3), Vector2i(16, 3))
	_check(over > 12.0, "over the ridge costs more than its 12 steps (%.1f)" % over)


func _test_message() -> void:
	print("== the terrain message ==")
	var message := BuilderHost.terrain_message("rl_hill")
	_check(not (message.get("relief", PackedByteArray()) as PackedByteArray).is_empty(), "it carries relief.png")
	message["name"] = "rl_hill_told"
	_check(BuilderHost.register_terrain(message), "a client reads it")
	var told := Level.load_level("rl_hill_told")
	_check(told["terrain"]["relief_given"] and told["terrain"]["relief"] == Level.load_level("rl_hill")["terrain"]["relief"], "the same ground")
	Level.unregister("rl_hill_told")


func _test_sample() -> void:
	print("== the sample level ==")
	var level := Level.load_level("sample")
	var terrain: Dictionary = level["terrain"]
	_check(terrain["relief_given"] and level["warnings"].is_empty(), "relief.png, nothing said (%s)" % [level["warnings"]])
	var top := Relief.at(terrain["relief"], terrain["relief_size"], Vector2i(13, 15))
	_check(top > 1.0, "a rise east of the stream (%.2f m)" % top)
	var steep := 0
	for y in range(11, 19):
		for x in range(13, 16):
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if Relief.cliff_between(Relief.at(terrain["relief"], terrain["relief_size"], Vector2i(x, y)),
						Relief.at(terrain["relief"], terrain["relief_size"], Vector2i(x, y) + d)) and x + d.x < 16 and y + d.y < 19:
					steep += 1
	_check(steep == 0, "walked all over (%d cliffs)" % steep)
	_check(terrain["stairs"].size() == 4, "its stairs and slopes as before (%s)" % [terrain["stairs"]])
	_check(_corners_agree(terrain).is_empty(), "walkably joined cells agree on every corner they share (%s)" % [_corners_agree(terrain)])


func _test_lay() -> void:
	print("== Relief.lay ==")
	var map := LevelMap.new(Vector2i(48, 40))
	for y in 40:
		for x in 48:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(5, 5), "void")
	var options := {"base": 4.0, "ridges": [[Vector2i(6, 4), Vector2i(20, 30)]], "valleys": [[Vector2i(30, 0), Vector2i(26, 39)]],
		"tilt": Vector2(0.0, -0.02), "plateaus": [{"rect": Rect2i(36, 4, 10, 10), "height": 3.0, "faces": ["west", "north"]}],
		"keep_flat": [Rect2i(8, 30, 4, 3)], "streams": 1, "width": 2}
	var laid := Relief.lay(map, Rect2i(0, 0, 48, 40), 3, options)
	var again := Relief.lay(map, Rect2i(0, 0, 48, 40), 3, options)
	_check(laid["relief"] == again["relief"] and laid["streams"] == again["streams"], "the same seed lays the same ground")
	_check(laid["relief"] != Relief.lay(map, Rect2i(0, 0, 48, 40), 4, options)["relief"], "another seed, other ground")
	_check(not laid["relief"].has(Vector2i(5, 5)), "void is left as it is")
	_check(laid["faces"].has(Terrain.edge_key(Vector2i(35, 8), Vector2i(1, 0))) and laid["faces"].has(Terrain.edge_key(Vector2i(40, 3), Vector2i(0, 1))),
		"lay returns the plateau's faces, for a later _limit to keep (%d)" % laid["faces"].size())
	for at: Vector2i in laid["relief"]:
		map.set_relief(at, laid["relief"][at])
	for at: Vector2i in laid["cells"]:
		map.set_cell(at, laid["cells"][at])
	var stray := 0
	var face := 0
	for at: Vector2i in map.cells:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next := at + step
			if not map.walkable(at) or not map.walkable(next) or map.cell(at) == "water" or map.cell(next) == "water":
				continue
			if Relief.cliff_between(map.relief_at(at), map.relief_at(next)):
				var on_face := (step == Vector2i(1, 0) and next.x == 36 and next.y >= 4 and next.y < 14) 						or (step == Vector2i(0, 1) and next.y == 4 and next.x >= 36)
				if on_face:
					face += 1
				else:
					stray += 1
	_check(stray == 0 and face >= 15, "walked everywhere but the plateau's west and north faces (%d face edges, %d others)" % [face, stray])
	var south := Relief.cliff_between(map.relief_at(Vector2i(40, 13)), map.relief_at(Vector2i(40, 14)))
	_check(not south, "its south side falls away walkably (%.2f to %.2f)" % [map.relief_at(Vector2i(40, 13)), map.relief_at(Vector2i(40, 14))])
	var pad: Array = []
	for y in range(30, 33):
		for x in range(8, 12):
			pad.append(Vector2i(x, y))
	_check(Relief.flat(map.relief, map.size, pad), "keep_flat is a pad")
	_check(laid["streams"].size() == 1 and laid["streams"][0].size() >= 10, "a stream down the valley (%s cells)" % [laid["streams"].map(func(p: Array) -> int: return p.size())])
	var path: Array = []
	for cell: Vector2i in laid["streams"][0]:
		path.append([cell.x, cell.y])
	var level := Level.parse(map.to_image(), null, {"outdoor": true, "streams": [{"path": path}]}, map.to_relief_image())
	_check(not level["warnings"].any(func(w: String) -> bool: return "stream" in w or "water" in w or "pond" in w),
		"its water runs down, under banks a lip over it (%s)" % [level["warnings"]])
	var painted := Relief.lay(map, Rect2i(0, 0, 48, 40), 3, options.merged({"kinds": true}))
	var cells: Dictionary = painted["cells"]
	var steep := 0
	var steep_rock := 0
	var bank_dirt := true
	for at: Vector2i in painted["relief"]:
		if cells.get(at, "") == "water" or not cells.has(at):
			continue
		var step := 0.0
		var by_water := false
		for d: Vector2i in Relief.FOUR:
			if cells.get(at + d, "") == "water":
				by_water = true
			elif painted["relief"].has(at + d):
				step = maxf(step, absf(float(painted["relief"][at + d]) - float(painted["relief"][at])))
		if step >= Relief.ROCK_STEP + Relief.KIND_WANDER:
			steep += 1
			steep_rock += 1 if cells[at] == "stone" else 0
		if by_water and step < Relief.ROCK_STEP - Relief.KIND_WANDER and cells[at] != "dirt":
			bank_dirt = false
	_check(steep > 0 and steep_rock == steep, "kinds: rock on every steep cell (%d of %d)" % [steep_rock, steep])
	_check(bank_dirt and cells.values().has("grass") and cells.values().has("dirt"), "dirt banks by the water, grass and bare dirt elsewhere")
	var padded := Relief.pad(map, Rect2i(20, 20, 3, 3))
	var ring: Array = padded["relief"].keys()
	_check(ring.size() == 25 and Relief.flat(PackedFloat32Array(padded["relief"].values()), Vector2i(25, 1),
		range(25).map(func(i: int) -> Vector2i: return Vector2i(i, 0)), 0.0), "Relief.pad levels a footprint and its apron (%d cells)" % ring.size())


## An escarpment (525 amended (2)): a face down its line, its long back
## slope walked, ramps at its way and its ends, everything reached.
## Curves (decision 559): a sample every SPACING along a smooth curve
## through the points, widths eased between theirs; the raster an open
## curve's cells within its width, its middle a side step at a time; a
## closed curve's cells inside it.
func _test_curves() -> void:
	print("== Curves ==")
	var points := PackedVector2Array([Vector2(0, 5), Vector2(10, 2), Vector2(20, 8), Vector2(30, 5)])
	var widths := PackedFloat32Array([1.0, 3.0, 3.0, 1.0])
	var curve := Curves.sample(points, widths)
	var sampled: PackedVector2Array = curve["points"]
	var even := true
	for i in range(1, sampled.size() - 1):
		even = even and absf(sampled[i].distance_to(sampled[i - 1]) - Curves.SPACING) < 0.02
	_check(sampled[0].distance_to(points[0]) < 0.01 and sampled[-1].distance_to(points[3]) < 0.3 and even,
		"sampled every quarter cell from its first point to its last (%d points, %.1f cells)" % [sampled.size(), curve["length"]])
	var through := Array(points.slice(1, 3))
	_check(through.all(func(point: Vector2) -> bool: return Curves.nearest(curve, point)["distance"] < 0.05), "it passes through its points")
	var turns := 0.0
	var tangents: PackedVector2Array = curve["tangents"]
	for i in range(1, tangents.size()):
		turns = maxf(turns, absf(tangents[i].angle_to(tangents[i - 1])))
	_check(turns < 0.2 and tangents.size() == sampled.size(), "smooth: no turn over 0.2 rad a sample (%.3f)" % turns)
	var at_point := Curves.nearest(curve, Vector2(10, 2))
	var wide_ok: bool = absf(at_point["width"] - 3.0) < 0.05 and absf(Curves.nearest(curve, Vector2(0, 5))["width"] - 1.0) < 0.05
	_check(wide_ok, "its width is each point's there (%.2f at the second)" % at_point["width"])
	var raster := Curves.cells(curve, false)
	var middle := Curves.middle(curve)
	var stepped := true
	for i in range(1, middle.size()):
		stepped = stepped and absi(middle[i].x - middle[i - 1].x) + absi(middle[i].y - middle[i - 1].y) == 1
	var within := true
	for cell: Vector2i in raster:
		var near := Curves.nearest(curve, Vector2(cell))
		within = within and (near["distance"] < near["width"] / 2.0 + 0.01 or middle.has(cell))
	_check(stepped and middle[0] == Vector2i(0, 5) and middle[-1] == Vector2i(30, 5) and middle.all(func(cell: Vector2i) -> bool: return raster.has(cell)),
		"its middle a side step at a time, end to end, in its cells (%d)" % middle.size())
	_check(within and raster.has(Vector2i(10, 1)) and raster.has(Vector2i(10, 3)) and not raster.has(Vector2i(1, 4)),
		"its cells lie within its width there: 3 wide at the second point, 1 at the first")
	var pond := Curves.sample(PackedVector2Array([Vector2(5, 5), Vector2(15, 4), Vector2(16, 12), Vector2(6, 13)]), PackedFloat32Array([0, 0, 0, 0]), true)
	var inside := Curves.cells(pond, true)
	_check(inside.has(Vector2i(10, 8)) and not inside.has(Vector2i(2, 8)) and inside.keys().all(func(cell: Vector2i) -> bool: return Curves.inside(pond, Vector2(cell))),
		"a closed curve's cells are those inside it (%d)" % inside.size())
	var pond_points: PackedVector2Array = pond["points"]
	_check(pond_points[0].distance_to(pond_points[-1]) < 0.3, "a closed curve comes round to its start")
	# A region traced into a closed curve (568): a few points, its cells about the region's.
	var region := {}
	for y in range(-4, 5):
		for x in range(-5, 6):
			if Vector2(x / 5.0, y / 4.0).length() <= 1.0:
				region[Vector2i(20 + x, 20 + y)] = true
	var traced := Curves.trace(region)
	var zero := PackedFloat32Array()
	zero.resize(traced.size())
	var back := Curves.cells(Curves.sample(traced, zero, true), true)
	var shared := back.keys().filter(func(cell: Vector2i) -> bool: return region.has(cell)).size()
	_check(traced.size() >= 4 and traced.size() < region.size() / 3 and shared >= region.size() * 0.8 and back.size() <= region.size() * 1.25,
		"a region traced (568): %d points for %d cells, the curve holding %d of them (%d in all)" % [traced.size(), region.size(), shared, back.size()])


## Level lays "waters" and "roads" from their curves (decision 559): the
## cells the layout lacks made water and said, a stream's path from its
## middle, a pond's cells inside it, a road's ground its kind.
func _test_curves_laid() -> void:
	print("== waters and roads laid from curves ==")
	var size := Vector2i(24, 16)
	var rows: Array[String] = []
	for y in 2 * size.y - 1:
		rows.append(".".repeat(2 * size.x - 1))
	var markers := {}
	for y in size.y:
		for x in size.x:
			markers[Vector2i(x, y)] = "grass"
	markers[Vector2i(1, 14)] = "start"
	var field := PackedFloat32Array()
	for y in size.y:
		for x in size.x:
			field.append(4.0 - 0.1 * x)
	var config := {"outdoor": true,
		"waters": [{"points": [[0, 4, 2], [8, 2, 2.5], [16, 6, 2], [23, 4, 2]]}, {"points": [[4, 9], [10, 9, 0], [10, 13, 0], [4, 13, 0]], "closed": true},
			{"points": [[14, 9, 0], [20, 9, 0], [20, 13, 0]], "closed": true}],
		"roads": [{"points": [[0, 7, 1.5], [23, 8, 1.5]], "kind": "stone"}]}
	var level := Level.parse(Level.image_from_rows(rows, markers), null, config, Relief.image(field, size))
	var terrain: Dictionary = level["terrain"]
	var warned: Array = level["warnings"]
	_check(warned.any(func(w: String) -> bool: return w.begins_with("waters 1 has a point")) and terrain["waters"].size() == 2,
		"a point not [x, y, width] leaves its water out, said (%s)" % [warned])
	var river: Dictionary = terrain["waters"][0]
	var wet := {}
	for cell: Vector2i in terrain["water"]:
		wet[cell] = true
	var raster := Curves.cells(river["curve"], false)
	_check(raster.keys().all(func(cell: Vector2i) -> bool: return wet.has(cell) or not Rect2i(Vector2i.ZERO, size).has_point(cell)) and not terrain["floor"].has(Vector2i(8, 2)),
		"the river's cells are water, out of the floor (%d)" % raster.size())
	_check(warned.any(func(w: String) -> bool: return w.begins_with("water 0's curve covers")), "the cells the layout had dry are said")
	var streams: Array = terrain["streams"]
	_check(streams.size() == 1 and streams[0]["path"][0] == Vector2i(0, 4) and streams[0]["path"][-1] == Vector2i(23, 4),
		"its \"streams\" path from its middle, source to mouth (%s)" % [streams])
	var pond: Dictionary = terrain["waters"][1]
	_check(pond["closed"] and wet.has(Vector2i(17, 10)) and not wet.has(Vector2i(13, 10)), "the pond's cells, inside its curve, are water")
	_check(terrain["kinds"].get(Vector2i(5, 7), "") == "stone" and terrain["kinds"].get(Vector2i(5, 11), "") == "grass", "the road's ground is stone, beside it grass")


## A river laid along a meander (decision 559): its middle one step at a
## time, its water never rising, swinging well off its line and back, about
## its width wide, the same for the same seed.
func _test_river() -> void:
	print("== Relief.lay rivers ==")
	var size := Vector2i(40, 60)
	var map := LevelMap.new(size)
	for y in size.y:
		for x in size.x:
			map.set_cell(Vector2i(x, y), "grass")
	var options := {"base": 6.0, "amplitude": 0.5, "streams": 0, "valleys": [[Vector2i(20, 0), Vector2i(20, 59)]],
		"valley_depth": 2.0, "valley_floor": 12.0, "valley_fall": 3.0, "valley_width": 18.0,
		"rivers": [{"line": [Vector2i(20, 0), Vector2i(20, 59)], "wavelength": 20.0, "amplitude": 7.0, "width": [1.5, 3.0]}]}
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, size), 7, options)
	_check(laid["streams"].size() == 1 and laid["waters"].size() == 1, "one river, its curve in waters, its middle in streams")
	if laid["streams"].size() != 1 or laid["waters"].size() != 1:
		return
	var water: Dictionary = laid["waters"][0]
	var curve := Curves.sample(water["points"], water["widths"])
	var raster := Curves.cells(curve, false)
	var made: Array = laid["cells"].keys().filter(func(at: Vector2i) -> bool: return laid["cells"][at] == "water")
	_check(made.all(func(at: Vector2i) -> bool: return raster.has(at)) and raster.keys().all(func(at: Vector2i) -> bool: return laid["cells"].get(at, "") == "water" or not map.walkable(at)),
		"its water is its curve's raster, as Level lays it on load (%d cells)" % made.size())
	var widths: PackedFloat32Array = water["widths"]
	var thinnest := Array(widths).min() as float
	var widest := Array(widths).max() as float
	_check(thinnest >= 1.5 and widest <= 3.0 and widest - thinnest > 0.6, "its width varies along it (%.2f to %.2f)" % [thinnest, widest])
	var path: Array[Vector2i] = laid["streams"][0]
	var steps_ok := true
	var falls := true
	var spread := Vector2i(1 << 30, -(1 << 30))
	for i in path.size():
		steps_ok = steps_ok and laid["cells"].get(path[i], "") == "water"
		spread = Vector2i(mini(spread.x, path[i].x), maxi(spread.y, path[i].x))
		if i > 0:
			var step := path[i] - path[i - 1]
			steps_ok = steps_ok and absi(step.x) + absi(step.y) == 1
			falls = falls and laid["relief"][path[i]] <= laid["relief"][path[i - 1]] + 0.0001
	_check(path[0].y == 0 and path[-1].y == size.y - 1 and steps_ok, "its middle runs source to mouth, water, a side step at a time (%d cells, %s to %s, steps %s)" % [path.size(), path[0], path[-1], steps_ok])
	_check(falls, "its water never rises downstream")
	_check(spread.x <= 14 and spread.y >= 26, "it swings about 7 cells either way of its line (columns %d to %d)" % [spread.x, spread.y])
	_check(made.size() > path.size() * 1.3 and made.size() < path.size() * 3.2, "about its width wide (%d cells of water, %d in its middle)" % [made.size(), path.size()])
	var again := Relief.lay(map, Rect2i(Vector2i.ZERO, size), 7, options)
	_check(again["streams"][0] == path, "the same seed lays the same river")
	var other := Relief.lay(map, Rect2i(Vector2i.ZERO, size), 8, options)
	_check(other["streams"][0] != path, "another seed, other loops")


## A road laid as a curve (decision 563): from its start to its end over
## the bridge (water crossed nowhere else), its cells on walkable ground with
## no cliff between them, round (no sharp turn); none where no way is.
func _test_road() -> void:
	print("== Relief.road ==")
	var size := Vector2i(40, 30)
	var map := LevelMap.new(size)
	for y in size.y:
		for x in size.x:
			map.set_cell(Vector2i(x, y), "water" if x in [19, 20] else "grass")
			map.set_relief(Vector2i(x, y), 2.0 + (1.5 if x > 30 and y < 8 else 0.0))
	var crossings := {Vector2i(19, 22): true, Vector2i(20, 22): true}
	var laid := Relief.road(map, Vector2i(3, 4), [], Vector2i(36, 26), 2.0, crossings)
	_check(not laid.is_empty(), "a road from (3, 4) to (36, 26) over the bridge")
	if laid.is_empty():
		return
	var cells: Dictionary = laid["cells"]
	var on_ground := true
	var cliff := false
	for cell: Vector2i in cells:
		on_ground = on_ground and (map.walkable(cell) or crossings.has(cell))
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if cells.has(cell + step) and Relief.cliff_between(map.relief_at(cell), map.relief_at(cell + step)):
				cliff = true
	var wet_crossed := cells.keys().filter(func(cell: Vector2i) -> bool: return map.cell(cell) == "water")
	_check(on_ground and not cliff and wet_crossed.all(func(cell: Vector2i) -> bool: return crossings.has(cell)) and not wet_crossed.is_empty(),
		"its cells on the ground, the water crossed only on the bridge (%s), no cliff between them" % [wet_crossed])
	var points: PackedVector2Array = laid["points"]
	_check(points[0] == Vector2(3, 4) and points[-1] == Vector2(36, 26), "from its start to its end (%s to %s)" % [points[0], points[-1]])
	var curve := Curves.sample(points, laid["widths"])
	var tangents: PackedVector2Array = curve["tangents"]
	var sharpest := 0.0
	for i in range(1, tangents.size()):
		sharpest = maxf(sharpest, absf(tangents[i].angle_to(tangents[i - 1])))
	_check(sharpest < 0.35, "round: no turn over 0.35 rad a quarter cell (%.3f)" % sharpest)
	_check(Relief.road(map, Vector2i(3, 4), [], Vector2i(36, 26), 2.0, {}).is_empty(), "no bridge, no way over: none")


func _test_escarpment() -> void:
	print("== Relief.lay escarpments ==")
	var size := Vector2i(40, 50)
	var map := LevelMap.new(size)
	for y in size.y:
		for x in size.x:
			map.set_cell(Vector2i(x, y), "grass")
	var options := {"base": 4.0, "amplitude": 0.0, "streams": 0,
		"escarpments": [{"line": [Vector2i(20, 1), Vector2i(20, 48)], "face": "east", "height": 3.0, "back": 15.0, "ways": [0.5]}]}
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, size), 5, options)
	for at: Vector2i in laid["relief"]:
		map.set_relief(at, laid["relief"][at])
	var drop := func(y: int) -> float: return map.relief_at(Vector2i(20, y)) - map.relief_at(Vector2i(21, y))
	# Its way's ramp fans out along the foot, so the face is lower near it.
	_check(drop.call(11) > 2.5 and drop.call(38) > 2.5, "a face of about its height down the line (%.2f, %.2f)" % [drop.call(11), drop.call(38)])
	_check(laid["faces"].has(Terrain.edge_key(Vector2i(20, 11), Vector2i(1, 0))), "its edges are returned as faces")
	_check(not Relief.cliff_between(map.relief_at(Vector2i(20, 24)), map.relief_at(Vector2i(21, 24)))
		and not Relief.cliff_between(map.relief_at(Vector2i(20, 2)), map.relief_at(Vector2i(21, 2))),
		"walked across at its way and its tapered end (%.2f, %.2f)" % [drop.call(24), drop.call(2)])
	_check(map.relief_at(Vector2i(20, 8)) - map.relief_at(Vector2i(6, 8)) > 2.0, "its back rises to the line (%.2f to %.2f)" % [map.relief_at(Vector2i(6, 8)), map.relief_at(Vector2i(20, 8))])
	var stray := 0
	for at: Vector2i in map.cells:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if map.cells.has(at + step) and Relief.cliff_between(map.relief_at(at), map.relief_at(at + step)) 					and not laid["faces"].has(Terrain.edge_key(at, step)):
				stray += 1
	_check(stray == 0, "no cliff but on its face (%d others)" % stray)
	var floor := {}
	for at: Vector2i in map.cells:
		floor[at] = true
	var area := {"relief": map.relief, "relief_size": size, "stairs": {}, "heights": {}, "edges": {}, "floor": floor, "size": size}
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	field.fill(-1.0)
	WorldRoutes._flood(area, Vector2i(30, 8), {}, field)
	_check(not field.has(-1.0), "every cell is walked to from below the face (%d not)" % field.count(-1.0))


func _test_hills() -> void:
	print("== levels/hills ==")
	var level := Level.load_level("hills")
	var terrain: Dictionary = level["terrain"]
	_check(terrain["relief_given"] and level["warnings"].is_empty(), "relief.png, nothing said (%s)" % [level["warnings"]])
	var field := Level.walk_relief(terrain)
	var size: Vector2i = terrain["relief_size"]
	var floor: Dictionary = {}
	for cell: Vector2i in terrain["floor"]:
		floor[cell] = true
	var wet: Dictionary = {}
	for cell: Vector2i in terrain["water"]:
		wet[cell] = true
	var off_face := 0
	var face := 0
	for cell: Vector2i in floor:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if floor.has(cell + step) and Relief.cliff_between(Relief.at(field, size, cell), Relief.at(field, size, cell + step)):
				if step == Vector2i(1, 0) and cell.x == 61 and cell.y < 46:
					face += 1
				else:
					off_face += 1
	_check(face >= 30 and off_face >= 60, "the plateau's west face and the escarpments' (%d and %d edges)" % [face, off_face])
	var west := []
	for y in range(8, 30):
		for x in range(20, 40):
			var drop := Relief.at(field, size, Vector2i(x, y)) - Relief.at(field, size, Vector2i(x + 1, y))
			if floor.has(Vector2i(x, y)) and floor.has(Vector2i(x + 1, y)) and drop > Relief.WALK_RISE:
				west.append(drop)
	west.sort()
	_check(west.size() >= 15 and west[west.size() / 2] > 2.5, "the west escarpment's face is about 3 m (%d edges, median %.2f)" % [west.size(), west[west.size() / 2] if not west.is_empty() else 0.0])
	var lowest := INF
	var highest := -INF
	for cell: Vector2i in floor:
		lowest = minf(lowest, Relief.at(field, size, cell))
		highest = maxf(highest, Relief.at(field, size, cell))
	_check(_corners_agree(terrain).is_empty(), "walkably joined cells agree on every corner they share (%s)" % [_corners_agree(terrain)])
	_check(highest - lowest > 8.0, "hills and valleys: %.1f m between the lowest and the highest" % (highest - lowest))
	var kinds := {}
	for cell: Vector2i in terrain["kinds"]:
		# A ford's footing is the ground beside it, stone mid-river (559).
		if not terrain["fords"].has(cell):
			kinds[terrain["kinds"][cell]] = int(kinds.get(terrain["kinds"][cell], 0)) + 1
	_check(kinds.get("stone", 0) == 0 and kinds.get("grass", 0) > 3000 and kinds.get("dirt", 0) > 500,
		"its ground by slope: grass, bare dirt on the steep bands, crests and banks, no stone (paving) on its slopes (%s)" % [kinds])
	var course: Array = terrain["streams"][0]["path"]
	var columns := course.map(func(cell: Vector2i) -> int: return cell.x)
	_check(course.size() > 120 and columns.max() - columns.min() >= 16,
		"the river loops down the valley's length (%d cells, columns %d to %d; 559)" % [course.size(), columns.min(), columns.max()])
	_check(terrain["streams"].size() == 2 and not terrain["fords"].is_empty() and level["buildings"].any(func(b: Dictionary) -> bool: return b["slot"] == "bridge"),
		"its river and the fall's stream, a ford and a bridge")
	# The fall (570): the stream off the plateau drops its face's height
	# between two cells of its path, into a 3 x 3 pool.
	var fall_path: Array = terrain["streams"][1]["path"] if terrain["streams"].size() == 2 else []
	var fall := Vector2i(-1, -1)
	var drop := 0.0
	for i in range(1, fall_path.size()):
		var here := Relief.at(field, size, fall_path[i - 1]) - Relief.at(field, size, fall_path[i])
		if here > drop:
			drop = here
			fall = fall_path[i]
	# Its pool: the water at its foot's level within 2.5 cells, wider than the stream.
	var landing := Relief.at(field, size, fall)
	var pool := 0
	for y in range(-3, 4):
		for x in range(-3, 4):
			var at := fall + Vector2i(x, y)
			if wet.has(at) and Vector2(x, y).length() <= 2.5 and absf(Relief.at(field, size, at) - landing) < 0.5:
				pool += 1
	_check(drop > 5.0 and pool >= 7, "a fall off the plateau's cliff, %.1f m, into a pool at %s (%d cells at its level; 570)" % [drop, fall, pool])
	var area := {"relief": field, "relief_size": size, "stairs": terrain["stairs"], "heights": {}, "edges": terrain["edges"], "floor": floor, "size": size}
	var reached := PackedFloat32Array()
	reached.resize(size.x * size.y)
	reached.fill(-1.0)
	WorldRoutes._flood(area, level["spawn_points"]["from_wilds"], {}, reached)
	var unreached := floor.keys().filter(func(cell: Vector2i) -> bool: return reached[cell.y * size.x + cell.x] < 0.0)
	_check(unreached.is_empty(), "every floor cell is walked to from the link (%d not: %s)" % [unreached.size(), unreached.slice(0, 5)])
	var roads: Array = terrain["roads"]
	var road_cells := Curves.cells(roads[0]["curve"], false) if roads.size() == 1 else {} as Dictionary[Vector2i, int]
	var road_points: PackedVector2Array = roads[0]["points"] if roads.size() == 1 else PackedVector2Array()
	var bridge_cell: Vector2i = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "bridge")[0]["rect"].position
	_check(roads.size() == 1 and roads[0]["kind"] == "dirt" and road_cells.has(bridge_cell) and road_points[-1].x < 20.0
		and road_cells.keys().all(func(cell: Vector2i) -> bool: return terrain["kinds"].get(cell, "dirt") == "dirt"),
		"a dirt road from the link over the bridge and up through the west way (563; %d cells)" % road_cells.size())
	var top := Vector2i(80, 20)
	var steps := WorldRoutes._steps_between(area, level["spawn_points"]["from_wilds"], top)
	_check(floor.has(top) and steps > 0.0, "the plateau's top is walked to from the link, round by its spur (%.0f steps)" % steps)
	var foot := Vector2i(58, 30)
	_check(floor.has(foot) and Relief.at(field, size, top) - Relief.at(field, size, foot) > 4.0, "it stands over the valley at its face")


## levels/wilds' relief (decision 565): given, nothing said; the ridge's
## face about its height; every floor cell walked to from the castle's
## link on flat ground walked to still (the face cuts nothing off); every link, spawn
## point and start on level ground (its pad), so a saved spot or an arrival
## is never on a slope or a face.
func _test_wilds() -> void:
	print("== levels/wilds ==")
	var level := Level.load_level("wilds")
	var terrain: Dictionary = level["terrain"]
	_check(terrain["relief_given"] and level["warnings"].is_empty(), "relief.png, nothing said (%s)" % [level["warnings"]])
	var field := Level.walk_relief(terrain)
	var size: Vector2i = terrain["relief_size"]
	var floor: Dictionary = {}
	for cell: Vector2i in terrain["floor"]:
		floor[cell] = true
	var drops := []
	for cell: Vector2i in floor:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if floor.has(cell + step) and Relief.cliff_between(Relief.at(field, size, cell), Relief.at(field, size, cell + step)):
				drops.append(absf(Relief.at(field, size, cell) - Relief.at(field, size, cell + step)))
	drops.sort()
	_check(drops.size() >= 60 and drops[drops.size() / 2] > 2.5, "the ridge's face, about 3.5 m (%d edges, median %.2f)" % [drops.size(), drops[drops.size() / 2] if not drops.is_empty() else 0.0])
	var area := {"relief": field, "relief_size": size, "stairs": terrain["stairs"], "heights": {}, "edges": terrain["edges"], "floor": floor, "size": size}
	var reached := PackedFloat32Array()
	reached.resize(size.x * size.y)
	reached.fill(-1.0)
	WorldRoutes._flood(area, level["spawn_points"]["from_castle"], {}, reached)
	var unreached := floor.keys().filter(func(cell: Vector2i) -> bool: return reached[cell.y * size.x + cell.x] < 0.0)
	# The layout's own islands (cells the forest closes in) are as they were.
	var flat := area.duplicate()
	var level_ground := PackedFloat32Array()
	level_ground.resize(field.size())
	flat["relief"] = level_ground
	var reached_flat := PackedFloat32Array()
	reached_flat.resize(size.x * size.y)
	reached_flat.fill(-1.0)
	WorldRoutes._flood(flat, level["spawn_points"]["from_castle"], {}, reached_flat)
	var cut_off := unreached.filter(func(cell: Vector2i) -> bool: return reached_flat[cell.y * size.x + cell.x] >= 0.0)
	_check(cut_off.is_empty(), "the relief cuts nothing off: every floor cell walked to on flat ground still is (%d not: %s)" % [cut_off.size(), cut_off.slice(0, 5)])
	var spots: Array[Vector2i] = []
	for link: Dictionary in level["links"]:
		spots.append(link["tile"])
	for at: Vector2i in level["spawn_points"].values():
		spots.append(at)
	for at: Vector2i in level["starts"]:
		spots.append(at)
	var tilted := spots.filter(func(at: Vector2i) -> bool:
		var here := Relief.at(field, size, at)
		for step in Relief.FOUR:
			if floor.has(at + step) and absf(Relief.at(field, size, at + step) - here) > Relief.PAD_FLAT:
				return true
		return false)
	_check(tilted.is_empty(), "every link, spawn point and start stands on level ground (%d spots; tilted: %s)" % [spots.size(), tilted])
	# The marks (567): each solid through, no door, in open ground; the
	# stones' ring walked into between them.
	var marks := {}
	var solid: Dictionary = {}
	for cell: Vector2i in terrain.get("solid", []):
		solid[cell] = true
	var through := true
	for building: Dictionary in level["buildings"]:
		var slot := str(building["slot"])
		if slot in Level.DOORLESS:
			marks[slot] = int(marks.get(slot, 0)) + 1
			through = through and not building.has("door") and Level.rect_cells(building["rect"]).all(func(cell: Vector2i) -> bool: return solid.has(cell) and not floor.has(cell))
	_check(marks == {"building.great_tree": 1, "building.cairn": 1, "building.waystone": 1, "building.standing_stone": 8} and through,
		"the marks: a great tree, a cairn, a waystone, a ring of 8 standing stones, each solid through, no door (567; %s)" % [marks])
	var stones: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.standing_stone")
	var ring_middle := Vector2i.ZERO
	for stone: Dictionary in stones:
		ring_middle += (stone["rect"] as Rect2i).position
	ring_middle /= maxi(1, stones.size())
	_check(floor.has(ring_middle) and reached[ring_middle.y * size.x + ring_middle.x] >= 0.0, "the ring's middle %s is walked to, between the stones" % ring_middle)
	# The water (568): a river the wilds' length, crossed by a ford and a
	# bridge (both walked over), the ponds closed curves; still nothing cut off.
	var waters: Array = terrain["waters"]
	var open_waters := waters.filter(func(w: Dictionary) -> bool: return not w["closed"])
	var ponds := waters.filter(func(w: Dictionary) -> bool: return w["closed"])
	var course: Array = terrain["streams"][0]["path"] if not terrain["streams"].is_empty() else []
	_check(open_waters.size() == 1 and ponds.size() == 3 and course.size() > 200,
		"a river down the valley (%d cells in its middle) and three ponds as curves (568)" % course.size())
	var bridged: Array = terrain.get("bridged", [])
	_check(not terrain["fords"].is_empty() and not bridged.is_empty()
		and terrain["fords"].all(func(cell: Vector2i) -> bool: return reached[cell.y * size.x + cell.x] >= 0.0)
		and bridged.all(func(cell: Vector2i) -> bool: return reached[cell.y * size.x + cell.x] >= 0.0),
		"crossed by a ford (%d cells) and a bridge (%d), both walked to" % [terrain["fords"].size(), bridged.size()])
	# The roads (569): from the castle's, the hills' and the forest's links to
	# the waystone, the hills road over the bridge, their ground dirt.
	var roads: Array = terrain["roads"]
	var starts_at := roads.map(func(road: Dictionary) -> Vector2i: return Vector2i((road["points"] as PackedVector2Array)[0]))
	var over_bridge := roads.any(func(road: Dictionary) -> bool:
		var cells := Curves.cells(road["curve"], false)
		return bridged.all(func(cell: Vector2i) -> bool: return cells.has(cell)))
	var dirt := roads.all(func(road: Dictionary) -> bool:
		return Curves.cells(road["curve"], false).keys().all(func(cell: Vector2i) -> bool:
			return not floor.has(cell) or terrain["kinds"].get(cell, "") == "dirt"))
	_check(roads.size() == 3 and starts_at.has(level["spawn_points"]["from_castle"]) and starts_at.has(level["spawn_points"]["from_hills"])
		and starts_at.has(level["spawn_points"]["from_forest"]) and over_bridge and dirt,
		"three dirt roads from the castle's, the hills' and the forest's links, the hills road over the bridge (569; from %s)" % [starts_at])


## A bridge's deck kept out of the relief (505 amended): under each of the
## hills' and the wilds' bridges the relief is the water's, the walked relief
## the deck's (its banks' height), and a walk from bank to bank goes
## straight over it, as before.
func _test_bridge_decks() -> void:
	print("== bridge decks ==")
	for name: String in ["hills", "wilds"]:
		var level := Level.load_level(name)
		var terrain: Dictionary = level["terrain"]
		var size: Vector2i = terrain["relief_size"]
		var walked := Level.walk_relief(terrain)
		var bridge: Dictionary = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == Level.BRIDGE)[0]
		var cells := Level.rect_cells(bridge["rect"])
		var under := cells.all(func(cell: Vector2i) -> bool:
			return Relief.at(terrain["relief"], size, cell) < float(bridge["elevation"]) - 0.1 and is_equal_approx(Relief.at(walked, size, cell), float(bridge["elevation"])))
		var floor: Dictionary = {}
		for cell: Vector2i in terrain["floor"]:
			floor[cell] = true
		var area := {"relief": walked, "relief_size": size, "stairs": terrain["stairs"], "heights": {}, "edges": terrain["edges"], "floor": floor, "size": size}
		var banks: Array = bridge["banks"]
		var steps := WorldRoutes._steps_between(area, banks[0], banks[1])
		var straight := float(cells.size() + 1)
		_check(under and steps > 0.0 and steps < straight + 1.5,
			"%s: the relief under the bridge is the water's, the walked one its deck's; bank to bank %.1f steps (straight over: %.0f)" % [name, steps, straight])


## The first few pairs of orthogonal neighbours of [param terrain]'s
## relief, no cliff between them, whose shared corners differ (the view
## would draw a face between them); [] if none.
static func _corners_agree(terrain: Dictionary) -> Array:
	var field := Level.walk_relief(terrain)
	var size: Vector2i = terrain["relief_size"]
	var out := []
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var mine := Relief.corner_heights(field, size, cell)
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var next := cell + step
				if not Relief.on_map(size, next) or Relief.cliff_between(Relief.at(field, size, cell), Relief.at(field, size, next)):
					continue
				var theirs := Relief.corner_heights(field, size, next)
				# East: my (1, 0), (1, 1) are its (0, 0), (0, 1); south: my (0, 1), (1, 1) its (0, 0), (1, 0).
				var pairs := [[1, 0], [3, 2]] if step.x == 1 else [[2, 0], [3, 1]]
				for pair: Array in pairs:
					if absf(mine[pair[0]] - theirs[pair[1]]) > 0.0001 and out.size() < 4:
						out.append([cell, next, mine[pair[0]], theirs[pair[1]]])
	return out


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
