class_name Pushable
extends GridEntity
## Inert object. It never acts; it only moves when World shoves it as part of
## another entity's try_move, and only if the mover is massive enough.


func _init() -> void:
	pushable = true
	body_material = BodyMaterial.WOOD
	mass = 40.0
