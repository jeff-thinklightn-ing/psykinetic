extends RefCounted
## Walks a body to a cell in a test, whichever way World walks it (decision
## 688): on the grid a step at a time (World.try_move along World.walk_path,
## when its timer allows), as a free body (World.free_walk) by one tick's
## input command at a time toward the next cell of that path, slowing onto
## the cell's centre. World is stepped a tick at a time. Preload it:
## `const Walk := preload("res://tests/walk.gd")`.


## Walks [param entity] to [param cell] within [param most_ticks] ticks:
## true once it stands there (a free body on the cell's centre).
static func to(entity: GridEntity, cell: Vector2i, most_ticks := 400) -> bool:
	var start := World.tick
	while World.tick - start < most_ticks:
		if arrived(entity, cell):
			return true
		toward(entity, cell)
		World.step()
	return arrived(entity, cell)


## Whether [param entity] stands on [param cell] (a free body on its centre).
static func arrived(entity: GridEntity, cell: Vector2i) -> bool:
	return entity.tile == cell and (not World.free_body(entity) or entity.free_pos.distance_to(Vector2(cell)) < 0.05)


## One tick's walk toward [param cell]: a step on the grid if its timer
## allows, else a free body's command for a tick toward the path's next
## cell, at most what reaches that cell's centre.
static func toward(entity: GridEntity, cell: Vector2i) -> void:
	var path: Array[Vector2i] = []
	if entity.tile != cell:
		path = World.walk_path(entity.tile, cell)
	if not World.free_body(entity):
		if not path.is_empty() and World.tick >= entity.next_move_tick:
			World.try_move(entity, path[0] - entity.tile)
		return
	var next: Vector2i = path[0] if not path.is_empty() else cell
	var way := Vector2(next) - entity.free_pos
	if way.length() < 0.0001:
		return
	var speed := 1.0 / World.step_ticks(entity, World._free_axis(way))
	World.free_input(entity, way / maxf(way.length(), speed), World.TICK_DT)


## Walks [param entity] a step [param direction] (one of World.DIRECTIONS)
## from where it stands: true if it got there.
static func step(entity: GridEntity, direction: Vector2i, most_ticks := 40) -> bool:
	return to(entity, entity.tile + direction, most_ticks)
