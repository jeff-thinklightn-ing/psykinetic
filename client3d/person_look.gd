class_name PersonLook
extends RefCounted
## A person's look (decision pending: the character generator's game side):
## what tools/body_gen.py's bodies are drawn as for one person, made from
## their spawn spec's "look", space-separated key=value words, every one
## optional:
##   seed=48213 body=female build=heavy stature=tall age=old posture=stooped
##   hair=long hair_colour=grey beard=none headwear=hood apron=yes skin=3
##   shoulders=broad
## and (decision 480) garb=none|vest|coat|cape|rolled (clothes over the
## tunic), headwear=cap (a labourer's soft cap) and trade=<a resident's
## trade> (npc's look_spec writes it from the card): a trade dresses them
## (TRADE_GARB) where no garb or headwear is said, the card's own words
## winning; a person's face its own (FACE_KEYS, seeded, never said);
## clothes=forest|grave (793: a bandit's or a grave robber's tunic and
## trousers in its own colours, CLOTHES, by the same draws as a town's);
## worn=leather|mail|plate|robes (armour, a resident's: npc's look_spec;
## a player's or a companion's is their worn item, Client3D._sync_worn);
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
## Hair and beard against the skin in value (the coordinator, 11-14, the faces package): hair whose lightness (CIELAB
## L*) is nearer the skin's than HAIR_STEP is moved away from it in lightness alone (hue and chroma kept), at most
## HAIR_MOVE_MAX, and only while it stays nearer its own named colour than any other (chestnut stays chestnut);
## the skin never moves (it is what a player picked). Where both ways reach the step, the smaller move; else the way
## ending further apart. Seven pairs stop short at the cap or the name (view_test _test_hair_value lists each).
const HAIR_STEP := 16.0
## The two-light rule (the coordinator's, on the pinned probe row; heads by day): the step also judged as the game draws
## hair and face, at noon and at 19:00, with the lantern dark by day (451 amended (8)), measured off ui-design's covered
## 64-still grids (gridcov12_4f354927e, gridcov19c_67eb7783a: crown and face inside each still): a crown's drawn L* by its
## colour's L* at 0, 5 .. 100 (HAIR_LIT), and a face's drawn L* by its skin's (FACE_LIT by FACE_SKIN_L, the eight SKINS).
## A hair takes the noon-drawn move (_hair_drawn_move) in place of the palette's (_hair_palette_move) only where it
## stands further from the face at noon and no nearer at 19:00 (_hair_moved), and is not one of HAIR_KEPT; a drawn move
## stops where the drawn crown stops darkening (the knots' floor: black on the darkest skins).
const HAIR_LIT := {"noon": [20.3, 20.3, 21.7, 23.6, 27.1, 30.4, 34.9, 39.1, 43.4, 47.5, 52.2, 56.5, 61.1, 65.3, 70.1, 74.6,
	78.9, 80.0, 80.0, 80.0, 80.0], "evening": [13.7, 13.7, 14.8, 17.1, 20.9, 23.8, 27.5, 31.6, 34.5, 38.4, 41.4, 45.4, 49.5,
	53.3, 56.2, 60.9, 64.9, 65.0, 65.0, 65.0, 65.0]}
const FACE_SKIN_L := [27.8, 37.4, 46.2, 55.2, 64.1, 71.3, 78.1, 86.5]
const FACE_LIT := {"noon": [24.9, 32.3, 39.1, 46.3, 53.5, 59.2, 64.7, 71.7], "evening": [18.8, 25.1, 31.2, 37.5, 43.7, 48.6,
	53.1, 58.5]}
