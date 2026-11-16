extends RefCounted
## The pinned looks (pc-character, the tail and the long beard): what a seed
## and a worker id draw, as lines, so a change to PersonLook or ResidentCard
## shows who it changes. Written once from main (tests/look_pins.txt) and
## checked by view_world_test's _test_look_pins: every line the same, but for
## the two words the rule allows. The same file runs on a checkout without
## the two words (EXTRAS_OFF read from the class if it has it), so main's
## lines and the take's come from one function.
##   L <seed> <body> <hair> <beard> <parts> | <the rest's md5>   a seed alone
##   R <seed> <body> <hair> <beard> <parts> | <md5>               a robber's look (always hooded)
##   P <seed> | <md5 of everything>                         a player's: never changes
##   C <worker id> <name> <pronoun> <hair> <beard> | <md5> a resident's card, look's hair and beard apart
## Write: a scene whose node calls lines() (autoloads loaded), into tests/look_pins.txt.

const LOOKS := 2000
const ROBBERS := 1000
const PLAYERS := 400
const CARDS := 2000
const NAMES := ["Bran", "Maud", "Alder", "Hob", "Isolde", "Rowan", "Odo", "Edda", "Pike", "Tamsin"]
const ROBBER := "headwear=hood garb=none apron=no clothes=grave"
const PLAYER := "headwear=none apron=no garb=none"


static func lines() -> PackedStringArray:
	var out := PackedStringArray()
	var off := str(load("res://client3d/person_look.gd").get_script_constant_map().get("EXTRAS_OFF", ""))
	for i in LOOKS:
		out.append("L %s" % _look_line(_seed(i), ""))
	for i in ROBBERS:
		out.append("R %s" % _look_line(_seed(LOOKS + i), " " + ROBBER))  # Seeds of their own: a sample apart from the L lines.
	for i in PLAYERS:
		var seed := _seed(LOOKS + ROBBERS + i)
		out.append("P %d | %s" % [seed, _md5(PersonLook.make("seed=%d %s%s" % [seed, PLAYER, off]), [])])
	for i in CARDS:
		var id := "pin-%d" % i
		var name: String = NAMES[i % NAMES.size()]
		var card := ResidentCard.roll(id, name, "farmer")
		var look: Dictionary = card["look"]
		var rest := card.duplicate(true)
		(rest["look"] as Dictionary).erase("hair")
		(rest["look"] as Dictionary).erase("beard")
		out.append("C %s %s %s %s %s | %s" % [id, name, card["traits"]["pronoun"], str(look.get("hair", "")).replace(" ", "_"),
			look.get("beard", ""), JSON.stringify(rest, "", true).md5_text()])
	return out


static func _seed(i: int) -> int:
	return absi(hash(("pin:%d" % i).sha256_text()))  # Spread (a short string's hash runs on by one).


static func _look_line(seed: int, words: String) -> String:
	var look := PersonLook.make("seed=%d%s" % [seed, words])
	return "%d %s %s %s %s | %s" % [seed, look.body, look.hair, look.beard, ",".join(look.parts), _md5(look, ["hair", "beard", "parts"])]


## Every drawn field of [param look] but its words and [param apart], keys sorted.
static func _md5(look: PersonLook, apart: Array) -> String:
	var said := PackedStringArray()
	var names := PackedStringArray()
	for prop: Dictionary in look.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and not str(prop["name"]) in apart and str(prop["name"]) != "words":
			names.append(str(prop["name"]))
	names.sort()
	for name in names:
		said.append("%s=%s" % [name, _sorted(look.get(name))])
	return " ".join(said).md5_text()


static func _sorted(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var parts := PackedStringArray()
		for key: Variant in keys:
			parts.append("%s:%s" % [key, _sorted(value[key])])
		return "{" + ",".join(parts) + "}"
	return var_to_str(value)
