class_name Pushable
extends GridEntity
## Inert object. It never acts; it only moves when World pushes it. The default
## is a wooden crate that breaks; set body_material to STONE for a boulder.


func _init() -> void:
	pushable = true
	body_material = BodyMaterial.WOOD
	mass = 30.0
	max_hp = 12
