class_name ScriptedMind
extends CompanionMind
## The rule-based mind, and the fallback for every other one. Gets out of
## the owner's way at once when they bump into it; obeys the owner's last
## order; otherwise retreats toward the owner when low on hp, attacks the
## nearest hostile within reach, and follows.

const ATTACK_RANGE := 3
const RETREAT_BELOW := 0.3


func _init() -> void:
	kind = "scripted"


func decide(context: Dictionary) -> Dictionary:
	if str(context.get("trigger", "")) == Companion.BUMPED:
		return {"intent": "YIELD", "target": null, "say": ""}
	var hp := float(context.get("hp", 0))
	var max_hp := float(context.get("max_hp", 1))
	if max_hp > 0.0 and hp / max_hp < RETREAT_BELOW:
		return {"intent": "RETREAT", "target": null, "say": ""}
	match str(context.get("last_order", "")):
		"hold":
			return {"intent": "HOLD", "target": null, "say": ""}
		"fallback":
			return {"intent": "RETREAT", "target": null, "say": ""}
		"attack":
			var ordered := str(context.get("order_target", ""))
			if not ordered.is_empty():
				return {"intent": "ATTACK", "target": ordered, "say": ""}
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
