class_name CompanionFacts
extends RefCounted
## What has become true of a companion since her card was written
## (decision 294): facts about her and her own past, from what she
## witnessed (written from templates, no model) and from what was said with
## her player (one cheap call after a stretch of talk, Companion._extract);
## and her beliefs about the world, kept apart: Lore owns what is true of
## the world, and nothing here is written to levels/lore. Every entry is a
## plain third-person sentence, never transcript. Per player's companion,
## saved in her record ("facts", "beliefs"). The earliest fact stands: the
## extraction is shown what is already true and drops what contradicts it,
## and her voice is told her facts as true. Caps and the prompt budget are
## data (companion_traits.json "growth").

## The extraction, after a stretch of talk: what is now true of her.
const EXTRACT_SYSTEM := """You keep the record of a character in a story: what is true of %s, who travels with %s.
You are given what is already true of her, what she believes, and a stretch of what was just said between them.
List anything new that is now true of %s and her own past, people she knows, what she likes, fears or thinks: things she
said of herself, or that %s said of her and she went along with. Leave out what %s said that she did not take up,
and anything said in jest or out of the story. Leave out anything already listed, and anything that goes against
what is already true. What either of them claims about the world itself (places, peoples, history, the land) is not
a fact about her. Under beliefs put only what someone else told her about the world and she took up, never her own words.
What she says she does not know, has not seen or does not recognise is neither a fact nor a belief: leave it out. Nothing
may go against what is true of the world. Write each as one plain sentence in the third
person, naming her. Usually there is nothing new. Reply with one JSON object and nothing else:
{"facts": ["..."], "beliefs": ["..."]}."""
## The merge, when her facts are over the cap: the oldest of what she
## witnessed told as a short history.
const MERGE_SYSTEM := """You keep the record of a character in a story. Tell these things that happened to %s as her history,
in two or three plain sentences in the third person, keeping what matters most. Reply with one JSON object and
nothing else: {"facts": ["<the history>"]}."""
## Her not knowing, which is never a fact or a belief (decision 400: "I
## don't know who Pip is" became "Wren has not seen Pip before", against
## lore, and "she does not know what a stag is" a belief): dropped when
## proposed in talk and when her record loads (talk entries only).
const NOT_KNOWING := "(?i)\\b(does not|doesn't|did not|didn't|has not|hasn't|have not|haven't|had not|cannot|can't) (know|knew|seen|see|saw|met|meet|heard of|recogni[sz]e\\w*|remember\\w*)\\b|\\bnever (met|heard of|knew)\\b|\\bunfamiliar\\b|\\bnot familiar\\b|\\bnew to her\\b|\\bwonders? (who|what)\\b|\\bwho (that|he|she|they) (is|was|are|were)\\b|\\bunknown to her\\b"
## Most a call may add, and the longest an entry is.
const PER_CALL := 4
const ENTRY_MAX := 200

## {id, text, from ("event", "talk", "history"), when (unix time), player
## (her player's id when it was written)}, oldest first.
var facts: Array[Dictionary] = []
## {id, text, when, player}, oldest first.
var beliefs: Array[Dictionary] = []
var _next := 1


static func growth() -> Dictionary:
	var table: Variant = CompanionCard.tables().get("growth", {})
	return table if table is Dictionary else {}


static func setting(key: String, otherwise: int) -> int:
	return int(growth().get(key, otherwise))


## From her record's arrays (anything malformed left out).
static func from_record(saved_facts: Variant, saved_beliefs: Variant) -> CompanionFacts:
	var made := CompanionFacts.new()
	made.facts = _entries(saved_facts)
	made.beliefs = _entries(saved_beliefs)
	for entry in made.facts + made.beliefs:
		made._next = maxi(made._next, int(str(entry["id"]).trim_prefix("f").trim_prefix("b")) + 1)
	return made


