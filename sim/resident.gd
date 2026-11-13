class_name Resident
extends GridEntity
## A town's resident as a body in it (decision 333). The record is the
## economy's (Towns.residents, Production.worker); the body is Main's,
## spawned while the zone is awake (Main._sync_residents) and never saved:
## at a spawn it stands where its day puts it at that hour.
##
## Its day is levels/residents.json: by its trade, the hours at work and at
## home (DayNight's clock), the square any other hour. Main gives it its
## places (cells: the inside of the building its trade works in, its home,
## the square round the town's store); it walks there as a companion does
## (World.find_path, a route kept till it is blocked) and, in the square,
## strolls to another cell now and then. A raider (a monster not of the
## wild, or a wolf) it sees or hears, or a blow, and it hides at home till
## none has been about for HIDE_TICKS. It never fights and says nothing
## yet. Far from every player and companion (FAR_TILES) it thinks every
## FAR_EVERY ticks and is walked there at once (World.walk), as monsters
## are by the world tick.

enum Doing { WORK, HOME, SQUARE, HIDE, WELL, INN, TEMPLE, ROUNDS, STRAYED, ESCORT, BED, VISIT }
## Doing by the place word Townsfolk.whereabouts gives (decision 404).
const DOING_AT := {"work": Doing.WORK, "home": Doing.HOME, "square": Doing.SQUARE, "well": Doing.WELL, "inn": Doing.INN, "temple": Doing.TEMPLE,
	"rounds": Doing.ROUNDS}
## Where it is, in its voice's words (facts_now).
const WHERE_WORDS := {Doing.WORK: "at your work", Doing.HOME: "at home", Doing.SQUARE: "in the square", Doing.HIDE: "hiding at home from raiders",
	Doing.WELL: "at the well", Doing.INN: "at the inn", Doing.TEMPLE: "at the temple", Doing.ROUNDS: "on your rounds, at a neighbour's door",
	Doing.STRAYED: "lost beyond the walls, far from the town", Doing.ESCORT: "being walked home, following at heel",
	Doing.BED: "sick in your bed at home", Doing.VISIT: "at a sick neighbour's bedside, seeing to them"}
const SIGHT_RANGE := 7
## It looks and listens for raiders every so many ticks.
const LOOK_EVERY := 5
## It stays hidden so long after a raider was last about (ticks).
const HIDE_TICKS := 600
## In the square it strolls to another cell about this often (ticks).
const WANDER_TICKS := 80
## Idle, whatever it is doing (the frozen-townsfolk mend, Jeff 2026-11-10: "townspeople frozen staring
## at the wall all day"), it moves on to another spot of its place this often: STROLL_TICKS plus up to
## STROLL_SPREAD more, its own by a hash (37.5 ticks a game minute: 12 to 32 game minutes, 45 to 120 real
## seconds; the coordinator, 2026-11-11: a shorter wait reads as restless). A seat: SEAT_TICKS plus up to
## SEAT_SPREAD (30 to 60 game minutes, settling in).
const STROLL_TICKS := 450
## The inn's fire takes this many before a table pair is started, and the counter this many before a
## second pair is (875 amended (2)).
const INN_FIRE_MOST := 3
const INN_COUNTER_FIRST := 1
const STROLL_SPREAD := 750
const SEAT_TICKS := 1125
## A night-goer the inn had no room for (875, "Umbrage at night"; Main's places "short_stands"): its stands
## in the open last SHORT_STAND_TICKS plus up to SHORT_STAND_SPREAD (2 to 5 game minutes), a stroll and
## not a vigil; never the cell it stands on or the one it left (_free_cell).
const SHORT_STAND_TICKS := 75
const SHORT_STAND_SPREAD := 115
const SEAT_SPREAD := 1125
## The doings it strolls in while idle (no task, not abed): not hiding, sick, led, lost, visiting the sick.
const STROLLS: Array[Doing] = [Doing.WORK, Doing.HOME, Doing.SQUARE, Doing.WELL, Doing.INN, Doing.TEMPLE, Doing.ROUNDS]
## The poses a spot gives (Level.spots_from's "pose"): its activity word while it is there, drawn by
## Client3D.ACTIVITIES (animation's); "stand" is none.
const POSES: Array[String] = ["sit", "lean"]
## 853's moving on (the strolls, and a new cell on every pick): off, a body keeps a cell it stands on in
## its place and only the square strolls, as before; resident_test's cases from before 853 run with it off.
static var keep_moving := true
## The ticks a body stands on its cell after a word of these ends, before its first step: the client's
## get-up (animation's, 2026-11-10: Sitting_Exit 1.03 s for the seat words, Counter_Exit 1.17 s for tend);
## stepped off sooner, the client cuts it short.
const GET_UP := {"sit": 15, "sit_talk": 15, "sit_listen": 15, "tend": 12, "lean": 5}  # A ground sit's get-up 1.45 s, a lean's step-off 0.5 s (animation's, 853 amended (2)).
## Shown work's bouts (853 amended (8), the coordinator: "a smith hammering without pause for a whole
## stay reads as a machine"): seconds of the word, then seconds standing, each bout's length from the
## body's own seed.
const BOUT_WORK := Vector2i(20, 40)
const BOUT_REST := Vector2i(5, 15)
## A keeper serving a player at the barter window (853 amended (8)) stays turned to them this long from
## each barter, unless they walk off (ADDRESS_REACH).
const SERVE_SECONDS := 30
const FAR_TILES := 30
const FAR_EVERY := 20
## A step blocked so many times, and it looks for a new way.
const STUCK_TRIES := 3
## No way to its goal, it chooses again after so many ticks, plus up to
## PATH_RETRY_SPREAD by its id, so a crowd at one door doesn't move as one (762 amended (3)).
const PATH_RETRY_TICKS := 40
const PATH_RETRY_SPREAD := 20
## Its way somewhere looks at this many tiles at most (decision 818; the town soak at
## 16 players: a goal walled off by a crowd made the unbounded search close
## the whole wilds, 1.3-1.5 s in one tick; at this bound about 110 ms). The
## wilds' winding ways of ~200 steps close up to 12000 (path_bound_test).
## Not found within it, it waits PATH_RETRY_TICKS as for no way.
const RESIDENT_SEARCH_TILES := 16000
## Bodies farther than this from it are planned through (World.find_path's
## bodies_within, 818): a crowd across the square moves; one beside it is met by
## _step's stuck count.
const RESIDENT_BODIES_WITHIN := 3
const NO_CELL := Vector2i(-99999, -99999)
const PLACE_OF := {Doing.WORK: "work", Doing.HOME: "home", Doing.SQUARE: "square", Doing.HIDE: "home",
	Doing.WELL: "well", Doing.INN: "inn", Doing.TEMPLE: "temple", Doing.ROUNDS: "rounds", Doing.STRAYED: "strayed", Doing.ESCORT: "strayed",
	Doing.BED: "home", Doing.VISIT: "visit"}

## Production's worker id ("companion:<player id>" for a companion resting
## in town: decision 333 amended), the town (a stockpile place id) and its
## trade ("" for none: the default day, its work the square).
var worker_id := ""
## A companion's player's id, "" for a town's own resident.
var player_id := ""
## Its name (the worker's, or the companion's), and for a companion her own
## card (her record's), "" for a town's resident: theirs is rolled.
var person := ""
var card := ""
## Its town's name, as the world map has it (Main's).
var town_name := ""
var town := ""
var trade := ""
## Its hidden personality type (decision 393: the worker record's,
## Townsfolk.roll_type; "" for a companion), server side only, never shown.
var type := ""
## Who is speaking to it now (a player id and their shown name), for its
## offers (decision 435); "" between asks.
var asked_by := ""
var asked_by_name := ""
## What the asking player's question is answered with from the world's data (890; Main._asked_facts):
## set for the prompt being built, then cleared, as asked_by.
var asked_facts: Array[String] = []
## Whether these are their first words together (decision 443).
var first_words := false
## Where it goes: "work", "home", "square" -> Rect2i of cells (Main's).
var places: Dictionary = {}
var senses: Senses
var doing := Doing.SQUARE
## Lost beyond the walls (decision 487): standing at the card's cell till
## someone walks them home; escort_of is the player they follow (whoever
## spoke to them last), at heel (companions' Heel, decision 485).
var strayed := false
## The sought entry this body is (decision 613, npc's side; economy's Towns.sought): its worker id while it
## stands at its refuge, lost or held, or follows the player leading it home; "" for a townsman. With it strayed
## is true (the stray's stand-and-follow tick serves), holder the faction holding it ("" lost) and where
## economy's where-word for the refuge.
var sought := ""
var holder := ""
var where := ""
## A forest camp's trader (799, npc's side): his trader place id ("forest/loop_camp_trader"), "" for the rest;
## never a monster's foe (enemy-ai's Monster._may_fight). Server only.
var camp_trader := ""
var escort_of := ""
## What they lie abed with (decision 501 amended, ui's ask): the sickness's
## kind ("a fever", "a cough"), "" when well. Replicated, so a client can
## name it in the cursor hint and the talk panel's title; the server sets it
## on its sim tick from the town's record (Townsfolk.sickness_of).
var ailing := ""
var escort_name := ""
## The medicine man's visit (decision 501): {"rect": the sick one's home, "who": their id, "until": World.steps}; {} for none.
## The guard captain's walk to a post a wave is coming at (771 amended (3)): {"rect": the post, "name", "post": true, "until"}.
## A guard laid up hurt (791): {"rect": the temple, "laid_up": true, "until"}.
var visit: Dictionary = {}
## A guard's (decision 791): what it holds, [right, left] (the left "" for
## now: a shield or a bow later needs no new protocol), and the armour it
## wears, by trade (arm()); replicated for the views.
var hands := PackedStringArray()
var worn := ""
## Main's: a guard says one of residents.json guard_fight's lines ("call",
## "fall_back") and rallies others (body, key).
var guard_told: Callable
## The foe a guard fights, its pulling back hurt, when it last called.
var _foe: Monster = null
var _fall_back := false
var _called_at := -1
## Companions' Heel (decision 485), loaded by path so this script stands
## with or without it: without, the lost one waits where they are.
const HEEL_SCRIPT := "res://sim/heel.gd"
var _heel: RefCounted = null
var _goal := NO_CELL
var _route: Array[Vector2i] = []
var _stuck := 0
var _hide_until := -1
## Its town is under a threat (decision 762; Main sets it each sync): it
## shelters (Doing.HIDE at places' "shelter"), unless asleep in a bed under a
## roof and already inside that building (bedtime never walks it out of its
## shelter across town: 762 amended), or its trade is the fight (FIGHTERS),
## which turns out to the square.
var sheltering := false
## The trades whose job is the fight (762): they turn out, never hide.
const FIGHTERS: Array[String] = ["guard"]
var _wander_at := -1
## The cell it last walked off (the mend: a stroll never goes back to it next) and its count of picks
## (the pick's hash changes with each).
var _left := NO_CELL
var _picks := 0
## The spot it is going to or at ({} for a cell of the rect): Level.spots_from's {use, cell, face, pose}.
var _spot: Dictionary = {}
var _rise_until := -1  # Getting up (GET_UP): no step before this tick.
## When it chooses again after finding no way to its goal; -1 for none (762 amended (3)).
var _retry_at := -1
## Addressing a player who clicked them (decision 560, npc's side): the
## addressed body's node path, replicated for the look and the talking
## clip (pc-character's), "" when none; they stand facing them until
## _address_until or the player leaves ADDRESS_REACH.
var addressing := ""
var _address_until := -1
const ADDRESS_REACH := 2
var _address_reach := ADDRESS_REACH  # A hail's from farther (853 amended (8)).
## Shown work (853 amended (8)): the word it shows at its work spot, "" off one; whether this bout is
## work or rest, and the tick it ends (-1: a fresh bout of work next).
var _shown := ""
var _bout_on := false
var _bout_end := -1
## Visible work (decision 566, npc's side): what the body is doing where it
## stands, replicated for pc-character's clip with the tool in hand ("chop",
## "carry_log", "saw", "hammer", "sleep"; 566 amended, phase 2: "stalk",
## "carry_game", "hoe", "carry_sack", "herd", "shear"; "" idle), set from [member task]
## (Main's, from the sim's state: {kind, cell, face, walking}) while the
## routine says work, and "sleep" at home in the sleep hours. The sim's
## yields and clocks never read it: a body is the visible version of work
## the production tick already does.
var activity := ""
var task := {}
## Woken in the night (decision 751): DayNight steps until which the sleep
## hours do not hold for it (a fight near or a hit), -1 for none.
var _woken_until := -1.0
var _listened := -1


## Its voice (decision 336): asked only when spoken to, one ask at a time
## for all residents (Main), with facts only: who it is, its work, the
## town's wants and shop, the hour and weather.
## What the model gives back is held to the rule by code too (the words
## soak of 2026-10-19: a resident ran to three sentences one time in four,
## and one began "Bea says:"): two_sentences, with the speaker's [param name]
## so only their own name is cut from the front.
static func two_sentences(line: String, name := "") -> String:
	return str(spoken(line, name)["say"])


