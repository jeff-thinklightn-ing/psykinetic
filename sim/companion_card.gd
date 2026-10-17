class_name CompanionCard
extends RefCounted
## Who a companion is (decision 293): her traits, rolled once from
## levels/companion_traits.json when she is first given and kept in her
## record ("traits"), and the card written from them, a paragraph, by one
## call to the voice model (Companion.write_card), with one sentence of how
## she and her player met. Until that call answers, or if it never does,
## her card is plain_card: the traits said as plain facts. What she is told
## is what is true of her; never a line to say.

const TRAITS := "res://levels/companion_traits.json"
## The traits rolled, in the order the card's facts are told.
const KEYS: Array[String] = ["pronoun", "birthplace", "parentage", "profession", "hobby", "food", "temperament", "fear",
	"speech", "how_we_met"]
## The card call: one paragraph, a sentence of how they met, as JSON.
const CARD_SYSTEM := """You write a character card for a companion in a game: who she is, from facts given. Write in the
third person with the pronoun given, in plain words, one paragraph of four to six sentences: what she is like, what she cares about, how she
speaks, what she fears. Use every fact; add nothing that goes against them. Never write speech, dialogue or quotes,
and never use the words game, player or companion. Then one sentence, in the third person, of how she and %s met,
from the fact given. Reply with one JSON object and nothing else: {"card": "<the paragraph>", "how_we_met": "<the sentence>"}."""

static var _tables := {}


## The tables, read once.
static func tables() -> Dictionary:
	if _tables.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRAITS)) if FileAccess.file_exists(TRAITS) else null
		_tables = parsed if parsed is Dictionary else {"_none": true}
	return _tables


## Whether [param name] is one of the companions from before the roll
## (the table's "legacy": Wren, Nix), kept as they are; they rest in town
## between trips.
static func is_legacy(name: String) -> bool:
	var legacy: Variant = tables().get("legacy", {})
	return legacy is Dictionary and legacy.has(name) and not name.begins_with("_")


## Traits rolled for the companion of player [param player_id]: each of
## KEYS from its table, and a name unless [param keep_name] (a companion
## that has one keeps it); a name in [param taken] is rolled again. The
## same player id rolls the same. {name, pronoun, ..., profession (its
## words), trade, how_we_met (the seed, with {player} and {pronoun} in it)}.
static func roll(player_id: String, keep_name := "", taken: Array[String] = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("companion:" + player_id)
	var table := tables()
	var traits := {}
	var names: Array = table.get("name", ["Pip"])
	var name := keep_name
	if name.is_empty():
		for attempt in 20:
			name = str(names[rng.randi_range(0, names.size() - 1)])
			if name not in taken:
				break
	else:
		rng.randi()  # The same roll for the rest, named or not.
	traits["name"] = name
	for key in KEYS:
		var options: Array = table.get(key, [""])
		var picked: Variant = options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else ""
		if key == "profession" and picked is Dictionary:
			traits["profession"] = str(picked.get("words", ""))
			traits["trade"] = str(picked.get("trade", ""))
		else:
			traits[key] = str(picked)
	# One from before keeps her fixed facts; the roll fills in round them.
	if is_legacy(name):
		var fixed: Variant = table["legacy"][name].get("fixed", {})
		if fixed is Dictionary:
			for key: String in fixed:
				traits[key] = str(fixed[key])
	traits["body"] = String(body_of(traits, player_id))
	return traits


## Her body, &"male" or &"female" (decision 293 amended, for pc-character's
## Companion.body, decision 388: which body the view draws and whose voice
## her efforts have): her traits' "body" when they have one; else "he"
## male and "she" female, and "they" by [param seed] (her player's id),
## the same every time, so a record from before has one too.
static func body_of(traits: Dictionary, seed: String) -> StringName:
	var given := str(traits.get("body", ""))
	if given in ["male", "female"]:
		return StringName(given)
	match str(traits.get("pronoun", "")):
		"he":
			return &"male"
		"she":
			return &"female"
	return &"male" if absi(hash("body:" + seed)) % 2 == 0 else &"female"


## The how_we_met seed for her and [param player]: "Jeff found her hiding
## in a ruined mill".
static func met(traits: Dictionary, player: String) -> String:
	var object: String = {"she": "her", "he": "him", "they": "them"}.get(str(traits.get("pronoun", "she")), "her")
	var start := str(traits.get("how_we_met", ""))
	var said := start.replace("{player}", player)
	# At the start of the sentence it is the subject.
	said = said.replace("{pronoun} ", str(traits.get("pronoun", "she")) + " ") if start.begins_with("{pronoun}") else said
	said = said.replace("{pronoun}", object)
	return said


## Her card as plain facts, before (or without) the written one.
static func plain_card(traits: Dictionary) -> String:
	var she := str(traits.get("pronoun", "she"))
	var her: String = {"she": "her", "he": "his", "they": "their"}.get(she, "her")
	var is_ := "are" if she == "they" else "is"
	var name := str(traits.get("name", ""))
	var who := ", %s," % traits["who"] if traits.has("who") else ""
	var sentences: Array[String] = [
		"%s%s was born in %s, %s." % [name, who, traits.get("birthplace", "a place far off"), traits.get("parentage", "")],
		"%s %s %s, and %s." % [she.capitalize(), "were" if she == "they" else "was", traits.get("profession", ""), traits.get("temperament", "")],
		"In quiet hours %s like%s %s, and %s favourite food is %s." % [she, "" if she == "they" else "s", traits.get("hobby", ""), her, traits.get("food", "")],
		"%s %s afraid of %s." % [she.capitalize(), is_, traits.get("fear", "")],
		"%s speak%s in %s." % [she.capitalize(), "" if she == "they" else "s", traits.get("speech", "")],
	]
	if traits.has("aspiration"):
		var though := ", though %s" % traits["though"] if traits.has("though") else ""
		sentences.insert(2, "%s %s%s." % [she.capitalize(), traits["aspiration"], though])
	return " ".join(sentences).replace(", .", ".")


## The card call's user message: the facts, one a line.
static func facts(traits: Dictionary, player: String) -> String:
	var lines: Array[String] = ["Name: %s" % traits.get("name", "")]
	# Fixed facts beyond the table's own (who she is, what she wants).
	for key: String in traits:
		if key not in KEYS and key not in ["name", "trade", "body"]:
			lines.append("%s: %s" % [key.capitalize(), traits[key]])
	for key in KEYS:
		if key == "how_we_met":
			lines.append("How they met: %s" % met(traits, player))
		elif key == "pronoun":
			lines.append("Pronoun: %s" % traits.get(key, "she"))
		else:
			lines.append("%s: %s" % [key.capitalize(), traits.get(key, "")])
	return "\n".join(lines)
