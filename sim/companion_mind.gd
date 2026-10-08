class_name CompanionMind
extends RefCounted
## What decides a companion's intent. A mind only ever answers a question;
## it never touches positions, damage, or anything else in the sim. The
## companion validates the answer against the intent whitelist and the live
## world before acting on it (see docs/design.md, "The mind never acts").
##
## decide() is asked on a decision window with a context Dictionary:
## The player a companion belongs to is, in everything its mind reads, its
## companion, by name: never an owner.
##   card            personality card (String)
##   together        "Jeff is your companion. You travel together by choice."
##   log             the party log's tail, repeats collapsed (Array[String])
##   nearby          [{name, type, dx, dy, hostile, hp, max_hp}], at most 6
##   hp, max_hp, stamina, max_stamina
##   companion       {name, hp, max_hp, stamina, max_stamina, dx, dy} or {}
##   intent          the current intent name
##   trigger         why it is asked now ("" on an ordinary window); for a
##                   bump, "Jeff bumped into you", with
##   companion_direction {dx, dy}: the way they were walking ({} otherwise)
##   free_cells      [{dx, dy}]: free cells next to it ([] otherwise)
##   recent_hits     [{on: "you"|"Jeff", by, amount, cause, ticks_ago}]
##   companion_said  what they just said, with trigger "Jeff just said to
##                   you" ("" otherwise)
## It answers {"intent": String, "target": String|null, "say": String,
## optionally "why": String}, or {} when it has no answer right now (an
## async mind still waiting): then the companion's last decision stands,
## and only a companion with none yet takes the scripted mind's answer.

## For the console and logs: "scripted", "ollama".
var kind := "mind"


func decide(_context: Dictionary) -> Dictionary:
	return {}


## Called every tick: the requests that came back since, answered or not
## ({prompt, trigger, raw, answer, error, latency_ms}); [] for a mind that
## answers at once.
func take_results() -> Array[Dictionary]:
	return []