## The gesture verbs a resident's narration may turn on, each with its
## participle (336 amended): nothing that moves, gives or takes.
const GESTURES := {"nod": "nodding", "shrug": "shrugging", "sigh": "sighing", "smile": "smiling", "grin": "grinning", "frown": "frowning",
	"glance": "glancing", "lean": "leaning", "pause": "pausing", "turn": "turning", "straighten": "straightening", "wipe": "wiping",
	"scratch": "scratching", "rub": "rubbing", "chuckle": "chuckling", "laugh": "laughing", "exhale": "exhaling", "blink": "blinking",
	"squint": "squinting", "gesture": "gesturing", "fold": "folding", "tilt": "tilting", "shake": "shaking", "raise": "raising",
	"lower": "lowering", "wave": "waving", "clear": "clearing", "set": "setting", "look": "looking", "lift": "lifting", "snort": "snorting",
	"cough": "coughing", "wince": "wincing", "shift": "shifting", "stare": "staring", "spit": "spitting", "nudge": "nudging", "purse": "pursing"}
## A sentence of second-person narration: "You" and a gesture verb, or one
## naming your voice, eyes, hands or face.
const NARRATION := "^[Yy]ou (nods?|shrugs?|sighs?|smiles?|grins?|frowns?|glances?|leans?|pauses?|turns?|straightens?|wipes?|scratch(es)?|rubs?|chuckles?|laughs?|exhales?|blinks?|squints?|gestures?|folds?|tilts?|shakes?|raises?|lowers?|waves?|clears?|sets? down|lifts?|snorts?|coughs?|winces?|shifts?|stares?|spits?|purses?|looks? (up|down|over|around|away|out|back|aside))\\b|\\byour (voice|eyes|hands?|face|gaze|brow|jaw|shoulders)\\b"
## An action the sim did not do, a thought or a plan: never an aside.
const NOT_DONE := "\\b(walk|go|goe|give|take|hand|step|leave|sit|stand|pick|put|pour|open|close|fetch|come|run|move|cross|carry|bring|follow|lead|think|wonder|decide|remember|consider|plan|hope|wish)(s|es|ing)?\\b"


## What the model gave back, held to the rule (decision 336, amended from
## Jeff's play on v0.1.160: "town npc verbalize their thoughts", then "might
## be interesting if there's some sort of narration quality"): {say, aside}.
## The model wrapped the words in stage direction ("You nod, your voice
## steady despite the rain. "Jeff, I've been meaning to thank you..."") and
## the whole of it reached the bubble, cut to two sentences with the words
## themselves the ones cut. Now: asterisked and bracketed actions come out;
## when the answer holds quoted speech, the quoted words are the speech and
## the rest narration; else each sentence of second-person narration
## (NARRATION) is; the speech is cut to two sentences as before, "" when
## none (not said). The narration becomes one clause of how it was said, in
## the third person with [param possessive] ("his", "her", "their"), no
## end mark, never the speaker's [param name]: a clause naming the voice is
## preferred ("his voice steady despite the rain"); else a gesture turned to
## its participle ("looking up from his workbench", "nodding"); a gesture
## with something after its verb joins a voice clause's words when the two
## stay within eight words ("looking up from his workbench, low and
## careful"); a bare gesture gives way to the voice. A clause of walking,
## giving, taking, or of thought or plan (NOT_DONE) is never an aside.
static func spoken(line: String, name := "", possessive := "their") -> Dictionary:
	var said := line.strip_edges()
	var lead_word := name if not name.is_empty() else "[A-Z][\\w'-]*"
	var own := RegEx.create_from_string("^\\s*" + lead_word + "(\\s+says)?\\s*:\\s*\"?")
	var lead := own.search(said)
	if lead != null:
		said = said.substr(lead.get_end()).strip_edges().trim_suffix("\"")
	var narration: Array[String] = []
	var marked := RegEx.create_from_string("\\*([^*]*)\\*|\\(([^)]*)\\)|\\[([^\\]]*)\\]")
	for m: RegExMatch in marked.search_all(said):
		var inner := (m.get_string(1) + m.get_string(2) + m.get_string(3)).strip_edges()
		if not inner.is_empty():
			narration.append(inner)
	said = marked.sub(said, " ", true).strip_edges()
	var quotes := RegEx.create_from_string("[\"“]([^\"”]*[A-Za-z][^\"”]*)[\"”]")
	var quoted: Array = quotes.search_all(said).map(func(m: RegExMatch) -> String: return m.get_string(1).strip_edges())
	var say := ""
	if not quoted.is_empty():
		say = " ".join(quoted)
		for part: String in sentences(quotes.sub(said, " ", true)):
			narration.append(part)
	else:
		var told := RegEx.create_from_string(NARRATION)
		var kept: Array[String] = []
		for part: String in sentences(said):
			if told.search(part.strip_edges()) != null:
				narration.append(part)
			else:
				kept.append(part)
		say = "".join(kept)
	var parts := sentences(say.strip_edges())
	if parts.size() > 2:
		say = "".join(parts.slice(0, 2))
	return {"say": say.strip_edges(), "aside": aside_of(narration, name, possessive)}


## One clause of how it was said, from the model's [param narration]
## (spoken): "" for none that fits.
static func aside_of(narration: Array[String], name: String, possessive: String) -> String:
	var not_done := RegEx.create_from_string(NOT_DONE)
	var voiced := RegEx.create_from_string("^(his|her|their) voice\\b")
	var clause_ends := RegEx.create_from_string(",|;")
	var named := RegEx.create_from_string("\\b" + name + "\\b") if not name.is_empty() else null
	var voice := ""
	var gesture := ""
	var bare := true
	for part: String in narration:
		for clause: String in clause_ends.sub(part, "|", true).split("|", false):
			var words := _third_person(clause, name, possessive)
			if words.is_empty() or not_done.search(words) != null or (named != null and named.search(words) != null):
				continue
			if voice.is_empty() and voiced.search(words) != null:
				voice = words
			elif gesture.is_empty():
				var turned := _participle(words)
				if not turned.is_empty():
					gesture = turned
					bare = turned.find(" ") < 0
	if voice.is_empty():
		return gesture
	if gesture.is_empty() or bare:
		return voice
	var joined := gesture + ", " + voiced.sub(voice, "").strip_edges()
	return joined if joined.split(" ").size() <= 8 else voice


## [param clause] in the third person: "your" and "yourself" to the
## resident's, the name's possessive to the pronoun's, no end mark, no
## capital.
static func _third_person(clause: String, name: String, possessive: String) -> String:
	var words := clause.strip_edges().rstrip(".!?… ").strip_edges()
	if words.is_empty():
		return ""
	var reflexive: String = {"his": "himself", "her": "herself"}.get(possessive, "themselves")
	words = RegEx.create_from_string("\\byourself\\b").sub(words, reflexive, true)
	words = RegEx.create_from_string("\\b[Yy]our\\b").sub(words, possessive, true)
	if not name.is_empty():
		words = RegEx.create_from_string("\\b" + name + "'s\\b").sub(words, possessive, true)
	return words.left(1).to_lower() + words.substr(1)


## [param words] as a participle clause when they begin with a gesture verb
## ("you look up from his workbench" -> "looking up from his workbench",
## "nods" -> "nodding"); "" otherwise.
static func _participle(words: String) -> String:
	var m := RegEx.create_from_string("^(?:you )?([a-z]+)(.*)$").search(words)
	if m == null:
		return ""
	var verb := m.get_string(1)
	var rest := m.get_string(2)
	var more := rest.find(" and ")  # "nod and say nothing more": the gesture alone.
	if more >= 0:
		rest = rest.left(more)
	for form: String in [verb, verb.trim_suffix("s"), verb.trim_suffix("es")]:
		if GESTURES.has(form):
			return (GESTURES[form] + rest).strip_edges()
	return ""


## [param text] cut into sentences, each with its end mark and the space
## after; an unfinished tail is a sentence too.
static func sentences(text: String) -> Array[String]:
	var out: Array[String] = []
	var at := 0
	for m: RegExMatch in RegEx.create_from_string("[^.!?]+[.!?]+[\"'”]?\\s*").search_all(text):
		out.append(m.get_string())
		at = m.get_end()
	if at < text.length() and not text.substr(at).strip_edges().is_empty():
		out.append(text.substr(at))
	return out


const VOICE := """You are %s, who lives in %s and works there%s. You are no adventurer: you live and work in the town. Someone has just spoken to you.

Who you are:
%s

What is true now:
%s

Say what you would say out loud right now, as yourself, in one or two short sentences, to %s, speaking to them as "you". Your words are only what you say aloud: never describe what you do, and never begin with your own name or "says". Never narrate yourself: no "You nod", nothing of your face, hands or voice, no asterisks, and no quotation marks round your words, which are the whole of your answer. Asked about someone nothing above speaks of, say plainly that you know little of them: never invent what another said of them. %s"""
## What its voice may say of the world (decision 378): an official's what
## it knows alone; others' what they know and have heard, as heard; then by
## its role's creativity and integrity (Lore.profile, 1..10: HIGH or more,
## LOW or less, as lore derives its binding) whether it may embellish and whether it may lie. A
## companion resting in town speaks as she does with her player.
const BOUND := {
	"official": "Of the world, say only what is written above as what you know; what is only said, say as said, never as certain; of anything else, say you cannot speak to it.",
	"heard": "Of the world, say only what is written above: what you have heard, say as heard, naming who told you.",
	"embellish": "You may embellish what you know, in your own way.",
	"plain": "Never make up more than you know; anything else you don't know, so say so rather than guess.",
	"lie": "You may lie about yourself, as yourself would: where you were, what you did, what you own. Never put a deed or a word on a named neighbour that is not written above.",
	"honest": "Never say what you believe is false.",
	"companion": "What is written above is what you know; anything else you don't know, so say so rather than guess.",
}
const HIGH := 7
const LOW := 3
## The most of lore's facts a voice is told, in characters.
const LORE_CHARS := 600


func _init() -> void:
	super()
	max_hp = 10
	replicate("ailing")
	replicate("addressing")
	replicate("activity")
	# Who they are reaches a joined client too (562 amended (4)): the talk bar's verbs read trade (Main._barters),
	# the card and the hail read person; set on the server after the spawn, so on change carries them.
	replicate("trade")
	replicate("person")
	# Its town under a threat (762 amended, ui's side): the talk bar offers no Barter (Main._sheltering_seen).
	replicate("sheltering")
	# A guard's spear and mail and its fall (decision 791): the views draw the spear in hand (World.wielded),
	# the mail (PersonLook reads worn) and the lying and the rise (pc-character's side).
	replicate("hands")
	replicate("worn")
	replicate("down_until")
	replicate("downed_until")
	move_ticks = 3.0
	senses = Senses.new(self, SIGHT_RANGE, -1.0)


## The label over a resident's head: the name alone on one line (333 amended
## twice; Jeff, 2026-10-22: "have their name on one line overhead, lets drop
## the profession"). The trade is kept in the call for its callers; the
## greeting word, the ledger and the party log's prose still name it.
static func label_of(person_name: String, _of_trade: String) -> String:
	return person_name


## What one of [param of_trade] is doing at [param hour] (0..24), by its
## routine (decision 404, Townsfolk.whereabouts: the season, its hidden
## type, its own clock and the temple day by [param worker_id]).
static func doing_at(of_trade: String, hour: float, season := "", type := "", worker_id := "", day := -1, mood := "") -> Doing:
	return DOING_AT.get(Townsfolk.whereabouts(day_key(of_trade, worker_id), hour, season, type, worker_id, day, mood), Doing.SQUARE)


## The stall's keeper's day in residents.json (853 amended (11)): his stall is his work.
const VENDOR_DAY := "vendor"


## Whose day [param worker_id] keeps (853 amended (11)): the stall's keeper (Offers.VENDOR) his own, "vendor", while
## his trade stays "" (his voice, offers and lore unmoved); anyone else its trade's.
static func day_key(of_trade: String, worker_id: String) -> String:
	return VENDOR_DAY if worker_id.begins_with(Offers.VENDOR) else of_trade


## What one of [param of_trade] (hidden [param type], [param worker_id]) is
## doing now, on the world's clock and season: from the clock alone, so a
## body spawned as a player walks up starts at the right stint.
static func doing_now(of_trade: String, type := "", worker_id := "") -> Doing:
	var now := DayNight.now()
	return doing_at(of_trade, DayNight.hour(now), Season.name_at(World.steps), type, worker_id, Townsfolk.day_of(now),
		Townsfolk.mood_of(World.production, worker_id))  # A resting companion kept apart sits alone (555, npc's side).


