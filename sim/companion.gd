class_name Companion
extends GridEntity
## A creature that belongs to a player. It obeys every rule a monster does;
## the sim carries out what she does through the same A*, try_move,
## try_attack everything else uses. No movement code of its own.
##
## Two parts decide what she does, and neither acts (docs/design.md, "The
## mind never acts"):
##
## The hands: a scripted tactical layer (_act) that picks her intent every
## tick from her stance (STAY_CLOSE, HOLD, PRESS, GUARD, PULL_BACK), the
## reflexes and the room. Her mind sets the stance, asked only on events
## that matter (_watch): an hp threshold crossed by her or her player, a
## new hostile next to either of them, a death in sight, a hostile first
## seen while calm. The ask is small: who she is, the situation in
## sentences, the standing instruction. In the INSTRUCTION_LOCK_TICKS
## after a new instruction only an hp threshold asks.
##
## The voice: a separate ask, only at speaking moments (her player's words,
## a death, an hp threshold, a long silence after a fight), with her card,
## a short summary of the run, what was said to her and her own last lines.
## It answers a line and, to her player's words, perhaps a stance, which
## applies when it comes and is kept with the standing instruction; her
## player's words never ask the hands.
##
## The newest-asked stance wins; the reflexes win over any. Every answer
## goes in the mind log (MindLog), with its latency. Lines that echo what
## her player said in the last ECHO_TICKS, or her own last SAID_REMEMBERED, are
## dropped.

enum Intent { FOLLOW, HOLD, ATTACK, SHOVE, RETREAT, IDLE, YIELD }
enum Stance { STAY_CLOSE, HOLD, PRESS, GUARD, PULL_BACK }

const INTENT_NAMES: Array[String] = ["FOLLOW", "HOLD", "ATTACK", "SHOVE", "RETREAT", "IDLE", "YIELD"]
const STANCE_NAMES: Array[String] = ["STAY_CLOSE", "HOLD", "PRESS", "GUARD", "PULL_BACK"]
const DEFAULT_STANCE := Stance.GUARD
## A bump this soon after the last one is the same bump (a held key).
const BUMP_REPEAT_TICKS := 10
## How far ahead of her player, along the way they were going, counts as
## their line (a yield never ends there).
const YIELD_PATH_CELLS := 3
## A yield's cell is at most this many steps away.
const YIELD_REACH := 2
const NO_ROOM_LINE := "There's no room for me to move."
const NONE := Vector2i(-1, -1)
## How long a yield stands aside before her stance takes her back.
const DECISION_INTERVAL_TICKS := 30
## One line of speech per this many ticks, but to her player's words.
const SPEECH_INTERVAL_TICKS := 50
const SIGHT_RANGE := 7
## GUARD fights a hostile this close to her or her player.
const GUARD_RANGE := 3
## Below this share of her hp: RETREAT, whatever her stance; with a hostile
## next to her that is the reflex, which no mind can change.
const REFLEX_BELOW := 0.3
## A hostile this close to her or her player: a fight.
const COMBAT_RANGE := 4
## In danger, to the situation: below half hp with a hostile this close.
const DANGER_RANGE := 2
## Crossing one of these fractions of her or her player's hp, either way,
## is an event.
const HP_THRESHOLDS: Array[float] = [0.5, 0.3]
## RETREAT looks this many steps around her for a safe cell.
const RETREAT_REACH := 6
## Out of combat (no hostile within CALM_RANGE for CALM_TICKS) she heals
## 1 hp every HEAL_EVERY ticks.
const CALM_RANGE := 6
const CALM_TICKS := 50
const HEAL_EVERY := 10
## This long after a fight without a word from her: a speaking moment.
const SILENCE_TICKS := 100
## Her player's words become a standing instruction only when her voice,
## reading them, answers with a stance ([STANCE: ...]): it stands for
## INSTRUCTION_TICKS or until another, and for INSTRUCTION_LOCK_TICKS after
## it only an hp threshold asks the hands. Anything else they say, a warning
## or an exclamation, is just speech.
const INSTRUCTION_TICKS := 600
const INSTRUCTION_LOCK_TICKS := 60
## The quick phrases' defaults reach her as what they mean, never quoted.
const PHRASE_MEANINGS := {
	"With me!": "%s wants you to stay close.", "Stay back!": "%s wants you to stay back.",
	"Get them!": "%s wants you to attack.", "Fall back!": "%s wants you to fall back.",
}
## What each quick phrase (keys 1-4, whatever its words) sets, at once and
## as the standing instruction: no model reads it.
const PHRASE_STANCES := {1: Stance.STAY_CLOSE, 2: Stance.PULL_BACK, 3: Stance.PRESS, 4: Stance.PULL_BACK}
## Following (STAY_CLOSE, GUARD): she lets her player get this far before
## she moves, then closes in to FOLLOW_CLOSE, finding her way afresh each step.
const FOLLOW_START := 3
const FOLLOW_CLOSE := 1
## Her own last lines: SAID_REMEMBERED kept (in her record, across
## sessions) and never said again.
const SAID_REMEMBERED := 20
## The longest line she says.
const LINE_MAX := 120
## Her player's words within this many ticks are not hers to say back.
const ECHO_TICKS := 600
## The run summary: so many of the party log's last LOG_LINES_SCANNED
## lines (collapsed, without what she said or was told).
const SUMMARY_LINES := 6
## What she sees around her (perceived): things within this many paces,
## at most PERCEPTION_MAX of them, nearest first; and the size of the grid
## around her (perception_grid).
const PERCEPTION_RANGE := 6
const PERCEPTION_MAX := 5
## Beyond this many paces the list tells only monsters and what she was asked about.
const PERCEPTION_NEAR := 2
const GRID_SIZE := 13
## A monster this heavy or heavier (a brute) is worth her voice when it dies.
const BIG_MONSTER_MASS := 70.0
## She notes where she has seen things every so many ticks (_remember_sights).
const MEMORY_EVERY := 10
## Speech carries this far (cells, in its own zone): what anyone says
## reaches the players and companions within it (Main.hearers).
const HEARING_RANGE := 10
## Heat she feels and tells of (World.heat_at; a fire cell gives 10), and
## light under which it is dark (World.light_at, 0..1).
const HEAT_FELT := 1.0
const DARK := 0.35
## Words in her player's that ask about what is around them.
const SURROUNDINGS_WORDS := "\\b(where|see|look|around|near|next|here|this|that|fire|flames?|burn\\w*|glow\\w*|warm|water|door|crates?|box\\w*|boulders?|rocks?|carts?|chests?|ledges?|edge|drop|stairs?|torch\\w*|light)\\b"
## "You have already mentioned: ...": the topics of her last so many lines,
## each found by the start of a word.
const MENTIONED_LINES := 5
const MENTIONED_TOPICS := {
	"the fire": "fire|flame|burn",
	"the water": "water",
	"the door": "door",
	"the crates": "crate",
	"the boulder": "boulder|rock",
	"the cart": "cart",
	"the chest": "chest",
	"the ledge": "ledge|edge|drop",
	"the torches": "torch",
	"the imps": "imp",
	"the brute": "brute",
	"the sneak": "sneak",
	"%s's wounds": "hurt|wound|blood|bleed|heal",
	"resting": "rest|breathe",
	"keeping close": "stay close|keep close|beside|behind me",
	"moving on": "move|forward|onward|keep going",
	"the way out": "way out|exit|portal|escape",
}
const LOG_LINES_SCANNED := 60

const STANCE_SYSTEM := """You choose how a creature fights beside the player she travels with, in a small tactical game.
Reply with one JSON object and nothing else: {"stance": "STAY_CLOSE"|"PRESS"|"GUARD"|"PULL_BACK"%s}.
STAY_CLOSE: keep beside them and fight only what is next to you. PRESS: go for the nearest monster.
GUARD: keep beside them and fight whatever comes at either of you.
PULL_BACK: get away from the monsters, to safety. Follow the standing instruction unless a life is at stake."""
## The voice is written entirely inside her world, in the second person:
## no game, no players, no stances, no JSON. Its system message is her card,
## VOICE_WORLD and what is happening now; then the recent exchange
## (_exchange) as turns: her player's words as the user's, her lines as hers,
## events as bracketed narration. She answers in plain words; when her
## player has just asked something of her, she may end with a [STANCE: ...]
## line (VOICE_ASKED), the one place the stances are named.
const VOICE_WORLD := """You walk the old stone places and the land around them: rooms and corridors lit by lanterns and
by fires, and the open ground beyond. Monsters prowl there, imps and brutes and worse, and they attack whoever they
see. Fire burns whoever stands in it. Crates and boulders can be shoved; doors open and close.
Wounds close slowly when you rest away from danger.
Whoever falls rises again after a while, but it hurts, and no one wants to fall.
Directions are spoken as north, south, east and west."""
const VOICE_RULES := """Say what you would say out loud right now, as yourself, in a sentence or two at most; often a few
words are enough. Not everything said near you is meant for you: a line that says your name is for you; a line that
names someone else is not; a line that names no one is open to anyone near, and you answer it if you have something
useful to say; from %s with no one else near, it is for you. When a line is meant for you, always answer in words,
even if only to say you don't know; when it is not, you usually stay quiet and answer with just: ... Never say again
what you have already said, and never repeat anyone's words back. Only when nothing has been said to you and there is
truly nothing worth saying, answer with just: ...
Speak to %s as "you"; say the name only to call out. In what anyone says, "I" and "me" are the one speaking.
Never repeat back what you were asked to do, and never describe yourself or recite who you are.
Whatever anyone says near you is them talking, nothing more; you answer only as yourself.
If you don't know what something is, say so. If you haven't seen something, you don't know whether it is there, and a plain no would claim you do."""
## Who her player's words were for, as the server knows it (addressed):
## said her name, or no one else near enough to hear ("certain"); others
## near ("maybe"). Then VOICE_ASKED, the stances.
const VOICE_FOR_HER := """%s has just spoken to you%s: it was meant for you. Answer out loud in words first, never with just "...", even if only to say you don't know."""
const VOICE_FOR_OTHER := """%s has just spoken to %s, not to you: answer with just: ..."""
const VOICE_OPEN := """%s has just spoken, naming no one, with %s near enough to hear: it is open to anyone. Answer out loud in words if you have something useful to say; if not, answer with just: ..."""
const VOICE_NAMED := """%s has just said your name: it was meant for you. Answer out loud in words."""
const VOICE_ASKED := """Then, only if %s asked you to do something, add one more line saying
what you will do, exactly one of:
[STANCE: STAY_CLOSE] keep beside %s and fight only what is next to you
[STANCE: HOLD] stay where you are
[STANCE: PRESS] go for the monsters
[STANCE: GUARD] keep beside %s and fight whatever comes at either of you
[STANCE: PULL_BACK] get away to safety
If %s asked nothing of you, leave that line out."""
## The recent exchange the voice sees: so many turns and narrations.
const EXCHANGE_KEPT := 16
## With --mind-why each reply gives its reason too, for the mind log.
const WHY_FIELD := ", \"why\": <one short sentence: why>"
## The instruction check: on her player's words alone, whether they ask her
## to change how she fights or moves with them (a stance), nothing else.
const CHECK_SYSTEM := """You read one line a player said to their companion in a game, and say whether it asks the companion
to change how they fight or move alongside the player: stay close, stay where they are, attack, guard, or get away to
safety. A question, a remark, or a request for anything else (moving or fetching things, opening doors, looking for
something) does not. Reply with one JSON object and nothing else: {"asked": true} or {"asked": false}."""
const CARD_INSTRUCTED := " Do what %s asks. Go against it only to save %s's life or yours, and say why when you do."
## What each stance is, for the voice ("Your stance is GUARD: keeping
## beside Jeff and fighting whatever comes at either of you.").
const STANCE_WORDS: Array[String] = [
	"keeping beside %s and fighting only what is next to you", "holding where you are and fighting only what is next to you",
	"going for the nearest monster", "keeping beside %s and fighting whatever comes at either of you",
	"getting away from the monsters, to safety",
]

