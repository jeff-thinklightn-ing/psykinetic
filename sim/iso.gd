class_name Iso
## Grid <-> local pixel projection. A fixed-elevation view of the ground
## plane (vertical foreshortened to a half) turned about the vertical by
## `azimuth`: 0 is the classic 2:1 diamond view, where the grid's x axis
## runs down-right and y down-left, and +-45 degrees is the axis-aligned
## view, where a cell is an upright 2:1 rectangle. Everything drawn on the
## ground (floor, walls, doors, ripples, hover) and every sprite anchor
## goes through here; heights are vertical and do not turn. The sim never
## reads it.
##
## At azimuth 0 the projection must agree with art/tileset.tres (32x16,
## isometric, diamond down); Main checks this against the TileMapLayer at
## startup and turns the layer with `ground_transform`.

const TILE_SIZE := Vector2i(32, 16)
const HALF := Vector2(16, 8)
## One grid unit on the ground plane, in px: at azimuth 0 a cell's edge is
## the diamond's side, from (0, 8) to (16, 0).
const UNIT := 16.0 * sqrt(2.0)
## Vertical foreshortening of the ground plane.
const ELEVATION := 0.5
const AZIMUTH_LIMIT := 45.0
## Where tile (0, 0)'s centre sits, in grid units: the TileSet lays the
## diamonds out so that a cell's centre is one unit along x from its grid
## point. A grid-space offset, so it turns with the view.
const ORIGIN := Vector2(1, 0)

## How tall things are drawn, in tile heights (one tile height = TILE_SIZE.y
## pixels on screen before camera zoom). The only place a size is stated:
## entity sprites are scaled to these by EntityFactory, walls drawn to
## theirs by WallEdge. Keyed by shape; "wall" is the wall block.
const HEIGHTS := {
	"capsule": 1.5,  # characters: players, imps, companions
	"wall": 3.0,
	"cube": 0.8,     # crates
	"barrel": 0.9,
	"sphere": 1.2,   # the boulder
	"slab": 0.4,
	"flat": 0.1,
}

## Degrees, -AZIMUTH_LIMIT..AZIMUTH_LIMIT. Set through set_azimuth.
static var azimuth := 0.0


## Drawn height of [param what] (a HEIGHTS key) in pixels.
static func height_px(what: String) -> float:
	return float(HEIGHTS[what]) * TILE_SIZE.y


static func set_azimuth(degrees: float) -> void:
	azimuth = clampf(degrees, -AZIMUTH_LIMIT, AZIMUTH_LIMIT)


## Where the grid's x axis points on the ground, as a screen angle: 45
## degrees (down-right) at azimuth 0, 0 (right) at +45, 90 (down) at -45.
static func _heading() -> float:
	return deg_to_rad(45.0 - azimuth)


## One grid unit along x and along y, on screen.
static func axis_x() -> Vector2:
	var heading := _heading()
	return Vector2(cos(heading), sin(heading) * ELEVATION) * UNIT


static func axis_y() -> Vector2:
	var heading := _heading()
	return Vector2(-sin(heading), cos(heading) * ELEVATION) * UNIT


## A ground-plane offset in grid units, on screen.
static func project(grid: Vector2) -> Vector2:
	return axis_x() * grid.x + axis_y() * grid.y


## The projection as a transform, grid units to local px (no offset).
static func ground_transform() -> Transform2D:
	return Transform2D(axis_x(), axis_y(), Vector2.ZERO)


## Continuous grid coordinates to local px: a tile's centre is its integer
## coordinates, its cell the unit square around them.
static func grid_to_local(grid: Vector2) -> Vector2:
	return project(grid + ORIGIN)


## Centre of [param tile] in local px.
static func tile_to_local(tile: Vector2i) -> Vector2:
	return grid_to_local(Vector2(tile))


## [param local] in continuous grid units (see grid_to_local).
static func local_to_grid(local: Vector2) -> Vector2:
	return ground_transform().affine_inverse() * local - ORIGIN


## Tile whose cell contains [param local].
static func local_to_tile(local: Vector2) -> Vector2i:
	var grid := local_to_grid(local)
	return Vector2i(roundi(grid.x), roundi(grid.y))


## The ground direction that runs straight down the screen, toward the
## camera, in grid units.
static func view_direction() -> Vector2:
	var heading := _heading()
	return Vector2(sin(heading), cos(heading))


## Whether the +x face of an east edge ([param side] Terrain.EAST) or the
## +y face of a south edge (Terrain.SOUTH) points toward the camera. Edge-on
## counts as facing, so the classification is steady at the limits.
static func faces_camera(side: int) -> bool:
	var view := view_direction()
	var normal := Vector2(1, 0) if side == Terrain.EAST else Vector2(0, 1)
	return normal.dot(view) >= -0.0001