func _sim_tick() -> void:
	if not Net.is_authority():
		return
	if World.is_downed(self):
		return  # Downed (791, a guard): it lies till raised or carried off.
	if strayed:
		_tick_strayed()
		return
	if Townsfolk.is_sick(World.production, worker_id):
		# Sick (decision 501): in bed, or walked to the healer by the player who spoke to them.
		var kind := str(Townsfolk.sickness_of(World.production, worker_id).get("kind", "a fever"))
		if ailing != kind:
			ailing = kind
		var leader := _escort_leader()
		if leader != null:
			doing = Doing.ESCORT
			if _heel == null and ResourceLoader.exists(HEEL_SCRIPT):
				_heel = load(HEEL_SCRIPT).new()
			if _heel != null:
				_heel.call("follow", self, leader)
			return
		escort_of = ""
		if doing != Doing.BED or _goal == NO_CELL:
			doing = Doing.BED
			_pick_goal()
		if not _far():
			_step()
		elif tile != _goal:
			World.walk(self, _goal, FAR_EVERY)
		return
	if not ailing.is_empty():
		ailing = ""  # Well again (501 amended).
	if not visit.is_empty() and World.steps >= int(visit.get("until", 0)):
		visit = {}
	if not addressing.is_empty():
		# Addressing a player (560): standing, facing them, while the stop lasts and they stay in reach.
		var who := get_node_or_null(NodePath(addressing)) as GridEntity
		if World.tick < _address_until and who != null and who.spawned and World.distance(who.tile, tile) <= _address_reach:
			# Turned to them (853: clicked mid-stroll, World.face is refused till its step is done; it turns then).
			var way := _toward(who.tile)
			if way != facing:
				World.face(self, way)
			return
		addressing = ""
	# A body at a task (566; 521 amended) keeps the near tick and its real route however far the players are:
	# the trip's clock runs whether anyone watches, and the far walk's cadence would eat the spell at the site.
	var far := _far() and task.is_empty()
	if far and (World.tick + id) % FAR_EVERY != 0:
		return
	if not far and World.tick % LOOK_EVERY == 0 and (activity.is_empty() or activity in POSES):
		_look()  # Not while at work or asleep (566): the work sets the facing. Sat or leaning, it still looks.
	if not far and trade in FIGHTERS and _fight():
		return  # A guard at a foe (791): the fight is the tick.
	if World.tick - hurt_tick <= 1:
		_hide_until = World.tick + HIDE_TICKS
	var hidden := World.tick < _hide_until
	var now := Doing.VISIT if not visit.is_empty() else doing_now(trade, type, worker_id)
	if laid_up():
		now = Doing.VISIT  # Laid up hurt at the temple (791): off duty till its time is out.
	elif trade in FIGHTERS and (hidden or sheltering or _fall_back):
		now = Doing.SQUARE  # The fight is its job (762): it turns out.
	elif hidden or (sheltering and not (now == Doing.HOME and sleeps_now() and bool(places.get("bed_roofed", false)) \
			and (places["bed"] as Rect2i).has_point(tile))):
		now = Doing.HIDE  # Abed under a roof, it sleeps on (762); not yet under it, it keeps to its shelter (762 amended).
	if now != doing or _goal == NO_CELL:
		doing = now
		_pick_goal()
	elif keep_moving and not far and tile == _goal and World.tick >= _wander_at and _strolls():
		_pick_goal()  # Idle, it moves on (the mend): every doing that has nothing to do, not only the square.
	elif not keep_moving and doing == Doing.SQUARE and tile == _goal and World.tick >= _wander_at:
		_pick_goal()  # Before 853: the square's stroll alone.
	elif _retry_at >= 0 and World.tick >= _retry_at:
		_pick_goal()  # Its way was shut (a body in the door, its cell taken): it tries again (762 amended (3)).
	_show_work()
	if far:
		if tile != _goal:
			World.walk(self, _goal, FAR_EVERY)
		return
	_step()
	if keep_moving and tile == _goal and (activity in POSES or (activity.is_empty() and _strolls())):
		_face_open()  # Not on its way to bed (its head to the wall is _show_work's), nor at a task.


## Lost (decision 487): stands where it is, or follows the player who spoke
## to it at heel while they are near; Main ends it at the town's ground.
func _tick_strayed() -> void:
	var leader := _escort_leader()
	if leader == null:
		doing = Doing.STRAYED
		escort_of = ""
		return
	doing = Doing.ESCORT
	if _heel == null and ResourceLoader.exists(HEEL_SCRIPT):
		_heel = load(HEEL_SCRIPT).new()
	if _heel != null:
		_heel.call("follow", self, leader)


## The player it follows, while spawned here and within FAR_TILES; null.
func _escort_leader() -> GridEntity:
	if escort_of.is_empty():
		return null
	for entity in World.get_entities():
		if entity is Player and entity.spawned and (entity as Player).player_id == escort_of and World.distance(tile, entity.tile) <= FAR_TILES:
			return entity
	return null


## [param player_id] (named [param player_name]) spoke to it while lost: it
## follows them home from now (decision 487).
func start_escort(player_id: String, player_name: String) -> void:
	escort_of = player_id
	escort_name = player_name


## Whether one of a faction's people can see it now (decision 613, npc's
## side; the coordinator's ruling with enemy-ai: a held one follows only
## when no holder sees them, and a brute beside the imps counts the same
## with no allies read): any monster that is not a beast, within
## SIGHT_RANGE with a line of sight. A beast never holds anyone.
func watched() -> bool:
	if senses == null:
		return false
	for entity in World.monsters():
		if entity is Animal or not entity.spawned or not entity is Monster:
			continue
		if World.distance(tile, entity.tile) <= SIGHT_RANGE and senses.sees(entity, -1, false):
			return true
	return false


## Whether no player or companion is within FAR_TILES.
func _far() -> bool:
	for entity in World.sought():
		if entity.spawned and World.distance(tile, entity.tile) <= FAR_TILES:
			return false
	return true


## A raider seen, or heard since it last listened (a monster not of the
## wild, or a wolf, or a fight): it hides.
func _look() -> void:
	for entity in World.monsters():
		if entity.spawned and not Companion.harmless(entity) \
				and World.distance(tile, entity.tile) <= SIGHT_RANGE and senses.sees(entity):
			if World.tick >= _hide_until and player_id.is_empty():
				Townsfolk.saw_raiders(World.production, worker_id)  # A fact on its card (decision 398).
			_hide_until = World.tick + HIDE_TICKS
			return
	for noise: Dictionary in senses.heard:
		if int(noise["tick"]) <= _listened:
			continue
		var source: Variant = noise["source"]
		var raider: bool = is_instance_valid(source) and source is Monster and not Companion.harmless(source)
		if raider or noise["kind"] == &"fight" or noise["kind"] == &"door_broken":
			_hide_until = World.tick + HIDE_TICKS
	if not senses.heard.is_empty():
		_listened = int(senses.heard.back()["tick"])


## Where it goes for what it is doing now: where it stands, if that is in
## the place already (but for a stroll in the square), else a free cell of
## the place; with no such place, the square's.
func _pick_goal() -> void:
	_route.clear()
	_retry_at = -1
	_stuck = 0
	var area: Rect2i = places.get(PLACE_OF[doing], places.get("square", Rect2i())) if doing != Doing.ROUNDS else _round_area()
	if doing == Doing.HIDE:
		area = places.get("shelter", places.get("home", places.get("square", Rect2i())))  # Its shelter (762), else home.
	if doing == Doing.VISIT and visit.get("rect") is Rect2i:
		area = visit["rect"]
	if doing == Doing.WORK and not task.is_empty():
		_goal = task["cell"]  # At the work the sim says (566): the woodlot's spot, the build's cells, the store with the log.
		return
	if _abed_time():
		_goal = _bed()
		return
	# Staggered by body (the coordinator: thirteen at once must not look like a drill); a seat is kept twice as long.
	_wander_at = World.tick + STROLL_TICKS + absi(hash([id, _picks])) % STROLL_SPREAD
	if bool(places.get("short_stands", false)):
		_wander_at = World.tick + SHORT_STAND_TICKS + absi(hash([id, _picks, "short"])) % SHORT_STAND_SPREAD  # 875.
	_spot = {}
	var spot := _free_spot(_spot_use())
	if not spot.is_empty():
		_spot = spot
		_set_goal(spot["cell"])
		if str(spot.get("pose", "")) == "sit":
			_wander_at = World.tick + SEAT_TICKS + absi(hash([id, _picks, "sit"])) % SEAT_SPREAD
		return
	if area.size == Vector2i.ZERO:
		_goal = tile
		return
	# In the temple (734 amended (4)): off its doors, its counter and its respawn (Main's "temple_keep").
	var keep: Array = places.get("temple_keep", []) if area == places.get("temple") else []
	# Always a cell to walk to in a doing that strolls (the mend): one it stood on already in the place kept
	# it there for hours (the square, the work, the inn and the well were one rect with no building for its
	# trade). Hiding, sick abed, led or at a bedside it stays where it is in the place, as before.
	var stays := (doing not in STROLLS or not keep_moving and not (doing == Doing.SQUARE and _goal != NO_CELL)) \
		and area.has_point(tile) and not keep.has(tile)
	_set_goal(tile if stays else _free_cell(area, keep))


## The home the lawspeaker's rounds (decision 459) have him at now: one of
## places["rounds"] ([{rect, who, id}], Main's, the town's homes in order),
## by the day and the hour; his own home when the town has none.
func _round_area() -> Rect2i:
	var stop := _round_stop()
	return stop.get("rect", places.get("home", Rect2i())) if not stop.is_empty() else places.get("home", Rect2i())


func _round_stop() -> Dictionary:
	var stops: Array = places.get("rounds", [])
	if stops.is_empty():
		return {}
	var now := DayNight.now()
	var index := Townsfolk.round_stop(stops.size(), Townsfolk.day_of(now), DayNight.hour(now))
	return stops[index] if index >= 0 and index < stops.size() and stops[index] is Dictionary else {}


## The cells with room _free_cell tries a way to before it takes a crowded one (853 amended (7)).
const ROOM_TRIES := 3


## A free cell of [param area] other than where it stands, from a start a hash of its id, the tick and
## its count of picks chooses, and not the cell it just left unless no other is free (the mend: a start
## of (id * 31 + tick) % 81 at a stroll every 81 ticks fell on the same cell each time, and Gar stepped
## between two cells all night); where it stands if none. With 853's moving on, a cell with room
## first (853 amended (7)): open ground (its eight neighbours walkable), none of them another body's
## cell or another resident's goal, and a way to it (find_path, ROOM_TRIES such cells at most); else
## any free cell, as before.
func _free_cell(area: Rect2i, keep: Array = []) -> Vector2i:
	var count := area.size.x * area.size.y
	if count <= 0:
		return tile
	_picks += 1
	var start := absi(hash([id, World.tick, _picks])) % count
	var near := _others_near() if keep_moving else {}
	var tries := 0
	var back := NO_CELL
	var crowded := NO_CELL
	for i in count:
		var at := area.position + Vector2i((start + i) % count % area.size.x, (start + i) % count / area.size.x)
		if at == tile or not World.is_free(at) or keep.has(at) or World.is_link_cell(at):
			continue  # A link's cell is a player's way out alone (571): Aldous stood two hours by the crypt stair.
		if at == _left:
			back = at
			continue
		if not keep_moving:
			return at
		if not near.has(at) and tries < ROOM_TRIES and World.DIRECTIONS.all(func(way: Vector2i) -> bool: return World.is_walkable(at + way)):
			tries += 1
			if not World.find_path(tile, at, false, null, RESIDENT_SEARCH_TILES, false, {}, true, World.PATH_FIRE_EXTRA,
					RESIDENT_BODIES_WITHIN).is_empty():
				return at
			continue  # Room it has no way to now.
		if crowded == NO_CELL:
			crowded = at  # Crowded, or room past ROOM_TRIES unchecked: as before 853 amended (7).
	if crowded != NO_CELL:
		return crowded
	return back if back != NO_CELL else tile


## The cells beside another body (853 amended (7), npc's look at Umbrage: strollers' free cells fell
## shoulder to shoulder, about 2,760 silent body-minutes a day): each cell on or next to another
## entity's, or next to another resident's goal. A talk pair's cells are spots ("talk"), not picked here.
func _others_near() -> Dictionary:
	var near := {}
	for other: GridEntity in World.entities():
		if other == self:
			continue
		var cells: Array[Vector2i] = [other.tile]
		if other is Resident and (other as Resident)._goal != NO_CELL and (other as Resident)._goal != other.tile:
			cells.append((other as Resident)._goal)
		for cell: Vector2i in cells:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					near[cell + Vector2i(dx, dy)] = true
	return near


## The goal [param cell], the cell it stands on noted as left when it is another.
## Main's places for it now (each sync, 875 amended (1)): when the place of its doing has moved and its goal
## is no longer in it, a new goal from the new place. A Mughouse goer whose evening ended was handed the
## floor's door as its every place but kept the corner of the common room it had just picked, and stood
## there till it was let go (maps' run, 21:45: the hunter at (11,11), spot_uses []); the goal was only
## picked again on a change of doing or a stroll, and abed it never strolls. A task's goal, its rounds, a
## visit and a walk with someone keep theirs.
func take_places(given: Dictionary) -> void:
	var key := str(PLACE_OF.get(doing, "square"))
	var was: Variant = places.get(key)
	places = given
	if _goal == NO_CELL or not task.is_empty() or doing in [Doing.ROUNDS, Doing.VISIT, Doing.ESCORT, Doing.STRAYED]:
		return
	var now: Variant = places.get(key)
	if now is Rect2i and now != was and (now as Rect2i).size != Vector2i.ZERO and not (now as Rect2i).has_point(_goal):
		_pick_goal()


func _set_goal(cell: Vector2i) -> void:
	if cell != tile:
		_left = tile
	_goal = cell


