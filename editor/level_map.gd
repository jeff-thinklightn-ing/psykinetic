class_name LevelMap
extends RefCounted
## A level's layout.png as the level editor holds it: what each cell is and
## what each edge is, read from and written back to the double-resolution
## image (docs/levels.md; Level.parse reads the same pixels). A cell is a
## legend meaning ("stone", "monster_imp", "start", ...), absent for void;
## an edge is "wall" or "door", absent for clear. Edges are keyed as
## Terrain's: Vector3i(x, y, side), side Terrain.EAST (between (x, y) and
## (x + 1, y)) or Terrain.SOUTH (between (x, y) and (x, y + 1)).

## A new map's size, in cells.
const NEW_SIZE := Vector2i(32, 24)
const EDGE_KINDS: Array[String] = ["wall", "door"]

var size := NEW_SIZE
## The picture's size in pixels: 2W - 1 by 2H - 1 for a new map; a map read
## from a file keeps the file's (some have a spare edge column or row).
var pixels := Vector2i(NEW_SIZE.x * 2 - 1, NEW_SIZE.y * 2 - 1)
var cells: Dictionary[Vector2i, String] = {}
var edges: Dictionary[Vector3i, String] = {}
## height.png: cell -> level 1..Level.MAX_HEIGHT (0 is left out).
var heights: Dictionary[Vector2i, int] = {}
## Meaning -> colour: the default legend with level.json's overrides.
var colours: Dictionary[String, Color] = {}
## Pixels whose colour is not in the legend, found on load (they become
## void on save).
var unknown_pixels := 0


func _init(cell_size := NEW_SIZE, config := {}) -> void:
	size = cell_size
	pixels = Vector2i(cell_size.x * 2 - 1, cell_size.y * 2 - 1)
	colours = legend_colours(config)


## The legend as meaning -> colour (Level.LEGEND, then level.json's "legend").
static func legend_colours(config: Dictionary) -> Dictionary[String, Color]:
	var out: Dictionary[String, Color] = {}
	for meaning: String in Level.LEGEND:
		out[meaning] = Color(str(Level.LEGEND[meaning]))
	var overrides: Variant = config.get("legend", {})
	if overrides is Dictionary:
		for meaning: String in overrides:
			out[meaning] = Color(str(overrides[meaning]))
	return out


## The map in [param image] (layout.png) with [param config] (level.json).
static func from_image(image: Image, config := {}) -> LevelMap:
	var pixels := image.get_size()
	var map := LevelMap.new(Vector2i((pixels.x + 1) / 2, (pixels.y + 1) / 2), config)
	map.pixels = pixels
	var by_colour := Level.legend(config)
	for y in pixels.y:
		for x in pixels.x:
			if x % 2 == 1 and y % 2 == 1:
				continue  # A corner: means nothing.
			var colour := image.get_pixel(x, y)
			var meaning := "void"
			if colour.a >= 0.5:
				var key := (colour.r8 << 16) | (colour.g8 << 8) | colour.b8
				if by_colour.has(key):
					meaning = by_colour[key]
				else:
					map.unknown_pixels += 1
			if x % 2 == 0 and y % 2 == 0:
				if meaning not in ["void", "wall", "door"]:
					map.cells[Vector2i(x / 2, y / 2)] = meaning
			elif meaning in EDGE_KINDS:
				var edge := Vector3i(x / 2, y / 2, Terrain.EAST if x % 2 == 1 else Terrain.SOUTH)
				map.edges[edge] = meaning
	return map


## A copy of this map that can change without changing it.
func copy() -> LevelMap:
	var out := LevelMap.new(size)
	out.pixels = pixels
	out.colours = colours.duplicate()
	out.cells = cells.duplicate()
	out.edges = edges.duplicate()
	out.heights = heights.duplicate()
	return out


## Reads [param image] (height.png, the size of layout.png) into
## [member heights]; false, reading nothing, if its size is not [member pixels].
func read_heights(image: Image) -> bool:
	heights.clear()
	if image == null or image.get_size() != pixels:
		return false
	for y in size.y:
		for x in size.x:
			var level := clampi(roundi(image.get_pixel(x * 2, y * 2).r8 / float(Level.GREY_PER_LEVEL)), 0, Level.MAX_HEIGHT)
			if level > 0:
				heights[Vector2i(x, y)] = level
	return true


