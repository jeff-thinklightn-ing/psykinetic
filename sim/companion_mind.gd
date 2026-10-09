class_name CompanionMind
extends RefCounted
## What sets a companion's stance and speaks for her. A mind only ever
## answers a question; it never touches positions, damage, or anything
## else in the sim. The companion's hands (Companion._act) carry out the
## stance every tick, and the companion checks every answer (see
## docs/design.md, "The mind never acts").
##
## Two asks, each a Dictionary with kind, serial, trigger, system and user
## (the prompt's two messages, as text), and for a mind that reads facts
## rather than text hp, max_hp, spoken_to and heard:
##   stance(ask)  on an event that matters: answers {"stance": name} (one
##                of Companion.STANCE_NAMES), optionally "why".
##   voice(ask)   at a speaking moment: answers {"say": line or "",
##                "stance": name or ""}, optionally "why".
##   check(ask)   the instruction check, on her player's words alone (user):
##                answers {"asked": true} if they ask her to change how she
##                fights or moves with them, {"asked": false} otherwise.
## Either answers {} when its answer comes later, through take_results().
## The player a companion travels with is named in what it reads, never
## called an owner or a companion.

## For the console and logs: "scripted", "ollama".
var kind := "mind"


func stance(_ask: Dictionary) -> Dictionary:
	return {}


func voice(_ask: Dictionary) -> Dictionary:
	return {}


func check(_ask: Dictionary) -> Dictionary:
	return {}


## Whether an ask of [param _what] ("stance", "voice") is still out; a busy
## kind is asked again by the companion once it is free.
func busy(_what: String) -> bool:
	return false


## Called every tick: the asks that came back since, answered or not
## ({kind, serial, prompt, trigger, raw, answer, error, latency_ms,
## spoken_to}); [] for a mind that answers at once.
func take_results() -> Array[Dictionary]:
	return []