## Whether it strolls now (the mend): idle in a doing of STROLLS, no task, not abed, not addressing.
func _strolls() -> bool:
	return doing in STROLLS and task.is_empty() and addressing.is_empty() and not _abed_time()


## The spots' use its doing takes (Level.spots_from's "use"): the square's hours take the square's,
## the fire's and the talk's alike; "" for a doing with none.
func _spot_use() -> String:
	match doing:
		Doing.WORK:
			return "work" if task.is_empty() else ""
		Doing.SQUARE:
			return "square"
		Doing.WELL:
			return "well"
		Doing.INN:
			return "inn"
		Doing.TEMPLE:
			return "temple"
	return ""


## A free spot of [param use] from Main's places["spots"] (its town's; a work spot its trade's), not the
## one it stands on nor the one it just left unless no other is free, by the same changing hash as
## _free_cell; the square's hours choose among the square's, the fire's and the talk's spots; {} for none.
func _free_spot(use: String) -> Dictionary:
	if use.is_empty() or not places.get("spots") is Dictionary:
		return {}
	var spots: Dictionary = places["spots"]
	var pool: Array = []
	for each: String in (["square", "fire", "talk"] if use == "square" else [use]):
		pool.append_array(spots.get(each, []))
	if pool.is_empty():
		return {}
	if use == "work":
		# Behind a guest (875 amended (2)): a work spot facing the cell a guest's held stand faces (the taverner's
		# behind the counter end a drinker stands at), else as any.
		var behind := work_behind(pool, _stand_faces())
		if not behind.is_empty():
			return behind
	if use == "inn":
		var taken := {}
		for other: GridEntity in World.entities():
			if other != self and other is Resident and not (other as Resident)._spot.is_empty():
				taken[(other as Resident)._spot["cell"]] = true
		return inn_pick(pool, taken)
	_picks += 1
	var start := absi(hash([id, World.tick, _picks])) % pool.size()
	var back := {}
	var here := {}
	for i in pool.size():
		var spot: Dictionary = pool[(start + i) % pool.size()]
		var cell: Vector2i = spot["cell"]
		if cell == tile:
			if use == "work":
				here = spot  # 853 amended (13): the work spot it stands on, kept when no other is free.
			continue
		if not World.is_free(cell) or World.is_link_cell(cell):
			continue
		if cell == _left:
			back = spot
			continue
		return spot
	# None other free: at work it stays on its own (Rolf stepped off his stall's only spot each stroll, a minute or
	# two each, to a free cell of his work rect: maps' day run); a seat on the square or a well's stand is still
	# left for a stroll (the mend: folk move on). Else back to the one it left.
	return here if not here.is_empty() else back


## The cells the inn's counter stands other bodies hold face (875 amended (2)): where guests drink.
func _stand_faces() -> Dictionary:
	var faces := {}
	for other: GridEntity in World.entities():
		if other != self and other is Resident and str((other as Resident)._spot.get("pose", "")) == "stand" \
				and str((other as Resident)._spot.get("use", "")) == "inn":
			faces[(other as Resident)._spot.get("face")] = true
	return faces


## The work spot of [param pool] to move to between bouts (875 amended (3)): when the one it holds faces
## no guest's stand of [param faces] and another free one does, that one; else {} (it stays).
func guest_end(pool: Array, faces: Dictionary) -> Dictionary:
	if pool.size() < 2 or faces.is_empty() or _spot.is_empty() or faces.has(_spot.get("face")):
		return {}
	var end := work_behind(pool, faces)
	return {} if end.is_empty() or end.get("cell") == _spot.get("cell") else end


## Of [param pool]'s free work spots, one facing a cell in [param faces] (the cells guests' held counter stands
## face), {} for none (875 amended (2)): the taverner tends the end of the bar a guest drinks at.
func work_behind(pool: Array, faces: Dictionary) -> Dictionary:
	if faces.is_empty():
		return {}
	for spot: Dictionary in pool:
		var cell: Vector2i = spot["cell"]
		if faces.has(spot.get("face")) and (cell == tile or (World.is_free(cell) and not World.is_link_cell(cell))):
			return spot
	return {}


## The inn's room (875 amended (2), the coordinator's ruling): of [param pool]'s free spots, not in
## [param taken] (the cells other bodies hold or are walking to), the first group with one: a table seat (a
## "talk" spot with a "pair") whose mate is held, so it joins a pair talking; the fire (a sit that is no
## table's) while fewer than INN_FIRE_MOST of its seats are held; a table pair with neither held while no
## table is held, so it starts the first; the counter (a "stand") while fewer than INN_COUNTER_FIRST stand
## there; another table pair; the counter; then any. Groups read from the spots themselves, nothing in data:
## Umbrage's five hearth stools all filled before a second table seat, a hearth in an empty room.
func inn_pick(pool: Array, taken: Dictionary) -> Dictionary:
	var pairs := {}  # pair -> its cells
	var fire_held := 0
	var counter_held := 0
	var table_held := false
	for spot: Dictionary in pool:
		var pair := str(spot.get("pair", "")) if str(spot.get("use", "")) == "talk" else ""
		if not pair.is_empty():
			(pairs.get_or_add(pair, []) as Array).append(spot["cell"])
			table_held = table_held or taken.has(spot["cell"])
		elif taken.has(spot["cell"]):
			if str(spot.get("pose", "")) == "stand":
				counter_held += 1
			else:
				fire_held += 1
	var groups: Array = [[], [], [], [], [], [], []]  # join, fire, the first pair, the counter's first, another pair, the counter, any
	var back := {}
	var here := {}
	for spot: Dictionary in pool:
		var cell: Vector2i = spot["cell"]
		if cell == tile and not taken.has(cell):
			here = spot  # Seated with nowhere else free, it stays (853 amended (13)'s rule).
			continue
		if cell == tile or taken.has(cell) or not World.is_free(cell) or World.is_link_cell(cell):
			continue
		if cell == _left:
			back = spot
			continue
		var pair := str(spot.get("pair", "")) if str(spot.get("use", "")) == "talk" else ""
		if not pair.is_empty():
			var mate_held := (pairs[pair] as Array).any(func(c: Vector2i) -> bool: return c != cell and taken.has(c))
			groups[0 if mate_held else (4 if table_held else 2)].append(spot)
		elif str(spot.get("pose", "")) == "stand":
			groups[3 if counter_held < INN_COUNTER_FIRST else 5].append(spot)
		else:
			groups[1 if fire_held < INN_FIRE_MOST else 6].append(spot)
	_picks += 1
	for group: Array in groups:
		if not group.is_empty():
			return group[absi(hash([id, World.tick, _picks])) % group.size()]
	return here if not here.is_empty() else back


## Standing idle or at a spot, it faces the open (the mend: Hob stood seven hours with his face to the
## well's stone): at a spot its "face"; else, the cell before it shut, the open way of the eight
## nearest the middle of its place.
func _face_open() -> void:
	if not _spot.is_empty() and tile == _spot.get("cell"):
		var way := _toward(_spot["face"])
		if facing != way:
			World.face(self, way)
		return
	if facing != Vector2i.ZERO and World.is_walkable(tile + facing):
		return
	var area: Rect2i = places.get(PLACE_OF.get(doing, "square"), places.get("square", Rect2i()))
	var middle := Vector2(area.get_center()) if area.size != Vector2i.ZERO else Vector2(tile)
	var best := Vector2i.ZERO
	var best_d := INF
	for way: Vector2i in World.DIRECTIONS:
		if not World.is_walkable(tile + way):
			continue
		var d := Vector2(tile + way).distance_squared_to(middle)
		if d < best_d:
			best_d = d
			best = way
	if best != Vector2i.ZERO and facing != best:
		World.face(self, best)


## The voice ask for [param line], said to it by [param speaker]
## (CompanionMind.voice's shape, plain text back).
func voice_ask(speaker: String, line: String, serial: int) -> Dictionary:
	var system := system_for(speaker, asked_topics(line))
	var user := "%s says to you: \"%s\"" % [speaker, line]
	return {"kind": "voice", "serial": serial, "trigger": "%s spoke to %s." % [speaker, person], "speaker": person,
		"system": system, "user": user, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
		"spoken_to": true, "asked": true, "heard": line}


## The one prompt for who they are (voice_ask's and hail_ask's); [param about] what was asked (asked_topics), its facts first.
func system_for(speaker: String, about := PackedStringArray()) -> String:
	return VOICE % [person, town_name if not town_name.is_empty() else "a town", " as a " + trade if not trade.is_empty() else "", card_words(),
		" ".join(facts_now(about)), speaker, bound_words()]


# --- Speaking unprompted (decision 554) ------------------------------------------------

## The user turn of a hail: the cue is the whole of what is on their mind.
const HAIL_USER := "%s comes within speaking distance of you. One thing is on your mind: %s Say one line to them about it, unprompted, as yourself and in your own words, not the words above. Say only what the thought holds: add no place, cause, name or detail it does not give, for nothing else is true. Ask nothing of them you would not ask to their face."
## The trial's turn (554 amended; Jeff, 2026-10-22: "trial with livelier"), chosen by townsfolk.json hail.lively:
## one small everyday detail allowed, nothing invented that the bound names. Strict is one edit away.
const HAIL_USER_LIVELY := "%s comes within speaking distance of you. One thing is on your mind: %s Say one line to them about it, unprompted, as yourself and in your own words, not the words above. Say what the thought holds, in your own colour: you may add one small everyday detail of your own things (a broken wheel, a barrel, the mud on your boots), but invent no person, no place, no building, no name, no price, no weather, no cause, and cast no doubt on the thought; name nobody it does not, for nothing else is true. Ask nothing of them you would not ask to their face."

## The greeting cue by standing (Standing.words' word -> the thought).
const HAIL_GREETINGS := {
	"stranger": "%s is a stranger to you; you greet them as the town does a newcomer.",
	"known": "You have met %s before; you greet them as one you know.",
	"trusted": "You trust %s; you greet them warmly.",
	"wronged": "%s wronged you once; you greet them coolly, and say so without a quarrel.",
}
## A stranger's greeting, each resident's own (by its id), so a town does not
## greet a newcomer with one line three times (playtest's reward tour; the
## coordinator: Jeff's "same things a lot"; voice's words: none says "as the
## town does a newcomer", which made "You're new to the town" every time).
const HAIL_STRANGER := [
	"%s is a stranger to you; you remark on something they carry or wear.",
	"%s is a stranger to you; you ask them what brings them here.",
	"%s is a stranger to you; you tell them your name and your trade.",
	"%s is a stranger to you; you wish them a good day and ask whether they mean to stay.",
	"%s is a stranger to you; you give them a short nod and a word of welcome, no more.",
	"%s is a stranger to you; you ask where they've come from and say a word about the road.",
]
## A stranger the town already knows of (Main's known_of: what they did here,
## or that others in town have met them): no longer new to all of it.
const HAIL_KNOWN_OF := "%s is a stranger to you, but you have heard of them: %s. You greet them as someone whose name has reached you, and say what you heard."

## Spoken unprompted to [param speaker] (decision 554; the ask Main queues
## as a voice ask, lowest of all): voice_ask's shape with [param cue]
## ({kind, text}, hail_cue's) as the user turn, trigger "hail: <kind>".
func hail_ask(speaker: String, cue: Dictionary, serial: int, how := "hail") -> Dictionary:
	var system := system_for(speaker)
	# The lively trial (554 amended) colours the news, the ruling and the sky only: a plea is an ask with a number in
	# it (the colour twice ate the sum in the batch), a greeting a table word; both keep the strict turn.
	var lively := bool(Townsfolk.rules().get("hail", {}).get("lively", false)) and str(cue.get("kind", "")) in SHARED_CUES
	var user := (HAIL_USER_LIVELY if lively else HAIL_USER) % [speaker, str(cue.get("text", ""))]
	return {"kind": "voice", "serial": serial, "trigger": "%s: %s, %s to %s." % [how, str(cue.get("kind", "")), person, speaker], "speaker": person,
		"system": system, "user": user, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
		"spoken_to": false, "asked": false, "heard": "", "hail": str(cue.get("kind", "")), "cue": str(cue.get("text", ""))}


## Their hails on [param card]: {to: {player id: day of the last}, said:
## [the cue texts said, newest last, said_kept of them], sky: the sky
## sentence last hailed about}, made when missing.
static func hails_of(card: Dictionary) -> Dictionary:
	var hails: Variant = card.get("hails")
	if not hails is Dictionary:
		hails = {}
		card["hails"] = hails
	if not hails.get("to") is Dictionary:
		hails["to"] = {}
	if not hails.get("said") is Array:
		hails["said"] = []
	return hails


## Whether [param card]'s person hailed [param player_id] on [param day] already.
static func hailed_today(card: Dictionary, player_id: String, day: int) -> bool:
	return int(hails_of(card).get("to", {}).get(player_id, -1)) == day


