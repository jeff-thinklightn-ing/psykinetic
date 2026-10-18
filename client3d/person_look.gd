class_name PersonLook
extends RefCounted
## A person's look (decision pending: the character generator's game side):
## what tools/body_gen.py's bodies are drawn as for one person, made from
## their spawn spec's "look", space-separated key=value words, every one
## optional:
##   seed=48213 body=female build=heavy stature=tall age=old posture=stooped
##   hair=long hair_colour=grey beard=none headwear=hood apron=yes skin=3
##   shoulders=broad
## and people=orc or people=kobold (decision 478): one of the Blood Rot's
## allies (orc.glb, kobold.glb), drawn in its people's own skins (PEOPLE_SKINS,
## the Blood Rot's greens), wearing only its people's parts (an orc its hair
## or none, a kobold its miner's cap or none), in its people's posture.
## A word missing (or a value not known) is decided by the seed, the same on
## every client; a key not known is passed over, so words can be added later.
## The look gives the body (male or female), its shape keys' values, its
## stature (the whole model's scale), the parts it wears (body_gen's
## WEARABLES, by mesh name), its colours and its posture.

const BUILDS := ["lean", "middling", "middling", "heavy"]
const STATURES := ["short", "middling", "middling", "tall"]
const AGES := ["young", "grown", "grown", "old"]
## A stature's scale, give or take STATURE_SPREAD.
const STATURE_SCALE := {"short": 0.92, "middling": 1.0, "tall": 1.06}
const STATURE_SPREAD := 0.02
## A named build or age: its key at this, give or take KEY_SPREAD.
const BUILD_KEY := 0.6
const AGE_KEY := 0.8
const KEY_SPREAD := 0.15
## Broad or narrow shoulders up to this, either way; hips up to these (a man, a woman).
const SHOULDERS_MAX := 0.6
const HIPS_MAX := {"male": 0.5, "female": 0.9}
## Skin tones, lightest to darkest (skin=1..8); hair colours by name.
const SKINS := ["f1d3bd", "e3b99c", "d4a585", "c49075", "a97a5a", "8f6446", "74503a", "5a3a2a"]
const HAIR_COLOURS := {"black": "1f1a17", "dark": "3b2a20", "brown": "564135", "chestnut": "7a5232",
	"fair": "a0703e", "blond": "c8a060", "red": "8a3a20", "grey": "b0aca4"}
## How likely an old person's unnamed hair is grey.
const OLD_GREY := 0.7
## Clothes when the look gives none (a player's tunic is their colour instead).
const TUNICS := ["838065", "6b7a8a", "8a5a4a", "5f6e4e", "9a8a6a", "6a5a7a"]
const TROUSERS := ["533e2d", "3f3a34", "4a4a3e", "5a4632"]
## Hair styles by body, as the seed picks them (bald among a man's, more so old).
const HAIR_STYLES := {"male": ["cropped", "cropped", "long", "bald"], "female": ["bound", "bound", "long"]}
const HAIR_PARTS := {"cropped": "Hair_Cropped", "bound": "Hair_Bound", "long": "Hair_Long", "bald": ""}
const BEARD_PARTS := {"none": "", "short": "Beard_Short", "full": "Beard_Full"}
const HEADWEAR_PARTS := {"none": "", "hood": "Hood", "hat": "Hat_Brimmed"}
## How likely an unnamed beard (a grown or old man's), and which.
const BEARD_CHANCE := 0.5
## How likely unnamed headwear is a hood, a hat.
const HOOD_CHANCE := 0.1
const HAT_CHANCE := 0.12
const POSTURES := ["straight", "stooped", "slouching"]
## An ally's skins (decision 478), tints of the Blood Rot's green, and hair.
const PEOPLE_SKINS := {"orc": ["6f8a4a", "5f7a40", "7d9152", "56703c", "68804a"],
	"kobold": ["7f8a52", "8a8a4a", "6e7d48", "93955a", "77854e"]}
const PEOPLE_HAIR := "1f1a17"
## An orc's hair: cropped, bound (a topknot) or none.
const ORC_HAIR := ["cropped", "bound", "bald"]
## How likely a kobold wears its miner's cap.
const KOBOLD_CAP_CHANCE := 0.6
## An ally's posture: an orc's slouch, a kobold's crouch.
const PEOPLE_POSTURES := {"orc": "slouching", "kobold": "stooped"}
## How likely an old person with no posture named stoops.
const OLD_STOOPED := 0.3