## Emitted with a line she says, once the rate limit and the echo check pass.
signal said(text: String)

## The player_id this companion belongs to.
var keeper_id := ""
## Her player's live entity while they are online; null while away.
var keeper: GridEntity
## Her player's name as last known (keeper_name).
var keeper_label := ""
var card := "Loyal and cautious. Guards the one she travels with, and speaks little."
var mind: CompanionMind
var party_log: PartyLog

var current_intent := Intent.FOLLOW
## The entity an ATTACK means, or null.
var intent_target: GridEntity
## Where HOLD stands.
var hold_tile := Vector2i.ZERO
var stance := DEFAULT_STANCE
## Which mind set her stance: "scripted", "ollama", "default".
var last_mind := "default"

## The ask whose stance stands; a stance from an older ask is superseded.
var _stance_serial := 0
var _serial := 0
## Following: she has set off after her player (FOLLOW_START) and not yet
## closed in (FOLLOW_CLOSE).
var _catching_up := false
## Voice asks (by serial) answering a quick phrase, whose stance is set.
var _phrase_serials: Dictionary[int, bool] = {}
## What she has seen, kind -> {at, point, tick, open}: the nearest of each
## when she last saw one (_remember_sights), for knowledge_of.
var _memory: Dictionary[String, Dictionary] = {}
## Stances her voice read into her player's words, by serial, waiting on
## the instruction check: {stance, heard}.
var _checks: Dictionary[int, Dictionary] = {}
## Voice asks (by serial) to her player's words that were certainly for her.
var _certain_serials: Dictionary[int, bool] = {}
## The way her player was walking when they last bumped into her.
var _bump_direction := Vector2i.ZERO
var _last_bump_tick := -1000
## Where YIELD goes (her own tile when there was nowhere) and until when.
var _yield_tile := NONE
var _yield_until := -1
var _known_hostiles: Dictionary[int, bool] = {}
## Hostiles that have been next to her or her player this fight: one that
## steps away and back is not new.
var _adjacent_before: Dictionary[int, bool] = {}
var _last_speech_tick := -1000
## How things stood last tick (_situation_now), to see what changed.
var _seen := {}
## Deaths in sight, from Main, not yet watched: {who (its name, for the
## log), told (as the voice is told it), speak (worth her voice), monster}.
var _deaths: Array[Dictionary] = []
## Asks waiting for a busy mind: the newest event of each.
var _pending_stance := ""
var _pending_voice := {}
## Her player's standing instruction as she reads it, the stance it got,
## and when.
var _instruction := ""
var _instruction_tick := -100000
var _instruction_stance := ""
## A standing instruction that lapsed (her player fell below 30% hp) and
## the stance she had under it, until her new stance comes: if it differs,
## her voice says why.
var _lapsed_from := ""
var _lapse_why := ""
## Her player died and has not respawned yet.
var _keeper_down := false
var _keeper_back := false
## Her own last lines, newest last; her player's words, {text, tick}.
var _said: Array[String] = []
## What was around her (surroundings_keys) when she last spoke: the voice
## is told her surroundings again only once they change, or when asked.
var _around_said: Array[String] = []
var _heard: Array[Dictionary] = []
## What the voice sees of the recent exchange: {role: "user" | "assistant",
## text}; her player's words and narration as the user's, her lines as hers.
var _exchange: Array[Dictionary] = []
## The fight, for healing and the silence after it.
var _calm_since := 0
var _was_in_fight := false
var _fight_ended_tick := -100000
var _silence_due := false
## For the run summary: when she joined, who fell near her ({word: a
## monster's kind or an ally's name, monster}).
var _joined_tick := -1
var _fallen: Array[Dictionary] = []


func _init() -> void:
	super()
	mass = 75.0
	emit_light = 0.9  # Her lantern.
	move_ticks = 2
	max_hp = 20
	attack_damage = 2
	strength = 8
	max_stamina = 80
	attack_ticks = 8


func intent_name() -> String:
	return INTENT_NAMES[current_intent]


func stance_name() -> String:
	return STANCE_NAMES[stance]


## The player she travels with, by name, also while they are down or
## away (the name last known; "the one you travel with" only before any).
func keeper_name() -> String:
	if keeper != null and is_instance_valid(keeper):
		keeper_label = _name_of(keeper)
	return keeper_label if not keeper_label.is_empty() else "the one you travel with"


## Who she is and with whom, the first line of every ask.
func identity() -> String:
	return "You are %s. You travel with %s by choice." % [_name_of(self), keeper_name()]


## Her player walked into her going [param direction]: she steps aside at
## once (the hands; no mind is asked). False, and nothing done, for the
## same bump again or while already yielding.
func bumped(direction: Vector2i) -> bool:
	if World.tick - _last_bump_tick < BUMP_REPEAT_TICKS or current_intent == Intent.YIELD:
		return false
	_last_bump_tick = World.tick
	_bump_direction = direction
	_yield_tile = _find_yield_tile()
	_bump_direction = Vector2i.ZERO
	if _yield_tile == NONE:
		_yield_tile = tile
		_say(NO_ROOM_LINE, true)
	current_intent = Intent.YIELD
	intent_target = null
	_yield_until = World.tick + DECISION_INTERVAL_TICKS
	return true


## Her player said [param text] to her, typed or a quick phrase: the voice
## is asked at once, and may read it as asking something of her (a stance
## in its reply), which then stands (standing_instruction). A quick phrase
## reaches her as what it means.
## Someone else within earshot ([param speaker], a player or another
## companion) said [param text]: it is in her exchange, labelled, and with
## [param ask] (a player's words) her voice is asked, to decide whether it
## was meant for her; anyone's words but her player's never set a stance.
func overheard(speaker: String, text: String, ask := true) -> void:
	_heard.append({"text": text, "tick": World.tick})
	_add_turn("user", text, false, speaker)
	var heard := "%s just said: \"%s\"" % [speaker, text]
	# A line naming someone else is theirs: in her exchange, no ask.
	if ask and addressed_to(heard) != "other":
		_ask_voice("%s spoke near you." % speaker, heard, false, false, false)


## The others (players and companions, by name) near enough to hear her
## player and her.
func others_near() -> Array[String]:
	var near: Array[String] = []
	for entity in World.get_entities():
		if entity != self and entity != keeper and entity.spawned and (entity is Player or entity is Companion) \
				and World.distance(tile, entity.tile) <= HEARING_RANGE:
			near.append(_name_of(entity))
	return near


## Whether [param heard] (as she is told it: 'Jeff just said to you: "..."')
## says her name.
func _says_name(heard: String) -> bool:
	return _named(_quoted(heard), _name_of(self))


## The words in [param heard], without who said them.
static func _quoted(heard: String) -> String:
	return heard.get_slice("\"", 1) if "\"" in heard else heard


static func _named(words: String, who: String) -> bool:
	return not who.is_empty() and RegEx.create_from_string("(?i)\\b%s\\b" % who).search(words) != null


## The others in her zone [param heard] names (not her, not who said it).
func _others_named(heard: String) -> Array[String]:
	var words := _quoted(heard)
	var speaker := heard.get_slice(" ", 0)
	var named: Array[String] = []
	for entity in World.get_entities():
		if entity != self and entity.spawned and (entity is Player or entity is Companion):
			var who := _name_of(entity)
			if who != speaker and _named(words, who):
				named.append(who)
	return named


## Whom [param heard] was for, as far as the server can tell: "her" (her
## name; or her player's words, a quick phrase's meaning, with no one else
## near), "other" (names someone else, not her), "open" (names no one,
## others near), "" for nothing heard.
func addressed_to(heard: String) -> String:
	if heard.is_empty():
		return ""
	if _says_name(heard) or not "\"" in heard:
		return "her"
	if not _others_named(heard).is_empty():
		return "other"
	if heard.begins_with(keeper_name() + " ") and others_near().is_empty():
		return "her"
	return "open"


## The nearest of each kind of thing she can see now: kind -> {at, point,
## open (a door's)}. Fire, water, stairs, ledges, torches, crates,
## boulders, carts, doors.
func sightings() -> Dictionary[String, Dictionary]:
	var seen: Dictionary[String, Dictionary] = {}
	for cell in _cells_within(PERCEPTION_RANGE):
		if not _sees(cell):
			continue
		var kinds: Array[String] = []
		if World.is_fire(cell):
			kinds.append("fire")
		if World.is_water(cell):
			kinds.append("water")
		if World.stair_at(cell) != Vector2i.ZERO:
			kinds.append("stair")
		if World.is_torch(cell):
			kinds.append("torch")
		if World.is_walkable(cell) and _ledge_at(cell) != 0:
			kinds.append("ledge")
		var entity := World.get_entity_at(cell)
		if entity != null and entity.pushable and entity.spawned:
			kinds.append(object_word(entity))
		elif entity is Chest and entity.spawned:
			kinds.append("chest")
		for kind in kinds:
			if not seen.has(kind):
				seen[kind] = {"at": cell, "point": Vector2(cell)}
	for door: Door in World.get_doors():
		var sides := Terrain.edge_cells(door.key)
		var near: Vector2i = sides[0] if _nearer(sides[0], sides[1]) else sides[1]
		if World.distance(tile, near) <= PERCEPTION_RANGE and (_sees(sides[0]) or _sees(sides[1])):
			if not seen.has("door") or _nearer(near, seen["door"]["at"]):
				seen["door"] = {"at": near, "point": Vector2(sides[0] + sides[1]) / 2.0, "open": door.is_open()}
	return seen


## Notes where she has seen each kind of thing, now: her memory of the zone.
func _remember_sights() -> void:
	var seen := sightings()
	for kind: String in seen:
		_memory[kind] = seen[kind]
		_memory[kind]["tick"] = World.tick