## What [param worker_id] has to say to [param player_id] ([param player_name])
## on first seeing them today, from the card, the town's news and its memory
## only, the first that applies: their own plea (Offers' plea: kin sick, a
## loan, a grudge), the town's own news of today (its event lines: a wagon
## struck, home or lost, the runner; never talk, which hails themselves
## feed), a memory the lawspeaker ruled today, the sky ([param sky],
## DayNight.describe's sentence) when it has changed since they last spoke
## of it, a greeting by standing. A cue said to anyone before (the card's
## said) is skipped, and a shared one (SHARED_CUES) this player heard today
## from anyone ([param heard], Main's); no greeting when [param greeting_ok]
## is false (Main's cap of hail.greetings_a_day a player a day from the
## whole town, the coordinator's: a newcomer is greeted, not mobbed). A
## stranger's greeting is the resident's own of HAIL_STRANGER, or, with
## [param known_of] (what the town knows of them), HAIL_KNOWN_OF.
## {kind, text}, {} for nothing to say.
static func hail_cue(worker_id: String, town: String, player_id: String, player_name: String, production: Production, now: int, sky: String,
		given: Dictionary = Offers.ctx, heard: Array = [], greeting_ok := true, known_of := "") -> Dictionary:
	var card := Townsfolk.card_of(production, worker_id)
	if card.is_empty():
		return {}
	var hails := hails_of(card)
	var said: Array = hails["said"]
	var today := Townsfolk.day_of(now)
	var cues: Array[Dictionary] = []
	var with_production := given.duplicate()
	with_production["production"] = production
	for offer: Dictionary in Offers.of(worker_id, player_id, with_production):
		if str(offer.get("kind", "")) == Offers.PLEA and not str(offer.get("words", "")).is_empty():
			cues.append({"kind": "plea", "text": "You have a plea to make: %s" % _sentence(str(offer["words"]))})
			break
	var log: Variant = Offers._call(given, "memory", [town]) if not town.is_empty() else null
	if log is Array:
		var newest := {}
		var ruled := {}
		for entry: Variant in log:
			if not entry is Dictionary or str(entry.get("tier", "")) == TownMemory.LEFT:
				continue
			var ruling: Variant = entry.get("ruling", {})
			if bool(entry.get("event", false)) and str(entry.get("said_by", "")) != worker_id and (not ruling is Dictionary or ruling.is_empty()) \
					and str(entry.get("about", "")) != player_id \
					and Townsfolk.day_of(int(entry.get("first_said", -1))) == today and int(entry.get("first_said", -1)) >= int(newest.get("first_said", -1)):
				newest = entry
			if ruling is Dictionary and ruling.has("step") and Townsfolk.day_of(int(ruling.get("step", -1))) == today and int(ruling.get("step", -1)) >= int(ruled.get("ruling", {}).get("step", -1)):
				ruled = entry
		if not newest.is_empty():
			cues.append({"kind": "news", "text": "I heard today that %s" % _sentence(_lead(str(newest.get("text", ""))))})
		if not ruled.is_empty():
			var because := str(ruled.get("ruling", {}).get("because", ""))
			cues.append({"kind": "ruling", "text": "I heard the lawspeaker rule today that %s%s" % [_lead(str(ruled.get("text", ""))).trim_suffix("."),
				_sentence(", because " + because.trim_suffix(".")) if not because.is_empty() else "."]})
	if not sky.is_empty() and str(hails.get("sky", "")) != sky:
		cues.append({"kind": "sky", "text": _sentence(sky)})
	var word := Standing.words(card, player_id) if Standing.met_in_person(card, player_id) else "stranger"  # Heard of, not met (853 amended (5)).
	if greeting_ok and word == "stranger":
		cues.append({"kind": "greeting", "text": HAIL_KNOWN_OF % [player_name, known_of.trim_suffix(".")] if not known_of.is_empty()
			else str(HAIL_STRANGER[absi(hash(worker_id)) % HAIL_STRANGER.size()]) % player_name})
	elif greeting_ok and HAIL_GREETINGS.has(word):
		cues.append({"kind": "greeting", "text": HAIL_GREETINGS[word] % player_name})
	for cue: Dictionary in cues:
		if said.has(cue["text"]):
			continue
		if str(cue["kind"]) in SHARED_CUES and heard.has(cue["text"]):
			continue  # The town's one fact a day to this player; a greeting or a plea is each resident's own.
		return cue
	return {}


## The cue kinds that are the town's to tell once a day to one player (the
## heard argument); the plea and the greeting are each resident's own.
const SHARED_CUES := ["news", "ruling", "sky"]


## [param text] with its first letter lowered after "I heard ...", unless
## its first word is a name (anything but these openers keeps its capital).
const LEAD_WORDS := ["The", "A", "An", "It", "There", "They", "He", "She", "We", "Our", "Their", "His", "Her", "Some", "No", "Two", "Three", "Many"]
static func _lead(text: String) -> String:
	var first := text.get_slice(" ", 0)
	return Hearsay._lower_first(text) if LEAD_WORDS.has(first) else text


## [param text] ended with a full stop when it has none.
static func _sentence(text: String) -> String:
	var clean := text.strip_edges()
	return clean if clean.is_empty() or clean.ends_with(".") or clean.ends_with("!") or clean.ends_with("?") else clean + "."


## A hail of [param worker_id] to [param player_id] that was not said (the
## mind slow or down): the day's mark and the cue's text go back off the
## card, so it can be tried again later today.
static func hail_undone(production: Production, worker_id: String, player_id: String, cue_text: String) -> void:
	var card := Townsfolk.card_of(production, worker_id)
	if card.is_empty():
		return
	var hails := hails_of(card)
	hails["to"].erase(player_id)
	hails["said"].erase(cue_text)
	production.set_card(worker_id, card)


## [param cue] said by [param worker_id] to [param player_id] on
## [param day] (the hail queued): the card remembers the day, the text
## (the newest said_kept, townsfolk.json "hail") and the sky it spoke of.
static func hail_done(production: Production, worker_id: String, player_id: String, cue: Dictionary, day: int, sky: String) -> void:
	var card := Townsfolk.card_of(production, worker_id)
	if card.is_empty():
		return
	var hails := hails_of(card)
	hails["to"][player_id] = day
	var said: Array = hails["said"]
	said.append(str(cue.get("text", "")))
	var keep := int(Townsfolk.rules().get("hail", {}).get("said_kept", 8))
	while said.size() > keep:
		said.pop_front()
	if str(cue.get("kind", "")) == "sky":
		hails["sky"] = sky
	production.set_card(worker_id, card)


# --- Visible work (decision 566, npc's side) ---------------------------------------------

## The body's activity from the sim's state, each tick: at work with a task,
## the task's kind once at its cell (facing the task's "face" cell), or on
## the way when the task is "walking" (a log carried home); at home in the
## sleep hours, "sleep" on the bed cell, lying along the room's long side
## with the head to the wall; else "". A task's goal is kept when the
## routine's pick strayed from it.
func _show_work() -> void:
	var was := activity
	_show_work_now()
	if GET_UP.has(was) and activity != was:
		_rise_until = World.tick + int(GET_UP[was])  # Its get-up plays out on its cell (animation's).


func _show_work_now() -> void:
	if doing == Doing.WORK and not task.is_empty():
		var cell: Vector2i = task.get("cell", NO_CELL)
		if cell != NO_CELL and _goal != cell:
			_aim(cell)
		if tile == cell:
			# The stroke starts once the body has turned to its work (521 amended; the soak caught chops facing
			# the way it arrived): World.face is refused while the arriving step still runs.
			var face: Vector2i = task.get("face", NO_CELL)
			if face != NO_CELL and face != tile and facing != _toward(face):
				World.face(self, _toward(face))
			# A load carried there (walking) stays on the shoulder while it turns (853 amended (12)): it goes
			# down when the sim's next leg says, not for the turn.
			activity = str(task.get("kind", "")) if bool(task.get("walking", false)) or face == NO_CELL or face == tile or facing == _toward(face) else ""
		else:
			activity = str(task.get("kind", "")) if bool(task.get("walking", false)) else ""
		return
	if _abed_time():
		var bed := _bed()
		var head := _head()
		if _goal != bed:
			_aim(bed)
		if tile == bed:
			if facing != head:
				World.face(self, head)
			activity = "sleep" if facing == head else ""
		else:
			activity = ""
		return
	var on_spot: bool = not _spot.is_empty() and tile == _spot.get("cell") and facing == _toward(_spot["face"])
	if on_spot and doing == Doing.WORK and task.is_empty() and str(_spot.get("use", "")) == "work":
		var word := show_word(str(_spot.get("trade", "")))
		if _bout_end >= 0 and World.tick >= _bout_end:
			# Between bouts, to the counter end a guest has come to (875 amended (3); maps' film at 22:00: the
			# taverner tended (8,2) with her one guest at (10,4), as she had picked on taking the spot).
			var spots: Variant = places.get("spots")
			var end := guest_end(spots.get("work", []) if spots is Dictionary else [], _stand_faces())
			if not end.is_empty():
				_spot = end
				_set_goal(end["cell"])
				_shown = ""
				_bout_end = -1
				activity = ""
				return
		if not word.is_empty():
			activity = word if _bout(word) else ""  # Shown work (853 amended (8)): its trade's, in bouts.
			return
	_shown = ""
	_bout_end = -1
	var pose := str(_spot.get("pose", "")) if on_spot else ""
	activity = pose if pose in POSES else ""


## The word a work spot of [param trade] shows (853 amended (8), slice 2): levels/residents.json
## "show", "" for a trade with none (its clip or prop not in yet).
static func show_word(trade: String) -> String:
	var table: Variant = Townsfolk.days().get("show", {})
	return str(table.get(trade, "")) if table is Dictionary and not trade.is_empty() and trade != "_" else ""


## Whether it shows its trade's work now (853 amended (8)): Main stops it for a hail or a sale.
func showing_work() -> bool:
	return not _shown.is_empty() and activity == _shown


## Whether it is on its work spot showing its work, in a bout or the rest between (853 amended (8)).
func at_shown_work() -> bool:
	return not _shown.is_empty()


## Whether this tick is in a bout of [param word]'s work (true) or a rest between (false): a fresh
## stay starts with work; each bout's length is the body's own (BOUT_WORK, BOUT_REST).
func _bout(word: String) -> bool:
	if _shown != word or _bout_end < 0:
		_shown = word
		_bout_on = true
		_bout_end = World.tick + _bout_ticks(true)
	elif World.tick >= _bout_end:
		_bout_on = not _bout_on
		_bout_end = World.tick + _bout_ticks(_bout_on)
	return _bout_on


func _bout_ticks(work: bool) -> int:
	var span := BOUT_WORK if work else BOUT_REST
	return (span.x + absi(hash([id, _bout_end, work])) % (span.y - span.x + 1)) * World.TICK_RATE


## A new goal, the route begun afresh.
func _aim(cell: Vector2i) -> void:
	_goal = cell
	_route.clear()
	_stuck = 0


## The direction from here toward [param cell], one of the eight.
func _toward(cell: Vector2i) -> Vector2i:
	var d := cell - tile
	if d == Vector2i.ZERO:
		return facing
	return Vector2i(signi(d.x), signi(d.y)) if absi(d.x) == absi(d.y) else (Vector2i(signi(d.x), 0) if absi(d.x) > absi(d.y) else Vector2i(0, signi(d.y)))


## Whether this body goes to bed now (decision 751): the sleep hours, a bed
## under a roof (Main's places["bed"]: its house, else the inn, else a roofed
## workplace; none, it stays up), and not woken this hour.
func sleeps_now() -> bool:
	return asleep_now(worker_id) and places.get("bed") is Rect2i and (places["bed"] as Rect2i).size != Vector2i.ZERO \
		and DayNight.now() >= _woken_until


## Where it lies (decision 751): its bed's cell (Main's places["bed_at"],
## buildings' bed, npc's side (4)), else the corner rule in places["bed"].
func _bed() -> Vector2i:
	var at: Variant = places.get("bed_at")
	if at is Dictionary and (at as Dictionary).get("cell") is Vector2i:
		return at["cell"]
	return bed_cell(places.get("bed", places.get("home", Rect2i())), places.get("square", Rect2i()))  # 875 amended (1): a floor's goer has no bed.


## The way its head points in bed: the bed's own (places["bed_at"]), else
## along the room's long side into the corner.
func _head() -> Vector2i:
	var at: Variant = places.get("bed_at")
	if at is Dictionary and (at as Dictionary).get("head") is Vector2i and at["head"] != Vector2i.ZERO:
		return at["head"]
	return head_of(places["bed"], _bed())


## Whether it goes to its bed now (751): in its sleep spell, at home; or (751 amended (6), the coordinator's
## ruling: the medicine man stood his whole spell at his hut a cell from his own bed, his night pick being
## work) at work with no task when its bed lies in the place it works at or in the building that holds it.
## It sleeps there and keeps the work the rest of the night.
func _abed_time() -> bool:
	if not sleeps_now():
		return false
	if doing == Doing.HOME:
		return true
	if doing != Doing.WORK or not task.is_empty():
		return false
	var bed := _bed()
	var work: Rect2i = places.get("work", Rect2i())
	if work.size == Vector2i.ZERO:
		return false
	if work.has_point(bed):
		return true
	var roof: Dictionary = Companion.building_at(bed)
	return not roof.is_empty() and roof == Companion.building_at(work.get_center())


## Whether it lies asleep in its bed now (decision 751): silent, no talk.
func sleeping() -> bool:
	return activity == "sleep" and sleeps_now()


