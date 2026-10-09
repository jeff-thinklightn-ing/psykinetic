class_name HudCompass
extends Control
## A small compass in the HUD's top-right corner: N (and E, S, W, smaller)
## where the level's north is on screen, so it turns with the 3D camera's
## yaw. Main sets north_on_screen each frame from the view.

const RADIUS := 34.0
const MARGIN := 24.0
const TOP := 90.0
const RING := Color(0.85, 0.82, 0.74, 0.55)
const BACK := Color(0.08, 0.07, 0.06, 0.45)
const NORTH := Color(0.95, 0.35, 0.25)
const LETTER := Color(0.95, 0.92, 0.85)

## The screen direction of the level's north (unit; y down).
var north_on_screen := Vector2.UP:
	set(value):
		if value.length() > 0.001 and not value.normalized().is_equal_approx(north_on_screen):
			north_on_screen = value.normalized()
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Below the hint line, in from the right edge, whatever the window's size.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -RADIUS * 2.0 - MARGIN
	offset_right = -MARGIN
	offset_top = TOP
	offset_bottom = TOP + RADIUS * 2.0


func _draw() -> void:
	var centre := Vector2.ONE * RADIUS
	draw_circle(centre, RADIUS, BACK)
	draw_arc(centre, RADIUS, 0.0, TAU, 48, RING, 2.0, true)
	var font := get_theme_default_font()
	var points := [["N", 0.0, 18, NORTH], ["E", 90.0, 12, LETTER], ["S", 180.0, 12, LETTER], ["W", 270.0, 12, LETTER]]
	for point: Array in points:
		var toward := north_on_screen.rotated(deg_to_rad(point[1]))
		var font_size: int = point[2]
		var text_size := font.get_string_size(point[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var at := centre + toward * (RADIUS - font_size * 0.75)
		draw_string(font, at + Vector2(-text_size.x / 2.0, font_size * 0.35), point[0], HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, point[3])
	draw_line(centre, centre + north_on_screen * (RADIUS * 0.45), NORTH, 3.0, true)


## The compass point the camera faces (the way up the screen goes), for
## [param north_on_screen]: "north-west".
static func facing(north: Vector2) -> String:
	# North's angle on screen, clockwise from up; up is that far the other way.
	var degrees := rad_to_deg(atan2(north.x, -north.y))
	return World.COMPASS[posmod(roundi(-degrees / 45.0), 8)]
