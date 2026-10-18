class_name Minimap
extends Control
## The zone you are in, as a map (decision 321): drawn from its Level data
## (the terrain and level Main holds for it, never the TerrainBorder
## glimpses), one pixel a cell, the ground in the palette's swatches, water,
## walls and doors; over it you (pointing where the camera looks), your
## companion, the other players, the start cells, the ways out and the
## level's places. No monsters: finding them is the game. North-up.
##
## Two views: a corner map, always on, centred on you and never showing past
## the zone's edge; and the big map (M), the whole zone fitted to most of the
## screen, zoomed in steps (the wheel) round you. Client only: nothing from
## the server but what is already replicated.

const CORNER_SIZE := 160.0
const CORNER_MARGIN := 12.0
## Below the compass, top right: the pack and the gold have the bottom.
const CORNER_TOP := 150.0
## Sizes are for a 1080-line screen; a taller one scales them (ui_scale).
const BASE_HEIGHT := 1080.0
const LABEL_SIZE := 16
const TITLE_SIZE := 20
const BIG_FRACTION := 0.72
const ZOOMS: Array[float] = [1.0, 2.0, 4.0]
const PALETTE := "res://art/kit/palette.png"
const SWATCH := 16
## Swatches of art/kit/palette.png by ground kind (as the 3D view's ground).
const GROUND_SWATCHES := {"grass": Vector2i(4, 3), "dirt": Vector2i(3, 4), "stone": Vector2i(1, 3), "sand": Vector2i(3, 1)}
## Its frame, water, marks and labels take the shared theme's colours and
## serif (UiTheme, docs/ui_style.md); the ground keeps the palette's swatches.
static var WATER: Color = UiTheme.color("water")
const WALL := Color(0.16, 0.14, 0.12)
static var DOOR: Color = UiTheme.color("brass")
static var FRAME: Color = UiTheme.color("backing")
static var START: Color = UiTheme.color("text")
static var WAY_OUT: Color = UiTheme.color("party")
static var PLACE: Color = UiTheme.color("brass_bright")
static var YOU: Color = UiTheme.color("text")

## The big map is open.
var big := false
## Which of ZOOMS the big map is at.
var zoom_step := 0
## The zone's map: one pixel a cell, null before the first rebuild.
var texture: ImageTexture
var image: Image
## The zone's size in cells, its name to show, and what to mark from its level.
var cells := Vector2i.ZERO
var title := ""
var starts: Array[Vector2i] = []
## {cell, label}: links at their marker, neighbours at the middle of their side.
var ways_out: Array[Dictionary] = []
## {cell, name, kind}: the level's places.
var places: Array[Dictionary] = []
## Main's: () -> Array of {cell: Vector2, kind: "you"|"companion"|"player"|"door", colour, facing: Vector2}.
var marks: Callable = func() -> Array: return []

static var _palette: Image


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


## What [param kind] of ground looks like: its palette swatch's middle.
static func ground_colour(kind: String) -> Color:
	if _palette == null:
		var loaded: Texture2D = load(PALETTE)
		_palette = loaded.get_image() if loaded != null else Image.create(1, 1, false, Image.FORMAT_RGBA8)
		if _palette.is_compressed():
			_palette.decompress()
	var swatch: Vector2i = GROUND_SWATCHES.get(kind, GROUND_SWATCHES["grass" if kind == "forest" else "stone"])
	var at := swatch * SWATCH + Vector2i(SWATCH / 2, SWATCH / 2)
	if at.x >= _palette.get_width() or at.y >= _palette.get_height():
		return Color(0.4, 0.45, 0.35)
	var colour := _palette.get_pixelv(at)
	return colour.darkened(0.3) if kind == "forest" else colour