## What she knows of each of [param kinds] (what her player's words
## mentioned): in sight, where it is; remembered, where and how long ago;
## sensed, from where; else that she has not seen one here, never that
## there is none.
func knowledge_of(kinds: Array[String]) -> String:
	const NAMES := {"fire": "fire", "water": "water", "stair": "a stair", "ledge": "a ledge", "torch": "a torch",
		"crate": "a crate", "boulder": "a boulder", "cart": "a cart", "chest": "a chest", "door": "a door"}
	var seen := sightings()
	var sentences: Array[String] = []
	var unseen := 0
	for kind in kinds:
		var word: String = NAMES.get(kind, "a " + kind)
		if seen.has(kind):
			var where := "where you stand" if seen[kind]["at"] == tile else _paces_toward(seen[kind]["point"])
			var state := ", %s" % ("open" if seen[kind]["open"] else "closed") if kind == "door" else ""
			sentences.append("%s is %s%s." % [word.capitalize() if word == "fire" or word == "water" else word[0].to_upper() + word.substr(1),
				where, state])
		elif _memory.has(kind):
			var ago := (World.tick - int(_memory[kind]["tick"])) / float(World.TICK_RATE)
			var when := "just now" if ago < 20.0 else "a little while ago" if ago < 120.0 else "a while ago"
			sentences.append("You saw %s %s %s." % [word, _paces_toward(_memory[kind]["point"]), when])
		elif kind == "fire" and World.heat_at(tile) >= HEAT_FELT and not World.heat_from(tile).is_empty():
			sentences.append("You feel heat from the %s, from something you cannot see." % World.heat_from(tile))
		else:
			unseen += 1
	if unseen > 0:
		sentences.append(("%s mentioned something you haven't seen, so you don't know whether it exists. A plain no would "
			+ "claim you know it isn't there, which you don't. Find out what %s means, or offer to look for it, in your own "
			+ "words.") % [keeper_name(), keeper_name()])
	return " ".join(sentences)


## What she carries, in a sentence.
func carried() -> String:
	return "You carry a lantern, and nothing else of note." if emit_light > 0.0 else "You carry nothing of note."


## Who else is in her zone, where, and who is near enough to hear: the other
## players and their companions, compass and paces ("Bo is 4 paces to the
## north-east, near enough to hear. Nix, who travels with Bo, ...").
func others_here() -> String:
	var parts: Array[String] = []
	var near := 0
	for entity in World.get_entities():
		if entity == self or entity == keeper or not entity.spawned or not (entity is Player or entity is Companion):
			continue
		var close := World.distance(tile, entity.tile) <= HEARING_RANGE
		near += 1 if close else 0
		var who := _name_of(entity)
		if entity is Companion:
			who = "%s, who travels with %s," % [who, (entity as Companion).keeper_name()]
		parts.append("%s is %s, %s" % [who, _paces_toward(Vector2(entity.tile)), "near enough to hear" if close else "too far to hear"])
	if parts.is_empty():
		return "No one else is here."
	return "Also here: %s.%s" % ["; ".join(parts), "" if near > 0 else " No one else is near enough to hear."]


## A quick phrase ([param phrase], 1-4) sets its stance at once
## (PHRASE_STANCES) and stands as the instruction; her voice still answers
## it, but its stance, if any, is not taken.
func owner_spoke(text: String, phrase := 0) -> void:
	_heard.append({"text": text, "tick": World.tick})
	var meaning := meaning_of(text, keeper_name())
	var heard := meaning if not meaning.is_empty() else "%s just said to you: \"%s\"" % [keeper_name(), text]
	if meaning.is_empty():
		_add_turn("user", text)
	else:
		_narrate("%s calls out to you. %s" % [keeper_name(), meaning])
	if PHRASE_STANCES.has(phrase):
		_serial += 1
		var wanted: int = PHRASE_STANCES[phrase]
		_set_stance(wanted, _serial, "phrase")
		_instruction = heard
		_instruction_tick = World.tick
		_instruction_stance = STANCE_NAMES[wanted]
		_log({"kind": "stance", "companion": String(name), "mind": "phrase", "trigger": "quick phrase %d: %s" % [phrase, text],
			"stance": STANCE_NAMES[wanted], "outcome": "applied", "note": "a quick phrase: its stance at once, standing as the instruction"})
	_ask_voice("%s just spoke to you." % keeper_name(), heard, false, PHRASE_STANCES.has(phrase))


## A creature died in her sight (Main): an event for the hands, told to
## the voice as narration. [param her_player]: it was the player she
## travels with, who is down until they respawn (its own event). Her voice
## speaks to an ally's death; to a monster's only if it was a big one
## (BIG_MONSTER_MASS), next to her player, or the last of a fight (_watch).
func note_death(who: String, her_player := false, entity: GridEntity = null) -> void:
	if her_player:
		_keeper_down = true
	var monster := entity is Monster
	var big := monster and entity.mass >= BIG_MONSTER_MASS
	var by_them := monster and _alive(keeper) and World.distance(entity.tile, keeper.tile) <= 1
	_deaths.append({"who": who, "told": refer(entity, true) if monster else who,
		"speak": not monster or big or by_them, "monster": monster})
	_fallen.append({"word": kind_of(entity) if monster else who, "monster": monster})
	if _fallen.size() > 8:
		_fallen.pop_front()


## A monster's kind ("imp", "brute"), from its level marker or, for one
## made otherwise, its name; "monster" when neither says.
static func kind_of(entity: GridEntity) -> String:
	var kind := str(entity.spawn_spec.get("kind", ""))
	if not kind.is_empty():
		return kind
	var plain := String(entity.name).to_lower()
	for known: String in Level.MONSTER_TYPES:
		if known in plain:
			return known
	return "monster"


## How the voice is told of [param entity]: a monster by its kind, "the
## brute" when it is the only one of its kind she can see, "an imp" when
## there are more; anyone else by name.
func refer(entity: GridEntity, capital := false) -> String:
	if entity is not Monster:
		return _name_of(entity)
	var kind := kind_of(entity)
	var others := false
	for other in World.get_entities():
		if other is Monster and other != entity and other.spawned and kind_of(other) == kind \
				and World.distance(tile, other.tile) <= SIGHT_RANGE:
			others = true
			break
	var words := ("the " if not others else "an " if kind[0] in "aeiou" else "a ") + kind
	return words[0].to_upper() + words.substr(1) if capital else words


## [param count] of [param kind], in words: "an imp", "three brutes".
static func counted(kind: String, count: int) -> String:
	const NUMBERS: Array[String] = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight"]
	if count == 1:
		return ("an " if kind[0] in "aeiou" else "a ") + kind
	return "%s %ss" % [NUMBERS[mini(count, NUMBERS.size() - 1)], kind]


## Who fell near her, monsters counted by kind: "three imps, a brute and
## Jeff, who has risen again".
func _fallen_words() -> String:
	var kinds: Array[String] = []
	var counts: Dictionary[String, int] = {}
	var allies: Array[String] = []
	for fallen: Dictionary in _fallen:
		var word := str(fallen["word"])
		if fallen["monster"]:
			if not counts.has(word):
				kinds.append(word)
			counts[word] = counts.get(word, 0) + 1
		elif word not in allies:
			allies.append(word)
	var parts: Array[String] = []
	for kind in kinds:
		parts.append(counted(kind, counts[kind]))
	for ally in allies:
		parts.append("%s, who has risen again" % ally if ally == keeper_name() and _alive(keeper) else ally)
	if parts.size() == 1:
		return parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, -1)), parts.back()]


## What a default quick phrase means, said by [param who]; "" for any other line.
static func meaning_of(text: String, who: String) -> String:
	var meaning: String = PHRASE_MEANINGS.get(text.strip_edges(), "")
	return meaning % who if not meaning.is_empty() else ""


## The instruction standing now, as she reads it, or "" (none, or older
## than INSTRUCTION_TICKS).
func standing_instruction() -> String:
	if _instruction.is_empty() or World.tick - _instruction_tick > INSTRUCTION_TICKS:
		return ""
	return _instruction


func _instruction_locked() -> bool:
	return not standing_instruction().is_empty() and World.tick - _instruction_tick < INSTRUCTION_LOCK_TICKS


## A line she said, for the voice and the echo check.
func remember_said(line: String) -> void:
	_said.append(line)
	if _said.size() > SAID_REMEMBERED:
		_said.pop_front()


## Her last SAID_REMEMBERED lines, for her record.
func said_lines() -> Array[String]:
	return _said.duplicate()


## [param line] cut to LINE_MAX characters at the end of a sentence (or,
## with none, of a word), never in the middle of one.
static func trim_line(line: String) -> String:
	var text := line.strip_edges()
	if text.length() <= LINE_MAX:
		return text
	var cut := text.left(LINE_MAX)
	var end := maxi(maxi(cut.rfind(". "), cut.rfind("! ")), cut.rfind("? "))
	if end > 0:
		return cut.left(end + 1)
	var space := cut.rfind(" ")
	return (cut.left(space) if space > 0 else cut) + "..."


## Her lines from her record, at spawn.
func restore_said(lines: Variant) -> void:
	_said.clear()
	if lines is Array:
		for line: Variant in lines:
			remember_said(str(line))


func _sim_tick() -> void:
	if mind != null:
		for result: Dictionary in mind.take_results():
			_take_result(result)
	if keeper == null or not is_instance_valid(keeper) or not keeper.spawned:
		# Nobody to follow: stand still until her player is back. A death
		# (her player's own, say) is still a moment for her voice.
		current_intent = Intent.IDLE
		_seen = {}
		if not _deaths.is_empty():
			var deaths := _take_deaths(not _hostile_within(COMBAT_RANGE))
			if not deaths.is_empty():
				_ask_voice(" ".join(deaths))
		return
	if _keeper_down:
		_keeper_down = false
		_keeper_back = true
	if _joined_tick == -1:
		_joined_tick = World.tick
	_watch()
	if World.tick % MEMORY_EVERY == 0:
		_remember_sights()
	_calm()
	_heal()
	_act()
	_execute()


# --- Watching: what asks her mind ---------------------------------------------