## Woken (decision 751): up for the rest of the game hour, out of bed.
func wake() -> void:
	if not asleep_now(worker_id):
		return
	_woken_until = DayNight.now() + maxi(DayNight.day_steps, 24) / 24.0
	if activity == "sleep":
		activity = ""
		_pick_goal()


## Whether [param of_id]'s sleep spell holds now (772: Townsfolk.sleep_spell;
## residents.json "sleep" from..to for no id).
static func asleep_now(of_id := "") -> bool:
	return Townsfolk.asleep_at(of_id, DayNight.hour(DayNight.now()))


## The bed in [param home]: its walkable corner farthest from the square's
## middle (the door's side faces the street), else its middle.
static func bed_cell(home: Rect2i, square: Rect2i) -> Vector2i:
	var middle := square.get_center() if square.size != Vector2i.ZERO else home.get_center()
	var corners: Array[Vector2i] = [home.position, home.position + Vector2i(home.size.x - 1, 0),
		home.position + Vector2i(0, home.size.y - 1), home.position + home.size - Vector2i.ONE]
	corners.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - middle).length_squared() > (b - middle).length_squared())
	for corner: Vector2i in corners:
		if World.is_walkable(corner):
			return corner
	return home.get_center()


## Which way a sleeper's head points on [param bed] in [param home]: along
## the room's long side, into the corner.
static func head_of(home: Rect2i, bed: Vector2i) -> Vector2i:
	var middle := home.get_center()
	if home.size.x >= home.size.y:
		return Vector2i(1 if bed.x >= middle.x else -1, 0)
	return Vector2i(0, 1 if bed.y >= middle.y else -1)


# --- Addressed by a click (decision 560, npc's side) -------------------------------------

## Stops and turns to [param target], addressing them for [param ticks] while they stay within
## [param reach] (ADDRESS_REACH; a hail called across the square, its distance then).
func address(target: GridEntity, ticks: int, reach := ADDRESS_REACH) -> void:
	if showing_work():
		# Spoken to, it stops its work for the talk (853 amended (8)): its get-up on its cell, and a fresh
		# bout once the talk is over.
		_rise_until = World.tick + int(GET_UP.get(activity, 0))
		activity = ""
		_bout_end = -1
	addressing = String(target.get_path())
	_address_until = World.tick + ticks
	_address_reach = maxi(reach, ADDRESS_REACH)
	var d := target.tile - tile
	if d != Vector2i.ZERO:
		var way := Vector2i(signi(d.x), signi(d.y)) if absi(d.x) == absi(d.y) else (Vector2i(signi(d.x), 0) if absi(d.x) > absi(d.y) else Vector2i(0, signi(d.y)))
		World.face(self, way)
		if facing != way and Net.is_authority() and spawned:
			_world_set_facing(way)  # Clicked mid-stroll (853): World.face waits out a step; a click turns it now.


## The word said at once when clicked, from townsfolk.json "greet": the
## standing's word when [param standing_word] has one (wronged, known,
## trusted), else one of the trade's lines (the default's for a trade not
## listed), picked by [param seed] so the same person says the same thing
## for a day and another the next.
static func greet_word(trade: String, standing_word: String, rules: Dictionary, seed: int) -> String:
	var by_standing: Variant = rules.get("standing", {})
	if by_standing is Dictionary and by_standing.has(standing_word):
		# Wronged and trusted: one of their lines by the day (853 amended (5)); known has the trade's, as a stranger.
		var said: Variant = by_standing[standing_word]
		if said is Array and not (said as Array).is_empty():
			return str(said[absi(seed) % (said as Array).size()])
		if said is String:
			return said
	var trades: Variant = rules.get("trades", {})
	var lines: Variant = trades.get(trade, trades.get("default", [])) if trades is Dictionary else []
	if not lines is Array or (lines as Array).is_empty():
		return "What is it?"
	return str(lines[absi(seed) % (lines as Array).size()])


## Who it is: a companion's own card; else its resident card (decision 398:
## Townsfolk.card_of, rolled by its worker id and kept on the worker
## record: the written paragraph or the plain facts), its hidden type when
## it has one (decision 393: a standing fact, kept hidden, that shapes its
## lines; the type's profile, companions' 378, does the rest), and what has
## become true of it since (the card's facts, newest first).
func card_words() -> String:
	if not card.is_empty():
		return card
	var own := Townsfolk.card_of(World.production, worker_id)
	var words := ResidentCard.words(own) if not own.is_empty() else "%s lives and works in the town." % person
	if not type.is_empty() and type != Townsfolk.STEADY:
		words += "\n%s is a %s, and keeps it hidden." % [person, type.replace("_", " ")]
	var facts := ResidentCard.facts_words(own) if not own.is_empty() else ""
	if not facts.is_empty():
		words += "\n" + facts
	return words


## What is true now, a sentence each: the hour and the weather, its work,
## how it last ate and traded (means_words), whether raiders have carried it
## off before (Towns.taken_before), what the town is short of, what its shop
## has.
func facts_now(about := PackedStringArray()) -> Array[String]:
	var out: Array[String] = []
	var hour := Companion.time_words(DayNight.hour(DayNight.now()))
	var sky := ""
	if World.fields.outdoor and Companion.WEATHER_WORDS.has(str(World.fields.weather.get("kind", ""))):
		sky = ", and " + Companion.WEATHER_WORDS[World.fields.weather["kind"]]
	out.append("It is %s%s." % [hour, sky])
	out.append("You are %s." % WHERE_WORDS.get(doing, "in the town"))
	var sick := Townsfolk.sickness_of(World.production, worker_id)
	if not sick.is_empty():
		# Sick (decision 501): what ails it, how long, and whether anyone has seen to it.
		var days := Townsfolk.day_of(World.steps) - int(sick.get("since", 0))
		out.append("You are sick with %s and have kept to your bed %s." % [sick.get("kind", "a fever"), "since this morning" if days <= 0 else "for %d day%s" % [days, "" if days == 1 else "s"]])
		if int(sick.get("treated", -1)) >= 0:
			out.append("%s saw to you today, and you expect to be on your feet tomorrow." % sick.get("cured_by", "Someone"))
		else:
			out.append("Nobody has seen to you yet. You would be glad of the medicine man, or of being walked to the healer's hut, or of a remedy.")
	if laid_up():
		out.append(str(guard_rule().get("laid_up", "You were carried to the temple hurt in last night's fighting, and are off duty until tomorrow.")))  # 791.
	elif bool(visit.get("post", false)):
		out.append("Something is coming at %s in the dark, and you are going there to stand with the watch." % visit.get("name", "a post"))  # 771 amended (3).
	elif not visit.is_empty():
		out.append("You are on your way to %s's bedside, to see to %s." % [visit.get("name", "a neighbour"), visit.get("name", "them")])
	if not sought.is_empty():
		# The sought (decision 613, npc's side): who sent for it, where it is and why it follows, or will not yet.
		var town_word := str(World.holdings.place(town).get("name", town)) if World.holdings != null else town
		var trade_word := trade.replace("_", " ")
		var where_word := Towns.where_words(where)
		if not escort_of.is_empty() and not escort_name.is_empty():
			out.append("%s found you %s and is leading you to %s, whose people sent word for a %s; you will live and work there as its %s, and you follow close." % [escort_name, where_word, town_word, trade_word, trade_word])
		elif holder.is_empty():
			out.append("You set out for %s, whose people sent word for a %s, and lost your way %s. You have not been there yet and know nobody in it. You would follow whoever speaks to you, and ask nothing else." % [town_word, trade_word, where_word])
		else:
			out.append("You are held %s by the %s and made to work for them. You will follow nobody while one of them can see you, and you say so plainly; when none of them watches, a word from whoever speaks to you and you go. You set out for %s, whose people sent word for a %s, and have never been there." % [where_word, holder.replace("_", " "), town_word, trade_word])
	elif strayed:
		# Lost beyond the walls (decision 487): where home lies, and that it follows whoever speaks to it.
		var square: Rect2i = places.get("square", Rect2i())
		var toward := ""
		if square.size != Vector2i.ZERO:
			var d := square.get_center() - tile
			toward = (" The town lies to the %s." % ("east" if d.x > 0 else "west")) if absi(d.x) >= absi(d.y) else (" The town lies to the %s." % ("south" if d.y > 0 else "north"))
		if doing == Doing.ESCORT and not escort_name.is_empty():
			out.append("You lost your way beyond the walls; %s is walking you home and you follow close.%s" % [escort_name, toward])
		else:
			out.append("You lost your way beyond the walls and have not been home.%s You would be glad to be walked home: you follow whoever speaks to you." % toward)
	if trade == "lawspeaker":
		# The town's lawspeaker (decision 459): what he is for, whose door he
		# stands at, and the disputes before him.
		out.append("You are the town's lawspeaker: you keep what the town remembers and hold it straight. Lore is fact; what the town remembers is memory; one person's talk is talk.")
		var scholar := _scholar_of_town()
		if not scholar.is_empty():
			out.append("%s, the town's scholar, keeps the chronicle: what is set down there the town remembers; send a doubter to %s." % [scholar, scholar])  # 491
	if hidden_type() == Townsfolk.SCHOLAR:
		# The scholar's chronicle (decision 491): what they keep, and what they proposed to lore.
		out.append("You keep the town's chronicle: what the lawspeaker set down, what the town proposed to the lore-keepers, and the disputes before him. When asked what is true, say what is set down and no more.")
		var kept: Variant = Offers._call(Offers.ctx, "memory", [town]) if not town.is_empty() else null
		var statuses: Variant = Offers._call(Offers.ctx, "statuses")
		if kept is Array:
			for entry: Variant in kept:
				if entry is Dictionary and bool(entry.get("proposed", false)):
					var status := str(statuses.get("%s %s" % [town, entry.get("id", "")], "open")) if statuses is Dictionary else "open"
					out.append("You proposed to the lore-keepers that %s: it is %s." % [TownMemory.clause(str(entry.get("text", ""))), status])
		var stop := _round_stop()
		if doing == Doing.ROUNDS and not str(stop.get("who", "")).is_empty():
			out.append("You stand at %s's door." % stop["who"])
		var log: Variant = Offers._call(Offers.ctx, "memory", [town]) if not town.is_empty() else null
		if log is Array:
			for entry: Variant in log:
				if entry is Dictionary and bool(entry.get("dispute", false)) and str(entry.get("tier", "")) in [TownMemory.BELIEF, TownMemory.CANDIDATE]:
					out.append("A dispute is before you: %s, says %s.%s" % [Hearsay._lower_first(str(entry.get("text", ""))),
						World.production.worker(str(entry.get("said_by", ""))).get("name", "someone") if World.production != null else "someone",
						" %s laid it before you." % entry["brought"].get("by_name", "A traveller") if entry.get("brought") is Dictionary else ""])
	out.append(work_words())
	out.append_array(means_words())
	# What it knows of the world, and has heard (decision 378); a companion
	# resting here knows what she knows with her player (decision 381).
	if not player_id.is_empty():
		var hers := Companion.lore_words(person)
		if not hers.is_empty():
			out.append(hers)
	if not asked_facts.is_empty():
		out.append("What was just asked, and what is true of it now: %s" % " ".join(asked_facts))  # 890, ahead of lore.
	var known := world_facts(about)
	if not known.is_empty():
		out.append("What you know of the world: %s" % " ".join(known))
	if binding() in ["townsfolk", "free"] and World.production != null:
		var heard := Hearsay.prompt_words(World.production.worker(worker_id).get("heard", []))
		if not heard.is_empty():
			out.append(heard)
	# A companion who left her player (581 amended, npc's side): why, and what
	# might bring her back, only to that player; companions' words, as written.
	if not player_id.is_empty() and player_id == asked_by and World.production != null:
		for id: String in World.production.worker_ids():
			var record := World.production.worker(id)
			if str(record.get("origin", "")) != Townsfolk.COMPANION + player_id:
				continue  # Her worker ("companion:<her name>") has her player for its origin.
			for key: String in ["left_why", "left_back"]:
				if not str(record.get(key, "")).is_empty():
					out.append(str(record[key]))
	# Why they would not travel with the one asking (686, npc's side); companions' words, as written.
	if not asked_by.is_empty() and World.production != null:
		var refused := str(World.production.worker(worker_id).get("asked", {}).get(asked_by, ""))
		if not refused.is_empty():
			out.append(refused)
	# What it can offer the one speaking to it, and what they promised it
	# (decision 435): facts, never lines.
	if player_id.is_empty() and not asked_by.is_empty():
		var offered := Offers.voice_words(worker_id, asked_by, asked_by_name)
		if not offered.is_empty():
			out.append(offered)
	# What it thinks of them, and whether they have spoken before (decision 443).
	if player_id.is_empty() and not asked_by.is_empty() and World.production != null:
		var card := Townsfolk.card_of(World.production, worker_id)
		if first_words:
			out.append("This is the first time %s has spoken to you." % asked_by_name)
		else:
			var regard := Standing.fact(card, asked_by, asked_by_name)
			if not regard.is_empty():
				out.append(regard)
	# A companion's past is in her own card; a resident's, in the town's records.
	var taken := World.towns.taken_before(worker_id) if World.towns != null and player_id.is_empty() else 0
	if taken > 0:
		out.append("You have been carried off by raiders %s, and brought home." % ("once" if taken == 1 else "twice" if taken == 2 else "more than twice"))
	if World.production != null:
		var short: Dictionary = World.production.signals_of(town, Production.items_catalog()).get("short", {})
		var wants: Array = short.keys()
		wants.sort()
		out.append("The town is short of %s." % _listed(wants) if not wants.is_empty() else "The town is short of nothing it needs.")
	if World.economy != null:
		var counts := {}
		for each: Dictionary in World.economy.goods(town):
			var what := str(each["id"]).replace("_", " ")
			counts[what] = int(counts.get(what, 0)) + 1
		var goods: Array = []
		var kinds: Array = counts.keys()
		kinds.sort()
		for what: String in kinds:
			goods.append(Companion.counted(what, counts[what]))
		out.append("The town's shop has %s." % _listed(goods) if not goods.is_empty() else "The town's shop has nothing for sale.")
	return out