## What a player may choose for their look (the options panel's Character
## section; Net.tidy_look keeps only these): each key's values; seed's empty
## list, a whole number.
const PLAYER_CHOICES := {
	"seed": [],
	"build": ["lean", "middling", "heavy"],
	"stature": ["short", "middling", "tall"],
	"hair": ["cropped", "bound", "long", "bald"],
	"hair_colour": ["black", "dark", "brown", "chestnut", "fair", "blond", "red", "grey"],
	"beard": ["none", "short", "full"],
	"skin": ["1", "2", "3", "4", "5", "6", "7", "8"],
}

var seed := 0
var body := &"male"
## "human", "orc" or "kobold" (decision 478).
var people := "human"
var words := {}
## Shape key name -> value (0..1).
var keys := {}
var scale := 1.0
## The parts it wears, by mesh name (body_gen's WEARABLES).
var parts: Array[String] = []
## skin, hair, tunic, trousers -> colour.
var colours := {}
var posture := "straight"
## Its words as they came out, said or seeded (the Character section shows them).
var build := ""
var stature := ""
var age := ""
var hair := ""
var hair_colour := ""
var beard := ""
var skin := 1


## The look [param look] gives; [param body_by_default] when it names none
## (the pronoun's body, CompanionCard.body_of's rule), else the seed's.
static func make(look: String, body_by_default := &"") -> PersonLook:
	var out := PersonLook.new()
	for word in look.split(" ", false):
		var pair := word.split("=")
		if pair.size() == 2:
			out.words[pair[0]] = pair[1]
	out.seed = int(out.words.get("seed", "0"))
	out._resolve(body_by_default)
	return out


func _word(key: String, known: Array, rng: RandomNumberGenerator, choices: Array) -> String:
	var said := str(words.get(key, ""))
	var picked: String = choices[rng.randi() % choices.size()]  # Drawn whether used or not, so later words keep their draws.
	return said if said in known else picked


