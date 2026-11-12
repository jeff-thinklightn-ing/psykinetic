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
	var plain := Minimap.ground_colour(str(kinds.get(Vector2i(2, 0), "stone")), true)
	_check(map.image.get_size() == Vector2i(3, 3), "one pixel a cell (%s)" % map.image.get_size())
	var open_cell := map.image.get_pixel(2, 0)
	_check(open_cell.v >= plain.darkened(Minimap.RELIEF).v - 0.01 and open_cell.v <= plain.lightened(Minimap.RELIEF).v + 0.01
		and absf(open_cell.h - plain.h) < 0.02 and open_cell.a == 1.0,
		"open ground is its kind's map colour, shaded at most RELIEF by height (indoors, stone is the floors' stone), the zone's border left to the frame (%s, %s)" % [plain, open_cell])
	_check(map.image.get_pixel(0, 0).v < plain.v and map.image.get_pixel(1, 0).v < plain.v,
		"a wall darkens the cells either side of it")
	_check(map.image.get_pixel(2, 1).is_equal_approx(Minimap.WATER) and Minimap.WATER == UiTheme.color(&"map_water"), "water is the maps' water blue (873)")
	_check(map.image.get_pixel(2, 2).a == 0.0, "where there is no floor nothing is drawn")
	_check(map.title == "The Little Room", "the big map's title is the zone's name (%s)" % map.title)
	_check(map.starts.has(Vector2i(0, 1)), "it marks the start cells (%s)" % [map.starts])
	_check(map.ways_out.any(func(way: Dictionary) -> bool: return way["cell"] == Vector2i(1, 2) and way["label"] == "Test room" and way["to"] == "test_room"),
		"and the ways out, named by where they go's title, never its id (589 amended (2); %s)" % [map.ways_out])
	_check(level["links"].size() == 2 and map.ways_out.size() == 1 and not map.ways_out.any(func(way: Dictionary) -> bool: return way["cell"] == Vector2i(0, 2)),
		"a hidden link is no way out on the map: not marked, not named (589 amended; %s)" % [map.ways_out])
	_check(map.ways_out.all(func(way: Dictionary) -> bool: return (way["cue"] in Level.CUES or way["cue"] == "edge") and way["facing"] is Vector2i),
		"each way out carries its built cue and the way it faces (589, ui's side)")
	_check(Minimap.label_of("sealed", "the Ossuary") == "a sealed way" and Minimap.label_of("arch", "the Castle") == "to the Castle",
		"a sealed way's words name no destination; the rest say where they go")
	Level.register("mm_untitled", Level.image_from_rows([".."]), null, {})
	_check(Minimap.title_of("mm_untitled") == "" and Minimap.label_of("arch", Minimap.title_of("mm_untitled")) == ""
		and Minimap.title_of("mm_room") == "the Little Room" and Minimap.title_of("test_room") == "Test room",
		"a title said mid-line; a place with no title gets no words, never its id (589 amended (2))")
	_check(map.places.any(func(place: Dictionary) -> bool: return place["name"] == "the well"), "and the zone's places")
	var wilds := Level.load_level("wilds")
	var started := Time.get_ticks_usec()
	map.rebuild(wilds)
	print("    the wilds (%s cells) drawn in %.1f ms" % [wilds["size"], (Time.get_ticks_usec() - started) / 1000.0])
	_check(map.image.get_size() == Vector2i(wilds["size"]) and map.places.any(func(place: Dictionary) -> bool: return place["kind"] == "stockpile")
		and map.ways_out.any(func(way: Dictionary) -> bool: return way["label"] == "the Foothills"),
		"the wilds: the town's store and the way north (to the foothills since 745) are on it")
	# The ground as the eye sees it (873): grass green, dirt brown, stone grey,
	# from the theme; shading by the zone's own range, so no wash.
	var grass := Minimap.ground_colour("grass")
	var dirt := Minimap.ground_colour("dirt")
	_check(grass.g > grass.r and grass.g > grass.b and dirt.r > dirt.g and dirt.g > dirt.b,
		"grass is drawn green and dirt brown (873; they were swapped: %s, %s)" % [grass, dirt])
	_check(Minimap.ground_colour("stone") == UiTheme.color(&"map_stone") and Minimap.ground_colour("stone", true) == UiTheme.color(&"map_floor")
		and Minimap.ground_colour("mud") == UiTheme.color(&"map_stone") and Minimap.ground_colour("forest") == UiTheme.color(&"map_forest"),
		"each kind's colour is the theme's map_ colour; any other kind is stone, indoors the floors' stone")
	var w_terrain: Dictionary = wilds["terrain"]
	var w_kinds: Dictionary = w_terrain["kinds"]
	var washed := 0
	var shown := 0
	for cell: Vector2i in w_terrain["floor"]:
		var kind := str(w_kinds.get(cell, "stone"))
		var base := Minimap.ground_colour(kind)
		var drawn := map.image.get_pixelv(cell)
		if not drawn.is_equal_approx(Minimap.WATER):
			shown += 1
			if drawn.v > base.lightened(Minimap.RELIEF).v + 0.01:
				washed += 1
	_check(shown > 0 and washed == 0, "no ground in the wilds is lit past its kind's colour by more than RELIEF (873; %d of %d)" % [washed, shown])
	# The stream, the woods and the rocks as the eye sees them (873 amended (1)).
	var fords: Array = w_terrain.get("fords", [])
	var ford_water := fords.filter(func(cell: Vector2i) -> bool: return map.image.get_pixelv(cell).is_equal_approx(Minimap.WATER))
	_check(fords.size() > 20 and ford_water.size() == fords.size(),
		"the wilds' stream (its fords) is drawn as water, as the 3D runs it (%d of %d)" % [ford_water.size(), fords.size()])
	var w_floor := {}
	for cell: Vector2i in w_terrain["floor"]:
		w_floor[cell] = true
	for cell: Vector2i in w_terrain["water"]:
		w_floor[cell] = true
	var w_rocks := {}
	for cell: Vector2i in w_terrain.get("rocks", []):
		w_rocks[cell] = true
	var w_size: Vector2i = wilds["size"]
	# The landmarks' footprints (884), drawn as their own mark, not woods.
	var marked := {}
	var mounds: Array = wilds["buildings"].filter(func(b: Dictionary) -> bool: return str(b.get("slot", "")) in Forage.LANDMARKS)
	for building: Dictionary in mounds:
		var rect: Rect2i = Level.building_rect(building)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				marked[Vector2i(x, y)] = true
	var empty := 0
	var stray := 0
	var woods := 0
	var wrong := 0
	var border_open := 0
	var border_drawn := 0
	for y in w_size.y:
		for x in w_size.x:
			var cell := Vector2i(x, y)
			if w_floor.has(cell) or marked.has(cell):
				continue
			var drawn := map.image.get_pixelv(cell)
			var on_border := x == 0 or y == 0 or x == w_size.x - 1 or y == w_size.y - 1
			if drawn.a == 0.0:
				empty += 1
			elif drawn.is_equal_approx(Minimap.WOODS):
				woods += 1
			elif not (w_rocks.has(cell) and drawn.is_equal_approx(UiTheme.color(&"map_stone"))):
				wrong += 1
			if on_border:
				if drawn.a == 0.0:
					border_open += 1
				else:
					border_drawn += 1
	# Every empty cell is joined to the border through empty cells (the band
	# beyond the torn edge); none is a hole inside the zone.
	var beyond := Minimap._beyond_edge(map.image, w_size)
	for y in w_size.y:
		for x in w_size.x:
			if map.image.get_pixel(x, y).a == 0.0 and not beyond.has(Vector2i(x, y)):
				stray += 1
	_check(woods > 0 and wrong == 0 and Minimap.WOODS == UiTheme.color(&"map_woods"),
		"inside the edge the woods are map_woods and a rock is stone, never darkened by its wall (%d woods, %d else)" % [woods, wrong])
	_check(empty > 0 and stray == 0 and border_open > 0 and border_drawn == 0,
		"the torn edge is framed (884): the no-floor band joined to the border is left to the frame (%d empty, %d of them inside, %d border cells drawn)" % [empty, stray, border_drawn])
	# The barrow's mound (884): a ring of kerb stones, a grass dome, its doorway
	# where the barrow's way (not hidden) meets its north edge.
	_check(Forage.LANDMARKS == ["building.mound"] and mounds.size() == 1, "the wilds have one landmark, the barrow's mound (%d)" % mounds.size())
	if mounds.size() == 1:
		var rect: Rect2i = Level.building_rect(mounds[0])
		var kerb := UiTheme.color(&"map_kerb")
		var ring_ok := true
		var dome_ok := true
		var round_ok := true
		var rings := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				var drawn := map.image.get_pixelv(cell)
				if cell == Vector2i(160, 160):
					continue
				if not Minimap.in_round(cell, rect):
					round_ok = round_ok and drawn.is_equal_approx(grass)
				elif Minimap.on_ring(cell, rect):
					ring_ok = ring_ok and drawn.is_equal_approx(kerb)
					rings += 1
				else:
					dome_ok = dome_ok and absf(drawn.h - grass.h) < 0.02 and drawn.v >= grass.v - 0.001 and not drawn.is_equal_approx(Minimap.WOODS)
		# 884 amended (1): it reads round: the footprint's corners are the meadow, and the ring touches each side's middle.
		var middles: Array[Vector2i] = [Vector2i(rect.position.x + rect.size.x / 2, rect.position.y), Vector2i(rect.position.x, rect.position.y + rect.size.y / 2),
			Vector2i(rect.end.x - 1, rect.position.y + rect.size.y / 2), Vector2i(rect.position.x + rect.size.x / 2, rect.end.y - 1)]
		var sides_ok := true
		for at: Vector2i in middles:
			sides_ok = sides_ok and (at == Vector2i(160, 160) or map.image.get_pixelv(at).is_equal_approx(kerb))
		_check(round_ok and rings > 8 and sides_ok and map.image.get_pixelv(rect.position).is_equal_approx(grass)
			and map.image.get_pixelv(rect.end - Vector2i.ONE).is_equal_approx(grass),
			"the mound reads round: its footprint's corners the meadow's grass, its ring touching each side (%d ring cells)" % rings)
		var crown := map.image.get_pixelv(rect.get_center())
		var foot := map.image.get_pixelv(rect.position + Vector2i(1, 1))
		_check(rect == Rect2i(155, 160, 12, 12) and ring_ok and dome_ok and crown.v > foot.v,
			"the mound is drawn as it looks from above: a ring of map_kerb, a grass dome lit toward its crown (%s, ring %s, dome %s)" % [rect, ring_ok, dome_ok])
		_check(map.image.get_pixel(160, 160).is_equal_approx(UiTheme.color(&"map_doorway"))
			and wilds["links"].any(func(link: Dictionary) -> bool: return link["tile"] == Vector2i(160, 160) and not bool(link.get("hidden", false))),
			"its doorway is dark where the barrow's way out, which the map shows, meets its edge")
	var castle_ways := map.ways_out.filter(func(way: Dictionary) -> bool: return way["to"] == "foothills")
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
	_check(map.ways_out.any(func(way: Dictionary) -> bool: return way["cell"] == Vector2i(199, 75) and way["label"] == "Test room"),
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
