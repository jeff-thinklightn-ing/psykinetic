class_name Iso
## Grid <-> local pixel conversion for the 2:1 diamond-down isometric layout.
## Must agree with art/tileset.tres (32x16, isometric, diamond down); Main
## checks this against the TileMapLayer at startup.

const TILE_SIZE := Vector2i(32, 16)
const HALF := Vector2(16, 8)


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
