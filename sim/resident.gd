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
const FAR_TILES := 30
const FAR_EVERY := 20
## A step blocked so many times, and it looks for a new way.
const STUCK_TRIES := 3
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
var escort_of := ""
## What they lie abed with (decision 501 amended, ui's ask): the sickness's
## kind ("a fever", "a cough"), "" when well. Replicated, so a client can
## name it in the cursor hint and the talk panel's title; the server sets it
## on its sim tick from the town's record (Townsfolk.sickness_of).
var ailing := ""
var escort_name := ""
## The medicine man's visit (decision 501): {"rect": the sick one's home, "who": their id, "until": World.steps}; {} for none.
var visit: Dictionary = {}
## Companions' Heel (decision 485), loaded by path so this script stands
## with or without it: without, the lost one waits where they are.
const HEEL_SCRIPT := "res://sim/heel.gd"
var _heel: RefCounted = null
var _goal := NO_CELL
var _route: Array[Vector2i] = []
var _stuck := 0
var _hide_until := -1
var _wander_at := -1
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
	move_ticks = 3.0
	senses = Senses.new(self, SIGHT_RANGE, -1.0)


## The name over a resident's head: "Bram [smith]", the profession in
## brackets after the name (Jeff, 2026-10-17: never "Bram, smith"), a trade
## id's underscores spaced ("medicine man"); the bare name for no trade.
static func label_of(person_name: String, of_trade: String) -> String:
	if of_trade.is_empty():
		return person_name
	return "%s [%s]" % [person_name, of_trade.replace("_", " ")]


## What one of [param of_trade] is doing at [param hour] (0..24), by its
## routine (decision 404, Townsfolk.whereabouts: the season, its hidden
## type, its own clock and the temple day by [param worker_id]).
static func doing_at(of_trade: String, hour: float, season := "", type := "", worker_id := "", day := -1) -> Doing:
	return DOING_AT.get(Townsfolk.whereabouts(of_trade, hour, season, type, worker_id, day), Doing.SQUARE)


## What one of [param of_trade] (hidden [param type], [param worker_id]) is
## doing now, on the world's clock and season: from the clock alone, so a
## body spawned as a player walks up starts at the right stint.
static func doing_now(of_trade: String, type := "", worker_id := "") -> Doing:
	var now := DayNight.now()
	return doing_at(of_trade, DayNight.hour(now), Season.name_at(World.steps), type, worker_id, Townsfolk.day_of(now))


func _sim_tick() -> void:
	if not Net.is_authority():
		return
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
	var far := _far()
	if far and (World.tick + id) % FAR_EVERY != 0:
		return
	if not far and World.tick % LOOK_EVERY == 0:
		_look()
	if World.tick - hurt_tick <= 1:
		_hide_until = World.tick + HIDE_TICKS
	var now := Doing.HIDE if World.tick < _hide_until else (Doing.VISIT if not visit.is_empty() else doing_now(trade, type, worker_id))
	if now != doing or _goal == NO_CELL:
		doing = now
		_pick_goal()
	elif doing == Doing.SQUARE and tile == _goal and World.tick >= _wander_at:
		_pick_goal()
	if far:
		if tile != _goal:
			World.walk(self, _goal, FAR_EVERY)
		return
	_step()


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
	_stuck = 0
	var area: Rect2i = places.get(PLACE_OF[doing], places.get("square", Rect2i())) if doing != Doing.ROUNDS else _round_area()
	if doing == Doing.VISIT and visit.get("rect") is Rect2i:
		area = visit["rect"]
	if area.size == Vector2i.ZERO:
		_goal = tile
		return
	if area.has_point(tile) and not (doing == Doing.SQUARE and _goal != NO_CELL):
		_goal = tile
	else:
		_goal = _free_cell(area)
	if doing == Doing.SQUARE:
		_wander_at = World.tick + WANDER_TICKS + (id * 7) % 40


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


