class_name ResidentCard
extends RefCounted
## Who a town resident is (decision 398), as a companion's card is who she
## is (293/294): traits rolled once from levels/resident_traits.json by the
## worker id (the same every time), how they came to the town, what they
## look like (a "look" the character generator reads, agreed with
## pc-character), and the facts that have become true of them since, from
## events only, written from templates (a neighbour carried off or home, a
## loan, raiders at the walls, kin, a grudge). The card is kept whole on
## economy's worker record ("card", Production.set_card) by Townsfolk, which
## makes it when first needed and grows it; this class is the card itself,
## pure. The voice reads plain_card (or the one paragraph the model wrote
## once, Townsfolk's call) and facts_words. What it is told is what is true
## of them: never a line to say.
##
## A card: {traits: {pronoun, birthplace, parentage, hobby, food,
## temperament, fear, speech}, came: words, look: {seed, build, stature,
## posture, hair, hair_colour, beard, shoulders, age}, facts: [{step, text}],
## card: the written paragraph or "", card_by: "model" or ""}.

const TRAITS := "res://levels/resident_traits.json"
const KEYS: Array[String] = ["pronoun", "birthplace", "parentage", "hobby", "food", "temperament", "fear", "speech"]
const LOOK_KEYS: Array[String] = ["build", "stature", "posture", "hair", "hair_colour", "beard", "shoulders", "headwear"]
## Trades that wear an apron (the look string's "apron", decision 419).
const APRON_TRADES: Array[String] = ["smith", "cook", "carpenter", "medicine_man"]
## The look string's keys, in order, after seed and body.
const SPEC_KEYS: Array[String] = ["build", "stature", "age", "posture", "shoulders", "hair", "hair_colour", "beard", "headwear"]
## The card call: one paragraph, as JSON, from the facts given.
const CARD_SYSTEM := """You write a character card for one of a town's people in a game: who they are, from facts given. Write in the
third person with the pronoun given, in plain words, one paragraph of four to six sentences: what they are like, what they care about, how they
speak, what they fear. Use every fact; add nothing that goes against them, and name no place or person the facts do not name. Never write speech, dialogue or quotes,
and never use the words game or player. Reply with one JSON object and nothing else: {"card": "<the paragraph>"}."""

static var _tables := {}


## The tables, read once.
static func tables() -> Dictionary:
	if _tables.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRAITS)) if FileAccess.file_exists(TRAITS) else null
		_tables = data if data is Dictionary else {"_none": true}
		if not data is Dictionary:
			push_warning("[resident card] %s is missing or not a JSON object: plain cards" % TRAITS)
	return _tables


## Uses [param given] in place of the file ({} to read it again): tests.
static func use_tables(given: Dictionary) -> void:
	_tables = given.duplicate(true)


