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
	if first not in Level.GROUNDS and first not in ["water", "fire"]:
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
