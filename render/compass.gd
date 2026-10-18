class_name HudCompass
extends Control
## The HUD's compass, top right: a dark translucent disc with a ring of
## ticks that turns with the camera so the level's north is where it is on
## screen, and N, E, S, W in bold outlined letters (N red) that move round
## with the ring but stay upright. Main sets north_on_screen each frame
## from the view. Sizes are in the HUD's units (the 3840 x 2160 canvas, so
## half as many pixels at 1080p): about 110 px across at 1080p. Its colours
## and letters are the shared theme's (UiTheme, docs/ui_style.md).

const RADIUS := 110.0
const MARGIN := 40.0
static var DISC: Color = UiTheme.color("backing")
static var RING: Color = UiTheme.color("text")
static var TICK: Color = Color(UiTheme.color("text"), 0.7)
static var NORTH: Color = UiTheme.color("alarm")
static var LETTER: Color = UiTheme.color("text")
static var OUTLINE: Color = UiTheme.color("outline")
const NORTH_SIZE := 46
const LETTER_SIZE := 36
static var OUTLINE_SIZE: int = UiTheme.constant("outline")

## The screen direction of the level's north (unit; y down).
var north_on_screen := Vector2.UP:
	set(value):
		if value.length() > 0.001 and not value.normalized().is_equal_approx(north_on_screen):
			north_on_screen = value.normalized()
			queue_redraw()
var _bold: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -RADIUS * 2.0 - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + RADIUS * 2.0
	_bold = UiTheme.font("serif_bold")


func _draw() -> void:
	var centre := Vector2.ONE * RADIUS
	draw_circle(centre, RADIUS, DISC)
	draw_arc(centre, RADIUS - 4.0, 0.0, TAU, 96, RING, 4.0, true)
	# Sixteen ticks, turning with north: long at the four points, middling
	# between them, short between those.
	for i in 16:
		var toward := north_on_screen.rotated(deg_to_rad(i * 22.5))
		var length := 26.0 if i % 4 == 0 else 16.0 if i % 2 == 0 else 9.0
		var width := 4.0 if i % 4 == 0 else 3.0
		draw_line(centre + toward * (RADIUS - 6.0), centre + toward * (RADIUS - 6.0 - length), TICK, width, true)
	# The letters ride the ring but stay upright.
	for point: Array in [["N", 0.0, NORTH_SIZE, NORTH], ["E", 90.0, LETTER_SIZE, LETTER],
			["S", 180.0, LETTER_SIZE, LETTER], ["W", 270.0, LETTER_SIZE, LETTER]]:
		var text: String = point[0]
		var font_size: int = point[2]
		var toward := north_on_screen.rotated(deg_to_rad(point[1]))
		var size := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := centre + toward * (RADIUS - 62.0)
		var baseline := at + Vector2(-size.x / 2.0, _bold.get_ascent(font_size) - size.y / 2.0)
		draw_string_outline(_bold, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, OUTLINE_SIZE, OUTLINE)
		draw_string(_bold, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, point[3])
	draw_circle(centre, 6.0, RING)


## The compass point the camera faces (the way up the screen goes), for
## [param north_on_screen]: "north-west".
static func facing(north: Vector2) -> String:
	# North's angle on screen, clockwise from up; up is that far the other way.
	var degrees := rad_to_deg(atan2(north.x, -north.y))
	return World.COMPASS[posmod(roundi(-degrees / 45.0), 8)]
