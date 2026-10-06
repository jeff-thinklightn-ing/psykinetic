class_name Iso
## Grid <-> local pixel conversion for the 2:1 diamond-down isometric layout.
## Must agree with art/tileset.tres (32x16, isometric, diamond down); Main
## checks this against the TileMapLayer at startup.

const TILE_SIZE := Vector2i(32, 16)
const HALF := Vector2(16, 8)

## How tall things are drawn, in tile heights (one tile height = TILE_SIZE.y
## pixels on screen before camera zoom). The only place a size is stated:
## entity sprites are scaled to these by EntityFactory, walls drawn to
## theirs by WallBlock. Keyed by shape; "wall" is the wall block.
const HEIGHTS := {
	"capsule": 1.5,  # characters: players, imps, companions
	"wall": 3.0,
	"cube": 0.8,     # crates
	"barrel": 0.9,
	"sphere": 1.2,   # the boulder
	"slab": 0.4,
	"flat": 0.1,
}


## Drawn height of [param what] (a HEIGHTS key) in pixels.
static func height_px(what: String) -> float:
	return float(HEIGHTS[what]) * TILE_SIZE.y


## Centre of [param tile] in the TileMapLayer's local space.
static func tile_to_local(tile: Vector2i) -> Vector2:
	return Vector2(
		(tile.x - tile.y) * HALF.x + HALF.x,
		(tile.x + tile.y) * HALF.y + HALF.y
	)


## Tile whose diamond contains [param local].
static func local_to_tile(local: Vector2) -> Vector2i:
	var u: float = (local.x - HALF.x) / HALF.x
	var v: float = (local.y - HALF.y) / HALF.y
	return Vector2i(roundi((u + v) * 0.5), roundi((v - u) * 0.5))
