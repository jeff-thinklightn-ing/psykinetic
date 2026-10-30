extends Node
## The minimap (decision 321): its picture is the zone's Level data (ground
## from the palette, water, walls darkening the cells either side, nothing
## where there is no floor), the start cells, ways out and places it marks,
## and its views: a corner map that never shows past the zone's edge, and
## the big map's zoom steps round you. It draws again only when what it
## shows changes (decision 482): you moving or turning, a mark, the big map
## opened or zoomed, a rebuild; not every frame. Run it with tests/run.ps1
## or run.sh.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_picture()
	_test_views()
	await _test_redraws()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_picture() -> void:
	print("== the picture is the zone's Level data ==")
	# Three cells by three: a wall between (0, 0) and (1, 0); water at (2, 1);
	# a start at (0, 1); a link at (1, 2) to test_room; (2, 2) no floor; a
	# hidden link at (0, 2) (608), which the map must not give away.
	var rows: Array[String] = [".#...", ".....", ".....", ".....", "....."]
	var image := Level.image_from_rows(rows, {Vector2i(2, 1): "water", Vector2i(0, 1): "start", Vector2i(1, 2): "link", Vector2i(0, 2): "link"})
	image.set_pixel(4, 4, Color(0, 0, 0, 0))
	Level.register("mm_room", image, null, {"name": "The Little Room",
		"links": [{"at": [1, 2], "to_map": "test_room"}, {"at": [0, 2], "to_map": "test_room", "to_spawn": "", "hidden": true}],
		"places": {"well": {"at": [2, 0], "kind": "other", "name": "the well"}}})
	var level := Level.load_level("mm_room")
	var map := Minimap.new()
	add_child(map)
	map.rebuild(level)
	var kinds: Dictionary = level["terrain"]["kinds"]
	var plain := Minimap.ground_colour(str(kinds.get(Vector2i(2, 0), "stone")))
	_check(map.image.get_size() == Vector2i(3, 3), "one pixel a cell (%s)" % map.image.get_size())
	_check(map.image.get_pixel(2, 0).is_equal_approx(plain), "open ground is its kind's palette swatch, the zone's border left to the frame (%s)" % plain)
	_check(map.image.get_pixel(0, 0).v < plain.v and map.image.get_pixel(1, 0).v < plain.v,
		"a wall darkens the cells either side of it")
	_check(map.image.get_pixel(2, 1).is_equal_approx(Minimap.WATER), "water is water's blue")
	_check(map.image.get_pixel(2, 2).a == 0.0, "where there is no floor nothing is drawn")
	_check(map.title == "The Little Room", "the big map's title is the zone's name (%s)" % map.title)
	_check(map.starts.has(Vector2i(0, 1)), "it marks the start cells (%s)" % [map.starts])
	_check(map.ways_out.any(func(way: Dictionary) -> bool: return way["cell"] == Vector2i(1, 2) and way["label"] == "test_room"),
		"and the ways out, named for where they go (%s)" % [map.ways_out])
	_check(level["links"].size() == 2 and map.ways_out.size() == 1 and not map.ways_out.any(func(way: Dictionary) -> bool: return way["cell"] == Vector2i(0, 2)),
		"a hidden link is no way out on the map: not marked, not named (589 amended; %s)" % [map.ways_out])
	_check(map.ways_out.all(func(way: Dictionary) -> bool: return (way["cue"] in Level.CUES or way["cue"] == "edge") and way["facing"] is Vector2i),
		"each way out carries its built cue and the way it faces (589, ui's side)")
	_check(Minimap.label_of("sealed", "barrow_deep") == "a sealed way" and Minimap.label_of("arch", "castle") == "to castle",
		"a sealed way's words name no destination; the rest say where they go")
	_check(map.places.any(func(place: Dictionary) -> bool: return place["name"] == "the well"), "and the zone's places")
	var wilds := Level.load_level("wilds")
	var started := Time.get_ticks_usec()
	map.rebuild(wilds)
	print("    the wilds (%s cells) drawn in %.1f ms" % [wilds["size"], (Time.get_ticks_usec() - started) / 1000.0])
	_check(map.image.get_size() == Vector2i(wilds["size"]) and map.places.any(func(place: Dictionary) -> bool: return place["kind"] == "stockpile")
		and map.ways_out.any(func(way: Dictionary) -> bool: return way["label"] == "foothills"),
		"the wilds: the town's store and the way north (to the foothills since 745) are on it")
	var castle_ways := map.ways_out.filter(func(way: Dictionary) -> bool: return way["label"] == "foothills")
	_check(castle_ways.size() == 1 and castle_ways[0]["cue"] == "arch" and castle_ways[0]["facing"] == Vector2i(0, -1),
		"the wilds' north link (the castle's till 745, the foothills' since) is an arch facing north on the big map (589; %s)" % [castle_ways])
	map.queue_free()


