class_name ScriptedMind
extends CompanionMind
## The rule-based mind, and what every headless test uses. Its stance:
## PULL_BACK below RETREAT_BELOW of her hp, GUARD otherwise. Its voice: a
## word when spoken to ("Hm?" to a question, "Mm." to anything else), and
## nothing at other moments; it never sets a stance from what is said
## (that would be the orders again: docs/decisions.md 76).

const RETREAT_BELOW := 0.3


func _init() -> void:
	kind = "scripted"


func stance(ask: Dictionary) -> Dictionary:
	var hp := float(ask.get("hp", 0))
	var max_hp := float(ask.get("max_hp", 1))
	if max_hp > 0.0 and hp / max_hp < RETREAT_BELOW:
		return {"stance": "PULL_BACK"}
	return {"stance": "GUARD"}


func voice(ask: Dictionary) -> Dictionary:
	if not ask.get("spoken_to", false):
		return {"say": "", "stance": ""}
	return {"say": "Hm?" if "?" in str(ask.get("heard", "")) else "Mm.", "stance": ""}