## The map drawn again from [param level] (Level.load_level's, as Main holds
## it for the zone it shows): on a change of zone and when the level is
## edited (a builder's "terrain").
func rebuild(level: Dictionary) -> void:
	var terrain: Dictionary = level.get("terrain", {})
	cells = level.get("size", Vector2i.ZERO)
	title = str(level.get("display_name", "")) if str(level.get("display_name", "")) != "" else str(level.get("name", ""))
	image = Image.create(maxi(cells.x, 1), maxi(cells.y, 1), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var kinds: Dictionary = terrain.get("kinds", {})
	var heights: Dictionary = terrain.get("heights", {})
	var by_kind := {}
	for cell: Vector2i in terrain.get("floor", []):
		var kind := str(kinds.get(cell, "stone"))
		if not by_kind.has(kind):
			by_kind[kind] = ground_colour(kind)
		var colour: Color = by_kind[kind]
		var height := int(heights.get(cell, 0))
		if height != 0:
			colour = colour.lightened(0.05 * height) if height > 0 else colour.darkened(0.06 * -height)
		image.set_pixelv(cell, colour)
	for cell: Vector2i in terrain.get("water", []):
		if Rect2i(Vector2i.ZERO, cells).has_point(cell):
			image.set_pixelv(cell, WATER)
	# A wall between two cells darkens the floor either side, once, so it shows
	# at one pixel a cell. The walls Level puts round the zone's border are
	# the map's own edge, drawn by its frame.
	var edges: Dictionary = terrain.get("edges", {})
	var inside := Rect2i(Vector2i.ZERO, cells)
	var walled := {}
	for key: Vector3i in edges:
		if int(edges[key]) != Terrain.Edge.WALL:
			continue
		var cell := Vector2i(key.x, key.y)
		var other := cell + (Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1))
		if inside.has_point(cell) and inside.has_point(other):
			walled[cell] = true
			walled[other] = true
	for cell: Vector2i in walled:
		if image.get_pixelv(cell).a > 0.0:
			image.set_pixelv(cell, image.get_pixelv(cell).lerp(WALL, 0.65))
	texture = ImageTexture.create_from_image(image)
	starts.assign(level.get("starts", []))
	ways_out.clear()
	for link: Dictionary in level.get("links", []):
		ways_out.append({"cell": link["tile"], "label": str(link["to_map"])})
	var neighbours: Dictionary = level.get("neighbours", {})
	for side: String in neighbours:
		var middle := Vector2i(cells.x / 2, cells.y / 2)
		var cell: Vector2i = {"north": Vector2i(middle.x, 0), "south": Vector2i(middle.x, cells.y - 1),
			"west": Vector2i(0, middle.y), "east": Vector2i(cells.x - 1, middle.y)}.get(side, middle)
		ways_out.append({"cell": cell, "label": str(neighbours[side])})
	places.clear()
	var listed: Dictionary = level.get("places", {})
	for key: String in listed:
		var place: Dictionary = listed[key]
		places.append({"cell": place["cell"], "name": place["name"], "kind": place["kind"]})


func toggle() -> void:
	big = not big
	queue_redraw()


func zoom(step: int) -> void:
	zoom_step = clampi(zoom_step + step, 0, ZOOMS.size() - 1)
	queue_redraw()


## How much bigger than at 1080 lines the screen's things are drawn (1 at least).
func ui_scale() -> float:
	var screen := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	return maxf(1.0, screen.y / BASE_HEIGHT)


## Where the map is drawn, which cells it shows and at what scale, for the
## view that is open, centred on [param centre] (your cell): {dest: Rect2,
## source: Rect2 (cells), scale}. The source never reaches past the zone.
func view(centre: Vector2) -> Dictionary:
	var screen := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var area := Vector2(cells)
	if area.x <= 0 or area.y <= 0:
		return {"dest": Rect2(), "source": Rect2(), "scale": 1.0}
	var scale: float
	var box: Vector2
	if big:
		var fit := minf(screen.x * BIG_FRACTION / area.x, screen.y * BIG_FRACTION / area.y)
		scale = fit * ZOOMS[zoom_step]
		box = (area * fit).min(screen * BIG_FRACTION)
	else:
		# A small zone fills the corner; a big one shows a cell a pixel (at
		# 1080 lines) round you.
		var side := CORNER_SIZE * ui_scale()
		scale = maxf(ui_scale(), floorf(side / maxf(area.x, area.y)))
		box = Vector2(side, side).min(area * scale)
	var seen := (box / scale).min(area)
	var start := (centre - seen / 2.0).clamp(Vector2.ZERO, area - seen)
	var dest_size := seen * scale
	var dest_pos := (screen - dest_size) / 2.0 if big 		else Vector2(screen.x - dest_size.x - CORNER_MARGIN * ui_scale(), CORNER_TOP * ui_scale())
	return {"dest": Rect2(dest_pos, dest_size), "source": Rect2(start, seen), "scale": scale}


