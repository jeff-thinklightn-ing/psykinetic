class_name Terrain
extends RefCounted
## The ASCII map and what it means. Double resolution: even coordinates are
## cells, odd coordinates are the edges between them; (odd, odd) positions
## are corners and are ignored. Cell symbols: "." floor, "~" fire, anything
## else nothing. Edge symbols: "#" wall, "+" door, anything else open. An
## edge is also a wall where a floor cell meets a non-floor cell, so maps
## need not spell out their outline; "#" on a cell position is nothing, kept
## so old cell maps still read (see expand()).
##
## Edges are keyed by the cell on their -x / -y side: Vector3i(x, y, side)
## with side EAST (between (x, y) and (x + 1, y)) or SOUTH (between (x, y)
## and (x, y + 1)).

enum { EAST, SOUTH }
enum Edge { OPEN, WALL, DOOR }


## The edge crossed leaving [param from] in orthogonal [param direction].
static func edge_key(from: Vector2i, direction: Vector2i) -> Vector3i:
	match direction:
		Vector2i(1, 0): return Vector3i(from.x, from.y, EAST)
		Vector2i(-1, 0): return Vector3i(from.x - 1, from.y, EAST)
		Vector2i(0, 1): return Vector3i(from.x, from.y, SOUTH)
		Vector2i(0, -1): return Vector3i(from.x, from.y - 1, SOUTH)
	push_error("edge_key: %s is not orthogonal" % direction)
	return Vector3i(from.x, from.y, EAST)


## The two cells an edge separates, -x / -y side first.
static func edge_cells(key: Vector3i) -> Array[Vector2i]:
	var a := Vector2i(key.x, key.y)
	return [a, a + (Vector2i(1, 0) if key.z == EAST else Vector2i(0, 1))]


## Reads [param rows] into {floor: Array[Vector2i], fire: Array[Vector2i],
## edges: Dictionary[Vector3i, Edge]} (open edges are absent).
static func parse(rows: Array[String]) -> Dictionary:
	var floor_tiles: Array[Vector2i] = []
	var fire_tiles: Array[Vector2i] = []
	var edges: Dictionary[Vector3i, int] = {}
	var height := (rows.size() + 1) / 2
	var width := 0
	for row in rows:
		width = maxi(width, (row.length() + 1) / 2)
	var is_floor := func(cell: Vector2i) -> bool:
		var symbol := _at(rows, cell * 2)
		return symbol == "." or symbol == "~"
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			match _at(rows, cell * 2):
				".": floor_tiles.append(cell)
				"~":
					floor_tiles.append(cell)
					fire_tiles.append(cell)
	# From -1: the outline along the top and left is owned by cells outside.
	for y in range(-1, height):
		for x in range(-1, width):
			var cell := Vector2i(x, y)
			for side in [EAST, SOUTH]:
				var key := Vector3i(x, y, side)
				var other := edge_cells(key)[1]
				var symbol := _at(rows, cell * 2 + (Vector2i(1, 0) if side == EAST else Vector2i(0, 1)))
				var kind := Edge.OPEN
				if symbol == "+":
					kind = Edge.DOOR
				elif symbol == "#" or (is_floor.call(cell) != is_floor.call(other)):
					kind = Edge.WALL
				if kind != Edge.OPEN:
					edges[key] = kind
	return {"floor": floor_tiles, "fire": fire_tiles, "edges": edges}


## An old cell map ("#" wall cells, "." floor) as double-resolution rows:
## cells spread out with open edges between them. Wall cells become nothing,
## and the outline rule puts walls on their sides. Any other symbol is kept on
## its cell for the caller (tests spawn entities from them).
static func expand(cell_rows: Array[String]) -> Array[String]:
	var rows: Array[String] = []
	for row in cell_rows:
		var spread := ""
		for i in row.length():
			spread += row[i] + " "
		rows.append(spread.rstrip(" "))
		rows.append("")
	rows.pop_back()
	return rows


static func _at(rows: Array[String], at: Vector2i) -> String:
	if at.y < 0 or at.y >= rows.size() or at.x < 0 or at.x >= rows[at.y].length():
		return " "
	return rows[at.y][at.x]