## [member heights] as height.png, [member pixels] big.
func to_height_image() -> Image:
	var image := Image.create_empty(pixels.x, pixels.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	for at: Vector2i in heights:
		if in_bounds(at):
			var grey := clampi(heights[at], 0, Level.MAX_HEIGHT) * Level.GREY_PER_LEVEL / 255.0
			image.set_pixel(at.x * 2, at.y * 2, Color(grey, grey, grey))
	return image


## A map [param new_size] cells big with every cell, edge and height of this
## one carried to where [param move] (Vector2i -> Vector2i, or null to leave
## it out) puts it. An edge goes with its two cells (so a quarter turn turns
## it too); what lands out of bounds is left out.
func transformed(new_size: Vector2i, move: Callable) -> LevelMap:
	var out := LevelMap.new(new_size)
	out.colours = colours.duplicate()
	for at: Vector2i in cells:
		var to: Variant = move.call(at)
		if to != null and out.in_bounds(to):
			out.cells[to] = cells[at]
	for at: Vector2i in heights:
		var to: Variant = move.call(at)
		if to != null and out.in_bounds(to):
			out.heights[to] = heights[at]
	for key: Vector3i in edges:
		var ends := Terrain.edge_cells(key)
		var a: Variant = move.call(ends[0])
		var b: Variant = move.call(ends[1])
		if a == null or b == null:
			continue
		var moved := Terrain.edge_key(a, b - a)
		if out.edge_in_bounds(moved):
			out.edges[moved] = edges[key]
	return out


## This map grown (or, negative, shrunk) by that many cells on each side.
## Everything keeps its place on the ground: what was at (x, y) is at
## (x + [param left], y + [param top]). The picture keeps any spare edge
## column or row it had.
func resized(left: int, top: int, right: int, bottom: int) -> LevelMap:
	var new_size := Vector2i(maxi(1, size.x + left + right), maxi(1, size.y + top + bottom))
	var offset := Vector2i(left, top)
	var out := transformed(new_size, func(at: Vector2i) -> Variant: return at + offset)
	out.pixels = pixels + (new_size - size) * 2
	return out


## [param config] (level.json) with every cell in it carried by [param move]
## (Vector2i -> Vector2i, or null for gone) and every facing turned
## [param turns] quarter turns clockwise: the centre, starts, spawn points,
## links, places, buildings (their footprints and facings), town walls, and each entity's cell, route and gather point. What [param move]
## drops is left out (an entity's entry, a link, a start; a waypoint; a gather
## point), each said in [param dropped]. The rest of the file is kept.
static func moved_config(config: Dictionary, move: Callable, turns := 0, dropped: Array[String] = []) -> Dictionary:
	var out := config.duplicate(true)
	var cell := func(value: Variant) -> Variant:
		var at: Variant = Level._tile(value)
		if at == null:
			return null
		var to: Variant = move.call(at)
		return [to.x, to.y] if to != null else null
	if out.has("centre"):
		var to: Variant = cell.call(out["centre"])
		if to == null:
			out.erase("centre")
		else:
			out["centre"] = to
	if out.get("starts") is Array:
		var starts: Array = []
		for start: Variant in out["starts"]:
			var to: Variant = cell.call(start)
			if to != null:
				starts.append(to)
			else:
				dropped.append("start %s" % [start])
		out["starts"] = starts
	if out.get("spawn_points") is Dictionary:
		var points: Dictionary = out["spawn_points"]
		for spawn_name: Variant in points.keys():
			var to: Variant = cell.call(points[spawn_name])
			if to != null:
				points[spawn_name] = to
			else:
				points.erase(spawn_name)
				dropped.append("spawn point %s" % spawn_name)
	if out.get("links") is Array:
		var links: Array = []
		for link: Variant in out["links"]:
			var to: Variant = cell.call(link.get("at") if link is Dictionary else null)
			if to != null:
				link["at"] = to
				links.append(link)
			else:
				dropped.append("link %s" % [link])
		out["links"] = links
	if out.get("places") is Dictionary:
		var places: Dictionary = out["places"]
		for key: Variant in places.keys():
			var place: Variant = places[key]
			var to: Variant = cell.call(place.get("at") if place is Dictionary else null)
			if to != null:
				place["at"] = to
			else:
				places.erase(key)
				dropped.append("place %s" % key)
	if out.get("markets") is Dictionary:
		var markets: Dictionary = out["markets"]
		for key: Variant in markets.keys():
			var market: Variant = markets[key]
			var to: Variant = cell.call(market.get("at") if market is Dictionary else null)
			if to != null:
				market["at"] = to
			else:
				markets.erase(key)
				dropped.append("market %s" % key)
	if out.get("streams") is Array:
		# A stream's course goes with it, cell by cell; one cut by the edge
		# keeps the part still on the map (decision 505).
		var streams: Array = []
		for entry: Variant in out["streams"]:
			var path: Array = []
			for point: Variant in (entry.get("path", []) if entry is Dictionary else []):
				var to: Variant = cell.call(point)
				if to != null:
					path.append(to)
			if path.size() >= 2:
				streams.append({"path": path})
			else:
				dropped.append("stream %s" % [entry])
		out["streams"] = streams
	if out.get("buildings") is Array:
		# A footprint goes by two opposite corners: wherever a turn puts
		# them, its top-left is the lesser of each, its size theirs.
		var buildings: Array = []
		for entry: Variant in out["buildings"]:
			var rect: Variant = Level.building_rect(entry)
			var a: Variant = move.call(rect.position) if rect != null else null
			var b: Variant = move.call(rect.end - Vector2i.ONE) if rect != null else null
			if a == null or b == null:
				dropped.append("building %s" % [entry])
				continue
			entry["at"] = [mini(a.x, b.x), mini(a.y, b.y)]
			if turns != 0:
				var turned := turn(Level.building_facing(entry), turns)
				entry["facing"] = [turned.x, turned.y]
			buildings.append(entry)
		out["buildings"] = buildings
	if out.get("town_walls") is Array:
		var rings: Array = []
		for entry: Variant in out["town_walls"]:
			var rect: Variant = Level.town_wall_rect(entry)
			var a: Variant = move.call(rect.position) if rect != null else null
			var b: Variant = move.call(rect.end - Vector2i.ONE) if rect != null else null
			if a == null or b == null:
				dropped.append("town wall %s" % [entry])
				continue
			entry["rect"] = [mini(a.x, b.x), mini(a.y, b.y), absi(a.x - b.x) + 1, absi(a.y - b.y) + 1]
			rings.append(entry)
		out["town_walls"] = rings
	if out.get("roofs") is Array:
		# A roof's ridge turns with it: along x, a quarter turn puts it along z.
		var roofs: Array = []
		for entry: Variant in out["roofs"]:
			var rect: Variant = Level.town_wall_rect(entry)
			var a: Variant = move.call(rect.position) if rect != null else null
			var b: Variant = move.call(rect.end - Vector2i.ONE) if rect != null else null
			if a == null or b == null:
				dropped.append("roof %s" % [entry])
				continue
			entry["rect"] = [mini(a.x, b.x), mini(a.y, b.y), absi(a.x - b.x) + 1, absi(a.y - b.y) + 1]
			if turns % 2 != 0 and entry.get("ridge") in ["x", "z"]:
				entry["ridge"] = "z" if entry["ridge"] == "x" else "x"
			roofs.append(entry)
		out["roofs"] = roofs
	if out.get("entities") is Array:
		var entities: Array = []
		for entry: Variant in out["entities"]:
			var to: Variant = cell.call(entry.get("at") if entry is Dictionary else null)
			if to == null:
				dropped.append("entity %s" % [entry])
				continue
			entry["at"] = to
			var facing: Variant = Level.facing_from(entry.get("facing"))
			if facing != null and turns != 0:
				var turned := turn(facing, turns)
				entry["facing"] = [turned.x, turned.y]
			var idle: Variant = entry.get("idle")
			if idle is Dictionary:
				if idle.get("route") is Array:
					var route: Array = []
					for point: Variant in idle["route"]:
						var moved: Variant = cell.call(point)
						if moved != null:
							route.append(moved)
						else:
							dropped.append("waypoint %s" % [point])
					if route.is_empty():
						idle.erase("route")
						idle.erase("loop")
					else:
						idle["route"] = route
				if idle.has("point"):
					var moved: Variant = cell.call(idle["point"])
					if moved != null:
						idle["point"] = moved
					else:
						dropped.append("gather point %s" % [idle["point"]])
						idle.erase("point")
			entities.append(entry)
		out["entities"] = entities
	return out


## [param direction] turned [param turns] quarter turns clockwise (y down).
static func turn(direction: Vector2i, turns: int) -> Vector2i:
	var out := direction
	for i in posmod(turns, 4):
		out = Vector2i(-out.y, out.x)
	return out


## The map as layout.png, [member pixels] big. A clear edge between
## two cells of one ground (or water, or fire) is painted that colour, and
## so is a corner with that ground on all four sides and no wall at it, so
## the picture reads as the map; anything else between cells is void.
func to_image() -> Image:
	var image := Image.create(pixels.x, pixels.y, false, Image.FORMAT_RGBA8)
	image.fill(colours["void"])
	for at: Vector2i in cells:
		if in_bounds(at):
			image.set_pixel(at.x * 2, at.y * 2, colours.get(cells[at], colours["void"]))
	for y in size.y:
		for x in size.x:
			for side in [Terrain.EAST, Terrain.SOUTH]:
				var key := Vector3i(x, y, side)
				if not edge_in_bounds(key):
					continue
				var pixel := Vector2i(x * 2 + 1, y * 2) if side == Terrain.EAST else Vector2i(x * 2, y * 2 + 1)
				var kind := edge(key)
				if kind != "clear":
					image.set_pixelv(pixel, colours[kind])
					continue
				var sides := Terrain.edge_cells(key)
				var filler := _filler([cell(sides[0]), cell(sides[1])])
				if not filler.is_empty():
					image.set_pixelv(pixel, colours[filler])
	for y in size.y - 1:
		for x in size.x - 1:
			var around := [cell(Vector2i(x, y)), cell(Vector2i(x + 1, y)), cell(Vector2i(x, y + 1)), cell(Vector2i(x + 1, y + 1))]
			var walled := edge(Vector3i(x, y, Terrain.EAST)) != "clear" or edge(Vector3i(x, y, Terrain.SOUTH)) != "clear" \
					or edge(Vector3i(x + 1, y, Terrain.SOUTH)) != "clear" or edge(Vector3i(x, y + 1, Terrain.EAST)) != "clear"
			var filler := _filler(around)
			if not walled and not filler.is_empty():
				image.set_pixel(x * 2 + 1, y * 2 + 1, colours[filler])
	return image


## The colour name to paint between [param around] cells: their ground
## when they are all the same ground, water or fire; "" otherwise.
static func _filler(around: Array) -> String:
	var first: String = around[0]
	if first not in Level.GROUNDS and first not in ["water", "fire", "ford", "tall_grass"]:
		return ""
	for each: String in around:
		if each != first:
			return ""
	return first


func in_bounds(at: Vector2i) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y


func edge_in_bounds(key: Vector3i) -> bool:
	if key.x < 0 or key.y < 0:
		return false
	if key.z == Terrain.EAST:
		return key.x < size.x - 1 and key.y < size.y
	return key.x < size.x and key.y < size.y - 1


## What cell [param at] is: a meaning, "void" for nothing.
func cell(at: Vector2i) -> String:
	return cells.get(at, "void")


## Sets cell [param at] to [param meaning] ("void" clears it). Returns what
## it was.
func set_cell(at: Vector2i, meaning: String) -> String:
	var old := cell(at)
	if meaning == "void":
		cells.erase(at)
	else:
		cells[at] = meaning
	return old


## What edge [param key] is: "wall", "door" or "clear".
func edge(key: Vector3i) -> String:
	return edges.get(key, "clear")


## Sets edge [param key] to [param kind] ("clear" clears it). Returns what
## it was.
func set_edge(key: Vector3i, kind: String) -> String:
	var old := edge(key)
	if kind == "clear":
		edges.erase(key)
	else:
		edges[key] = kind
	return old


## Whether a body could stand in [param at] (any meaning but void and water).
func walkable(at: Vector2i) -> bool:
	return cell(at) not in ["void", "water"]


## The ground a marker cell will get when loaded (Level: the kind most of
## its four neighbours are, stone if none), for drawing it.
func ground_under(at: Vector2i) -> String:
	var counts := {}
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var meaning := cell(at + direction)
		if meaning in Level.GROUNDS:
			counts[meaning] = int(counts.get(meaning, 0)) + 1
	var best := "stone"
	var most := 0
	for kind in Level.GROUNDS:
		if int(counts.get(kind, 0)) > most:
			best = kind
			most = int(counts[kind])
	return best


## Writes [param png_path]'s .import so Godot imports it as an Image (the
## dedicated server has no renderer to read a texture's pixels from). An
## import that already says Image is left alone; anything else is replaced.
## Returns true if it wrote one.
static func ensure_image_import(png_path: String, resource_path: String) -> bool:
	var import_path := png_path + ".import"
	if FileAccess.file_exists(import_path) and 'importer="image"' in FileAccess.get_file_as_string(import_path):
		return false
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	if file == null:
		push_warning("[editor] cannot write %s" % import_path)
		return false
	file.store_string('[remap]\n\nimporter="image"\ntype="Image"\n\n[deps]\n\nsource_file="%s"\n\n[params]\n\n' % resource_path)
	file.close()
	return true