## Where [param cell] (its middle) falls on screen in [param shown] (view()).
static func to_screen(cell: Vector2, shown: Dictionary) -> Vector2:
	var source: Rect2 = shown["source"]
	var dest: Rect2 = shown["dest"]
	return dest.position + (cell + Vector2(0.5, 0.5) - source.position) * float(shown["scale"])


func _draw() -> void:
	if texture == null:
		return
	var all: Array = marks.call()
	var centre := Vector2(cells) / 2.0
	for mark: Dictionary in all:
		if mark["kind"] == "you":
			centre = mark["cell"]
	var shown := view(centre)
	var dest: Rect2 = shown["dest"]
	var scale: float = shown["scale"]
	var ui := ui_scale()
	draw_rect(dest.grow(3.0 * ui), FRAME)
	draw_texture_rect_region(texture, dest, shown["source"], Color.WHITE, false, false)
	var font := UiTheme.font("serif")
	var label_size := int(LABEL_SIZE * ui)
	var dot := maxf(2.0 * ui, scale * 0.6)
	for cell in starts:
		_mark(to_screen(Vector2(cell), shown), dest, func(at: Vector2) -> void: draw_rect(Rect2(at - Vector2(dot, dot) / 2, Vector2(dot, dot)), START))
	for way: Dictionary in ways_out:
		var at := to_screen(Vector2(way["cell"]), shown)
		_mark(at, dest, func(p: Vector2) -> void:
			draw_circle(p, dot + 1.5, WAY_OUT)
			if big:
				draw_string(font, p + Vector2(dot + 4, 5), "to " + str(way["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, WAY_OUT))
	for place: Dictionary in places:
		var at := to_screen(Vector2(place["cell"]), shown)
		_mark(at, dest, func(p: Vector2) -> void:
			draw_rect(Rect2(p - Vector2(dot + 1, dot + 1), Vector2(dot + 1, dot + 1) * 2), PLACE, false, 1.5)
			if big:
				draw_string(font, p + Vector2(dot + 5, 5), str(place["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, PLACE))
	for mark: Dictionary in all:
		var at := to_screen(mark["cell"], shown)
		var colour: Color = mark.get("colour", YOU)
		match mark["kind"]:
			"door":
				_mark(at, dest, func(p: Vector2) -> void: draw_rect(Rect2(p - Vector2(dot, dot) / 2, Vector2(dot, dot)), DOOR))
			"player", "companion":
				_mark(at, dest, func(p: Vector2) -> void: draw_circle(p, dot if mark["kind"] == "player" else dot * 0.7, colour))
			"you":
				var facing: Vector2 = mark.get("facing", Vector2(0, -1))
				var size := maxf(8.0 * ui, dot * 2.5)
				var tip := at + facing.normalized() * size
				var side := facing.orthogonal().normalized() * size * 0.6
				var arrow := PackedVector2Array([tip, at - facing.normalized() * size * 0.5 + side,
					at - facing.normalized() * size * 0.5 - side])
				draw_colored_polygon(arrow, YOU)
				arrow.append(tip)
				draw_polyline(arrow, Color(0, 0, 0, 0.8), 1.5)
	if big:
		draw_string(font, dest.position + Vector2(0, -10 * ui), "%s%s" % [title, "  x%d" % int(ZOOMS[zoom_step]) if zoom_step > 0 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(TITLE_SIZE * ui), UiTheme.color("text"))


## Draws with [param draw] at [param at] only if it is on the map.
func _mark(at: Vector2, dest: Rect2, draw: Callable) -> void:
	if dest.has_point(at):
		draw.call(at)
