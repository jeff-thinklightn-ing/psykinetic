class_name Minimap
extends Control
## The zone you are in, as a map (decision 321): drawn from its Level data
## (the terrain and level Main holds for it, never the TerrainBorder
## glimpses), one pixel a cell, the ground in the palette's swatches, water,
## walls and doors; over it you (pointing where the camera looks), your
## companion, the other players, the start cells, the ways out and the
## level's places. No monsters: finding them is the game. North-up. A
## hidden link (608: behind a door nobody has found) is no way out here
## until it is found: not marked, not named (589 amended, ui's side). On
## the big map each way out is drawn as its built cue (589, ui's side;
## maps' Level.link_cues): an arch or a pair of waystones turned the way
## they stand, a dark mouth for a stair down, a light ring for a stair up,
## a struck dot for a sealed way that names no destination, the plain dot
## for a door between rooms and for a neighbour's side.
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
static var SEALED: Color = UiTheme.color("text_dim")
## The cues drawn as a glyph on the big map; the rest are the dot.
const GLYPH_CUES: Array[String] = ["arch", "waystones", "down", "up", "sealed"]
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
## {cell, label, cue, facing}: links at their marker with their built cue
## (Level.CUES) and the way it faces (a grid direction); neighbours at the
## middle of their side, cue "edge", facing out.
var ways_out: Array[Dictionary] = []
## {cell, name, kind}: the level's places.
var places: Array[Dictionary] = []
## Main's: () -> Array of {cell: Vector2, kind: "you"|"companion"|"player"|"door", colour, facing: Vector2}.
## The "you" mark's facing is the body's own (its replicated facing, a grid direction, decision 535).
var marks: Callable = func() -> Array: return []
## The screen direction of the level's north, set by Main from the view
## (the same turn HudCompass makes, Main.screen_north): the map turns so
## that up on it is up on the screen (decision 535, Jeff: "the minimap
## should probably rotate with compass and map"). A change queues one
## draw (none while the big map is open: it stays north-up, 535 amended);
## standing still, nothing draws (482).
var north_on_screen := Vector2.UP:
	set(value):
		if value.length() > 0.001 and not value.normalized().is_equal_approx(north_on_screen):
			north_on_screen = value.normalized()
			if not big:
				queue_redraw()

## How often it has drawn, and the microseconds drawing took (map_bench).
var draws := 0
var draw_usec := 0
## The marks as last drawn, and their hash: drawn again only when that
## changes (decision 482), or the map is rebuilt, opened or zoomed (each
## queues a draw), or resized (a Control redraws then by itself).
var _marks: Array = []
var _marks_hash := 0

static var _palette: Image


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if texture == null or not is_visible_in_tree():
		return
	var all: Array = marks.call()
	var now := hash(all)
	if now != _marks_hash:
		_marks = all
		_marks_hash = now
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
	var cues := {}  # tile -> {cue, facing, variant} (Level.link_cues, 589).
	for entry: Variant in terrain.get("link_cues", []):
		if entry is Dictionary and entry.get("tile") is Vector2i:
			cues[entry["tile"]] = entry
	for link: Dictionary in level.get("links", []):
		if bool(link.get("hidden", false)):
			continue  # Not given away (608; 589 amended).
		var built: Dictionary = cues.get(link["tile"], {})
		ways_out.append({"cell": link["tile"], "label": str(link["to_map"]), "cue": str(built.get("cue", link.get("cue", "none"))),
			"facing": built.get("facing", Vector2i(0, 1)) if built.get("facing") is Vector2i else Vector2i(0, 1)})
	var neighbours: Dictionary = level.get("neighbours", {})
	var outward := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "west": Vector2i(-1, 0), "east": Vector2i(1, 0)}
	for side: String in neighbours:
		var middle := Vector2i(cells.x / 2, cells.y / 2)
		var cell: Vector2i = {"north": Vector2i(middle.x, 0), "south": Vector2i(middle.x, cells.y - 1),
			"west": Vector2i(0, middle.y), "east": Vector2i(cells.x - 1, middle.y)}.get(side, middle)
		ways_out.append({"cell": cell, "label": str(neighbours[side]), "cue": "edge", "facing": outward.get(side, Vector2i(0, 1))})
	places.clear()
	var listed: Dictionary = level.get("places", {})
	for key: String in listed:
		var place: Dictionary = listed[key]
		places.append({"cell": place["cell"], "name": place["name"], "kind": place["kind"]})
	queue_redraw()


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
	var angle := turn()
	var dest_size := seen * scale
	if big and not is_zero_approx(angle):
		# The box holds the part shown however it is turned (its turned bounds).
		dest_size = Vector2(absf(dest_size.x * cos(angle)) + absf(dest_size.y * sin(angle)),
				absf(dest_size.x * sin(angle)) + absf(dest_size.y * cos(angle))).min(screen * BIG_FRACTION)
	var dest_pos := (screen - dest_size) / 2.0 if big else Vector2(screen.x - dest_size.x - CORNER_MARGIN * ui_scale(), CORNER_TOP * ui_scale())
	return {"dest": Rect2(dest_pos, dest_size), "source": Rect2(start, seen), "scale": scale,
		"angle": angle, "centre": start + seen / 2.0}


