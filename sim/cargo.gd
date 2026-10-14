class_name Cargo
extends Pushable
## A crate or a cart: a Pushable that carries things in its slots (Items),
## capacity of them (a crate 4, a cart 8: Level.CRATE, Level.CART). It
## pushes, tosses and breaks as any Pushable; what it holds adds to its mass
## (World._slots_changed) and goes along with it; broken, it spills what it
## held onto the ground where it stood. A player beside it opens it as a
## chest (World.reaches, Main); its slots replicate and save as a chest's.
## A place, not a carrier: things in it gain no carrier time.

## The most any container holds (a cart's); the pack panel has room for it.
const MAX := 8

## How many slots it has; setting it (a level's props) resizes them.
var capacity := 4:
	set(value):
		capacity = maxi(value, 0)
		if slots.size() != capacity:
			slots = Items.tidy(slots, capacity)


func _init() -> void:
	super()
	slots = Items.tidy([], capacity)
	replicate("slots")


## Its slots cut or padded to its capacity, after a spawn spec's props set
## them (EntityFactory.build).
func fit_slots() -> void:
	slots = Items.tidy(slots, capacity)


## What it carries: the ItemBook uids of its things (server).
func contents_uids() -> Array[int]:
	var uids: Array[int] = []
	for slot in slots.size():
		var uid := World.slot_uid(self, slot)
		if uid != 0:
			uids.append(uid)
	return uids
