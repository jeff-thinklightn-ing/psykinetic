class_name ScriptedMind
extends CompanionMind
## The rule-based mind, and the fallback for every other one. Gets out of
## its companion's way at once when they bump into it; otherwise retreats
## toward them when low on hp, attacks the nearest hostile within reach,
## and follows. What it is told it answers with a word, and goes on.

const ATTACK_RANGE := 3
const RETREAT_BELOW := 0.3


func _init() -> void:
	kind = "scripted"


func decide(context: Dictionary) -> Dictionary:
	var bumped: Variant = context.get("companion_direction", {})
	if bumped is Dictionary and not bumped.is_empty():
		return {"intent": "YIELD", "target": null, "say": ""}
	var answer := _decide(context)
	var said := str(context.get("companion_said", ""))
	if not said.is_empty():
		# Spoken to: a word back, and on with what it was going to do.
		answer["say"] = "Hm?" if "?" in said else "Mm."
	return answer


func _decide(context: Dictionary) -> Dictionary:
	var hp := float(context.get("hp", 0))
	var max_hp := float(context.get("max_hp", 1))
	if max_hp > 0.0 and hp / max_hp < RETREAT_BELOW:
		return {"intent": "RETREAT", "target": null, "say": ""}
	var nearest := _nearest_hostile(context.get("nearby", []))
	if not nearest.is_empty() and int(nearest["distance"]) <= ATTACK_RANGE:
		return {"intent": "ATTACK", "target": nearest["name"], "say": ""}
	return {"intent": "FOLLOW", "target": null, "say": ""}


static func _nearest_hostile(nearby: Variant) -> Dictionary:
	var best := {}
	if nearby is not Array:
		return best
	for entry in nearby:
		if entry is not Dictionary or not entry.get("hostile", false):
			continue
		var distance := maxi(absi(int(entry.get("dx", 0))), absi(int(entry.get("dy", 0))))
		if best.is_empty() or distance < int(best["distance"]):
			best = {"name": str(entry.get("name", "")), "distance": distance}
	return best