static func _entries(saved: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if saved is Array:
		for entry: Variant in saved:
			if entry is Dictionary and str(entry.get("text", "")) != "" and not (str(entry.get("from", "talk")) == "talk" and not_knowing(str(entry["text"]))):
				out.append({"id": str(entry.get("id", "")), "text": str(entry["text"]), "from": str(entry.get("from", "talk")),
					"when": int(entry.get("when", 0)), "player": str(entry.get("player", ""))})
	return out


## [param text] as a fact (from "event", "talk" or "history") unless it is
## not one (empty, too long, speech) or is already known. The new entry,
## or {}.
func add_fact(text: String, from: String, player_id: String) -> Dictionary:
	return _add(facts, "f", text, from, player_id)


func add_belief(text: String, player_id: String) -> Dictionary:
	var added := _add(beliefs, "b", text, "talk", player_id)
	while beliefs.size() > setting("beliefs_max", 8):
		beliefs.pop_front()
	return added


## Whether [param text] says only that she does not know (NOT_KNOWING).
static func not_knowing(text: String) -> bool:
	return RegEx.create_from_string(NOT_KNOWING).search(text) != null


func _add(into: Array[Dictionary], prefix: String, text: String, from: String, player_id: String) -> Dictionary:
	var said := text.strip_edges()
	if said.is_empty() or said.length() > ENTRY_MAX or said.contains("\"") or said.contains("“"):
		return {}
	if from == "talk" and not_knowing(said):
		return {}
	if not said.ends_with(".") and not said.ends_with("!") and not said.ends_with("?"):
		said += "."
	var plain := Companion._plain(said)
	var known: Array[String] = []
	for entry in facts + beliefs:
		known.append(Companion._plain(str(entry["text"])))
	if plain in known or Companion.near_repeat(plain, known):
		return {}
	var entry := {"id": "%s%d" % [prefix, _next], "text": said, "from": from,
		"when": int(Time.get_unix_time_from_system()), "player": player_id}
	_next += 1
	into.append(entry)
	return entry


## Over the cap: the oldest witnessed facts that a merge would fold into
## a history (all but the newest event_facts_shown), or [] if within it.
func to_merge() -> Array[Dictionary]:
	if facts.size() <= setting("facts_max", 24):
		return []
	var events := facts.filter(func(entry: Dictionary) -> bool: return entry["from"] == "event")
	return events.slice(0, maxi(events.size() - setting("event_facts_shown", 6), 0))


## The merge came back: [param merged] replaced by one history fact.
func merge(merged: Array[Dictionary], history: String, player_id: String) -> bool:
	var ids := merged.map(func(entry: Dictionary) -> String: return entry["id"])
	var kept := facts.filter(func(entry: Dictionary) -> bool: return entry["id"] not in ids)
	var before := facts.duplicate()
	facts.assign(kept)
	if add_fact(history, "history", player_id).is_empty():
		facts.assign(before)
		return false
	return true


## Without a merge (no model to write one): the oldest witnessed facts go
## until her facts are within the cap; talk facts stay as long as can be.
func trim() -> void:
	while facts.size() > setting("facts_max", 24):
		var oldest := -1
		for i in facts.size():
			if facts[i]["from"] == "event":
				oldest = i
				break
		facts.remove_at(oldest if oldest >= 0 else 0)


## What her voice is told, after her card: what is true of her (her talk
## facts and history first, then her newest witnessed facts), and what she
## believes, within prompt_chars; "" for nothing.
func prompt_words() -> String:
	var budget := setting("prompt_chars", 700)
	var events := facts.filter(func(entry: Dictionary) -> bool: return entry["from"] == "event")
	var chosen: Array[String] = []
	for entry in facts:
		if entry["from"] != "event":
			chosen.append(str(entry["text"]))
	for entry: Dictionary in events.slice(maxi(events.size() - setting("event_facts_shown", 6), 0)):
		chosen.append(str(entry["text"]))
	while not chosen.is_empty() and " ".join(chosen).length() > budget:
		chosen.pop_front()
	var held: Array[String] = []
	for entry in beliefs:
		held.append(str(entry["text"]))
	var parts: Array[String] = []
	if not chosen.is_empty():
		parts.append("Also true of you: %s" % " ".join(chosen))
	if not held.is_empty():
		parts.append("You believe, though it may not be so: %s" % " ".join(held))
	return " ".join(parts)


## The extraction's user message: her card, what is true and believed,
## and what was said.
func extract_prompt(card: String, lines: Array[String], world := "") -> String:
	var known: Array[String] = []
	for entry in facts:
		known.append("- " + str(entry["text"]))
	var held: Array[String] = []
	for entry in beliefs:
		held.append("- " + str(entry["text"]))
	var true_of_world := "\n\nTrue of the world, as she knows it (nothing may go against it): %s" % world.trim_prefix("What you know of the world: ") if not world.is_empty() else ""
	return "Her card: %s%s\n\nAlready true of her:\n%s\n\nShe believes:\n%s\n\nWhat was just said:\n%s" % [
		card, true_of_world, "\n".join(known) if not known.is_empty() else "- nothing more yet",
		"\n".join(held) if not held.is_empty() else "- nothing yet", "\n".join(lines)]


## One entry by id gone (the console's "companion forget"); whether it was.
func forget(id: String) -> bool:
	for list: Array[Dictionary] in [facts, beliefs]:
		for i in list.size():
			if list[i]["id"] == id:
				list.remove_at(i)
				return true
	return false
