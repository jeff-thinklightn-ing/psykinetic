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
	traits["look"] = roll_look(player_id, traits)
	traits["leanings"] = roll_leanings(player_id, traits)
	return traits


## Her leanings that weigh what she hears (decision 442, as a resident's,
## 378): each 1..10.
const LEANINGS: Array[String] = ["intellect", "superstition"]


## Her leanings, rolled for the companion of [param player_id] by a seed of
## their own (her traits' roll is as it was): {intellect, superstition};
## one from before (the table's legacy) has her fixed ones ("leanings").
static func roll_leanings(player_id: String, traits: Dictionary) -> Dictionary:
	var out := {}
	for key in LEANINGS:
		out[key] = leaning(traits, player_id, key)
	return out


## Her leaning [param key] ("intellect", "superstition"): a legacy one's
## fixed (they win over what was saved: one Pip, the resident and the
## companion alike), else her traits' "leanings", else rolled 1..10 by
## [param seed] (her player's id), the same every time, so a card from
## before has them with nothing saved.
## Her focus (decision 577): fighting, magic and stealth summing to 100.
const FOCUS: Array[String] = ["fight", "magic", "stealth"]


## The focus rules: companion_traits.json "focus".
static func focus_rules() -> Dictionary:
	var rules: Variant = tables().get("focus", {})
	return rules if rules is Dictionary else {}


## Her first focus from [param traits]: the legacy three's fixed ones, else
## even, moved by her profession's and temper's lean ("a hunter" to
## stealth), whole numbers summing to 100.
static func roll_focus(traits: Dictionary) -> Dictionary:
	var rules := focus_rules()
	var fixed: Variant = rules.get("legacy", {}).get(str(traits.get("name", "")))
	var raw := {"fight": 100.0 / 3, "magic": 100.0 / 3, "stealth": 100.0 / 3}
	if fixed is Dictionary:
		for kind in FOCUS:
			raw[kind] = float(fixed.get(kind, 0))
	else:
		for key in ["profession", "temperament"]:
			var lean: Variant = rules.get("lean", {}).get(str(traits.get(key, "")))
			if lean is Dictionary:
				for kind: String in lean:
					if kind in FOCUS:
						raw[kind] += float(lean[kind])
	return _whole(raw, float(rules.get("floor", 5)))


## [param focus] grown [param points] toward [param kind], the same taken
## from the other two in proportion to what they hold above the floor: a
## new focus (decision 577; Jeff: "growing positively can pull from the
## others"), to a tenth.
static func grow_focus(focus: Dictionary, kind: String, points: float) -> Dictionary:
	var floor_at := float(focus_rules().get("floor", 5))
	var out := {}
	for each in FOCUS:
		out[each] = float(focus.get(each, 100.0 / 3))
	var others := FOCUS.filter(func(each: String) -> bool: return each != kind)
	var spare := 0.0
	for each: String in others:
		spare += maxf(out[each] - floor_at, 0.0)
	var gain := minf(points, spare)
	if kind not in FOCUS or gain <= 0.0:
		return out
	out[kind] += gain
	for each: String in others:
		out[each] -= gain * maxf(out[each] - floor_at, 0.0) / spare
	for each in FOCUS:
		out[each] = snappedf(out[each], 0.1)
	# What the tenths left over: on the one grown.
	out[kind] = snappedf(100.0 - float(out[others[0]]) - float(out[others[1]]), 0.1)
	return out


## The focus she leans to: one at lean_at or above, "" for none.
static func lean_of(focus: Dictionary) -> String:
	var at := float(focus_rules().get("lean_at", 45))
	for kind in FOCUS:
		if float(focus.get(kind, 0)) >= at:
			return kind
	return ""


## [param raw] as whole numbers, none under [param floor_at], summing to 100.
static func _whole(raw: Dictionary, floor_at: float) -> Dictionary:
	var total := 0.0
	for kind in FOCUS:
		raw[kind] = maxf(float(raw[kind]), floor_at)
		total += raw[kind]
	var out := {}
	var given := 0
	for kind in FOCUS:
		out[kind] = roundi(float(raw[kind]) * 100.0 / total)
		given += out[kind]
	# Rounding's remainder on the largest.
	var top: String = FOCUS[0]
	for kind in FOCUS:
		if out[kind] > out[top]:
			top = kind
	out[top] += 100 - given
	return out


