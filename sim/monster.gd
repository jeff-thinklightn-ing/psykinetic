class_name Monster
extends GridEntity
## Attacks the nearest player when in melee reach; otherwise walks toward them
## while they are within sight range and in line of sight.

@export var sight_range := 7


func _sim_tick() -> void:
	var target := _nearest_player()
	if target == null:
		return
	if World.can_melee(tile, target.tile):
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
			var d := World.distance(tile, entity.tile)
			if d < nearest_distance:
				nearest = entity
				nearest_distance = d
	return nearest