## Pairs (hair/skin, skin 1 the palest) that keep the palette's colour where the rule would move them, on the
## coordinator's reading of one joined run of every choice (hairtable12/19_d308a98b5): dark/8, whose lighter move came
## nearer the face in colour difference (dE2000) at both hours though the knots, reading lightness alone, said further;
## chestnut/6 and chestnut/7, whose moves went to the skin's own hue band and read as a tan cap; fair/3, brown/5, dark/6
## and brown/6, whose moves brought that skin's nearest two hair names closer than the palette's nearest pair there.
const HAIR_KEPT := ["fair/3", "brown/5", "dark/6", "brown/6", "chestnut/6", "chestnut/7", "dark/8"]
const HAIR_MOVE_MAX := 13.0
const HAIR_MOVE_GRAIN := 0.25
## What a beard's front loses beside the cheek as drawn: it faces down, out of the sun (faces7's stills on skin 7: 3.1 L* on
## Oswin's full beard, 5.2 on the brown man's short one, against each one's hairline). A beard is set this much further
## from the skin than its hair, fading out where the hair already stands HAIR_STEP + BEARD_FACING off (beard_against).
const BEARD_FACING := 5.0
## How likely an old person's unnamed hair is grey.
const OLD_GREY := 0.7
## Clothes when the look gives none (a player's tunic is their colour instead).
const TUNICS := ["838065", "6b7a8a", "8a5a4a", "5f6e4e", "9a8a6a", "6a5a7a"]
const TROUSERS := ["533e2d", "3f3a34", "4a4a3e", "5a4632"]
## clothes= (793, pc-character's side): a foe's own colours for the tunic and
## trousers in place of a town's, [tunics, trousers]. forest, the bandits':
## moss, pine, olive and bark, darker and greener than any town's; grave, the
## grave robbers' (the Mound-breakers): greys and dirt browns, no green; so the
## two, both hooded, are told apart at a glance. The hood and vest are leather,
## on the palette, the same for all.
const FOREST_TUNICS := ["4a5a32", "3e4f2e", "5a6438", "4f4a2e", "3f5236"]
const FOREST_TROUSERS := ["3a3424", "2f3a26", "4a3e2a", "35301f"]
const GRAVE_TUNICS := ["6e6a64", "5a5652", "7a6e60", "605448", "4e4a46"]
const GRAVE_TROUSERS := ["3e3a36", "4a4038", "352f2a", "524a42"]
const CLOTHES := {"forest": [FOREST_TUNICS, FOREST_TROUSERS], "grave": [GRAVE_TUNICS, GRAVE_TROUSERS]}
## Hair styles by body, as the seed picks them (bald among a man's, more so old).
const HAIR_STYLES := {"male": ["cropped", "cropped", "long", "bald"], "female": ["bound", "bound", "long"]}
const HAIR_PARTS := {"cropped": "Hair_Cropped", "bound": "Hair_Bound", "long": "Hair_Long", "bald": "", "tail": "Hair_Cropped"}
## Bound hair's top-knot (419 amended (9)): its own part beside Hair_Bound, drawn only bare-headed. It stands 4.6 cm off
## the crown, so any headwear hides it rather than make room for it: the look's own hood, cap or hat here (and a cap or
## hat put on by a trade, _wear_headwear); a worn head-slot item and a bard's hat in Client3D (HEADWEAR_MESHES).
const HAIR_KNOT := "Hair_Bun"
## What a style wears beside its cap (the tail: the cropped cap and a tail at the nape), never under a hood.
## The seed never picks it from HAIR_STYLES (unchanged, so no look's hair draw moves): a look's word, or
## TAIL_SHARE of the men the seed gave cropped hair, by a roll drawn after every other (480's way).
const HAIR_ADDED := {"tail": "Hair_Tail"}
## The share of seeded cropped men who wear the tail, and of seeded full-bearded men the long beard (1 man
## in 8 and 1 in 16), each by its own roll drawn last in _resolve; never where the look says hair or beard,
## never an ally, never a player (look_for's EXTRAS_OFF; theirs only by their own choice).
const TAIL_SHARE := 0.25
const LONG_BEARD_SHARE := 1.0 / 3.0
## Appended to a player's look by Client3D.look_for: the two last rolls switched off.
const EXTRAS_OFF := " extras=no"
const BEARD_PARTS := {"none": "", "short": "Beard_Short", "full": "Beard_Full", "long": "Beard_Long"}
const HEADWEAR_PARTS := {"none": "", "hood": "Hood", "hat": "Hat_Brimmed", "cap": "Cap_Soft"}
## Garb (decision 480): what is worn over the tunic, by word; rolled is the
## sleeves rolled to the elbows.
const GARB_PARTS := {"none": "", "vest": "Vest", "coat": "Coat", "cape": "Cape", "rolled": "Sleeves_Rolled"}
## Armour (items' 622): each look's covering, by Items.armour_of's look
## (body_gen's Armour_* parts); worn, it is shown in place of the garb
## under it (GARB_UNDER_ARMOUR, the cape too), and hair and headwear stay.
const ARMOUR_PARTS := {"leather": "Armour_Leather", "mail": "Armour_Mail", "plate": "Armour_Plate", "robes": "Armour_Robes"}
const GARB_UNDER_ARMOUR: Array[String] = ["Vest", "Coat", "Apron", "Sleeves_Rolled", "Cape"]
## How likely a person with no garb said and no trade to dress them wears
## some, and which (one of these, alike).
const GARB_CHANCE := 0.3
const GARBS := ["vest", "coat", "cape", "rolled"]
## A trade's clothes, [garb, headwear], each "" for the look's own (decision
## 480, the trades economy's and npc's records name; an unknown trade is
## plain clothes). APRON_TRADES' apron is npc's look_spec's, as before.
const TRADE_GARB := {
	"hauler": ["rolled", "cap"], "labourer": ["rolled", "cap"], "farmer": ["rolled", "hat"],
	"guard": ["vest", ""], "hunter": ["cape", ""],
	"merchant": ["coat", ""], "lawspeaker": ["coat", ""], "priest": ["coat", ""],
	"smith": ["rolled", ""], "carpenter": ["rolled", ""], "tanner": ["rolled", ""], "fletcher": ["vest", ""],
}
## The face's planes (body_gen's face keys), each a seeded 0..FACE_MAX; a
## woman's jaw and brow at most FACE_MAX_FEMALE of it.
const FACE_KEYS := ["jaw", "nose", "brow", "cheeks", "eyes"]
const FACE_MAX := 1.0
const FACE_MAX_FEMALE := {"jaw": 0.35, "brow": 0.4}
## How likely an unnamed beard (a grown or old man's), and which.
const BEARD_CHANCE := 0.5
## How likely unnamed headwear is a hood, a hat.
const HOOD_CHANCE := 0.1
const HAT_CHANCE := 0.12
const POSTURES := ["straight", "stooped", "slouching"]
## An ally's skins (decision 478): an orc's grey-blues, a kobold's light reds
## (Jeff's picks); and hair.
const PEOPLE_SKINS := {"orc": ["6a7a8c", "5f7080", "74849a", "66768a", "5a6a7c"],
	"kobold": ["c8656e", "d0707a", "b85a66", "c26a76", "d27880"]}
