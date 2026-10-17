class_name Chest
extends GridEntity
## A chest: Chest.SLOTS slots of things (Items), on a tile. It never acts and
## does not break. A player beside it opens it with a click (Main) and drags
## things between it and their own slots; World.try_transfer moves them.
## Its slots are replicated to the clients in its zone and saved in the
## snapshot. A depot (level.json props {"depot": true}) keeps nothing: what
## is put in is banked in the town's stockpile at once (Stockpile).

const SLOTS := 4

## Whether this is a stockpile's depot.
var depot := false
## Whether this is a shop's counter (props {"shop": true}): it keeps
## nothing either; what is put in is sold to the town (World.try_transfer,
## Economy.sell), and a player beside it buys from the town's shop
## (World.try_buy).
var shop := false


func _init() -> void:
	super()
	acts = false
	body_material = BodyMaterial.WOOD
	mass = 200.0
	max_hp = 0
	slots = Items.tidy([], SLOTS)
	replicate("slots")
	replicate("slot_notes")


## Its slots cut or padded to SLOTS, after a spawn spec's props set them
## (EntityFactory.build).
func fit_slots() -> void:
	slots = Items.tidy(slots, SLOTS)
