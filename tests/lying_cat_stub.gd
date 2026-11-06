extends Monster
## A creature lying up with enemy-ai's hill cat methods (814), for
## companion_test: she points it out and never springs it.

var lies := true
var spotted: Dictionary = {}


func lying() -> bool:
	return lies


func spotted_by(player_id: String) -> bool:
	return spotted.has(player_id)


func mark_spotted(player_id: String) -> void:
	spotted[player_id] = true