## The card rolled for the resident whose worker id is [param worker_id],
## called [param person_name], of [param trade]: each of KEYS from its
## table, how they came (came_words: the record's [param origin] when it
## tells a real rescue, [param by] who did it, else the table), and their
## look. No facts yet.
static func roll(worker_id: String, person_name: String, trade: String, origin := "", by := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("resident:" + worker_id)
	var table := tables()
	var traits := {"name": person_name, "trade": trade}
	for key: String in KEYS:
		traits[key] = _pick(table.get(key, []), rng)
	var came := _pick(table.get("came", []), rng)
	var look := _roll_look(table.get("look", {}), rng, str(traits["pronoun"]), worker_id)
	return {"traits": traits, "came": came_words(origin, by, came), "look": look, "facts": [], "card": "", "card_by": ""}


## How they came to the town: a record whose [param origin] is a rescue
## ("rescued:<x>") was brought home from captivity, [param by] whoever did
## it when known; else [param rolled], the table's words.
static func came_words(origin: String, by: String, rolled: String) -> String:
	if origin.begins_with("rescued:"):
		return "was rescued from captivity and brought home to the town%s" % (" by " + by if not by.is_empty() else "")
	return rolled


## What they look like: age first (its words), then each of LOOK_KEYS;
## grey hair twice as likely for the old; no beard for a woman. "seed" is
## the id's hash, for the details no word names (pc-character draws them).
static func _roll_look(table: Dictionary, rng: RandomNumberGenerator, pronoun: String, worker_id: String) -> Dictionary:
	var look := {"seed": absi(hash("look:" + worker_id))}
	look["age"] = _pick(table.get("age", ["grown"]), rng)
	for key: String in LOOK_KEYS:
		var options: Array = table.get(key, []).duplicate()
		if key == "hair_colour" and look["age"] == "old" and "grey" in options:
			options.append("grey")
		look[key] = _pick(options, rng)
	if pronoun == "she":
		look["beard"] = "none"
	return look


## The look as the character generator reads it (pc-character's decision
## 419, agreed with companions): space-separated key=value, every key
## optional, so a word a card lacks (an old card's headwear) or a client
## does not know is left to the seed. "seed=48213 body=female build=heavy
## stature=tall age=old posture=stooped shoulders=narrow hair=bound
## hair_colour=grey beard=none headwear=hood apron=yes": body from the
## pronoun (none for "they": the seed picks), "bound" for the card's "bound
## up", the apron from [param trade] (APRON_TRADES). "" for a card with no
## look.
static func look_spec(card: Dictionary, trade := "") -> String:
	var look: Dictionary = card.get("look", {})
	if look.is_empty():
		return ""
	var parts: Array[String] = ["seed=%d" % int(look.get("seed", 0))]
	var body: String = {"she": "female", "he": "male"}.get(str(card.get("traits", {}).get("pronoun", "")), "")
	if not body.is_empty():
		parts.append("body=" + body)
	for key: String in SPEC_KEYS:
		var word := str(look.get(key, ""))
		if word.is_empty():
			continue
		if key == "hair" and word == "bound up":
			word = "bound"
		parts.append("%s=%s" % [key, word])
	parts.append("apron=%s" % ("yes" if trade in APRON_TRADES else "no"))
	return " ".join(parts)


static func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	if options.is_empty():
		return ""
	return str(options[rng.randi_range(0, options.size() - 1)])


## The card as plain facts (before, or without, the written paragraph).
static func plain_card(card: Dictionary) -> String:
	var traits: Dictionary = card.get("traits", {})
	var she := str(traits.get("pronoun", "she"))
	var her: String = {"she": "her", "he": "his"}.get(she, "their")
	var name := str(traits.get("name", ""))
	var trade := str(traits.get("trade", ""))
	var look: Dictionary = card.get("look", {})
	var sentences: Array[String] = [
		"%s was born in %s, %s." % [name, traits.get("birthplace", "a place not far off"), traits.get("parentage", "")],
		"%s %s." % [she.capitalize(), card.get("came", "lives in the town")],
		"%s is %s, and %s." % [she.capitalize(), "a " + trade.replace("_", " ") if not trade.is_empty() else "without a trade of %s own" % her, traits.get("temperament", "")],
		"In quiet hours %s likes %s, and %s favourite food is %s." % [she, traits.get("hobby", ""), her, traits.get("food", "")],
		"%s is afraid of %s." % [she.capitalize(), traits.get("fear", "")],
		"%s speaks in %s." % [she.capitalize(), traits.get("speech", "")],
	]
	if not look.is_empty():
		var hair := "bald" if look.get("hair", "") == "bald" else "%s hair, %s" % [look.get("hair_colour", ""), look.get("hair", "")]
		var beard := ", and a %s beard" % look["beard"] if look.get("beard", "none") not in ["none", ""] else ""
		sentences.append("%s is %s, %s and %s, %s, with %s%s." % [she.capitalize(), look.get("age", "grown"), look.get("stature", "middling"),
			look.get("build", "middling"), look.get("posture", "straight"), hair, beard])
	return " ".join(sentences).replace(", .", ".").replace("..", ".")


## The card's prose for the voice: the written paragraph when there is
## one, else the plain card.
static func words(card: Dictionary) -> String:
	var written := str(card.get("card", ""))
	return written if not written.is_empty() else plain_card(card)


## The card call's user message: the facts, one a line.
static func facts(card: Dictionary) -> String:
	var traits: Dictionary = card.get("traits", {})
	var lines: Array[String] = ["name: %s" % traits.get("name", ""), "pronoun: %s" % traits.get("pronoun", "")]
	for key: String in ["birthplace", "parentage"]:
		lines.append("%s: %s" % [key, traits.get(key, "")])
	lines.append("how they came to the town: %s" % card.get("came", ""))
	lines.append("work: %s" % (str(traits.get("trade", "")).replace("_", " ") if not str(traits.get("trade", "")).is_empty() else "none"))
	for key: String in ["hobby", "food", "temperament", "fear", "speech"]:
		lines.append("%s: %s" % [key, traits.get(key, "")])
	var look: Dictionary = card.get("look", {})
	if not look.is_empty():
		lines.append("looks: %s, %s, %s, %s, %s hair %s%s" % [look.get("age", ""), look.get("stature", ""), look.get("build", ""), look.get("posture", ""),
			look.get("hair_colour", ""), look.get("hair", ""), ", a %s beard" % look["beard"] if look.get("beard", "none") not in ["none", ""] else ""])
	for fact: Dictionary in card.get("facts", []):
		lines.append("also true: %s" % fact.get("text", ""))
	return "\n".join(lines)


## A written paragraph is taken if it is one with no speech in it (as
## 293's): true and the card changed, else false and the plain card stands.
static func take_written(card: Dictionary, written: String) -> bool:
	var text := written.strip_edges()
	if text.length() < 80 or text.contains("\"") or text.contains("“"):
		return false
	card["card"] = text
	card["card_by"] = "model"
	return true


# --- What becomes true of them -----------------------------------------------------

## [param text], a plain third-person sentence naming them, is true of
## them since [param step]: added once (the same words twice are one),
## the oldest dropped past the tables' facts_max. Whether it was new.
static func add_fact(card: Dictionary, step: int, text: String) -> bool:
	var list: Array = card.get("facts", [])
	for each: Variant in list:
		if each is Dictionary and str(each.get("text", "")) == text:
			return false
	list.append({"step": step, "text": text})
	var cap := int(tables().get("growth", {}).get("facts_max", 16))
	while list.size() > cap:
		list.pop_front()
	card["facts"] = list
	return true


## The facts for the voice: the newest (the tables' shown, within
## prompt_chars), told in the order they happened, so a homecoming follows
## the raid: "Also true of <name>: ..." or "" for none.
static func facts_words(card: Dictionary) -> String:
	var list: Array = card.get("facts", [])
	if list.is_empty():
		return ""
	var growth: Dictionary = tables().get("growth", {})
	var budget := int(growth.get("prompt_chars", 600))
	var shown := int(growth.get("shown", 6))
	var out: Array[String] = []
	var used := 0
	for i in range(list.size() - 1, -1, -1):
		var text := str(list[i].get("text", ""))
		if out.size() >= shown or used + text.length() > budget:
			break
		out.append(text)
		used += text.length() + 1
	out.reverse()
	return "Also true of %s: %s" % [card.get("traits", {}).get("name", "them"), " ".join(out)]


## The two facts of kin between [param a] and [param b] (cards; b was in the
## town first): [a's, b's], by [param kind] ("sister or brother", "cousin",
## "parent and child": b the parent).
static func kin_facts(a: Dictionary, b: Dictionary, kind: String) -> Array[String]:
	var a_name := str(a.get("traits", {}).get("name", ""))
	var b_name := str(b.get("traits", {}).get("name", ""))
	var a_she := str(a.get("traits", {}).get("pronoun", "she")) == "she"
	var b_she := str(b.get("traits", {}).get("pronoun", "she")) == "she"
	match kind:
		"cousin":
			return ["%s and %s are cousins." % [a_name, b_name], "%s and %s are cousins." % [b_name, a_name]]
		"parent and child":
			var parent := "mother" if b_she else "father"
			var child := "daughter" if a_she else "son"
			return ["%s is %s's %s." % [b_name, a_name, parent], "%s is %s's %s." % [a_name, b_name, child]]
	var a_word := "sister" if a_she else "brother"
	var b_word := "sister" if b_she else "brother"
	return ["%s is %s's %s." % [a_name, b_name, a_word], "%s is %s's %s." % [b_name, a_name, b_word]]


## The fact of [param a]'s grudge against [param b] [param cause] ("over a
## dog"), the same words in both cards.
static func grudge_fact(a: Dictionary, b: Dictionary, cause: String) -> String:
	return "%s bears a grudge against %s %s." % [a.get("traits", {}).get("name", ""), b.get("traits", {}).get("name", ""), cause]


## A faction as people name it, from lore's entry ("the goblins"), else
## "the <id>" with underscores spaced.
static func faction_name(faction: String) -> String:
	var entry: Dictionary = Lore.entries().get(faction, {})
	var name := str(entry.get("name", ""))
	return name if not name.is_empty() else "the " + faction.replace("_", " ")