func _resolve(body_by_default: StringName) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var said_body := str(words.get("body", ""))
	var body_roll := rng.randf()
	if said_body in ["male", "female"]:
		body = StringName(said_body)
	elif body_by_default != &"":
		body = body_by_default
	else:
		body = &"male" if body_roll < 0.5 else &"female"
	build = _word("build", ["lean", "middling", "heavy"], rng, BUILDS)
	stature = _word("stature", ["short", "middling", "tall"], rng, STATURES)
	age = _word("age", ["young", "grown", "old"], rng, AGES)
	if build != "middling":
		keys[build] = BUILD_KEY + rng.randf_range(-KEY_SPREAD, KEY_SPREAD)
	else:
		rng.randf()
	if age != "grown":
		keys[age] = AGE_KEY + rng.randf_range(-KEY_SPREAD, KEY_SPREAD)
	else:
		rng.randf()
	# Shoulders: named broad or narrow, that key at a seeded share of SHOULDERS_MAX
	# (at least half); middling or unnamed, a seeded little either way.
	var shoulders := rng.randf_range(-1.0, 1.0)
	var said_shoulders := str(words.get("shoulders", ""))
	if said_shoulders == "broad" or said_shoulders == "narrow":
		keys[said_shoulders] = (0.5 + 0.5 * absf(shoulders)) * SHOULDERS_MAX
	else:
		keys["broad" if shoulders > 0.0 else "narrow"] = absf(shoulders) * SHOULDERS_MAX * (0.5 if said_shoulders == "middling" else 1.0)
	keys["hips"] = rng.randf_range(0.0, HIPS_MAX[String(body)])
	scale = STATURE_SCALE[stature] + rng.randf_range(-STATURE_SPREAD, STATURE_SPREAD)
	# Colours.
	var skin_index := rng.randi() % SKINS.size()
	if str(words.get("skin", "")).is_valid_int():
		skin_index = clampi(int(words["skin"]) - 1, 0, SKINS.size() - 1)
	colours["skin"] = Color(SKINS[skin_index])
	skin = skin_index + 1
	var grey_roll := rng.randf()
	var grey := age == "old" and grey_roll < OLD_GREY
	var hair_name: String = HAIR_COLOURS.keys()[rng.randi() % (HAIR_COLOURS.size() - 1)]  # Any but grey.
	if grey:
		hair_name = "grey"
	if str(words.get("hair_colour", "")) in HAIR_COLOURS:
		hair_name = str(words["hair_colour"])
	colours["hair"] = Color(HAIR_COLOURS[hair_name])
	hair_colour = hair_name
	colours["tunic"] = Color(TUNICS[rng.randi() % TUNICS.size()])
	colours["trousers"] = Color(TROUSERS[rng.randi() % TROUSERS.size()])
	# Parts.
	var styles: Array = HAIR_STYLES[String(body)]
	hair = _word("hair", HAIR_PARTS.keys(), rng, styles)
	var beard_roll := rng.randf()
	beard = "none"
	if body == &"male" and age != "young" and beard_roll < BEARD_CHANCE:
		beard = "short" if rng.randf() < 0.5 else "full"
	else:
		rng.randf()
	if str(words.get("beard", "")) in BEARD_PARTS:
		beard = str(words["beard"])
	var headwear_roll := rng.randf()
	var headwear := str(words.get("headwear", ""))
	if not headwear in HEADWEAR_PARTS:
		headwear = "hood" if headwear_roll < HOOD_CHANCE else ("hat" if headwear_roll < HOOD_CHANCE + HAT_CHANCE else "none")
	parts.clear()
	# A hood is worn over the hair: the hair is not drawn under it.
	if HAIR_PARTS[hair] != "" and headwear != "hood":
		parts.append(HAIR_PARTS[hair])
	for part: String in [BEARD_PARTS[beard], HEADWEAR_PARTS[headwear]]:
		if part != "":
			parts.append(part)
	if str(words.get("apron", "")) == "yes":
		parts.append("Apron")
	var said_posture := str(words.get("posture", ""))
	var stoop_roll := rng.randf()
	posture = said_posture if said_posture in POSTURES else ("stooped" if age == "old" and stoop_roll < OLD_STOOPED else "straight")
	var said_people := str(words.get("people", ""))
	if said_people in PEOPLE_SKINS:
		_ally(said_people, rng)


## As one of [param said]'s people (decision 478), after the rest is drawn (so
## a person's draws are the same with or without this): one body, its
## people's skin and parts, its posture; no beard, no apron.
func _ally(said: String, rng: RandomNumberGenerator) -> void:
	people = said
	body = &"male"
	keys.erase("hips")
	var skins: Array = PEOPLE_SKINS[people]
	skin = rng.randi() % skins.size() + 1
	colours["skin"] = Color(skins[skin - 1])
	colours["hair"] = Color(PEOPLE_HAIR)
	hair_colour = "black"
	beard = "none"
	parts.clear()
	if people == "orc":
		hair = ORC_HAIR[rng.randi() % ORC_HAIR.size()]
		if HAIR_PARTS[hair] != "":
			parts.append(HAIR_PARTS[hair])
	else:
		hair = "bald"
		if rng.randf() < KOBOLD_CAP_CHANCE:
			parts.append("Cap_Candle")
	posture = str(words.get("posture", "")) if str(words.get("posture", "")) in POSTURES else PEOPLE_POSTURES[people]


## [param scene] (a body_gen body, as body_build made it) drawn as this look:
## its shape keys set, only the parts it wears shown, its colours on the
## body's instance uniforms (the tunic [param tunic] unless that is white).
## The scale is the caller's (the puppet's model scale).
func apply(scene: Node3D, tunic := Color.WHITE) -> void:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh.name != "Body":
			mesh.visible = String(mesh.name) in parts
		var shapes := mesh.mesh as ArrayMesh
		if shapes != null:
			for i in shapes.get_blend_shape_count():
				mesh.set_blend_shape_value(i, float(keys.get(String(shapes.get_blend_shape_name(i)), 0.0)))
		for part: String in colours:
			mesh.set_instance_shader_parameter(part, colours[part])
		if tunic != Color.WHITE:
			mesh.set_instance_shader_parameter("tunic", tunic)
