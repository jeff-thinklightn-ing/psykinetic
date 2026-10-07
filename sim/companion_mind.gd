class_name CompanionMind
extends RefCounted
## What decides a companion's intent. A mind only ever answers a question;
## it never touches positions, damage, or anything else in the sim. The
## companion validates the answer against the intent whitelist and the live
## world before acting on it (see docs/design.md, "The mind never acts").
##
## decide() is asked on a decision window with a context Dictionary:
##   card            personality card (String)
##   log             last 20 party-log sentences (Array[String])
##   nearby          [{name, type, dx, dy, hostile}] within sight
##   hp, max_hp, stamina, max_stamina
##   owner           {name, hp, max_hp, stamina, max_stamina, dx, dy} or {}
##   last_order      "" | "follow" | "hold" | "attack" | "fallback"
##   order_target    name of the entity the attack order meant, or ""
##   intent          the current intent name
##   trigger         why it is asked now ("" on an ordinary window); for a
##                   bump, "owner bumped into you", with
##   owner_direction {dx, dy}: the way the owner was walking ({} otherwise)
##   free_cells      [{dx, dy}]: free cells next to it ([] otherwise)
## and answers {"intent": String, "target": String|null, "say": String},
## or {} when it has no answer right now (an async mind still waiting), in
## which case the scripted mind's answer is used for that window.

## For the console and logs: "scripted", "ollama".
var kind := "mind"


func decide(_context: Dictionary) -> Dictionary:
	return {}


## Called every tick: an answer that arrived since, or {}.
func poll() -> Dictionary:
	return {}
