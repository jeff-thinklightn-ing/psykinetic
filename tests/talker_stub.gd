extends Monster
## A monster that talks, for resident_test (decision 546, npc's side): npc's
## speaker contract as enemy-ai's draugr (548) keeps it, with nothing of the
## draugr's own. Its deal wants 8 gold at least; it remembers what it was
## offered.

signal offer_spoken(player_id: String, offer: Dictionary)
signal offer_withdrawn(player_id: String)

var got: Array[int] = []
var pact := false


func _ready() -> void:
	super()
	talks = true


func offers_for(_player_id: String) -> Array[Dictionary]:
	if pact:
		return []
	return [{"id": "deal:%d" % get_instance_id(), "kind": "deal", "title": "Face the draugr",
		"words": "Give me gold and face me; win, and the dead will let you go.",
		"what": {"offering": 8, "least": 8, "most": 24}, "accept": "give", "cost": 8}]


func accept_offer(_player: Player, _offer: Dictionary, gold: int) -> Dictionary:
	got.append(gold)
	if gold < 8:
		return {"ok": false, "say": "That is not enough to wake me.", "line": ""}
	pact = true
	return {"ok": true, "say": "So be it. Come, then.", "line": "The pact is struck for %d gold." % gold}
