class_name Locker
extends Chest
## A player's own chest (decision 722; Jeff: "each char gets chest in town
## with 48 slots"): LOCKER_SLOTS slots, one per character, the same at every
## town's locker (a chest prop {"locker": true}). Opened there (World.
## open_locker), it stands on the locker's cell, never in its occupancy, and
## only its owner's client is sent it (_visible_to): each player opening
## the same locker sees their own. Its slots are the player record's
## (Main keeps record.locker from slots_changed), never the world snapshot's
## (Snapshot skips it); it is despawned with its player.

const LOCKER_SLOTS := 48

## Server only: whose it is (a player id), and the peer that sees it.
var player_id := ""
var viewer := 0
## Replicated: how many times it has been opened, the client's cue to show
## it (each open counts, so opening again shows it again).
var opened := 0


func _init() -> void:
	super()
	holds_cell = false  # It stands on the locker's own cell (World.spawn).
	slots = Items.tidy([], LOCKER_SLOTS)
	replicate("opened")


func fit_slots() -> void:
	slots = Items.tidy(slots, LOCKER_SLOTS)


func _visible_to(peer: int) -> bool:
	return peer == viewer and super(peer)