## A free cell of [param area], from a start its id and the tick choose;
## where it stands if none.
func _free_cell(area: Rect2i) -> Vector2i:
	var count := area.size.x * area.size.y
	var start := absi(id * 31 + World.tick) % count
	for i in count:
		var at := area.position + Vector2i((start + i) % count % area.size.x, (start + i) % count / area.size.x)
		if at != tile and World.is_free(at):
			return at
	return tile


## The voice ask for [param line], said to it by [param speaker]
## (CompanionMind.voice's shape, plain text back).
func voice_ask(speaker: String, line: String, serial: int) -> Dictionary:
	var system := VOICE % [person, town_name if not town_name.is_empty() else "a town", " as a " + trade if not trade.is_empty() else "", card_words(),
		" ".join(facts_now()), speaker, bound_words()]
	var user := "%s says to you: \"%s\"" % [speaker, line]
	return {"kind": "voice", "serial": serial, "trigger": "%s spoke to %s." % [speaker, person], "speaker": person,
		"system": system, "user": user, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
		"spoken_to": true, "asked": true, "heard": line}


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
func facts_now() -> Array[String]:
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
	if not visit.is_empty():
		out.append("You are on your way to %s's bedside, to see to %s." % [visit.get("name", "a neighbour"), visit.get("name", "them")])
	if strayed:
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
	var known := world_facts()
	if not known.is_empty():
		out.append("What you know of the world: %s" % " ".join(known))
	if binding() in ["townsfolk", "free"] and World.production != null:
		var heard := Hearsay.prompt_words(World.production.worker(worker_id).get("heard", []))
		if not heard.is_empty():
			out.append(heard)
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
	if str(job.get("kind", "")) == "build":
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


## Lore's agreed facts it knows (Lore.knower_for its trade, by its domain),
## a sentence each, weightiest first (a superstitious role's rumours before
## the rest: it repeats what is said), within LORE_CHARS; a rumour as what
## is said. A companion's are in her card and her own voice.
func world_facts() -> Array[String]:
	var out: Array[String] = []
	if not player_id.is_empty():
		return out
	var facts := Lore.known_by(Lore.knower_for(trade), PackedStringArray(), "agreed", hidden_type())
	var superstitious := leaning("superstition") >= HIGH
	# A secret (decision 546, npc's side, part 3) is told past the standing tier: to a player it trusts, and
	# to nobody else; Main hears which (ctx "secret_told", for Aldous's crypt secrets).
	var trusted := false
	if not asked_by.is_empty() and World.production != null:
		var own := Townsfolk.card_of(World.production, worker_id)
		trusted = not own.is_empty() and Standing.score(own, asked_by) >= Standing.setting("trusted")
	facts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if trusted and bool(a.get("secret", false)) != bool(b.get("secret", false)):
			return bool(a.get("secret", false))  # A secret is the rarest thing it can say: first, within the budget.
		if superstitious and bool(a.get("hearsay", false)) != bool(b.get("hearsay", false)):
			return bool(a.get("hearsay", false))
		return float(a["weight"]) > float(b["weight"]))
	var length := 0
	for fact in facts:
		if bool(fact.get("secret", false)):
			if not trusted:
				continue
			Offers._call(Offers.ctx, "secret_told", [asked_by, str(fact.get("id", ""))])
		var text := str(fact["text"]).strip_edges()
		if bool(fact.get("hearsay", false)):
			text = "It is said that %s" % Hearsay._lower_first(text)
		if length + text.length() > lore_budget():
			break
		length += text.length() + 1
		out.append(text)
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
	if tile == _goal or World.tick < next_move_tick:
		return
	if _route.is_empty():
		_route = World.find_path(tile, _goal, false)
		if _route.is_empty():
			_goal = tile  # No way there now: it waits, and chooses again later.
			return
	if World.try_move(self, _route[0] - tile):
		_route.pop_front()
		_stuck = 0
		return
	_stuck += 1
	if _stuck >= STUCK_TRIES:
		_route.clear()
		_stuck = 0
		if not World.is_free(_goal):
			_pick_goal()