## How far the map is turned on screen (radians, clockwise positive):
## from the level's north as the map holds it (World.north, a grid
## direction) to where the view puts it (north_on_screen). The corner map
## alone: the big map stays north-up (535 amended, maps: the land is read
## there as the level is laid out, "north of the square", the sides'
## links, the editor's view).
func turn() -> float:
	return 0.0 if big else Vector2(World.north).angle_to(north_on_screen)


## Where [param cell] (its middle) falls on screen in [param shown] (view()):
## turned about the box's middle by the view's turn (535).
static func to_screen(cell: Vector2, shown: Dictionary) -> Vector2:
	var dest: Rect2 = shown["dest"]
	var centre: Vector2 = shown.get("centre", (shown["source"] as Rect2).get_center())
	return dest.get_center() + ((cell + Vector2(0.5, 0.5) - centre) * float(shown["scale"])).rotated(float(shown.get("angle", 0.0)))


## The screen direction a grid direction [param facing] points in [param shown] (the arrow's, 535).
static func on_screen(facing: Vector2, shown: Dictionary) -> Vector2:
	return facing.normalized().rotated(float(shown.get("angle", 0.0)))


func _draw() -> void:
	if texture == null:
		return
	var started := Time.get_ticks_usec()
	draws += 1
	var all := _marks
	var centre := Vector2(cells) / 2.0
	for mark: Dictionary in all:
		if mark["kind"] == "you":
			centre = mark["cell"]
	var shown := view(centre)
	var dest: Rect2 = shown["dest"]
	var scale: float = shown["scale"]
	var ui := ui_scale()
	draw_rect(dest.grow(3.0 * ui), FRAME)
	# The zone's picture, turned about the box's middle and cut to the box
	# (535): the box's corners and the turned zone's, intersected, each
	# vertex mapped back to its cell for the texture.
	var angle: float = shown["angle"]
	var centre_cell: Vector2 = shown["centre"]
	var middle := dest.get_center()
	var zone_poly := PackedVector2Array()
	for corner: Vector2 in [Vector2.ZERO, Vector2(cells.x, 0), Vector2(cells), Vector2(0, cells.y)]:
		zone_poly.append(middle + ((corner - centre_cell) * scale).rotated(angle))
	var box_poly := PackedVector2Array([dest.position, Vector2(dest.end.x, dest.position.y), dest.end, Vector2(dest.position.x, dest.end.y)])
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(box_poly, zone_poly):
		var uvs := PackedVector2Array()
		for p: Vector2 in poly:
			uvs.append((centre_cell + ((p - middle) / scale).rotated(-angle)) / Vector2(cells))
		draw_polygon(poly, PackedColorArray([Color.WHITE]), uvs, texture)
	var font := UiTheme.font("serif")
	var label_size := int(LABEL_SIZE * ui)
	var dot := maxf(2.0 * ui, scale * 0.6)
	for cell in starts:
		_mark(to_screen(Vector2(cell), shown), dest, func(at: Vector2) -> void: draw_rect(Rect2(at - Vector2(dot, dot) / 2, Vector2(dot, dot)), START))
	for way: Dictionary in ways_out:
		var at := to_screen(Vector2(way["cell"]), shown)
		_mark(at, dest, func(p: Vector2) -> void:
			var cue := str(way.get("cue", "none"))
			var colour := SEALED if cue == "sealed" else WAY_OUT
			var glyph := big and cue in GLYPH_CUES
			var reach := maxf(3.0 * dot, 7.0 * ui) if glyph else dot
			if glyph:
				_draw_cue(p, cue, on_screen(Vector2(way.get("facing", Vector2i(0, 1))), shown), reach)
			else:
				draw_circle(p, dot + 1.5, colour)
			if big:
				draw_string(font, p + Vector2(reach + 4, 5), label_of(cue, str(way["label"])), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, colour))
	for place: Dictionary in places:
		var at := to_screen(Vector2(place["cell"]), shown)
		_mark(at, dest, func(p: Vector2) -> void:
			draw_rect(Rect2(p - Vector2(dot + 1, dot + 1), Vector2(dot + 1, dot + 1) * 2), PLACE, false, 1.5)
			if big:
				draw_string(font, p + Vector2(dot + 5, 5), str(place["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, PLACE))
	var on_map: Rect2 = (shown["source"] as Rect2).grow(1.0)
	for mark: Dictionary in all:
		if not on_map.has_point(mark["cell"]):
			continue  # Off the part shown (most of a big level's doors).
		var at := to_screen(mark["cell"], shown)
		var colour: Color = mark.get("colour", YOU)
		match mark["kind"]:
			"door":
				_mark(at, dest, func(p: Vector2) -> void: draw_rect(Rect2(p - Vector2(dot, dot) / 2, Vector2(dot, dot)), DOOR))
			"player", "companion":
				_mark(at, dest, func(p: Vector2) -> void: draw_circle(p, dot if mark["kind"] == "player" else dot * 0.7, colour))
			"you":
				# The body's facing, turned as the map is (535): the arrow points where the body's front points on screen.
				var facing := on_screen(mark.get("facing", Vector2(0, -1)), shown)
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
	draw_usec += Time.get_ticks_usec() - started


## Draws with [param draw] at [param at] only if it is on the map.
func _mark(at: Vector2, dest: Rect2, draw: Callable) -> void:
	if dest.has_point(at):
		draw.call(at)


## A way out's words on the big map: where it leads, or for a sealed way
## nothing of that (where it leads is learned by opening it).
static func label_of(cue: String, to_map: String) -> String:
	return "a sealed way" if cue == "sealed" else "to " + to_map


## The glyph for [param cue] at [param p], [param facing] the way it stands
## on screen (a unit vector), [param reach] its half size: an arch (two posts
## and a bow toward the facing), a pair of waystones either side of the way,
## a dark mouth (down), a light ring (up), a struck dot (sealed).
func _draw_cue(p: Vector2, cue: String, facing: Vector2, reach: float) -> void:
	var f := facing.normalized() if facing.length() > 0.001 else Vector2.DOWN
	var r := f.rotated(PI / 2.0)
	match cue:
		"arch":
			draw_circle(p - r * reach, reach * 0.3, WAY_OUT)
			draw_circle(p + r * reach, reach * 0.3, WAY_OUT)
			draw_arc(p, reach, (-r).angle(), (-r).angle() + PI, 24, WAY_OUT, 2.5, true)
		"waystones":
			for side: float in [-1.0, 1.0]:
				draw_line(p + r * reach * side - f * reach * 0.6, p + r * reach * side + f * reach * 0.6, WAY_OUT, 3.0, true)
		"down":
			draw_circle(p, reach, WALL)
			draw_arc(p, reach, 0.0, TAU, 32, WAY_OUT, 2.0, true)
		"up":
			draw_arc(p, reach, 0.0, TAU, 32, WAY_OUT, 2.0, true)
			draw_circle(p, reach * 0.45, YOU)
		"sealed":
			draw_circle(p, reach * 0.5, SEALED)
			draw_line(p - r * reach, p + r * reach, SEALED, 3.0, true)
		_:
			draw_circle(p, reach * 0.5, WAY_OUT)