static func leaning(traits: Dictionary, seed: String, key: String) -> int:
	var name := str(traits.get("name", ""))
	if is_legacy(name):
		var fixed: Variant = tables()["legacy"][name].get("leanings", {})
		if fixed is Dictionary and (fixed.get(key) is int or fixed.get(key) is float):
			return clampi(int(fixed[key]), 1, 10)
	var own: Variant = traits.get("leanings", {}).get(key) if traits.get("leanings") is Dictionary else null
	if own is int or own is float:
		return clampi(int(own), 1, 10)
	return 1 + absi(hash("%s:%s" % [key, seed])) % 10


## How she looks (pc-character's look keys, agreed with npc): each key's
## values, her look rolled from them with her traits; what is not here
## (headwear, apron, skin) the view takes from her seed.
const LOOKS := {
	"build": ["lean", "middling", "heavy"],
	"stature": ["short", "middling", "tall"],
	"age": ["young", "grown", "old"],
	"posture": ["straight", "stooped", "slouching"],
	"shoulders": ["narrow", "middling", "broad"],
	"hair": ["cropped", "bound", "long", "bald"],
	"hair_colour": ["black", "dark", "brown", "chestnut", "fair", "blond", "red", "grey"],
	"beard": ["none", "short", "full"],
}


## Her look, rolled for the companion of [param player_id] by a seed of its
## own (the traits' roll is as it was): {build, stature, ...}; a female
## body has no beard, and grey hair only when old. One from before (the
## table's legacy) has her fixed look ("look" in her entry).
static func roll_look(player_id: String, traits: Dictionary) -> Dictionary:
	var fixed := legacy_look(str(traits.get("name", "")))
	if not fixed.is_empty():
		return fixed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("look:" + player_id)
	var look := {}
	for key: String in LOOKS:
		var options: Array = LOOKS[key]
		look[key] = options[rng.randi_range(0, options.size() - 1)]
	if str(traits.get("body", "")) == "female":
		look["beard"] = "none"
	if look["hair_colour"] == "grey" and look["age"] != "old":
		look["hair_colour"] = "dark"
	return look


## The fixed look of one from before named [param name] (her legacy
## entry's "look"), {} for none.
static func legacy_look(name: String) -> Dictionary:
	if not is_legacy(name):
		return {}
	var fixed: Variant = tables()["legacy"][name].get("look", {})
	return fixed.duplicate() if fixed is Dictionary else {}


## Her look as the view reads it (spec["look"], pc-character's PersonLook):
## "seed=48213 body=female build=lean ...", her seed (her card's, of
## [param seed], her player's id) and body first, then her look's keys
## (her traits' "look", else a legacy one's fixed look); a card from before
## the look has seed and body alone, the rest the seed's.
static func look_of(traits: Dictionary, seed: String) -> String:
	var parts: Array[String] = ["seed=%d" % absi(hash("companion:" + seed)), "body=%s" % body_of(traits, seed)]
	var look: Variant = traits.get("look", {})
	if not look is Dictionary or look.is_empty():
		look = legacy_look(str(traits.get("name", "")))
	for key: String in LOOKS:
		if look.has(key) and str(look[key]) in LOOKS[key]:
			parts.append("%s=%s" % [key, look[key]])
	return " ".join(parts)


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
		if key not in KEYS and key not in ["name", "trade", "body", "look", "leanings"]:
			lines.append("%s: %s" % [key.capitalize(), traits[key]])
	for key in KEYS:
		if key == "how_we_met":
			lines.append("How they met: %s" % met(traits, player))
		elif key == "pronoun":
			lines.append("Pronoun: %s" % traits.get(key, "she"))
		else:
			lines.append("%s: %s" % [key.capitalize(), traits.get(key, "")])
	return "\n".join(lines)
