class_name Monster
extends GridEntity
## Attacks the nearest player when adjacent; otherwise walks toward them while
## they are within sight range and in line of sight.

@export var sight_range := 12


func _sim_tick() -> void:
	var target := _nearest_player()
	if target == null:
		return
	if World.are_adjacent(tile, target.tile):
		World.try_attack(self, target)
	elif World.tick >= next_move_tick and World.has_line_of_sight(tile, target.tile):
		var path := World.find_path(tile, target.tile, true)
		if not path.is_empty():
			World.try_move(self, path[0] - tile)


func _nearest_player() -> Player:
	var nearest: Player = null
	var nearest_distance := sight_range + 1
	for entity in World.get_entities():
		if entity is Player:
			var offset: Vector2i = (entity.tile - tile).abs()
			var distance: int = offset.x + offset.y
			if distance < nearest_distance:
				nearest = entity
				nearest_distance = distance
	return nearest
