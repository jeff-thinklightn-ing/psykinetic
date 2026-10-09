class_name Chest
extends GridEntity
## A chest: Chest.SLOTS slots of things (Items), on a tile. It never acts and
## does not break. A player beside it opens it with a click (Main) and drags
## things between it and their own slots; World.try_transfer moves them.
## Its slots are replicated to the clients in its zone and saved in the
## snapshot.

const SLOTS := 4


func _init() -> void:
	super()
	body_material = BodyMaterial.WOOD
	mass = 200.0
	max_hp = 0
	slots = Items.tidy([], SLOTS)
	replicate("slots")
