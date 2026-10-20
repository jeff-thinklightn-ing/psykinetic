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
	_test_hills()
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


func _test_hills() -> void:
	print("== levels/hills ==")
	var level := Level.load_level("hills")
	var terrain: Dictionary = level["terrain"]
	_check(terrain["relief_given"] and level["warnings"].is_empty(), "relief.png, nothing said (%s)" % [level["warnings"]])
	var field: PackedFloat32Array = terrain["relief"]
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
	_check(face >= 30 and off_face == 0, "one cliff, the plateau's west face (%d edges; %d elsewhere)" % [face, off_face])
	var lowest := INF
	var highest := -INF
	for cell: Vector2i in floor:
		lowest = minf(lowest, Relief.at(field, size, cell))
		highest = maxf(highest, Relief.at(field, size, cell))
	_check(_corners_agree(terrain).is_empty(), "walkably joined cells agree on every corner they share (%s)" % [_corners_agree(terrain)])
	_check(highest - lowest > 8.0, "hills and valleys: %.1f m between the lowest and the highest" % (highest - lowest))
	var kinds := {}
	for cell: Vector2i in terrain["kinds"]:
		kinds[terrain["kinds"][cell]] = int(kinds.get(terrain["kinds"][cell], 0)) + 1
	_check(kinds.get("stone", 0) > 500 and kinds.get("grass", 0) > 1000 and kinds.get("dirt", 0) > 200, "its ground by slope: rock, grass and bare dirt (%s)" % [kinds])
	_check(terrain["streams"][0]["path"].size() > 60, "the stream runs the valley's length (%d cells)" % terrain["streams"][0]["path"].size())
	_check(terrain["streams"].size() == 1 and not terrain["fords"].is_empty() and level["buildings"].any(func(b: Dictionary) -> bool: return b["slot"] == "bridge"),
		"its stream, a ford and a bridge")
	var area := {"relief": field, "relief_size": size, "stairs": terrain["stairs"], "heights": {}, "edges": terrain["edges"], "floor": floor, "size": size}
	var top := Vector2i(80, 20)
	var steps := WorldRoutes._steps_between(area, level["spawn_points"]["from_wilds"], top)
	_check(floor.has(top) and steps > 0.0, "the plateau's top is walked to from the link, round by its spur (%.0f steps)" % steps)
	var foot := Vector2i(58, 20)
	_check(floor.has(foot) and Relief.at(field, size, top) - Relief.at(field, size, foot) > 4.0, "it stands over the valley at its face")


## The first few pairs of orthogonal neighbours of [param terrain]'s
## relief, no cliff between them, whose shared corners differ (the view
## would draw a face between them); [] if none.
static func _corners_agree(terrain: Dictionary) -> Array:
	var field: PackedFloat32Array = terrain["relief"]
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