func _test_views() -> void:
	print("== the views ==")
	var rows: Array[String] = []
	for y in 2 * 150 - 1:
		rows.append(".".repeat(2 * 200 - 1))
	Level.register("mm_field", Level.image_from_rows(rows), null, {"neighbours": {"east": "test_room"}})
	var map := Minimap.new()
	add_child(map)
	map.rebuild(Level.load_level("mm_field"))
	var area := Rect2(Vector2.ZERO, Vector2(200, 150))
	_check(map.ways_out.any(func(way: Dictionary) -> bool: return way["cell"] == Vector2i(199, 75) and way["label"] == "test_room"),
		"a neighbour is marked at the middle of its side")
	var corner := map.view(Vector2(100, 75))
	var ui := map.ui_scale()
	_check((corner["source"] as Rect2).is_equal_approx(Rect2(20, 0, 160, 150)) and is_equal_approx(float(corner["scale"]), ui),
		"the corner map shows a cell a pixel (at 1080 lines) round you (%s, scale %s, screen x%s)" % [corner["source"], corner["scale"], ui])
	var at_edge := map.view(Vector2(198, 1))
	_check((at_edge["source"] as Rect2).end.x == 200.0 and at_edge["source"].position.y == 0.0,
		"near the zone's edge it stops at the edge, nothing past it (%s)" % at_edge["source"])
	map.rebuild(Level.load_level("mm_room"))
	var small := map.view(Vector2(1, 1))
	_check((small["source"] as Rect2).is_equal_approx(Rect2(0, 0, 3, 3)) and float(small["scale"]) > 1.0,
		"a small zone fills the corner, scaled up (scale %s)" % small["scale"])
	map.rebuild(Level.load_level("mm_field"))
	var dest: Rect2 = at_edge["dest"]
	var screen := map.get_viewport_rect().size
	_check(dest.end.x <= screen.x and is_equal_approx(dest.position.y, Minimap.CORNER_TOP * ui) and dest.position.x > screen.x / 2.0,
		"it sits top right, below the compass (%s)" % dest)
	var middle := Minimap.to_screen(Vector2(198, 1), at_edge)
	_check(dest.has_point(middle), "a cell maps into the map (%s)" % middle)
	_check(not map.big, "the big map starts closed")
	map.toggle()
	var big := map.view(Vector2(100, 75))
	_check(map.big and (big["source"] as Rect2).is_equal_approx(area), "M opens the big map: the whole zone (%s)" % big["source"])
	map.zoom(1)
	var nearer := map.view(Vector2(198, 148))
	_check(map.zoom_step == 1 and (nearer["source"] as Rect2).size.x < 200.0 and area.encloses(nearer["source"]),
		"a zoom step shows less of it, still inside the zone (%s)" % nearer["source"])
	map.zoom(5)
	_check(map.zoom_step == Minimap.ZOOMS.size() - 1, "zoom stops at its last step")
	map.zoom(-9)
	map.toggle()
	_check(not map.big and map.zoom_step == 0, "and back out, and closed")
	map.queue_free()


func _test_redraws() -> void:
	print("== drawn again only when what it shows changes (decision 482) ==")
	var rows: Array[String] = []
	for y in 2 * 20 - 1:
		rows.append(".".repeat(2 * 20 - 1))
	Level.register("mm_redraw", Level.image_from_rows(rows), null, {})
	var you := {"cell": Vector2(5, 5), "kind": "you", "facing": Vector2(0, -1)}
	var map := Minimap.new()
	map.marks = func() -> Array: return [you.duplicate(), {"cell": Vector2(8, 8), "kind": "door"}]
	add_child(map)
	map.rebuild(Level.load_level("mm_redraw"))
	await _frames(3)
	var drawn := map.draws
	_check(drawn > 0, "drawn once it has its picture (%d)" % drawn)
	await _frames(10)
	_check(map.draws == drawn, "ten frames with nothing changed: not drawn again (%d)" % (map.draws - drawn))
	you["cell"] = Vector2(6, 5)
	await _frames(2)
	_check(map.draws == drawn + 1, "you step: drawn again, once (%d)" % (map.draws - drawn))
	you["facing"] = Vector2(1, 0)
	await _frames(2)
	_check(map.draws == drawn + 2, "you turn: drawn again (%d)" % (map.draws - drawn))
	map.toggle()
	await _frames(2)
	_check(map.draws == drawn + 3, "the big map opened: drawn again (%d)" % (map.draws - drawn))
	map.zoom(1)
	await _frames(2)
	_check(map.draws == drawn + 4, "zoomed: drawn again (%d)" % (map.draws - drawn))
	map.rebuild(Level.load_level("mm_redraw"))
	await _frames(2)
	_check(map.draws == drawn + 5, "rebuilt: drawn again (%d)" % (map.draws - drawn))
	map.visible = false
	you["cell"] = Vector2(7, 5)
	await _frames(2)
	_check(map.draws == drawn + 5, "hidden: not drawn (%d)" % (map.draws - drawn))
	map.queue_free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