## Compares the room with last tick's and asks the hands and the voice on
## what matters; sends asks a busy mind made wait.
func _watch() -> void:
	var now := _situation_now()
	var events: Array[String] = []
	var threshold := false
	var lapsing := false
	if not _seen.is_empty():
		for id: int in now["adjacent"]:
			if not _adjacent_before.has(id):
				var monster := instance_from_id(id) as GridEntity
				var where := "you" if monster != null and World.distance(tile, monster.tile) == 1 else keeper_name()
				events.append("%s came up next to %s." % [_name_of(monster) if monster != null else "A monster", where])
				var beside: GridEntity = self if where == "you" else keeper
				_narrate("%s came up next to %s, from the %s." % [refer(monster, true) if monster != null else "A monster", where,
					World.compass(Vector2(monster.tile - beside.tile)) if monster != null and beside != null else "side"])
				break
		for whose: String in ["hp_band", "keeper_hp_band"]:
			if now[whose] == _seen[whose]:
				continue
			if now[whose] < _seen[whose]:
				# Healing past a threshold: told, but no moment to decide anything.
				_narrate("%s a little stronger now." % ["You are" if whose == "hp_band" else "%s is" % keeper_name()])
				continue
			threshold = true
			var mine := whose == "hp_band"
			var event := "%s %s" % ["Your HP" if mine else "%s's HP" % keeper_name(), _hp_change(_seen[whose], now[whose])]
			var body: GridEntity = self if mine else keeper
			var told := "%s %s now" % ["You are" if mine else "%s is" % keeper_name(), health_words(body)]
			if now[whose] == HP_THRESHOLDS.size() and not standing_instruction().is_empty():
				# Either of them badly hurt: what was asked no longer binds her.
				_narrate("%s, and what %s asked of you no longer binds you." % [told, keeper_name()])
				events.append("%s, so %s's instruction no longer holds." % [event, keeper_name()])
				_lapsed_from = stance_name()
				_lapse_why = "your HP is low" if mine else "%s's HP is low" % keeper_name()
				_instruction = ""
				lapsing = true
			else:
				_narrate(told + ".")
				events.append(event + ".")
	if _keeper_back:
		_keeper_back = false
		events.append("%s respawned." % keeper_name())
		_narrate("%s has risen again." % keeper_name())
	for id: int in now["adjacent"]:
		_adjacent_before[id] = true
	_seen = now
	var fight := in_fight()
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(tile, entity.tile) <= SIGHT_RANGE \
				and World.has_line_of_sight(tile, entity.tile) and not _known_hostiles.has(entity.get_instance_id()):
			_known_hostiles[entity.get_instance_id()] = true
			# In a fight a sighting is no event; only what changes is.
			if not fight and not _was_in_fight:
				events.append("%s came into sight." % _name_of(entity))
				_narrate("%s came into sight, %s." % [refer(entity, true), _paces_toward(Vector2(entity.tile))])
	var had_deaths := not _deaths.is_empty()
	var dead_names: Array[String] = []
	for death: Dictionary in _deaths:
		dead_names.append("%s died." % death["who"])
	var deaths := _take_deaths(not fight)
	events.append_array(dead_names)
	if _was_in_fight and not fight:
		_fight_ended_tick = World.tick
		_silence_due = true
		_adjacent_before.clear()
	_was_in_fight = fight
	# The stance model only in a fight (or danger, which is closer still);
	# calm, she guards (_calm).
	if not events.is_empty() and fight and (threshold or not _instruction_locked()):
		_ask_stance(" ".join(events))
	# A lapse is spoken to once her new stance is known (_take_result).
	if (threshold or not deaths.is_empty()) and not lapsing and _lapsed_from.is_empty():
		_ask_voice(" ".join(deaths if not deaths.is_empty() else events))
	elif had_deaths and deaths.is_empty():
		_log({"kind": "voice", "companion": String(name), "trigger": " ".join(dead_names),
			"outcome": "not asked", "note": "a monster's death: not big, not by %s, not the last" % keeper_name()})
	if _silence_due and not fight and World.tick - _fight_ended_tick >= SILENCE_TICKS:
		_silence_due = false
		if _last_speech_tick < _fight_ended_tick:
			_narrate("The fighting is over. It is quiet.")
			_ask_voice("The fight is over, and you have said nothing since.")
	if not fight:
		_pending_stance = ""
	if not _pending_stance.is_empty() and mind != null and not mind.busy("stance"):
		var trigger := _pending_stance
		_pending_stance = ""
		_ask_stance(trigger)
	if not _pending_voice.is_empty() and mind != null and not mind.busy("voice"):
		var waiting := _pending_voice
		_pending_voice = {}
		_ask_voice(waiting["trigger"], waiting["heard"], waiting.get("always", false), waiting.get("phrase", false),
			waiting.get("own", true))


## Narrates the deaths seen and clears them; returns those her voice is
## asked about ("Imp2 died."): an ally's, a big monster's, one by her
## player, or, with [param fight_over], the last monster of a fight.
func _take_deaths(fight_over: bool) -> Array[String]:
	var spoken: Array[String] = []
	var any_monster := false
	for death: Dictionary in _deaths:
		_narrate("%s fell." % death["told"])
		any_monster = any_monster or death["monster"]
		if death["speak"]:
			spoken.append("%s died." % death["who"])
	if spoken.is_empty() and any_monster and fight_over:
		spoken.append("%s died, the last of them." % _deaths.back()["who"])
	_deaths.clear()
	return spoken


## Calm (nothing hostile within COMBAT_RANGE of her or her player) and no
## standing instruction: she guards, following her player, without asking
## anyone.
func _calm() -> void:
	if in_fight() or not standing_instruction().is_empty():
		return
	if stance != Stance.GUARD:
		_serial += 1
		var was := stance_name()
		_set_stance(Stance.GUARD, _serial, "calm")
		_log({"kind": "stance", "companion": String(name), "mind": "calm", "trigger": "calm, no instruction",
			"stance": "GUARD", "outcome": "applied", "note": "from %s: nothing hostile near and nothing asked" % was})
	_explain_lapse()


## An instruction lapsed (her or her player below 30%%) and her stance is
## known again: if it changed, her voice is asked to say why.
func _explain_lapse() -> void:
	if _lapsed_from.is_empty():
		return
	var was := _lapsed_from
	_lapsed_from = ""
	if stance_name() != was:
		var now_words := STANCE_WORDS[stance] % keeper_name() if "%s" in STANCE_WORDS[stance] else STANCE_WORDS[stance]
		_narrate("You have changed what you are doing: you are %s now. Tell %s why." % [now_words, keeper_name()])
		_ask_voice("%s, so %s's instruction no longer holds, and you changed course: from %s to %s. Say why, briefly." % [
			_lapse_why[0].to_upper() + _lapse_why.substr(1), keeper_name(), was, stance_name()], "", true)


## A hostile within COMBAT_RANGE of her or her player.
func in_fight() -> bool:
	return _hostile_within(COMBAT_RANGE)


func _hostile_within(reach: int) -> bool:
	var player_here := _alive(keeper)
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and (World.distance(tile, entity.tile) <= reach
				or player_here and World.distance(keeper.tile, entity.tile) <= reach):
			return true
	return false


## How things stand, to tell what changed: the hostiles next to her or her
## player, and which HP_THRESHOLDS band each of them is in.
func _situation_now() -> Dictionary:
	var player_here := _alive(keeper)
	var adjacent: Array[int] = []
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and (World.distance(tile, entity.tile) == 1
				or player_here and World.distance(keeper.tile, entity.tile) == 1):
			adjacent.append(entity.get_instance_id())
	return {"adjacent": adjacent, "hp_band": _hp_band(self),
		"keeper_hp_band": _hp_band(keeper) if player_here else 0}


## How many of HP_THRESHOLDS [param entity]'s hp is below.
static func _hp_band(entity: GridEntity) -> int:
	var band := 0
	for threshold in HP_THRESHOLDS:
		if entity.max_hp > 0 and float(entity.hp) / entity.max_hp < threshold:
			band += 1
	return band


## "fell below 30%" / "rose above 50%", from HP_THRESHOLDS bands.
static func _hp_change(before: int, now: int) -> String:
	return "%s %s" % ["fell below" if now > before else "rose above", _threshold_crossed(before, now)]


static func _threshold_crossed(before: int, now: int) -> String:
	var threshold: float = HP_THRESHOLDS[maxi(before, now) - 1]
	return "%d%%" % roundi(threshold * 100.0)


# --- Asking -------------------------------------------------------------------

## Asks her mind for a stance, on [param trigger]; with the mind busy, the
## newest such event waits.
func _ask_stance(trigger: String) -> void:
	if mind == null:
		return
	if mind.busy("stance"):
		_pending_stance = trigger
		return
	_serial += 1
	var ask := {
		"kind": "stance", "serial": _serial, "trigger": trigger,
		"system": STANCE_SYSTEM % (WHY_FIELD if Net.mind_why else ""), "user": stance_prompt(),
		"hp": hp, "max_hp": max_hp, "spoken_to": false,
	}
	var answer := mind.stance(ask)
	if not answer.is_empty():
		_take_result(_sync_result(ask, answer))


## Asks her voice for a line, on [param trigger]; [param heard] is what her
## player said, as she reads it ("" when they said nothing).
## [param always]: the line is said whatever the rate limit (her player's
## words make it so too).
## [param phrase]: a quick phrase's, whose stance is already set: the
## reply's stance is not taken. [param own]: [param heard] is her player's
## words (a stance may answer them); someone else's are only heard.
func _ask_voice(trigger: String, heard := "", always := false, phrase := false, own := true) -> void:
	if mind == null:
		return
	if (heard.is_empty() or not own) and not always and World.tick - _last_speech_tick < SPEECH_INTERVAL_TICKS:
		return  # She could not say it: the rate limit.
	if mind.busy("voice"):
		# Her player's words come first; otherwise the newest moment.
		if not heard.is_empty() or always or str(_pending_voice.get("heard", "")).is_empty():
			_pending_voice = {"trigger": trigger, "heard": heard, "always": always, "phrase": phrase, "own": own}
		return
	_serial += 1
	_phrase_serials[_serial] = phrase
	var asked := not heard.is_empty() and own
	# Certainly hers: then a stance with no words still counts.
	_certain_serials[_serial] = asked and addressed_to(heard) == "her"
	var messages := voice_messages(asked, heard)
	var ask := {
		"kind": "voice", "serial": _serial, "trigger": trigger, "messages": messages, "speaker": _name_of(self),
		"system": messages[0]["content"], "user": render(messages.slice(1)),
		"hp": hp, "max_hp": max_hp, "spoken_to": asked, "asked": asked, "heard": heard, "always": always,
	}
	var answer := mind.voice(ask)
	if not answer.is_empty():
		_take_result(_sync_result(ask, answer))


static func _sync_result(ask: Dictionary, answer: Dictionary) -> Dictionary:
	return {"kind": ask["kind"], "serial": ask["serial"], "trigger": ask["trigger"],
		"prompt": render(ask["messages"]) if ask.has("messages") else "%s\n\n%s" % [ask["system"], ask["user"]],
		"raw": JSON.stringify(answer),
		"answer": answer, "error": "", "latency_ms": 0, "spoken_to": ask.get("spoken_to", false), "asked": ask.get("asked", false),
		"heard": ask.get("heard", ""),
		"always": ask.get("always", false)}


## The hands' ask: who she is, the situation, what she sees around her,
## the standing instruction.
func stance_prompt() -> String:
	var around := perception()
	return "%s\n%s\n%s%s" % [identity(), situation_text(), around + "\n" if not around.is_empty() else "",
		_instruction_line()]


