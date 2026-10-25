extends Monster
## A monster that talks, for resident_test (decision 546, npc's side): npc's
## speaker contract as enemy-ai's draugr (548) keeps it, with nothing of the
## draugr's own. Its deal wants 8 gold at least; it remembers what it was
## offered.

signal offer_spoken(player_id: String, offer: Dictionary)
signal offer_withdrawn(player_id: String)

var got: Array[int] = []
var pact := false
## A deal paid for already (548 amended): its offer is the free "again" one.
var paid := false


func _ready() -> void:
	super()
	talks = true


func offers_for(_player_id: String) -> Array[Dictionary]:
	if pact:
		return []
	if paid:
		return [{"id": "deal:%d:again" % get_instance_id(), "kind": "deal", "title": "Face the draugr again", "words": "Your gold is paid. Come, then.",
			"what": {"level": "easy", "steps": []}, "accept": "take", "cost": 0}]
	return [{"id": "deal:%d" % get_instance_id(), "kind": "deal", "title": "Face the draugr",
		"words": "Give me gold and face me; win, and the dead will let you go.",
		"what": {"offering": 8, "least": 8, "most": 24}, "accept": "give", "cost": 8}]


func accept_offer(_player: Player, _offer: Dictionary, gold: int) -> Dictionary:
	got.append(gold)
	if str(_offer.get("id", "")).ends_with(":again"):
		pact = true  # Paid for already (548 amended): no gold wanted.
		return {"ok": true, "say": "Come, then.", "line": "The pact is taken up again."}
	if gold < 8:
		return {"ok": false, "say": "That is not enough to wake me.", "line": ""}
	pact = true
	return {"ok": true, "say": "So be it. Come, then.", "line": "The pact is struck for %d gold." % gold}
