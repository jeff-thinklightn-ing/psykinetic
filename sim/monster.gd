class_name Monster
extends GridEntity
## Picks the nearest player it can see (within sight range, in line of sight).
## Attacks if that player is in melee reach, otherwise walks toward them.

## Mass reads off the body: the sprite runs from SHADE_LIGHT at
## SHADE_LIGHT_MASS to SHADE_DARK at SHADE_DARK_MASS. Darker is heavier.
const SHADE_LIGHT_MASS := 20.0
const SHADE_DARK_MASS := 80.0
const SHADE_LIGHT := Color(1.0, 0.62, 0.55)
const SHADE_DARK := Color(0.33, 0.04, 0.08)

@export var sight_range := 7


func _init() -> void:
	super()
	mass = 40.0
	move_ticks = 4
	max_hp = 12
	attack_damage = 1
	strength = 6
	max_stamina = 60
	attack_ticks = 10


func _ready() -> void:
	super()
	# An explicit tint wins; otherwise colour by mass.
	if _sprite != null and tint.a <= 0.0:
		var heaviness := clampf(inverse_lerp(SHADE_LIGHT_MASS, SHADE_DARK_MASS, mass), 0.0, 1.0)
		_sprite.modulate = SHADE_LIGHT.lerp(SHADE_DARK, heaviness)


func _sim_tick() -> void:
	var target := _nearest_visible_target()
	if target == null:
		return
	if World.can_melee(tile, target.tile):
		World.try_attack(self, target)
	elif World.tick >= next_move_tick:
		var path := World.find_path(tile, target.tile, true)
		if not path.is_empty():
			World.try_move(self, path[0] - tile)


## The nearest player, or companion whose owner is online, in sight.
## Entities still in their spawn grace are passed over.
func _nearest_visible_target() -> GridEntity:
	var nearest: GridEntity = null
	var nearest_distance := sight_range + 1
	for entity in World.get_entities():
		if entity.protected:
			continue  # Spawn grace.
		if entity is Player or (entity is Companion and entity.keeper != null):
			var d := World.distance(tile, entity.tile)
			if d < nearest_distance and World.has_line_of_sight(tile, entity.tile):
				nearest = entity
				nearest_distance = d
	return nearest
