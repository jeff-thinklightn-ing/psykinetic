class_name Player
extends GridEntity
## Walks toward its move order (set through World.order_move), re-pathing every
## step so it reacts to things moving. Stepping into the ordered tile pushes
## whatever is on it, if World allows.


func _sim_tick() -> void:
	if not has_move_order or World.tick < next_move_tick:
		return
	if tile == move_order:
		has_move_order = false
		return
	var path := World.find_path(tile, move_order, true)
	if path.is_empty() or not World.try_move(self, path[0] - tile):
		has_move_order = false