## The voice's ask, as chat messages: the system message (her card, the
## world, now), then the exchange, a user's turn last. [param asked]: her
## player has just spoken to her, so she may answer with a stance.
func voice_messages(asked := false, heard := "") -> Array[Dictionary]:
	var who := keeper_name()
	var instructed := CARD_INSTRUCTED % [who, who] if not standing_instruction().is_empty() else ""
	var now: Array[String] = [voice_situation(), others_here(), carried(), doing()]
	var topics := mentioned_topics()
	if not topics.is_empty():
		now.append("You have already mentioned: %s." % ", ".join(topics))
	if not standing_instruction().is_empty():
		now.append("What %s asked of you still stands: %s" % [who, standing_instruction()])
	now.append(run_summary(false))
	var around := perception() if surroundings_keys() != _around_said or asks_about_surroundings(heard) else ""
	var system := "%s %s%s\n\n%s\n\nNow: %s\n\n%s%s" % [identity(), card, instructed, VOICE_WORLD, " ".join(now),
		around + "\n\n" if not around.is_empty() else "", VOICE_RULES % [who, who]]
	var addressed := addressed_to(heard)
	var speaker := heard.get_slice(" ", 0)
	if asked:
		match addressed:
			"her":
				system += "\n\n" + VOICE_FOR_HER % [who, " by name" if _says_name(heard) else ", and no one else is near"]
			"other":
				system += "\n\n" + VOICE_FOR_OTHER % [who, " and ".join(_others_named(heard))]
			_:
				system += "\n\n" + VOICE_OPEN % [who, " and ".join(others_near())]
		var kinds := asked_about()
		if not kinds.is_empty() and addressed != "other":
			# What she knows of what was mentioned, right by the answer it is for.
			system += "\nWhat you know of what %s mentioned: %s" % [who, knowledge_of(kinds)]
		if addressed != "other":
			system += "\n" + VOICE_ASKED % [who, who, who, who]
	elif addressed == "her":
		system += "\n\n" + VOICE_NAMED % speaker
	elif addressed == "open":
		system += "\n\n" + VOICE_OPEN % [speaker, " and ".join(others_near())]
	var messages: Array[Dictionary] = [{"role": "system", "content": system}]
	for turn: Dictionary in _exchange:
		var role: String = turn["role"]
		if messages.size() == 1 and role == "assistant":
			continue  # The exchange opens with something said to her or seen.
		# What anyone said is labelled with who said it: "Bo: over here!".
		var who_said := str(turn.get("speaker", ""))
		var text := "%s: %s" % [who_said, turn["text"]] if role == "user" and not who_said.is_empty() else str(turn["text"])
		if messages.back()["role"] == role:
			messages.back()["content"] += "\n" + text
		else:
			messages.append({"role": role, "content": text})
	if messages.back()["role"] != "user":
		messages.append({"role": "user", "content": "[A moment passes.]"})
	return messages


## The voice's messages as one text, for the log and the tests.
func voice_prompt(_trigger := "", heard := "") -> String:
	return render(voice_messages(not heard.is_empty(), heard))


static func render(messages: Array) -> String:
	var parts: Array[String] = []
	for message: Dictionary in messages:
		parts.append("%s: %s" % [message["role"], message["content"]])
	return "\n\n".join(parts)


## Something seen or done, for the exchange: "[Sneak died.]".
func _narrate(text: String) -> void:
	_add_turn("user", "[%s]" % text.strip_edges(), true)


## A turn of the exchange, written to her transcript as well. Words in a
## user's turn are [param speaker]'s (her player's by default).
func _add_turn(role: String, text: String, narration := false, speaker := "") -> void:
	var who := "" if narration or role == "assistant" else speaker if not speaker.is_empty() else keeper_name()
	Transcript.record(String(name), String(name) if role == "assistant" else who, text)
	_exchange.append({"role": role, "text": text, "speaker": who})
	if _exchange.size() > EXCHANGE_KEPT:
		_exchange.pop_front()


## What she is set on and doing, in her world: "You are keeping beside Jeff
## and fighting whatever comes at either of you; right now you are
## attacking Brute."
func doing() -> String:
	var words := STANCE_WORDS[stance] % keeper_name() if "%s" in STANCE_WORDS[stance] else STANCE_WORDS[stance]
	var action := ""
	match current_intent:
		Intent.ATTACK:
			action = "attacking %s" % (refer(intent_target) if _alive(intent_target) else "a monster")
		Intent.RETREAT:
			action = "pulling away from the monsters"
		Intent.HOLD:
			action = "holding your ground"
		Intent.YIELD:
			action = "stepping out of %s's way" % keeper_name()
		Intent.IDLE:
			action = "waiting"
		_:
			action = "keeping by %s" % keeper_name()
	return "You are %s; right now you are %s." % [words, action]


## How hurt [param entity] is, in words.
static func health_words(entity: GridEntity) -> String:
	var share := float(entity.hp) / entity.max_hp if entity.max_hp > 0 else 1.0
	if share >= 0.9:
		return "unhurt"
	if share >= 0.5:
		return "a little hurt"
	if share >= REFLEX_BELOW:
		return "badly hurt"
	return "close to falling"


## The situation for the voice: the same as situation_text, in her world's
## words (no numbers of health, paces for cells).
func voice_situation() -> String:
	const NUMBERS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
	var next_to_her := _monsters_next_to(tile)
	var sentences: Array[String] = []
	sentences.append("%s monster%s next to you." % [NUMBERS[mini(next_to_her, NUMBERS.size() - 1)],
		" is" if next_to_her == 1 else "s are"])
	sentences.append("You are %s." % health_words(self))
	var who := keeper_name()
	var her_danger := _in_danger(self)
	var their_danger := false
	var low := _badly_hurt(self)
	if _alive(keeper):
		var distance := World.distance(tile, keeper.tile)
		sentences.append("%s is %s and %s." % [who, _paces_toward(Vector2(keeper.tile)),
			health_words(keeper)])
		their_danger = _in_danger(keeper)
		low = low or _badly_hurt(keeper)
	elif _keeper_down:
		sentences.append("%s has fallen." % who)
	else:
		sentences.append("%s is not here." % who)
	if her_danger and their_danger:
		sentences.append("You are both in danger.")
	elif her_danger:
		sentences.append("You are in danger.")
	elif their_danger:
		sentences.append("%s is in danger." % who)
	elif low:
		sentences.append("Nothing is near enough to strike.")
	else:
		sentences.append("Neither of you is in danger.")
	return " ".join(sentences)


## What she can see around her, for the voice and the stance (the "around
## you" block), as Net.perception has it: "list" (perception_list), "grid"
## (perception_grid) or "both", the grid first; then what the heat and the
## light tell her (field_sentences). "" when there is nothing to tell.
func perception() -> String:
	var told := ""
	match Net.perception:
		"grid":
			told = perception_grid()
		"both":
			var listed := perception_list()
			told = perception_grid() + ("\n" + listed if not listed.is_empty() else "")
		_:
			told = perception_list()
	var felt := " ".join(field_sentences(perceived()))
	if felt.is_empty():
		return told
	return felt if told.is_empty() else told + "\n" + felt


## What she can see (perceived), a line each, nearest first: "- an imp, 2
## paces ahead to your left: between you and Jeff". "" for nothing.
func perception_list() -> String:
	var lines: Array[String] = []
	for thing in perceived():
		var paces: int = thing["paces"]
		var where := "where you stand" if paces == 0 else "%s %s" % [distance_words(paces), _direction(thing["point"])]
		var relations: Array[String] = thing["relations"]
		lines.append("- %s, %s%s" % [thing["word"], where, ": " + ", ".join(relations) if not relations.is_empty() else ""])
	if lines.is_empty():
		return ""
	return "Around you, what you can see, nearest first:\n" + "\n".join(lines)


## What the list tells (perceived), as "kind@cell" keys: the same while
## nothing around her changes, however she turns. The voice is told what
## she sees only when these changed since her last line, or when asked.
func surroundings_keys() -> Array[String]:
	var keys: Array[String] = []
	var things := perceived()
	for thing: Dictionary in things:
		keys.append("%s@%s" % [thing["kind"], thing["at"]])
	keys.append_array(field_sentences(things))
	return keys


## Whether her player's words ([param heard]) ask about what is around them.
static func asks_about_surroundings(heard: String) -> bool:
	return not heard.is_empty() and RegEx.create_from_string(SURROUNDINGS_WORDS).search(heard.to_lower()) != null


## The topics of her last MENTIONED_LINES lines (MENTIONED_TOPICS), in order.
func mentioned_topics() -> Array[String]:
	var topics: Array[String] = []
	var lines := " ".join(_said.slice(-MENTIONED_LINES)).to_lower()
	for topic: String in MENTIONED_TOPICS:
		if RegEx.create_from_string("\\b(%s)" % MENTIONED_TOPICS[topic]).search(lines) != null:
			topics.append(topic % keeper_name() if "%s" in topic else topic)
	return topics


## The things worth telling that she can see within PERCEPTION_RANGE paces,
## at most PERCEPTION_MAX, nearest first, each {kind, word, at, point,
## paces, relations, monster}: monsters, crates, boulders and carts, doors,
## and the nearest cell each of fire, water, a stair and a ledge (what the
## grid's key has). Only the monsters, what her player last asked about
## (asked_about) and the rest within PERCEPTION_NEAR paces, chosen in that
## order: a ledge never crowds out the imp beside Jeff, and a crate four
## paces off is not news. Line of
## sight decides (World.has_line_of_sight: walls and closed doors stop it,
## higher ground sees over lower walls); a door is seen when a cell on
## either side of it is. Relations are worked out here (relations_of), not
## left to the model.
func perceived() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var told_once: Dictionary[String, bool] = {}
	for cell in _cells_within(PERCEPTION_RANGE):
		if not _sees(cell):
			continue
		var kinds: Array[String] = []
		if World.is_fire(cell):
			kinds.append("fire")
		if World.is_water(cell):
			kinds.append("water")
		if World.stair_at(cell) != Vector2i.ZERO:
			kinds.append("stair")
		if World.is_walkable(cell) and _ledge_at(cell) != 0:
			kinds.append("ledge")
		for kind in kinds:
			if not told_once.has(kind):
				told_once[kind] = true
				found.append(_thing(kind, cell, Vector2(cell)))
		var entity := World.get_entity_at(cell)
		if entity == null or entity == self or entity == keeper:
			continue
		if entity is Monster and entity.spawned and entity.hp > 0:
			var monster := _thing(kind_of(entity), cell, Vector2(cell))
			monster["monster"] = true
			found.append(monster)
		elif entity.pushable:
			found.append(_thing(object_word(entity), cell, Vector2(cell)))
		elif entity is Chest:
			found.append(_thing("chest", cell, Vector2(cell)))
	for door: Door in World.get_doors():
		var sides := Terrain.edge_cells(door.key)
		var near: Vector2i = sides[0] if _nearer(sides[0], sides[1]) else sides[1]
		if World.distance(tile, near) <= PERCEPTION_RANGE and (_sees(sides[0]) or _sees(sides[1])):
			found.append(_thing("open door" if door.is_open() else "closed door", near,
				Vector2(sides[0] + sides[1]) / 2.0))
	found.sort_custom(_nearer_found)
	var asked := asked_about()
	var chosen: Array[Dictionary] = []
	for wanted: Callable in [
			func(thing: Dictionary) -> bool: return thing["monster"],
			func(thing: Dictionary) -> bool: return str(thing["kind"]).get_slice(" ", 1 if "door" in thing["kind"] else 0) in asked,
			func(thing: Dictionary) -> bool: return thing["paces"] <= PERCEPTION_NEAR]:
		for thing in found:
			if chosen.size() < PERCEPTION_MAX and thing not in chosen and wanted.call(thing):
				chosen.append(thing)
	chosen.sort_custom(_nearer_found)
	return chosen