## What it is making now, from its workshop's job (Production): what, how
## far along, and what went into it; or that it has no work and why.
func work_words() -> String:
	if World.production == null or trade.is_empty():
		return "You have no trade to work at."
	var shop_id := World.production.workshop_of(worker_id)
	if shop_id.is_empty():
		return "You have no workshop to work in yet: the town has no building for your trade."
	var job := World.production.job(int(World.production.workshop(shop_id).get("job", 0)))
	if job.is_empty():
		return "Your workshop is idle: you are making nothing now."
	var what := str(job.get("recipe", "")).replace("_", " ")
	if str(job.get("recipe", "")).begins_with(Towns.HUT_REPAIR):
		what = "repair of your hut"  # Its mend (733): words, never the place id.
	elif str(job.get("kind", "")) == "build":
		what = "the town's " + what.trim_prefix("build:").trim_prefix(Towns.REPAIR)
	var made: Array = []
	var resources: Dictionary = job.get("resources", {})
	for each: String in resources:
		made.append(Companion.counted(each.replace("_", " "), int(resources[each])))
	var into := ", from %s" % _listed(made) if not made.is_empty() else ""
	if str(job.get("state", "")) == "waiting":
		return "Your next work is %s, waiting for its materials." % Companion._a(what)
	if str(job.get("state", "")) != "working":
		return "Your next work is %s%s, not yet begun." % [Companion._a(what), into]
	var share := float(job.get("worked", 0)) / maxf(float(job.get("needed", 1)), 1.0)
	var far := "just begun" if share < 0.25 else "under half done" if share < 0.5 else "over half done" if share < 0.9 else "nearly done"
	return "You are making %s%s: it is %s." % [Companion._a(what), into, far]


## How it last ate, what it owes the town's bank and whether it works that
## off (decision 354), its last trade and how many of the town the town
## feeds (Production's worker facts, Economy's: decision 353), a sentence each;
## none before its first meal or trade (decision 336 amended).
func means_words() -> Array[String]:
	var out: Array[String] = []
	if World.production == null:
		return out
	var me := World.production.worker(worker_id)
	if me.is_empty():
		return out
	var now := World.production.now()
	match str(me.get("fed", "")):
		"hungry":
			var since := int(me.get("hungry_since", 0))
			if since > 0 and now - since >= DayNight.day_steps:
				out.append("You have had nothing to eat since yesterday or before.")
			else:
				out.append("You went without at your last meal: there was nothing you could eat.")
		"dole":
			out.append("At your last meal the town fed you for nothing: you could not pay.")
	var owed := ceili(float(me.get("loan", 0.0)))
	if owed > 0:
		out.append("You owe the town %d gold." % owed)
	if bool(me.get("working_off", false)):
		out.append("You are working off your debt to the town, hauling for it, and cannot borrow more.")
	var trade_words := _trade_words(me.get("last_trade", {}), now)
	if not trade_words.is_empty():
		out.append(trade_words)
	var fed_free := World.production.on_dole(town)
	if fed_free > 0:
		out.append("%s of the town's folk ate from the town's dole or went hungry at their last meal." % ("One" if fed_free == 1 else str(fed_free)))
	return out


## [param last] (a worker's last_trade: {step, what, gold, with}) in words,
## "" for none: what was bought or sold, or a fee paid or earned.
static func _trade_words(last: Dictionary, now: int) -> String:
	var what := str(last.get("what", ""))
	if what.is_empty():
		return ""
	var with_whom := str(last.get("with", ""))
	var gold := int(last.get("gold", 0))
	var ago := ", a day or more ago" if now - int(last.get("step", now)) >= DayNight.day_steps else ""
	var price := " for %d gold" % gold if gold > 0 else ""
	if what.begins_with("bought "):
		var from := " from %s" % with_whom if not with_whom.is_empty() and with_whom != Economy.TREASURY and " from " not in what else ""
		return "You last %s%s%s%s." % [what, from, price, ago]
	if what.begins_with("sold "):
		var to := " to %s" % with_whom if not with_whom.is_empty() else ""
		return "You last %s%s%s%s." % [what, to, price, ago]
	if not with_whom.is_empty() and what.ends_with(" for " + with_whom):
		return "You were last paid %d gold by %s for %s%s." % [gold, with_whom, what.trim_suffix(" for " + with_whom), ago]
	return "You last paid %s %d gold for %s%s." % [with_whom if not with_whom.is_empty() else "someone", gold, (" " + what).replace(" their ", " your ").strip_edges(), ago]


## How its voice is bound to the world's facts (decision 378): a companion
## resting in town as a companion, else Lore.binding of its trade and its
## hidden type ("official", "free", "townsfolk"; a thieving priest is free).
func binding() -> String:
	if not player_id.is_empty():
		return "companion"
	return Lore.binding(trade, hidden_type())


## Its hidden type (npc's, on its worker record: "steady", "thief"...), ""
## for none.
func hidden_type() -> String:
	return str(World.production.worker(worker_id).get("type", "")) if World.production != null else ""


## One of its leanings, 1..10 ("intellect", "superstition", "creativity",
## "integrity"): its own, as its worker record has it (economy rolls each
## round its role's), else its trade's and type's (Lore.profile), else 5.
func leaning(key: String) -> int:
	var own: Variant = World.production.worker(worker_id).get(key) if World.production != null else null
	if own is int or own is float:
		return int(own)
	return int(Lore.profile(trade, hidden_type()).get(key, 5))


## Its voice's rule of the world (BOUND), from its binding and its role's
## profile.
func bound_words() -> String:
	var bound := binding()
	if bound == "companion":
		return BOUND["companion"]
	var parts: Array[String] = [BOUND["official"] if bound == "official" else BOUND["heard"]]
	parts.append(BOUND["embellish"] if leaning("creativity") >= HIGH else BOUND["plain"])
	parts.append(BOUND["lie"] if leaning("integrity") <= LOW else BOUND["honest"])
	return " ".join(parts)


## How much lore its voice is told, in characters: its hidden type's
## (residents.json "lore_chars": a scholar's is doubled, decision 440),
## else LORE_CHARS.
func lore_budget() -> int:
	return int(Townsfolk.days().get("lore_chars", {}).get(hidden_type(), LORE_CHARS))


## What a kept secret becomes in the prompt (615, npc's side; lore's kept_by; Jeff: "part of his pay is to keep
## what he sees to himself"): the deflection in the speaker's own words and never the fact's text, so no slip of
## the model can leak what it holds back.
## The priest's standing knowledge (decision 714, npc's side), outside the
## lore budget like KEPT_LINE: the knights in the Hall of Fallen Souls beneath
## the temple (832's switch-on, lore's words) and the relic's use; [param
## knight] the one whose sepulcher stands now, "" for none.
static func relic_line(knight: String) -> String:
	var now := "" if knight.is_empty() or knight == "<null>" else " The knight whose sepulcher lies open below now is %s." % knight
	if AstralKnight.altar_on:
		# 896 amended (1) (Jeff: the knight's thanks charges it; the priest only glad you're back; lore's place name).
		return ("Holy knights of the temple lie in the Hall of Fallen Souls, deep beneath this temple, and the Mound-breakers, the grave robbers in the crypt above it, dig for their bones to sell.%s"
			+ " Whoever brings a knight's remains up from below, you send to lay them on the knight's altar in the crypt's First Hall, where the knight's thanks charges that one's Encolpion Amulet;"
			+ " you are glad of everyone who comes back from below.") % now
	return ("Holy knights of the temple lie in the Hall of Fallen Souls, deep beneath this temple, and the Mound-breakers, the grave robbers in the crypt above it, dig for their bones to sell.%s"
		+ " Whoever brings a knight's remains back to you, you lay them on the altar, and the blessing charges that one's Encolpion Amulet;"
		+ " one who has no amulet is given one.") % now


const KEPT_LINE := "Some of what you see in your work you keep to yourself, as you are paid to: if asked about it, say only that you keep what you see to yourself, and say no more of it."


## Lore's facts for this body (615, npc's side): its trade's knower, and for
## the runner (his card's mark; Pip) the person knower of his own name when
## lore lists one, merged by id, a fact kept in either copy kept. Anyone
## else speaks by the trade alone, as before.
## With [param about] (asked_topics), only those of its facts about it (Lore.known_by's filter: never more).
func _facts_known(about := PackedStringArray()) -> Array[Dictionary]:
	var facts := Lore.known_by(Lore.knower_for(trade), about, "agreed", hidden_type())
	var own := person.to_lower()
	if own.is_empty() or own == Lore.knower_for(trade) or not Lore.knowers().has(own) or World.production == null \
			or not bool(Townsfolk.card_of(World.production, worker_id).get("runner", false)):
		return facts
	var by_id := {}
	for fact: Dictionary in facts:
		by_id[str(fact.get("id", ""))] = fact
	for fact: Dictionary in Lore.known_by(own, about, "agreed", hidden_type()):
		var id := str(fact.get("id", ""))
		if by_id.has(id):
			if bool(fact.get("kept", false)):
				(by_id[id] as Dictionary)["kept"] = true
		else:
			facts.append(fact)
			by_id[id] = fact
	return facts


## Lore's agreed facts it knows (Lore.knower_for its trade, by its domain),
## a sentence each, weightiest first (a superstitious role's rumours before
## the rest: it repeats what is said), within LORE_CHARS; a rumour as what
## is said. A companion's are in her card and her own voice. Those about
## [param about] (asked_topics: what the player asked) go first, in the
## same order among themselves (lore's audit, 853 amended (4)): a reorder
## of what it would say anyway, never one more fact (a secret stays untold).
func world_facts(about := PackedStringArray()) -> Array[String]:
	var out: Array[String] = []
	if not player_id.is_empty():
		return out
	var facts := _facts_known()
	var asked := {}
	if not about.is_empty():
		for fact: Dictionary in _facts_known(about):
			asked[str(fact.get("id", ""))] = true
	var kept := false
	var superstitious := leaning("superstition") >= HIGH
	# A secret (decision 546, npc's side, part 3) is told past the standing tier: to a player it trusts, and
	# to nobody else; Main hears which (ctx "secret_told", for Aldous's crypt secrets).
	var trusted := false
	if not asked_by.is_empty() and World.production != null:
		var own := Townsfolk.card_of(World.production, worker_id)
		trusted = not own.is_empty() and Standing.score(own, asked_by) >= Standing.setting("trusted")
	# Ties keep lore's file order (853 amended (9), lore's find): Godot's sort is not stable, so among equal
	# weights which fact the budget cut fell to any reshuffle of the data (Aldous's six secrets, 634
	# characters against 600: a new pond entry dropped the founding). Sorted by place, its index last.
	var order: Array = range(facts.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		var a: Dictionary = facts[i]
		var b: Dictionary = facts[j]
		if asked.has(str(a.get("id", ""))) != asked.has(str(b.get("id", ""))):
			return asked.has(str(a.get("id", "")))  # What was asked about first (853 amended (4)).
		if trusted and bool(a.get("secret", false)) != bool(b.get("secret", false)):
			return bool(a.get("secret", false))  # A secret is the rarest thing it can say: first, within the budget.
		if superstitious and bool(a.get("hearsay", false)) != bool(b.get("hearsay", false)):
			return bool(a.get("hearsay", false))
		if float(a["weight"]) != float(b["weight"]):
			return float(a["weight"]) > float(b["weight"])
		return i < j)
	var sorted: Array[Dictionary] = []
	for i: int in order:
		sorted.append(facts[i])
	facts = sorted
	var length := 0
	for fact in facts:
		if bool(fact.get("kept", false)):
			kept = true  # Held back (615): never in the words, to anyone, trusted or not; the stance below in its place.
			continue
		if bool(fact.get("secret", false)) and not trusted:
			continue
		var text := Hearsay.said_of(fact)
		if length + text.length() > lore_budget():
			break
		length += text.length() + 1
		out.append(text)
		if bool(fact.get("secret", false)):
			# Told only once it is in the words (546 amended: lore found a secret cut by the budget reported as told).
			Offers._call(Offers.ctx, "secret_told", [asked_by, str(fact.get("id", ""))])
	if kept:
		out.append(KEPT_LINE)  # Outside the budget: a stance, not a fact (615, npc's side).
	if trade == "priest":
		out.append(relic_line(str(Offers._call(Offers.ctx, "barrow_knight") if Offers.ctx.has("barrow_knight") else "")))  # 714, npc's side.
	# What the town remembers (447, ruled on by the lawspeaker, 448): as
	# memory, not fact, after lore's facts, within the same budget.
	var log: Variant = Offers._call(Offers.ctx, "memory", [town]) if not town.is_empty() else null
	if log is Array:
		for text: String in TownMemory.remembered(log):
			if length + text.length() > lore_budget():
				break
			length += text.length() + 1
			out.append(text)
	return out