## A kobold's (Jeff's p1, 478 restyled): its limbs and tail purple (the
## "trousers" tint on body_gen's kobold), its crest and ruff dark purple, its
## loincloth brown.
const KOBOLD_LIMBS := ["74508f", "6e4a8a", "7c5596", "664283"]
const KOBOLD_CREST := "4a2f5e"
const KOBOLD_LOINCLOTH := "6b4a35"
const PEOPLE_HAIR := "1f1a17"
## An orc's loincloth (Jeff's p2: bald, its loincloth brown).
const ORC_LOINCLOTH := "6b4a35"
## An ally's posture: an orc's slouch, a kobold's crouch.
const PEOPLE_POSTURES := {"orc": "stooped", "kobold": "slouching"}
## How likely an old person with no posture named stoops.
const OLD_STOOPED := 0.3

## What a player may choose for their look (the options panel's Character
## section; Net.tidy_look keeps only these): each key's values; seed's empty
## list, a whole number.
const PLAYER_CHOICES := {
	"seed": [],
	"build": ["lean", "middling", "heavy"],
	"stature": ["short", "middling", "tall"],
	"hair": ["cropped", "bound", "long", "bald", "tail"],
	"hair_colour": ["black", "dark", "brown", "chestnut", "fair", "blond", "red", "grey"],
	"beard": ["none", "short", "full", "long"],
	"skin": ["1", "2", "3", "4", "5", "6", "7", "8"],
	"hairroot": ["0", "2", "3"],  # SCRATCH (the root row): 0 off, 2 narrower (7 cm, 0.55), 3 wider and darker (11 cm, 0.45); human_body.gdshader's hair_root_try.
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
## A beard's colour (beard_against): the hair's, set further off the skin; on the beard's meshes' "hair" alone.
var beard_colour := Color.BLACK
var posture := "straight"
## Its words as they came out, said or seeded (the Character section shows them).
var build := ""
var stature := ""
var age := ""
var hair := ""
var hair_colour := ""
var beard := ""
var skin := 1
var garb := "none"
## The clothes word the look said ("forest", "grave": CLOTHES), else "".
var clothes := ""
var trade := ""
## The armour look its words say it wears (worn=), "" for none.
var worn := ""


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
	colours["hair"] = hair_against(hair_name, colours["skin"])
	beard_colour = beard_against(colours["hair"], colours["skin"])
	hair_colour = hair_name
	var tunic_roll := rng.randi()
	var trousers_roll := rng.randi()
	colours["tunic"] = Color(TUNICS[tunic_roll % TUNICS.size()])
	colours["trousers"] = Color(TROUSERS[trousers_roll % TROUSERS.size()])
	if CLOTHES.has(str(words.get("clothes", ""))):
		# The same draws, on the foe's own colours (793, pc-character's side).
		clothes = str(words["clothes"])
		var own: Array = CLOTHES[clothes]
		colours["tunic"] = Color(own[0][tunic_roll % (own[0] as Array).size()])
		colours["trousers"] = Color(own[1][trousers_roll % (own[1] as Array).size()])
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
		if HAIR_ADDED.has(hair):
			parts.append(HAIR_ADDED[hair])
	if hair == "bound" and headwear == "none":
		parts.append(HAIR_KNOT)
	for part: String in [BEARD_PARTS[beard], HEADWEAR_PARTS[headwear]]:
		if part != "":
			parts.append(part)
	if str(words.get("apron", "")) == "yes":
		parts.append("Apron")
	var said_posture := str(words.get("posture", ""))
	var stoop_roll := rng.randf()
	posture = said_posture if said_posture in POSTURES else ("stooped" if age == "old" and stoop_roll < OLD_STOOPED else "straight")
	# Drawn after everything above (decision 480), so a look from before keeps every
	# word it had: the face, then garb.
	var face := {}
	for key: String in FACE_KEYS:
		var most := float(FACE_MAX_FEMALE.get(key, FACE_MAX)) if body == &"female" else FACE_MAX
		face[key] = rng.randf() * most
	var garb_roll := rng.randf()
	var garb_pick: String = GARBS[rng.randi() % GARBS.size()]
	var said_people := str(words.get("people", ""))
	if said_people in PEOPLE_SKINS:
		_ally(said_people, rng)
		return
	# The last draws (after everything above, so every look keeps every word it
	# had): the tail on a seeded cropped man, the long beard on a seeded full one.
	var tail_roll := rng.randf()
	var long_roll := rng.randf()
	if body == &"male" and str(words.get("extras", "")) != "no":
		if hair == "cropped" and not words.has("hair") and tail_roll < TAIL_SHARE:
			hair = "tail"
			var at := parts.find(HAIR_PARTS[hair])
			if at >= 0:
				parts.insert(at + 1, HAIR_ADDED[hair])
		if beard == "full" and not words.has("beard") and long_roll < LONG_BEARD_SHARE:
			beard = "long"
			parts[parts.find(BEARD_PARTS["full"])] = BEARD_PARTS["long"]
	keys.merge(face)
	trade = str(words.get("trade", ""))
	var dressed: Array = TRADE_GARB.get(trade, ["", ""])
	var said_garb := str(words.get("garb", ""))
	if said_garb in GARB_PARTS:
		garb = said_garb
	elif dressed[0] != "":
		garb = dressed[0]
	elif not words.has("trade"):
		garb = garb_pick if garb_roll < GARB_CHANCE else "none"
	if not str(words.get("headwear", "")) in HEADWEAR_PARTS and dressed[1] != "":
		_wear_headwear(str(dressed[1]))
	if GARB_PARTS[garb] != "":
		parts.append(GARB_PARTS[garb])
	worn = str(words.get("worn", "")) if str(words.get("worn", "")) in ARMOUR_PARTS else ""


## [param worn] on the head, in place of any headwear drawn (a hood's hair
## shown again under a cap or hat).
func _wear_headwear(worn: String) -> void:
	for part: String in HEADWEAR_PARTS.values():
		parts.erase(part)
	parts.erase(HAIR_KNOT)
	if HAIR_PARTS[hair] != "" and not HAIR_PARTS[hair] in parts:
		parts.insert(0, HAIR_PARTS[hair])
	if HAIR_ADDED.has(hair) and not HAIR_ADDED[hair] in parts:
		parts.insert(1, HAIR_ADDED[hair])
	parts.append(HEADWEAR_PARTS[worn])


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
		hair = "bald"
		colours["tunic"] = Color(ORC_LOINCLOTH)
	else:
		# No cap or lamp (kobolds see in the dark); its limbs, crest and loincloth.
		hair = "bald"
		colours["trousers"] = Color(KOBOLD_LIMBS[rng.randi() % KOBOLD_LIMBS.size()])
		colours["hair"] = Color(KOBOLD_CREST)
		colours["tunic"] = Color(KOBOLD_LOINCLOTH)
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
		if String(mesh.name) in BEARD_PARTS.values() and people == "human":
			mesh.set_instance_shader_parameter("hair", beard_colour)
		if tunic != Color.WHITE:
			mesh.set_instance_shader_parameter("tunic", tunic)
		var root_try: Variant = {"0": Vector3(0.09, 1.0, 0.3), "2": Vector3(0.07, 0.55, 0.3), "3": Vector3(0.11, 0.45, 0.3)}.get(str(words.get("hairroot", "")))
		if root_try != null:  # SCRATCH (the root row)
			mesh.set_instance_shader_parameter("hair_root_try", root_try)
	dye_hood(scene)


## A hood worn with a cape is one garment, a hooded mantle (419 amended (2), the coordinator's
## ruling): while [param scene] shows both its look's Hood and its Cape, the Hood takes the Cape's
## colour, read from the palette at the Cape's own swatch (art-kit's row 8 the one source); a hood
## worn alone keeps its own (the dye's alpha 0). Run after anything that shows or hides either (apply,
## wear, Client3D._sync_worn_gear: a cloak or armour over the cape, a worn hood over the look's).
## A body without both (an orc, a kobold, the goblin) is left alone.
static func dye_hood(scene: Node3D) -> void:
	var hood := scene.find_child("Hood", true, false) as MeshInstance3D
	var cape := scene.find_child("Cape", true, false) as MeshInstance3D
	if hood == null or cape == null:
		return
	var dyed := hood.visible and cape.visible
	hood.set_instance_shader_parameter("dye", cape_colour(cape) if dyed else Color(0, 0, 0, 0))


static var _cape_colours := {}
## hair_against's answers, by hair name and skin.
static var _hair_against := {}


## [param name]'s hair colour drawn beside [param skin] (HAIR_STEP): the named colour, moved in lightness when the
## two are too near in value.
static func hair_against(name: String, skin: Color) -> Color:
	var key := name + "/" + skin.to_html(false)
	if not _hair_against.has(key):
		_hair_against[key] = _hair_moved(name, skin)
	return _hair_against[key]


## The two-light rule: the palette's move, or the noon-drawn one where that stands further from the face at noon
## and no nearer at 19:00, but for HAIR_KEPT.
static func _hair_moved(name: String, skin: Color) -> Color:
	var today := _hair_palette_move(name, skin)
	if "%s/%d" % [name, SKINS.find(skin.to_html(false)) + 1] in HAIR_KEPT:
		return today
	var drawn := _hair_drawn_move(name, skin)
	var ls := lab_of(skin).x
	var t := lab_of(today).x
	var d := lab_of(drawn).x
	var further_noon := absf(lit_hair(d, "noon") - lit_face(ls, "noon")) > absf(lit_hair(t, "noon") - lit_face(ls, "noon")) + 0.01
	var nearer_evening := absf(lit_hair(d, "evening") - lit_face(ls, "evening")) < absf(lit_hair(t, "evening") - lit_face(ls, "evening")) - 0.01
	if absf(d - t) > 0.01 and further_noon and not nearer_evening:
		return drawn
	return today


## A crown of L* [param l] as drawn in [param light] (HAIR_LIT).
static func lit_hair(l: float, light: String) -> float:
	var knots: Array = HAIR_LIT[light]
	var at := clampf(l / 5.0, 0.0, knots.size() - 1.001)
	var i := int(at)
	return lerpf(knots[i], knots[i + 1], at - i)


## A face of skin L* [param l] as drawn in [param light] (FACE_LIT by FACE_SKIN_L).
static func lit_face(l: float, light: String) -> float:
	var drawn: Array = FACE_LIT[light]
	if l <= FACE_SKIN_L[0]:
		return drawn[0]
	for i in FACE_SKIN_L.size() - 1:
		if l <= FACE_SKIN_L[i + 1]:
			return lerpf(drawn[i], drawn[i + 1], (l - FACE_SKIN_L[i]) / (FACE_SKIN_L[i + 1] - FACE_SKIN_L[i]))
	return drawn[drawn.size() - 1]


## The move the rule makes judged on the noon-drawn values (HAIR_LIT, FACE_LIT), as the palette rule below.
static func _hair_drawn_move(name: String, skin: Color) -> Color:
	var hair := Color(HAIR_COLOURS[name])
	var ls := lit_face(lab_of(skin).x, "noon")
	var h := lab_of(hair)
	var d := lit_hair(h.x, "noon") - ls
	if absf(d) >= HAIR_STEP:
		return hair
	var away := 1.0 if d > 0.0 else -1.0
	var a := _hair_reach_lit(name, h, ls, away)
	var b := _hair_reach_lit(name, h, ls, -away)
	var pick := a
	if a.x >= HAIR_STEP - 0.1 and b.x >= HAIR_STEP - 0.1:
		pick = a if absf(a.y) <= absf(b.y) else b
	elif b.x > a.x + 0.01:
		pick = b
	return from_lab(Vector3(h.x + pick.y, h.y, h.z))


static func _hair_reach_lit(name: String, h: Vector3, ls: float, sign_: float) -> Vector2:
	var move := 0.0
	while move + HAIR_MOVE_GRAIN <= HAIR_MOVE_MAX and sign_ * (lit_hair(h.x + sign_ * move, "noon") - ls) < HAIR_STEP:
		var next := h.x + sign_ * (move + HAIR_MOVE_GRAIN)
		if next <= 0.0 or next >= 100.0 or nearest_hair(from_lab(Vector3(next, h.y, h.z))) != name:
			break
		# A move that buys nothing is not made: past the knots' floor (or ceiling) the drawn crown no longer changes.
		if absf(lit_hair(next, "noon") - lit_hair(h.x + sign_ * move, "noon")) < 0.001:
			break
		move += HAIR_MOVE_GRAIN
	return Vector2(absf(lit_hair(h.x + sign_ * move, "noon") - ls), sign_ * move)


## The step judged on the palette's L* (the rule before the two-light one, still its first choice).
static func _hair_palette_move(name: String, skin: Color) -> Color:
	var hair := Color(HAIR_COLOURS[name])
	var ls := lab_of(skin).x
	var h := lab_of(hair)
	var d := h.x - ls
	if absf(d) >= HAIR_STEP:
		return hair
	var away := 1.0 if d > 0.0 else -1.0
	var a := _hair_reach(name, h, ls, away)
	var b := _hair_reach(name, h, ls, -away)
	var pick := a
	if a.x >= HAIR_STEP - 0.1 and b.x >= HAIR_STEP - 0.1:
		pick = a if absf(a.y) <= absf(b.y) else b
	elif b.x > a.x + 0.01:
		pick = b
	return from_lab(Vector3(h.x + pick.y, h.y, h.z))


## How far from [param ls] hair [param h] (L*a*b*) gets moving lightness in direction [param sign]: Vector2(the gap
## reached, the move), within HAIR_MOVE_MAX and while its nearest named colour is still [param name].
static func _hair_reach(name: String, h: Vector3, ls: float, sign_: float) -> Vector2:
	var move := 0.0
	while move + HAIR_MOVE_GRAIN <= HAIR_MOVE_MAX and sign_ * (h.x + sign_ * move - ls) < HAIR_STEP:
		var next := h.x + sign_ * (move + HAIR_MOVE_GRAIN)
		if next <= 0.0 or next >= 100.0 or nearest_hair(from_lab(Vector3(next, h.y, h.z))) != name:
			break
		move += HAIR_MOVE_GRAIN
	var reached := from_lab(Vector3(h.x + sign_ * move, h.y, h.z))
	return Vector2(absf(lab_of(reached).x - ls), sign_ * move)


## A beard of [param hair] (as hair_against drew it) beside [param skin]: its lightness moved further from the skin's by
## what its front loses as drawn (BEARD_FACING), less as the hair's own gap passes HAIR_STEP, none past HAIR_STEP +
## BEARD_FACING; hue and chroma kept, the skin never moved.
static func beard_against(hair: Color, skin: Color) -> Color:
	var ls := lab_of(skin).x
	var h := lab_of(hair)
	var extra := clampf(HAIR_STEP + BEARD_FACING - absf(h.x - ls), 0.0, BEARD_FACING)
	if extra <= 0.0:
		return hair
	var away := 1.0 if h.x >= ls else -1.0
	return from_lab(Vector3(clampf(h.x + away * extra, 0.0, 100.0), h.y, h.z))


## The named hair colour nearest [param c] in L*a*b*.
static func nearest_hair(c: Color) -> String:
	var at := lab_of(c)
	var best := ""
	var best_d := INF
	for name: String in HAIR_COLOURS:
		var dist := at.distance_squared_to(lab_of(Color(HAIR_COLOURS[name])))
		if dist < best_d:
			best_d = dist
			best = name
	return best


## [param c] (sRGB) in CIE L*a*b* (D65).
static func lab_of(c: Color) -> Vector3:
	var r := _srgb_lin(c.r)
	var g := _srgb_lin(c.g)
	var b := _srgb_lin(c.b)
	var fx := _lab_f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
	var fy := _lab_f(0.2126 * r + 0.7152 * g + 0.0722 * b)
	var fz := _lab_f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


## [param lab] (L*a*b*, D65) as an sRGB colour, each channel clamped and to 8 bits.
static func from_lab(lab: Vector3) -> Color:
	var fy := (lab.x + 16.0) / 116.0
	var x := _lab_fi(fy + lab.y / 500.0) * 0.95047
	var y := _lab_fi(fy)
	var z := _lab_fi(fy - lab.z / 200.0) * 1.08883
	return Color8(_srgb_byte(3.2406 * x - 1.5372 * y - 0.4986 * z), _srgb_byte(-0.9689 * x + 1.8758 * y + 0.0415 * z),
			_srgb_byte(0.0557 * x - 0.2040 * y + 1.0570 * z))


static func _srgb_lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _srgb_byte(v: float) -> int:
	v = clampf(v, 0.0, 1.0)
	return roundi((12.92 * v if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055) * 255.0)


static func _lab_f(v: float) -> float:
	return pow(v, 1.0 / 3.0) if v > 0.008856 else 7.787 * v + 16.0 / 116.0


static func _lab_fi(v: float) -> float:
	return v * v * v if v * v * v > 0.008856 else (v - 16.0 / 116.0) / 7.787


## [param cape]'s colour as drawn: its material's palette at the mean of its UVs (each part is on one
## swatch), alpha 1; the palette read once per mesh. Transparent where there is no palette to read.
static func cape_colour(cape: MeshInstance3D) -> Color:
	if cape.mesh == null:
		return Color(0, 0, 0, 0)
	var key := cape.mesh.get_rid()
	if _cape_colours.has(key):
		return _cape_colours[key]
	var colour := Color(0, 0, 0, 0)
	var material := cape.get_active_material(0) as ShaderMaterial
	var palette := material.get_shader_parameter("palette") as Texture2D if material != null else null
	if palette != null and cape.mesh.get_surface_count() > 0:
		var image := palette.get_image()
		if image == null or image.is_empty():
			# No image back from a renderer that keeps none (headless): the palette's own file.
			image = Image.load_from_file(palette.resource_path)
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			var uvs: PackedVector2Array = cape.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			var mean := Vector2.ZERO
			for uv in uvs:
				mean += uv
			mean /= maxf(1.0, uvs.size())
			var at := Vector2i((mean * Vector2(image.get_size())).floor()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
			colour = image.get_pixelv(at)
			colour.a = 1.0
	# Kept only when read: a cape not yet in the people's material (no palette) is asked again next time.
	if colour.a > 0.0:
		_cape_colours[key] = colour
	return colour


## [param scene] (as apply drew it) wearing armour (items' 622): the
## covering of [param id]'s look (Items.armour_of) shown, tinted the item's
## colour, the garb under it (GARB_UNDER_ARMOUR) hidden; with no armour id,
## the look's own worn= look in its kind's colour (armour_kind); with
## neither, the look's own parts again. A body without that covering (an
## ally's) wears nothing new and keeps its parts.
func wear(scene: Node3D, id: String) -> void:
	var armour := Items.armour_of(id) if not id.is_empty() else {}
	var look := str(armour.get("look", worn))
	var part := str(ARMOUR_PARTS.get(look, ""))
	if not part.is_empty() and scene.find_child(part, true, false) == null:
		part = ""
	var colour := Items.color_of(id) if not armour.is_empty() else Items.color_of(armour_kind(look))
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var name := String(mesh.name)
		if name.begins_with("Armour_"):
			mesh.visible = name == part
			if name == part:
				mesh.set_instance_shader_parameter("tunic", colour)
		elif name in GARB_UNDER_ARMOUR:
			mesh.visible = name in parts and part.is_empty()
	dye_hood(scene)


## The first kind in the catalog whose armour looks [param look]; "" for none.
static func armour_kind(look: String) -> String:
	for id: String in Items.all():
		if str(Items.armour_of(id).get("look", "")) == look:
			return id
	return ""