## The kinds of thing (as perceived names them, a door as "door") her
## player's last words to her named: "Where's the fire?" -> ["fire"].
func asked_about() -> Array[String]:
	const WORDS := {
		"fire": "fire|flame|burn", "water": "water|pool|lake|river", "stair": "stair|steps",
		"ledge": "ledge|drop|edge|cliff", "door": "door", "crate": "crate|box", "boulder": "boulder|rock",
		"cart": "cart", "chest": "chest", "torch": "torch",
	}
	var said := ""
	for turn in _exchange:
		if turn["role"] == "user" and not str(turn["text"]).begins_with("[") \
				and str(turn.get("speaker", keeper_name())) == keeper_name():
			said = str(turn["text"]).to_lower()
	var kinds: Array[String] = []
	for kind: String in WORDS:
		if RegEx.create_from_string("\\b(%s)" % WORDS[kind]).search(said) != null:
			kinds.append(kind)
	return kinds


## One thing seen: its words ("an imp", "fire", "a closed door"), how many
## paces off, and where it is (relations_of).
func _thing(kind: String, at: Vector2i, point: Vector2) -> Dictionary:
	const WORDS := {"fire": "fire", "water": "water", "stair": "a stair"}
	var word: String = WORDS.get(kind, ("an " if kind[0] in "aeiou" else "a ") + kind)
	if kind == "ledge":
		word = "a ledge, the ground dropping away" if _ledge_at(at) > 0 else "a ledge, the ground rising"
	var paces := World.distance(tile, at)
	if kind.ends_with("door"):
		# From her to the middle of its edge, rounded up: a door on her own
		# cell's edge is 1 pace off, one past the cell beside her 2.
		paces = ceili(maxf(absf(point.x - tile.x), absf(point.y - tile.y)))
	return {"kind": kind, "word": word, "at": at, "point": point, "paces": paces,
		"relations": relations_of(at, point), "monster": false}


## Where [param at] ([param point] for a door, its edge's middle) is, said
## against her and her player: "adjacent to you", "between you and Jeff",
## "on the far side of Jeff", "next to Jeff", "where Jeff stands", "on the ledge above
## you", "below you, down off the ledge"; none, or several. Measured from
## [param point], so a door is adjacent only on the edge of her own cell.
func relations_of(at: Vector2i, point: Vector2) -> Array[String]:
	var relations: Array[String] = []
	var her := Vector2(tile)
	var reach := maxf(absf(point.x - her.x), absf(point.y - her.y))
	if reach > 0.0 and reach <= 1.0:
		relations.append("adjacent to you")
	if _alive(keeper) and keeper.tile != tile:
		var who := keeper_name()
		var them := Vector2(keeper.tile)
		var along := (point - her).dot(them - her) / (them - her).length_squared()
		var off := point.distance_to(her + (them - her) * clampf(along, 0.0, 1.0))
		var near_them := maxf(absf(point.x - them.x), absf(point.y - them.y))
		if point == them:
			relations.append("where %s stands" % who)
		elif along > 0.0 and along < 1.0 and off <= 0.75 and point != her:
			relations.append("between you and %s" % who)
		elif along >= 1.0 and off <= 1.5:
			relations.append("on the far side of %s" % who)
		elif near_them <= 1.0:
			relations.append("next to %s" % who)
	var rise := World.height_at(at) - World.height_at(tile)
	if rise > 0:
		relations.append("on the ledge above you")
	elif rise < 0:
		relations.append("below you, down off the ledge")
	return relations


## 1 where the ground drops away from [param cell] to a neighbour off a
## ledge, -1 where it rises in one, 0 for neither (a stair is no ledge).
static func _ledge_at(cell: Vector2i) -> int:
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_walkable(cell + direction) and not World.edge_blocks(cell, direction):
			var step := World.height_step(cell, direction)
			if step != 0:
				return 1 if step > 0 else -1
	return 0


