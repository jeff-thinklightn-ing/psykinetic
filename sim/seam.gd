class_name Seam
extends GridEntity
## An ore seam in a mine's wall (decision 769; Jeff: "a mixture of
## clearing mobs, and mining"): struck with a tool (an item tagged "tool",
## the pick), each blow takes one of its hp; at none it gives a sack of ore
## at the miner's feet and is whole again, till its sacks are gone. Spent,
## it is rubble that still holds its cell, and it fills again refill_days
## game days later (World.refill_seams). Any other weapon rings off it
## (World._strike_seam). Never moves, never acts, never dies.
##
## It stands in a recess (Level: a floor cell walled on three sides), so
## neither it nor its rubble ever narrows a passage.
##
## Its state is kept in its spawn spec's props as well (sacks, spent_at),
## so the snapshot keeps it as it keeps any level entity's (Snapshot).

## What a sack is.
const ORE := "ore_sack"
## The blows a sack takes, the sacks a full seam gives, and the game days a
## spent one takes to fill again, unless the level says otherwise.
const BLOWS := 7
const SACKS := 3
const REFILL_DAYS := 3.0
## Its names, holding ore and worked out (voice's words).
const LABEL := "Ore seam"
const SPENT_LABEL := "Worked-out seam"

## Sacks it has left; 0 is spent.
@export var sacks := SACKS:
	set(value):
		sacks = maxi(value, 0)
		spent = sacks == 0
## The sacks it holds when full (a level's prop sets its sacks with it; a
## save's sacks, written after, then say what it has left).
@export var full_sacks := SACKS:
	set(value):
		full_sacks = maxi(value, 1)
		sacks = full_sacks
## World.steps when it was spent; -1 while it has ore.
@export var spent_at := -1
@export var refill_days := REFILL_DAYS
## Who struck it last and at which World.tick, a ringing blow too (769
## amended (LABEL): a companion mines beside her player while they dig).
## Server only, not kept.
var struck_by: GridEntity = null
var struck_at := -1
## Worked out, rubble (replicated: the views draw it so, and name it).
var spent := false:
	set(value):
		spent = value
		label = SPENT_LABEL if spent else LABEL


func _init() -> void:
	super()
	acts = false
	pushable = false
	body_material = BodyMaterial.STONE
	mass = 100000.0
	max_hp = BLOWS
	label = LABEL
	replicate("spent")


## Its state written into its spawn spec's props, for the snapshot.
func keep() -> void:
	var props: Dictionary = spawn_spec.get("props", {})
	props["sacks"] = sacks
	props["spent_at"] = spent_at
	spawn_spec["props"] = props


## Whether [param item] (an item id) bites a seam: a tool.
static func bites(item: String) -> bool:
	return not item.is_empty() and "tool" in Items.def(item).get("tags", [])