## What [param line] asks about, as Lore.known_by's topics (853 amended (4), lore's audit): each lore
## entry whose id or name it names, and each fact tag it names, a plural too ("wolves", "crypts"); none
## of TOPIC_SKIP. In entry order, then tag order; empty for a line naming none.
static func asked_topics(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var said := " %s " % Lore._words(line)
	if said.strip_edges().is_empty():
		return out
	for each: Array in _topic_words():
		if str(each[0]) not in out and (each[1] as Array).any(func(form: String) -> bool: return said.contains(" %s " % form)):
			out.append(str(each[0]))
	return out


## Tags that mark lore's own bookkeeping or a common word, never a topic asked.
const TOPIC_SKIP: Array[String] = ["jeff_agreed", "return", "setting"]
static var _topics: Array = []


## [[topic, [its word forms]]]: lore's entries by id and name, then its facts' tags; read once.
static func _topic_words() -> Array:
	if not _topics.is_empty():
		return _topics
	var tags: Array[String] = []
	var entries := Lore.entries()
	for id: String in entries:
		var entry: Dictionary = entries[id]
		var names: Array[String] = [Lore._words(id.replace("_", " ")), Lore._words(str(entry.get("name", "")))]
		var forms: Array = []
		for each in names:
			var bare := each.substr(4) if each.begins_with("the ") else each
			if not bare.is_empty() and bare not in forms:
				forms.append_array(_plurals(bare))
		_topics.append([id, forms])
		for tag: Variant in entry.get("tags", []):
			if str(tag) not in tags:
				tags.append(str(tag))
		for fact: Variant in entry.get("facts", []):
			if fact is Dictionary:
				for tag: Variant in fact.get("tags", []):
					if str(tag) not in tags:
						tags.append(str(tag))
	for tag in tags:
		if tag not in TOPIC_SKIP and not entries.has(tag):
			_topics.append([tag, _plurals(Lore._words(tag.replace("_", " ")))])
	return _topics


## [param words] and its plurals by its last word: +s, +es, f to ves.
static func _plurals(words: String) -> Array:
	var out := [words, words + "s", words + "es"]
	if words.ends_with("f"):
		out.append(words.left(-1) + "ves")
	return out


## The name of this town's scholar (the hidden type, 440), "" for none.
func _scholar_of_town() -> String:
	if World.production == null or town.is_empty():
		return ""
	for id: String in World.production.worker_ids(town):
		if str(World.production.worker(id).get("type", "")) == Townsfolk.SCHOLAR and not bool(World.production.worker(id).get("away", false)):
			return str(World.production.worker(id).get("name", id))
	return ""


## [param parts] in words: "a, b and c".
static func _listed(parts: Array) -> String:
	if parts.size() <= 1:
		return "" if parts.is_empty() else str(parts[0])
	return "%s and %s" % [", ".join(parts.slice(0, -1)), parts.back()]


## A step along its route to its goal, a new route when it has none or is
## stuck.
func _step() -> void:
	if tile == _goal or World.tick < next_move_tick or World.tick < _rise_until:
		return
	if _route.is_empty():
		_route = World.legs_path(tile, World.find_path(tile, _goal, false, null, RESIDENT_SEARCH_TILES, false, {}, true,
				World.PATH_FIRE_EXTRA, RESIDENT_BODIES_WITHIN), _goal, self)  # A few long legs, not a staircase (853 amended (6)).
		if _route.is_empty() and World.distance(tile, _goal) > 1 and World.is_walkable(_goal) and not World.is_free(_goal):
			_route = _path_beside(_goal)  # Another stands on it (853: one strolled onto the store's cell and the carrier stood).
		if _route.is_empty():
			if World.distance(tile, _goal) <= 1 and not World.is_free(_goal):
				return  # Beside it, the cell taken: it waits there for it.
			_goal = tile  # No way there now: it waits, and chooses again later (762 amended (3): whatever it is doing).
			_retry_at = World.tick + PATH_RETRY_TICKS + absi(id) % (PATH_RETRY_SPREAD + 1)
			return
	if World.try_move(self, _route[0] - tile):
		_route.pop_front()
		_stuck = 0
		return
	_stuck += 1
	if _stuck >= STUCK_TRIES:
		_route.clear()
		_stuck = 0
		if not World.is_free(_goal) or keep_moving and _strolls():
			_pick_goal()  # A stroll that cannot get there goes elsewhere (853).


## A route to a free cell beside [param cell], the nearest to it first, then to this body; [] for none.
func _path_beside(cell: Vector2i) -> Array[Vector2i]:
	var around: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var at := cell + Vector2i(dx, dy)
			if at != cell and World.is_free(at) and not World.is_link_cell(at):
				around.append(at)
	around.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return World.distance(a, tile) < World.distance(b, tile))
	for at in around:
		var way := World.find_path(tile, at, false, null, RESIDENT_SEARCH_TILES, false, {}, true,
				World.PATH_FIRE_EXTRA, RESIDENT_BODIES_WITHIN)
		if not way.is_empty():
			return World.legs_path(tile, way, at, self)
	return []


# --- Guards who fight (decision 791) -------------------------------------------
## A guard (FIGHTERS) armed by Main (arm) holds a manned post it was sent to
## (visit "post": the captain on a wave's first cue, another on a call), or
## the square when its town is under threat or it is hurt (residents.json
## guard_fight "fall_back_at" of its hp): it fights a foe within "hold" cells of that
## ground (a raider or wave monster, or one that threatens it or struck it),
## never one past "chase", from the side away from the watcher nearest the
## foe (so the watcher and the guard can flank it, 780); out of a monster's
## tell's cells first. It calls the others when it takes a foe. Beaten, it is
## downed, never killed (Main._downed); unraised, laid up at the temple.

## [param rule] residents.json guard_fight; [param captain] the town's captain:
## its hp, blow and cadence, a spear in the right hand and mail worn.
func arm(rule: Dictionary, captain: bool) -> void:
	var most := int(rule.get("captain_hp" if captain else "hp", 30))
	if max_hp != most:
		max_hp = most
		hp = most
	attack_damage = int(rule.get("captain_damage" if captain else "damage", 3))
	attack_ticks = int(rule.get("attack_ticks", 5))
	senses.take(rule.get("senses", {}))  # A guard's night eyes (784 amended's Senses.take).
	var gear: Dictionary = rule.get("gear", {})
	var held := Items.tidy([], Items.CARRIED)
	held[Items.RIGHT_HAND] = str(gear.get("right", "spear"))
	held[Items.ARMOUR] = str(gear.get("armour", "mail_armour"))
	if slots != held:
		slots = held
	if hands != PackedStringArray([held[Items.RIGHT_HAND], ""]):
		hands = PackedStringArray([held[Items.RIGHT_HAND], ""])
	if worn != held[Items.ARMOUR]:
		worn = held[Items.ARMOUR]


## Whether this body is an armed guard (arm).
func armed() -> bool:
	return trade in FIGHTERS and slots.size() > Items.ARMOUR and not slots[Items.RIGHT_HAND].is_empty()


## Whether it is laid up hurt (791): at the temple, off duty, till its time is out.
func laid_up() -> bool:
	return bool(visit.get("laid_up", false))


static func guard_rule() -> Dictionary:
	return Townsfolk.days().get("guard_fight", {})


## The ground it holds now: the square when its town is under threat or it
## is hurt, the post it was sent to, else where it stands if struck just
## now; a zero rect for none (it fights nothing).
func _hold_area() -> Rect2i:
	if laid_up():
		return Rect2i()
	if sheltering or _fall_back:
		return places.get("square", Rect2i())
	if bool(visit.get("post", false)) and visit.get("rect") is Rect2i:
		return visit["rect"]
	if World.tick - hurt_tick <= int(guard_rule().get("answer_ticks", 50)):
		return Rect2i(tile, Vector2i.ONE)
	return Rect2i()


## A guard's fight this tick: true while it is at a foe (striking, closing
## or stepping out of a tell), false to go about its night.
func _fight() -> bool:
	if not armed():
		return false
	var rule := guard_rule()
	if hp * 1.0 < max_hp * float(rule.get("fall_back_at", 0.4)):
		if not _fall_back:
			_fall_back = true
			_foe = null
			if guard_told.is_valid():
				guard_told.call(self, "fall_back")
	elif hp >= max_hp:
		_fall_back = false
	var hold := _hold_area()
	if hold.size == Vector2i.ZERO:
		_foe = null
		if hp < max_hp and World.tick - hurt_tick >= int(rule.get("rest_ticks", 600)) and (World.tick + id) % int(rule.get("heal_every", 100)) == 0:
			World.heal(self, 1)  # Let be, a guard mends slowly.
		return false
	if _foe != null and (not is_instance_valid(_foe) or not _foe.spawned or _foe.hp <= 0 or _foe.zone != zone
			or not hold.grow(int(rule.get("chase", 8))).has_point(_foe.tile)):
		_foe = null
	if _foe == null:
		_foe = _pick_foe(hold.grow(int(rule.get("hold", 4))))
		if _foe == null:
			return false
		if guard_told.is_valid() and (_called_at < 0 or World.tick - _called_at >= int(rule.get("call_ticks", 300))):
			_called_at = World.tick
			guard_told.call(self, "call")
	activity = ""
	var dodge := _dodge()
	if dodge != NO_CELL:
		if dodge != tile:
			_aim(dodge)
			_step()
		return true
	if World.in_reach(self, _foe):
		if facing != _toward(_foe.tile):
			World.face(self, _toward(_foe.tile))
		World.try_attack(self, _foe)
		return true
	var cell := _strike_cell(_foe)
	if cell != NO_CELL:
		if cell != _goal:
			_aim(cell)
		_step()
	return true


## The nearest foe it sees within [param area]: a raider or a wave's
## monster, one that would fight it, or one that struck it just now.
func _pick_foe(area: Rect2i) -> Monster:
	var best: Monster = null
	var best_d := 1 << 30
	for each: GridEntity in World.monsters():
		var foe := each as Monster
		if foe == null or not foe.spawned or foe.hp <= 0 or foe.zone != zone or not area.has_point(foe.tile):
			continue
		if not (foe.raid != "" or foe.threatens(self) or foe.struck_by == self):
			continue
		var d := World.distance(tile, foe.tile)
		if d < best_d and senses.sees(foe, d, false):  # In the dark, as far as guard_fight "senses" night lets it.
			best = foe
			best_d = d
	return best


## Where it strikes [param foe] from: of the cells it can strike it from,
## free and walkable, the one farthest from the player nearest the foe (so
## the two come at it from either side), then the nearest to it.
func _strike_cell(foe: Monster) -> Vector2i:
	var watcher: GridEntity = null
	var near := 1 << 30
	for each: GridEntity in World.sought():
		if each is Player and each.spawned and each.zone == zone and World.distance(each.tile, foe.tile) < near:
			watcher = each
			near = World.distance(each.tile, foe.tile)
	var best := NO_CELL
	var best_score := INF
	for cell: Vector2i in World.strike_cells(self, foe):
		if cell != tile and (not World.is_walkable(cell) or not World.is_free(cell)):
			continue
		var score := float(World.distance(tile, cell))
		if watcher != null:
			score -= 2.0 * World.distance(watcher.tile, cell)
		if score < best_score:
			best = cell
			best_score = score
	return best if best != NO_CELL else foe.tile


## A cell out of a monster's tell that would land on it soon (as a
## companion steps out of one): NO_CELL when it stands clear.
func _dodge() -> Vector2i:
	var danger := {}
	var mine := false
	var shown := World.telegraphs()
	for id: int in shown:
		var data: Dictionary = shown[id]
		if str(data.get("zone", "")) != zone or int(data.get("lands_tick", 0)) - World.tick > int(guard_rule().get("dodge_look", 6)):
			continue
		for cell: Array in data.get("cells", []):
			var at := Vector2i(int(cell[0]), int(cell[1]))
			danger[at] = true
			mine = mine or at == tile
	if not mine:
		return NO_CELL
	var best := NO_CELL
	var best_d := 1 << 30
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var at := tile + Vector2i(dx, dy)
			if danger.has(at) or not World.is_walkable(at) or not World.is_free(at):
				continue
			var d := maxi(absi(dx), absi(dy))
			if d < best_d:
				best = at
				best_d = d
	return best if best != NO_CELL else tile


## Sent to [param rect] by a guard's call or a wave's cue (791, 771 amended
## (3)): it goes there to hold it, unless laid up or already holding a post.
func rally(rect: Rect2i, place_name: String, until: int) -> void:
	if laid_up() or bool(visit.get("post", false)) or World.is_downed(self):
		return
	if sleeping():
		wake()  # Called out of bed to the fight.
	visit = {"rect": rect, "who": "", "name": place_name, "post": true, "until": until}