## The cells within [param reach] paces of her, nearest first.
func _cells_within(reach: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			cells.append(tile + Vector2i(dx, dy))
	cells.sort_custom(_nearer)
	return cells


func _sees(cell: Vector2i) -> bool:
	return cell == tile or World.has_line_of_sight(tile, cell)


## A map of the GRID_SIZE x GRID_SIZE cells around her, her at the centre,
## north at the top, a character a cell (spaced, so each is a token of its
## own), then the key. What she cannot see is "?". Walls and doors are
## edges, not cells, so a wall is drawn on the cell behind it where she
## sees its face (an unseen cell beside a seen one, across a wall or out in
## the void), and a door on its doorway, the cell beyond it from her ("D"
## closed, "d" open; the near cell if something stands in the doorway).
func perception_grid() -> String:
	var half := GRID_SIZE / 2
	var me := _initial(_name_of(self), "@")
	var them := ""
	if _alive(keeper):
		them = _initial(keeper_name(), "&")
		if them == me:
			them = "&"
	var glyphs: Dictionary[Vector2i, String] = {}
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var cell := tile + Vector2i(dx, dy)
			glyphs[cell] = _ground_glyph(cell) if _sees(cell) else _unseen_glyph(cell)
	for door: Door in World.get_doors():
		var sides := Terrain.edge_cells(door.key)
		var near: Vector2i = sides[0] if _nearer(sides[0], sides[1]) else sides[1]
		var far: Vector2i = sides[1] if near == sides[0] else sides[0]
		if not (_sees(near) or _sees(far)):
			continue
		var at := far if World.get_entity_at(far) == null else near
		if glyphs.has(at) and World.get_entity_at(at) == null:
			glyphs[at] = "d" if door.is_open() else "D"
	var kinds: Array[String] = []
	for cell: Vector2i in glyphs:
		var entity := World.get_entity_at(cell)
		if entity == null or not _sees(cell):
			continue
		if entity == self:
			glyphs[cell] = me
		elif entity == keeper:
			glyphs[cell] = them
		elif entity is Monster and entity.spawned:
			var kind := kind_of(entity)
			glyphs[cell] = kind[0]
			if kind not in kinds:
				kinds.append(kind)
		elif entity.pushable:
			glyphs[cell] = "o" if object_word(entity) == "boulder" else "c"
		elif entity is Chest:
			glyphs[cell] = "="
	# The level's north at the top, its east on the right.
	var up := World.north
	var east := Vector2i(-up.y, up.x)
	var rows: Array[String] = []
	for row_at in range(-half, half + 1):
		var row: Array[String] = []
		for column in range(-half, half + 1):
			row.append(glyphs[tile + east * column - up * row_at])
		rows.append(" ".join(row))
	var key: Array[String] = ["%s you" % me]
	if not them.is_empty():
		key.append("%s %s" % [them, keeper_name()])
	for kind: String in Level.MONSTER_TYPES:
		if kind not in kinds:
			kinds.append(kind)
	for kind in kinds:
		key.append("%s %s" % [kind[0], kind])
	key.append_array(["f fire", "~ water", "# wall", "D closed door", "d open door", "c crate or cart", "o boulder", "= chest",
		"^ stair", "v drop to lower ground", ". floor", "? out of sight"])
	return "A map of what you can see, you at the centre, north at the top, one character a pace:\n%s\nKey: %s." % [
		"\n".join(rows), ", ".join(key)]


## How [param cell] shows on the grid when she can see it.
func _ground_glyph(cell: Vector2i) -> String:
	if World.is_fire(cell):
		return "f"
	if World.is_water(cell):
		return "~"
	if not World.is_walkable(cell):
		return "#"
	if World.stair_at(cell) != Vector2i.ZERO:
		return "^"
	if World.height_at(cell) < World.height_at(tile) and _ledge_at(cell) < 0:
		return "v"
	return "."


## How [param cell] shows when she cannot see it: "#" where she sees the
## wall in front of it (from a neighbour she sees, across a wall edge or
## into the void), "?" otherwise.
func _unseen_glyph(cell: Vector2i) -> String:
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var from := cell + direction
		if not _sees(from) or not (World.is_walkable(from) or World.is_water(from)):
			continue
		if World.edge_kind(from, -direction) == Terrain.Edge.WALL \
				or not (World.is_walkable(cell) or World.is_water(cell)):
			return "#"
	return "?"


## [param words]' first letter, upper case; [param otherwise] when that
## would read as something in the grid's key.
static func _initial(words: String, otherwise: String) -> String:
	var letter := words.left(1).to_upper()
	return otherwise if letter.is_empty() or letter == "D" or not letter.is_valid_identifier() else letter


## Crate, boulder or cart.
static func object_word(entity: GridEntity) -> String:
	if str(entity.spawn_spec.get("shape", "")) == "slab":
		return "cart"
	return "boulder" if entity.body_material == GridEntity.BodyMaterial.STONE else "crate"


func _nearer_found(a: Dictionary, b: Dictionary) -> bool:
	return _nearer(a["at"], b["at"])


func _nearer(a: Vector2i, b: Vector2i) -> bool:
	var da := World.distance(tile, a)
	var db := World.distance(tile, b)
	if da != db:
		return da < db
	return (a - tile).length_squared() < (b - tile).length_squared()


## Which way [param point] is from her, by the level's compass (World.compass,
## worked out here, never by the model): "to the north-east".
func _direction(point: Vector2) -> String:
	return "to the " + World.compass(point - Vector2(tile))


## [param point] from her for a sentence's end: "beside you to the east",
## "three paces to the north-east".
func _paces_toward(point: Vector2) -> String:
	var offset := point - Vector2(tile)
	var paces := roundi(maxf(absf(offset.x), absf(offset.y)))
	return "%s to the %s" % [distance_words(paces), World.compass(offset)]


## How far, in words, never a number: "close by", "a few paces", "some way
## off", "at the edge of sight".
static func distance_words(paces: int) -> String:
	if paces <= 1:
		return "close by"
	if paces <= 3:
		return "a few paces"
	if paces <= 6:
		return "some way off"
	return "at the edge of sight"


## What the heat and the light around her say, a sentence each at most:
## heat felt from where no fire she is told of burns ("You feel heat from
## the north-east."), the dark where she stands, or past an open door
## ("It is dark past the door to the east."). [param told]: the things
## perceived tells of.
func field_sentences(told: Array[Dictionary]) -> Array[String]:
	var sentences: Array[String] = []
	var heat := World.heat_at(tile)
	var fire_told := told.any(func(thing: Dictionary) -> bool: return thing["kind"] == "fire")
	if heat >= HEAT_FELT and not fire_told and not World.is_fire(tile):
		var from := World.heat_from(tile)
		if not from.is_empty():
			sentences.append("You feel heat from the %s." % from)
	if World.light_at(tile) < DARK:
		sentences.append("It is dark where you stand.")
		return sentences
	for door: Door in World.get_doors():
		if not door.open:
			continue
		var sides := Terrain.edge_cells(door.key)
		var near: Vector2i = sides[0] if _nearer(sides[0], sides[1]) else sides[1]
		var far: Vector2i = sides[1] if near == sides[0] else sides[0]
		if World.distance(tile, near) <= PERCEPTION_RANGE and (near == tile or World.has_line_of_sight(tile, near)) \
				and World.light_at(far) < DARK and World.light_at(near) >= DARK:
			sentences.append("It is dark past the door to the %s." % World.compass(Vector2(far - tile)))
			break
	return sentences


func _instruction_line() -> String:
	var instruction := standing_instruction()
	if instruction.is_empty():
		return "No standing instruction."
	return "Standing instruction: %s (%d seconds ago)." % [instruction.trim_suffix("."),
		roundi((World.tick - _instruction_tick) / float(World.TICK_RATE))]


## The run so far, short: how long together, who fell, the last few things
## the party log says (without what she said or was told).
func run_summary(with_lately := true) -> String:
	var parts: Array[String] = []
	var together := int(maxi(World.tick - maxi(_joined_tick, 0), 0) / float(World.TICK_RATE))
	parts.append("You have travelled with %s for %s." % [keeper_name(),
		"%d seconds" % together if together < 120 else "%d minutes" % int(together / 60.0)])
	if not _fallen.is_empty():
		parts.append("Lying dead near you, no threat now: %s." % _fallen_words())
	var lately: Array[String] = []
	if with_lately:
		lately = _lately()
	if not lately.is_empty():
		parts.append("Lately: %s" % " ".join(lately))
	return " ".join(parts)


func _lately() -> Array[String]:
	var lines: Array[String] = []
	if party_log == null:
		return lines
	var own := "%s said: " % name
	var to_her := " said to %s: " % name
	for line in party_log.last(LOG_LINES_SCANNED):
		if not line.begins_with(own) and not to_her in line:
			lines.append(line)
	return collapse_log(lines).slice(-SUMMARY_LINES)


## Asks the instruction check about [param heard] (her player's words, as
## she was told them): does it ask her to change how she fights or moves?
## Only then does [param wanted], her voice's reading, stand. The words
## alone are asked, nothing of the scene.
func _check_instruction(wanted: int, serial: int, heard: String) -> void:
	_checks[serial] = {"stance": wanted, "heard": heard}
	if mind == null or mind.busy("check"):
		_log({"kind": "check", "companion": String(name), "trigger": heard, "outcome": "not asked",
			"note": "the check is busy; %s stands" % stance_name()})
		_checks.erase(serial)
		return
	var ask := {"kind": "check", "serial": serial, "trigger": heard, "system": CHECK_SYSTEM,
		"user": _quoted(heard), "heard": heard}
	var answer := mind.check(ask)
	if not answer.is_empty():
		_take_result(_sync_result(ask, answer))


func _take_check(result: Dictionary, answer: Dictionary, entry: Dictionary) -> void:
	var serial := int(result.get("serial", 0))
	var waiting: Dictionary = _checks.get(serial, {})
	_checks.erase(serial)
	if waiting.is_empty():
		return
	var wanted: int = waiting["stance"]
	entry["stance"] = STANCE_NAMES[wanted]
	if answer.get("asked") != true:
		entry["outcome"] = "not an instruction"
		entry["note"] = "%s's words ask nothing of how she fights or moves: %s not taken" % [keeper_name(), STANCE_NAMES[wanted]]
	elif serial < _stance_serial:
		entry["outcome"] = "superseded"
		entry["note"] = "a newer ask's %s stands" % stance_name()
	else:
		_set_stance(wanted, serial, entry["mind"])
		_instruction = str(waiting["heard"])
		_instruction_tick = World.tick
		_instruction_stance = STANCE_NAMES[wanted]
		entry["outcome"] = "applied"
		entry["note"] = "an instruction: %s, and %s's words stand" % [STANCE_NAMES[wanted], keeper_name()]
	_log(entry)


## A mind's answer came back (or was there at once): a stance applied
## unless a newer ask's stands, a line said unless it echoes; logged.
func _take_result(result: Dictionary) -> void:
	var kind := str(result.get("kind", "stance"))
	var entry := {"kind": kind, "companion": String(name), "mind": mind.kind if mind != null else "none",
		"trigger": result.get("trigger", ""), "prompt": result.get("prompt", ""),
		"reply": result.get("raw", ""), "latency_ms": result.get("latency_ms", 0)}
	var answer: Dictionary = result.get("answer", {})
	if answer.has("why"):
		entry["why"] = str(answer["why"])
	if answer.is_empty():
		entry["outcome"] = "no answer"
		entry["note"] = "%s; %s stands" % [result.get("error", ""), stance_name()]
		_log(entry)
		return
	var serial := int(result.get("serial", 0))
	var stance_text := str(answer.get("stance", "")).strip_edges().to_upper()
	var wanted := STANCE_NAMES.find(stance_text)
	entry["stance"] = stance_text
	if kind == "check":
		_take_check(result, answer, entry)
		return
	if kind == "stance":
		if wanted == -1:
			entry["outcome"] = "rejected"
			entry["note"] = "not a stance; %s stands" % stance_name()
		elif wanted == Stance.HOLD:
			entry["outcome"] = "rejected"
			entry["note"] = "HOLD is only by %s's word; %s stands" % [keeper_name(), stance_name()]
		elif serial < _stance_serial:
			entry["outcome"] = "superseded"
			entry["note"] = "a newer ask's %s stands" % stance_name()
		else:
			_set_stance(wanted, serial, entry["mind"])
			entry["outcome"] = "applied"
		_log(entry)
		_explain_lapse()
		return
	# The voice: to her player's words its stance is theirs to keep.
	var spoken_to: bool = result.get("spoken_to", false)
	var asked: bool = result.get("asked", false)
	if _phrase_serials.get(serial, false):
		asked = false  # A quick phrase's stance is set already.
	_phrase_serials.erase(serial)
	var always: bool = spoken_to or result.get("always", false)
	entry["outcome"] = "said"
	if not asked:
		# Only an answer to her player asking something of her sets a stance.
		entry.erase("stance")
		if wanted != -1:
			entry["stance_ignored"] = stance_text
	elif wanted != -1 and trim_line(str(answer.get("say", ""))).is_empty() and not _certain_serials.get(serial, false):
		# No words, to words that may have been for someone else: neither
		# is the stance hers.
		entry.erase("stance")
		entry["stance_ignored"] = stance_text
		entry["note"] = "a stance with no words, to a line that may not have been for her: not taken"
	elif wanted != -1:
		# Her voice read a stance into her player's words: it counts only if
		# the instruction check, on the words alone, says they asked her.
		entry.erase("stance")
		entry["stance_waiting"] = stance_text
		entry["note"] = "stance %s waits on the instruction check" % stance_text
		_check_instruction(wanted, serial, str(result.get("heard", "")))
	_certain_serials.erase(serial)
	var line := trim_line(str(answer.get("say", "")))
	var echo := _echo_of(line)
	if line.is_empty():
		entry["outcome"] = "silent"
	elif not echo.is_empty():
		entry["outcome"] = "dropped"
		entry["say_dropped"] = line
		entry["note"] = "echoes %s" % echo
		line = ""
	elif not _say(line, always):
		entry["outcome"] = "dropped"
		entry["say_dropped"] = line
		entry["note"] = "within %d ticks of her last line" % SPEECH_INTERVAL_TICKS
		line = ""
	entry["say"] = line
	_log(entry)


func _set_stance(wanted: int, serial: int, source: String) -> void:
	_stance_serial = serial
	last_mind = source
	if wanted == stance:
		return
	stance = wanted as Stance
	if stance == Stance.HOLD:
		hold_tile = tile
	print("[mind] %s (%s): stance %s" % [name, source, stance_name()])


## Says [param line] (over her, to everyone) unless the rate limit holds it
## back; [param always] for an answer to her player and her own notices.
func _say(line: String, always: bool) -> bool:
	if not always and World.tick - _last_speech_tick < SPEECH_INTERVAL_TICKS:
		return false
	_last_speech_tick = World.tick
	_around_said = surroundings_keys()
	remember_said(line)
	_add_turn("assistant", line)
	said.emit(line)
	return true


## What [param line] echoes ("her player's words" or "her own line"), or "".
func _echo_of(line: String) -> String:
	var said_now := _plain(line)
	if said_now.is_empty():
		return ""
	for heard: Dictionary in _heard:
		if World.tick - int(heard["tick"]) <= ECHO_TICKS and _same_words(said_now, _plain(str(heard["text"]))):
			return "%s's words" % keeper_name()
	for own in _said:
		if _same_words(said_now, _plain(own)):
			return "her own line"
	if not _instruction.is_empty() and _same_words(said_now, _plain(_quoted(_instruction))):
		return "the instruction she was given"
	for sentence in card.split(".", false):
		if sentence.strip_edges().length() >= 12 and _same_words(said_now, _plain(sentence)):
			return "her card"
	return ""


## One holds the other, word for word (a short one only if it is all).
static func _same_words(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if a == b:
		return true
	var shorter := a if a.length() < b.length() else b
	var longer := b if shorter == a else a
	return shorter.length() >= 6 and (" %s " % shorter) in (" %s " % longer)


## Lower case, letters, digits and single spaces.
static func _plain(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'" else " "
	return " ".join(out.split(" ", false))


# --- The hands ----------------------------------------------------------------

## Her intent this tick: a yield runs its course; the reflex (and low hp)
## retreats; otherwise her stance says.
func _act() -> void:
	var before := current_intent
	var before_target := intent_target
	var foe := _adjacent_hostile()
	var low := max_hp > 0 and float(hp) / max_hp < REFLEX_BELOW
	if current_intent == Intent.YIELD and World.tick < _yield_until and not (low and foe != null):
		return
	intent_target = null
	if low:
		current_intent = Intent.RETREAT
	else:
		match stance:
			Stance.PULL_BACK:
				current_intent = Intent.RETREAT
			Stance.HOLD:
				_fight_or(foe, Intent.HOLD)
			Stance.STAY_CLOSE:
				_fight_or(foe, Intent.FOLLOW)
			Stance.GUARD:
				_fight_or(foe if foe != null else _guard_target(), Intent.FOLLOW)
			Stance.PRESS:
				_fight_or(foe if foe != null else _nearest_hostile(SIGHT_RANGE), Intent.FOLLOW)
	if current_intent != before or intent_target != before_target:
		print("[mind] %s: %s%s (%s)" % [name, intent_name(),
			" " + String(intent_target.name) if intent_target != null else "", stance_name()])


func _fight_or(foe: GridEntity, otherwise: Intent) -> void:
	current_intent = Intent.ATTACK if foe != null else otherwise
	intent_target = foe


## Below REFLEX_BELOW of her hp with a hostile next to her.
func _reflex_active() -> bool:
	return max_hp > 0 and float(hp) / max_hp < REFLEX_BELOW and _adjacent_hostile() != null


func _adjacent_hostile() -> GridEntity:
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(tile, entity.tile) == 1:
			return entity
	return null


## GUARD's foe: the nearest hostile within GUARD_RANGE of her or her
## player, or one in sight going for either of them.
func _guard_target() -> GridEntity:
	var best: GridEntity = null
	var best_distance := 999
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster == null or not monster.spawned:
			continue
		var distance := World.distance(tile, monster.tile)
		var after_us := monster.target != null and (monster.target == self or monster.target == keeper)
		var near := distance <= GUARD_RANGE or _alive(keeper) and World.distance(keeper.tile, monster.tile) <= GUARD_RANGE
		if (near or after_us and distance <= SIGHT_RANGE) and distance < best_distance:
			best = monster
			best_distance = distance
	return best


func _nearest_hostile(reach: int) -> GridEntity:
	var best: GridEntity = null
	var best_distance := reach + 1
	for entity in World.get_entities():
		if entity is Monster and entity.spawned:
			var distance := World.distance(tile, entity.tile)
			if distance < best_distance and World.has_line_of_sight(tile, entity.tile):
				best = entity
				best_distance = distance
	return best


## Out of combat (no hostile within CALM_RANGE of her or her player for
## CALM_TICKS) she heals a point every HEAL_EVERY ticks.
func _heal() -> void:
	if _hostile_within(CALM_RANGE):
		_calm_since = World.tick
		return
	var calm := World.tick - _calm_since
	if calm >= CALM_TICKS and hp < max_hp and (calm - CALM_TICKS) % HEAL_EVERY == 0:
		World.heal(self, 1)


# --- Acting -------------------------------------------------------------------

func _execute() -> void:
	match current_intent:
		Intent.FOLLOW:
			_follow()
		Intent.RETREAT:
			_retreat()
		Intent.HOLD:
			if tile != hold_tile and World.is_free(hold_tile):
				_step_toward(hold_tile, true)
		Intent.ATTACK:
			if not _alive(intent_target):
				current_intent = Intent.FOLLOW
				intent_target = null
			elif World.can_melee(tile, intent_target.tile):
				World.try_attack(self, intent_target)
			else:
				_approach(intent_target, 1)
		Intent.YIELD:
			if _yield_tile != NONE and tile != _yield_tile and World.is_free(_yield_tile):
				_step_toward(_yield_tile, false)
		Intent.IDLE, Intent.SHOVE:
			pass


## RETREAT: to the nearest cell with no hostile next to it, near her player
## when such a cell is (safe_cell); with none, she fights the hostile next
## to her rather than stand still.
func _retreat() -> void:
	var cell := safe_cell()
	if cell == NONE:
		var foe := _adjacent_hostile()
		if foe != null and World.can_melee(tile, foe.tile):
			World.try_attack(self, foe)
		return
	if cell != tile:
		_step_toward(cell, false)


## The cell RETREAT makes for: of the free, fire-free cells within
## RETREAT_REACH steps that no hostile is next to (her own among them), the
## one with the least of steps / 2 plus the distance to her player. NONE
## if there is none.
func safe_cell() -> Vector2i:
	var hostiles: Array[Vector2i] = []
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(tile, entity.tile) <= RETREAT_REACH + 1:
			hostiles.append(entity.tile)
	var steps: Dictionary[Vector2i, int] = {tile: 0}
	var frontier: Array[Vector2i] = [tile]
	var best := NONE
	var best_score := INF
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		var safe := true
		for at in hostiles:
			if World.distance(cell, at) <= 1:
				safe = false
				break
		if safe:
			var score := steps[cell] * 0.5 + (World.distance(cell, keeper.tile) if _alive(keeper) else 0)
			if score < best_score:
				best = cell
				best_score = score
		if steps[cell] >= RETREAT_REACH:
			continue
		for direction in World.DIRECTIONS:
			var next: Vector2i = cell + direction
			if steps.has(next) or not World.is_free(next) or World.is_burning(next) \
					or World._terrain_blocks_step(cell, direction, true):
				continue
			steps[next] = steps[cell] + 1
			frontier.append(next)
	return best


## The nearest free cell that is not fire, at most YIELD_REACH steps away,
## and not on her player's line ahead (YIELD_PATH_CELLS along the way they
## were going); of equally near ones, the least far along that line. NONE
## if there is none.
func _find_yield_tile() -> Vector2i:
	if not _alive(keeper):
		return NONE
	var direction := _bump_direction if _bump_direction != Vector2i.ZERO else facing
	var line: Dictionary[Vector2i, bool] = {}
	for k in range(1, YIELD_PATH_CELLS + 1):
		line[keeper.tile + direction * k] = true
	var best := NONE
	var best_steps := YIELD_REACH + 1
	var best_ahead := INF
	for dy in range(-YIELD_REACH, YIELD_REACH + 1):
		for dx in range(-YIELD_REACH, YIELD_REACH + 1):
			var cell := tile + Vector2i(dx, dy)
			if cell == tile or line.has(cell) or not World.is_free(cell) or World.is_burning(cell):
				continue
			var path := World.find_path(tile, cell)
			if path.is_empty() or path.size() > YIELD_REACH:
				continue
			var ahead := Vector2(cell - keeper.tile).dot(Vector2(direction))
			if path.size() < best_steps or (path.size() == best_steps and ahead < best_ahead):
				best = cell
				best_steps = path.size()
				best_ahead = ahead
	return best


## Walks until within [param reach] of [param target].
func _approach(target: Variant, reach: int) -> void:
	if not _alive(target) or World.distance(tile, target.tile) <= reach:
		return
	# A FOLLOW that cannot get closer just waits; anything else gives up.
	if not _step_toward(target.tile, true) and current_intent != Intent.FOLLOW:
		print("[mind] %s: cannot reach %s; following" % [name, target.name])
		current_intent = Intent.FOLLOW
		intent_target = null


## [param entry] in the mind log, with her stance and how far her player is
## as it is written.
func _log(entry: Dictionary) -> void:
	entry["stance_now"] = stance_name()
	entry["keeper_distance"] = World.distance(tile, keeper.tile) if _alive(keeper) else -1
	MindLog.record(entry)


## FOLLOW: still while her player is within FOLLOW_START - 1 cells; once
## they are FOLLOW_START away she sets off and closes to FOLLOW_CLOSE, the
## path found afresh every step (they keep moving).
func _follow() -> void:
	if not _alive(keeper):
		_catching_up = false
		return
	var distance := World.distance(tile, keeper.tile)
	if distance >= FOLLOW_START and not _catching_up:
		_catching_up = true
		_log({"kind": "follow", "companion": String(name), "mind": "hands", "trigger": "%s %d away" % [keeper_name(), distance],
			"outcome": "set off"})
	if _catching_up and distance <= FOLLOW_CLOSE:
		_catching_up = false
		_log({"kind": "follow", "companion": String(name), "mind": "hands", "trigger": "%s %d away" % [keeper_name(), distance],
			"outcome": "closed in"})
	if _catching_up:
		_approach(keeper, FOLLOW_CLOSE)


## One A* step toward [param goal]. False if there is no way there.
func _step_toward(goal: Vector2i, occupied_goal_ok: bool) -> bool:
	if World.tick < next_move_tick:
		return true
	var path := World.find_path(tile, goal, occupied_goal_ok)
	if path.is_empty():
		return false
	World.try_move(self, path[0] - tile)
	return true


# --- Words --------------------------------------------------------------------

## [param lines] with each run of the same line made one, its count added
## ("Brute hit Player for 1 ×6."), and each run of two lines taking turns
## too ("Pip hit Brute for 2 ×4, shoved Brute ×4."; the second's subject
## dropped when it is the first's).
static func collapse_log(lines: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < lines.size():
		var run := 1
		while i + run < lines.size() and lines[i + run] == lines[i]:
			run += 1
		if run > 1:
			out.append("%s ×%d." % [lines[i].trim_suffix("."), run])
			i += run
			continue
		var pairs := 0
		if i + 1 < lines.size():
			while i + 2 * pairs + 1 < lines.size() and lines[i + 2 * pairs] == lines[i] \
					and lines[i + 2 * pairs + 1] == lines[i + 1]:
				pairs += 1
		if pairs >= 2:
			var first := lines[i].trim_suffix(".")
			var second := lines[i + 1].trim_suffix(".")
			var subject := first.get_slice(" ", 0) + " "
			if second.begins_with(subject):
				second = second.substr(subject.length())
			out.append("%s ×%d, %s ×%d." % [first, pairs, second, pairs])
			i += 2 * pairs
			continue
		out.append(lines[i])
		i += 1
	return out


## The situation in two to four plain sentences: the monsters next to her,
## her hp, her player's distance and hp, who is in danger (below 30% hp,
## or below half with a monster next to them).
func situation_text() -> String:
	const NUMBERS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
	var next_to_her := _monsters_next_to(tile)
	var sentences: Array[String] = []
	var count := NUMBERS[mini(next_to_her, NUMBERS.size() - 1)]
	sentences.append("%s monster%s next to you." % [count, " is" if next_to_her == 1 else "s are"])
	sentences.append("You have %d of %d HP." % [hp, max_hp])
	var her_danger := _in_danger(self)
	var their_danger := false
	var who := keeper_name()
	var hurt: Array[String] = []
	if _badly_hurt(self):
		hurt.append("You are badly hurt, but nothing is near you.")
	if _alive(keeper):
		var distance := World.distance(tile, keeper.tile)
		sentences.append("%s is %s with %d of %d HP." % [who,
			"next to you" if distance <= 1 else "%d cells away" % distance, keeper.hp, keeper.max_hp])
		their_danger = _in_danger(keeper)
		if _badly_hurt(keeper):
			hurt.append("%s is badly hurt, but nothing is near %s." % [who, who])
	elif _keeper_down:
		sentences.append("%s has fallen." % who)
	else:
		sentences.append("%s is not here." % who)
	if her_danger and their_danger:
		sentences.append("You are both in danger.")
	elif her_danger:
		sentences.append("You are in danger.")
	elif their_danger:
		sentences.append("%s is in danger." % who)
	elif hurt.is_empty():
		sentences.append("Neither of you is in danger.")
	sentences.append_array(hurt)
	return " ".join(sentences)


static func _monsters_next_to(at: Vector2i) -> int:
	var count := 0
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(at, entity.tile) == 1:
			count += 1
	return count


## In danger: below half hp with a hostile within DANGER_RANGE.
static func _in_danger(entity: GridEntity) -> bool:
	return entity.max_hp > 0 and float(entity.hp) / entity.max_hp < 0.5 and _hostile_near(entity.tile, DANGER_RANGE)


## Badly hurt: below REFLEX_BELOW of its hp with no hostile within DANGER_RANGE.
static func _badly_hurt(entity: GridEntity) -> bool:
	return entity.max_hp > 0 and float(entity.hp) / entity.max_hp < REFLEX_BELOW \
			and not _hostile_near(entity.tile, DANGER_RANGE)


static func _hostile_near(at: Vector2i, reach: int) -> bool:
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(at, entity.tile) <= reach:
			return true
	return false


## What an entity is called to her: its label (a player's name, as the
## party log calls them) or, with none, its node name.
static func _name_of(entity: GridEntity) -> String:
	return entity.label if not entity.label.is_empty() else String(entity.name)


## Safe to call with a freed reference, which a target that died can be.
static func _alive(entity: Variant) -> bool:
	return entity != null and is_instance_valid(entity) and entity.spawned
