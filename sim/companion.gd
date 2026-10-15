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

enum Intent { FOLLOW, HOLD, ATTACK, SHOVE, RETREAT, IDLE, YIELD, ERRAND }
enum Stance { STAY_CLOSE, HOLD, PRESS, GUARD, PULL_BACK }

const INTENT_NAMES: Array[String] = ["FOLLOW", "HOLD", "ATTACK", "SHOVE", "RETREAT", "IDLE", "YIELD", "ERRAND"]
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
## RETREAT looks this many steps around her for a safe cell, and takes one
## clear of hostiles sooner, by this much a tile up to RETREAT_CLEAR tiles
## from the nearest. She keeps to the one she chose while it stays safe and
## no other beats it by more than RETREAT_KEEP_MARGIN (with no hostile
## about, she takes the best: there is nothing to dither over); and a way
## that starts back the way she came costs RETREAT_TURN_BACK more. A cell
## two from a hostile is safe this tick and seldom the next, which is why
## clear counts for so much: else she runs from side to side of her player
## as the hostiles round them close in.
const RETREAT_REACH := 6
const RETREAT_CLEAR := 3
const RETREAT_CLEAR_WEIGHT := 2.0
const RETREAT_KEEP_MARGIN := 1.0
const RETREAT_TURN_BACK := 1.5
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
## A sentence is said again (near_repeat) when its words, these aside, are
## all in a sentence said lately, or share NEAR_SHARE of their words with
## it; plurals and -ing/-ed endings count as the same word.
const COMMON_WORDS: Array[String] = ["i", "ill", "im", "ive", "id", "we", "well", "were", "weve", "you", "youre", "youll",
	"the", "a", "an", "is", "are", "was", "it", "its", "to", "of", "and", "then", "now", "still", "will", "be", "me", "my",
	"us", "our", "on", "in", "at", "this", "that", "there", "here", "just", "so", "lets", "let", "all", "your", "up", "for"]
const NEAR_SHARE := 0.8
## What the other companions near her said in the last OTHERS_SAID_TICKS
## is not hers to say again.
const OTHERS_SAID_TICKS := 200
## A line of fewer words than this, unasked, is a fragment and not said,
## unless it is a call ("Behind you!").
const FRAGMENT_WORDS := 3
## Noises she heard and did not see: so many kept, told to her voice for
## NOISE_TOLD_TICKS; a loud one (NOISE_WORDS' asking kinds) asks her voice
## when calm, at most once in NOISE_ASK_TICKS. Steps and speech are not
## kept: speech reaches her as words (overheard), and steps are her party's.
const NOISES_KEPT := 6
const NOISE_TOLD_TICKS := 150
const NOISE_ASK_TICKS := 300
## Noise kind -> [how she is told it, whether it asks her voice].
const NOISE_WORDS := {
	&"fight": ["fighting", true], &"door": ["a door opening or shutting", false],
	&"door_struck": ["something striking a door", true], &"door_broken": ["a door breaking", true],
}
## What she can do when her player asks (can_do), offered to her voice by
## number ([DO: n]): open or close a door she sees, open a chest she sees
## and tell what is in it, or go and look where she cannot see (within her
## sight's range, at most LOOKS_OFFERED ways) and come back; at most
## ACTIONS_MAX in all. An errand ends after ERRAND_TICKS, when she is low,
## or when a monster she sees comes within ERRAND_BREAK; a look ends back
## within ERRAND_BACK of her player, telling what she saw within LOOK_AROUND
## of where she looked.
const LOOKS_OFFERED := 2
const ACTIONS_MAX := 6
const ERRAND_TICKS := 200
const ERRAND_BREAK := 4
const ERRAND_BACK := 2
const LOOK_AROUND := 2
## A sentence promising something (PROMISE) that is one of her errands
## (_errand_verbs) is said only when it names exactly one thing she could
## do now, which she then does; any other promise is roleplay and stays.
const PROMISE := "(?i)\\b(i'?ll|i will|let me|i'?m going to|i can|on it)\\b"
const COMPASS_WORD := "\\b(north-east|north-west|south-east|south-west|north|south|east|west)\\b"
## She notes where she has seen things every so many ticks (_remember_sights).
const MEMORY_EVERY := 10
## Speech carries this far (cells, in its own zone): what anyone says
## reaches the players and companions within it (Main.hearers), and her
## voice is asked only with a player this near (heard_by_anyone): the
## speech noise's own reach.
const HEARING_RANGE := Senses.NOISE_SPEECH
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
Wounds do not close on their own; a bandaging kit, used away from danger, mends them.
Whoever falls can be brought back, but it hurts, and no one wants to fall.
Directions are spoken as north, south, east and west."""
const VOICE_RULES := """Say what you would say out loud right now, as yourself, in one or two short sentences. However few
your words, say them as whole sentences, never a single word or a bare name. Your words are only what you say aloud:
never describe what you do or where you go. Not everything said near you is meant for you: a line that says your name is for you; a line that
names someone else is not; a line that names no one is open to anyone near, and you answer it if you have something
useful to say; from %s with no one else near, it is for you. When a line is meant for you, always answer in words,
even if only to say you don't know; when it is not, you usually stay quiet and answer with just: ... Never say again
what you have already said, and never repeat anyone's words back. Only when nothing has been said to you and there is
truly nothing worth saying, answer with just: ...
Speak to %s as "you", never of them by name, and to no one else unless they have just spoken to you or are in danger you must warn them
of; say a name only to call out. In what anyone says, "I" and "me" are the one speaking.
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
## What she can do now, by number, after VOICE_ASKED.
const VOICE_CAN_DO := """These you can do here and now:
%s
Only if %s asked you to do one of these, add one more line: [DO: its number]. Of these things, you can only promise what is on this list."""
## What she says is cleaned before it is said (spoken): a sentence in her
## last REPEAT_LINES lines is not said again; someone other than her player
## is spoken to only when they spoke to her (named her) within
## SPOKE_TO_HER_TICKS, or, unasked, at most once every ADDRESS_OTHER_TICKS
## when they are in danger or badly hurt; her player is "you", called by
## name only from further than CALL_OUT_PACES.
const REPEAT_LINES := 5
const SPOKE_TO_HER_TICKS := 300
const ADDRESS_OTHER_TICKS := 600
const CALL_OUT_PACES := 6
## A sentence of one word is a fragment, not said, unless it is one of
## these answers. Fragments said teach the voice more fragments.
const ONE_WORD_ANSWERS: Array[String] = ["yes", "no", "ready", "here", "coming", "sorry", "thanks", "okay", "ok", "aye"]
## Words that ask about what she carries: only then is her pack in her
## prompt, and only then may she speak of her lantern or bandages.
const ITEM_WORDS := "\\b(carry\\w*|pack|bag|items?|lanterns?|bandag\\w*|kit|holding|what (do|have) you (got|have))\\b"
const OWN_ITEMS := "\\b(lanterns?|bandag\\w*|pack)\\b"
## Narration in a line, not speech: her own name and a verb, a gesture,
## or herself moving into place ("You move to stand between ...").
const NARRATION := "(?i)^(%s) [a-z]+s\\b|^a moment passes\\b|^(you |)(nod|nods|smile|smiles|sigh|sighs|shrug|shrugs|grin|grins|frown|frowns)\\b|^you (move|step|walk|go|turn|shift|edge|plant|brace|position) .*\\b(stand|between|beside|in front of|yourself)\\b"
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
## Her card came back written (write_card): card, how_we_met, card_by set.
signal card_written
## What has become true of her changed (grown, decision 294), or the talk
## waiting to be read for it.
signal facts_changed

## The player_id this companion belongs to.
var keeper_id := ""
## Her player's live entity while they are online; null while away.
var keeper: GridEntity
## Her player's name as last known (keeper_name).
var keeper_label := ""
var card := "Loyal and cautious. Guards the one she travels with, and says little, in short, plain sentences."
## What she is made of (CompanionCard.roll), how she and her player met
## (a sentence), and who wrote her card: "plain" (her traits as facts) or
## "model" (written once by her voice's model: write_card).
var traits := {}
var how_we_met := ""
var card_by := "plain"
## What has become true of her since (CompanionFacts, decision 294); the
## stretch of talk with her player not yet read for it ("Jeff: ...", hers
## too), and when it was last added to; the facts a merge asked for is
## folding.
var grown := CompanionFacts.new()
var talk: Array[String] = []
var _talk_tick := -100000
var _merging: Array[Dictionary] = []
## The longest stretch of talk kept.
const TALK_KEPT := 30
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
## RETREAT: the safe cell she is making for (NONE: none chosen); where she
## was last, and the way she last stepped.
var _retreat_goal := NONE
var _retreat_at := NONE
var _retreat_heading := Vector2i.ZERO
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
## Her own last lines, newest last; words heard, {text, tick, speaker}.
var _said: Array[String] = []
## What was around her (surroundings_keys) when she last spoke: the voice
## is told her surroundings again only once they change, or when asked.
var _around_said: Array[String] = []
var _heard: Array[Dictionary] = []
## Who (by name) last named her when they spoke, and when; whom she last
## spoke to unasked, and when (spoken).
var _spoke_to_her: Dictionary[String, int] = {}
var _addressed: Dictionary[String, int] = {}
## What the voice sees of the recent exchange: {role: "user" | "assistant",
## text}; her player's words and narration as the user's, her lines as hers.
var _exchange: Array[Dictionary] = []
## The fight, for the silence after it.
var _was_in_fight := false
var _fight_ended_tick := -100000
var _silence_due := false
## For the run summary: when she joined, who fell near her ({word: a
## monster's kind or an ally's name, monster}).
var _joined_tick := -1
var _fallen: Array[Dictionary] = []
## What is new to her this run (a new Companion each zone and each
## reset): the kinds of monster she has seen, and seen fall. The first of a
## kind is worth her voice; the rest are told and pass. A fight is worth
## a word after it only if something in it was (_fight_notable).
var _kinds_seen: Dictionary[String, bool] = {}
var _kinds_fallen: Dictionary[String, bool] = {}
var _fight_notable := false
## What she sees, hears and remembers (Senses, as the monsters have):
## sight all round, by light (DARK), within SIGHT_RANGE.
var senses: Senses
## What she heard and could not see, newest last: {kind, at, tick}; up to
## NOISES_KEPT, told to her voice for NOISE_TOLD_TICKS; and the newest
## World.tick of senses.heard taken, and when a noise last asked her voice.
var _noises: Array[Dictionary] = []
var _heard_upto := -1
var _noise_asked_tick := -100000
## Her errand, or empty: what can_do offered ({verb, words, at, and its
## door, chest or cell}) with phase ("going", "doing", "returning"), the
## serial of the ask it answered, and when it gives up. What she was
## offered for each voice ask out, by serial; the asks that are her report
## of an errand (cleaned as an answer: what she tells is new).
var errand := {}
var _offering: Array[Dictionary] = []
var _offered: Dictionary[int, Array] = {}
var _report_serials: Dictionary[int, bool] = {}
## The trade she works in a town she stays in while her player is away
## (Main._stay_in_town; decision 284), or "".
var works_as := ""


## Her slots (Items): a pack and two hands, as a player's, empty at first;
## her player can get at them.
const SLOTS := Items.CARRIED


func _init() -> void:
	super()
	slots = Items.tidy([], SLOTS)
	replicate("slots")
	replicate("mending")
	# Her player's peer changes when they rejoin and she was waiting.
	replicate("keeper_peer")
	mass = 75.0
	senses = Senses.new(self, SIGHT_RANGE, -1.0)
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
	if _yield_tile == NONE and _alive(keeper) and keeper.tile + direction == tile \
			and World.swap_places(keeper, self, World.step_ticks(keeper, direction)):
		# Nowhere to step aside (a corridor, a dead end): she and her player
		# change places, as they walk.
		_yield_tile = tile
	elif _yield_tile == NONE:
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
	_heard.append({"text": text, "tick": World.tick, "speaker": speaker})
	_add_turn("user", text, false, speaker)
	var heard := "%s just said: \"%s\"" % [speaker, text]
	if _says_name(heard):
		_spoke_to_her[speaker] = World.tick
	# Someone else's player's words are first for their own companion: she
	# is asked only when they say her name. Otherwise they are in her
	# exchange, and that is all.
	if ask and _says_name(heard):
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


## What she carries, in a sentence: her lantern, what is in her hands and
## what is in her pack.
func carried() -> String:
	var items: Array[String] = []
	var held: Array[String] = []
	for i in slots.size():
		if not slots[i].is_empty():
			(held if i >= Items.PACK else items).append("a " + Items.name_of(slots[i]))
	var pack := "nothing" if items.is_empty() else ", ".join(items)
	var hands := "" if held.is_empty() else " In your hands: %s." % " and ".join(held)
	if emit_light > 0.0:
		return "You carry a lantern, and in your pack %s.%s" % [pack, hands]
	return "In your pack you carry %s.%s" % [pack, hands]


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
	_heard.append({"text": text, "tick": World.tick, "speaker": keeper_name()})
	_talked("%s: %s" % [keeper_name(), text])
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
		_called_off(_serial)
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
## (BIG_MONSTER_MASS), the first of its kind she has seen fall this run, or
## the last of a fight (_watch).
func note_death(who: String, her_player := false, entity: GridEntity = null) -> void:
	if her_player:
		_keeper_down = true
	var monster := entity is Monster
	var big := monster and entity.mass >= BIG_MONSTER_MASS
	var first := monster and not _kinds_fallen.has(kind_of(entity))
	if monster:
		_kinds_fallen[kind_of(entity)] = true
	var speak := not monster or big or first
	_fight_notable = _fight_notable or speak
	_deaths.append({"who": who, "told": refer(entity, true) if monster else who, "speak": speak, "monster": monster})
	_fallen.append({"word": kind_of(entity) if monster else who, "monster": monster})
	if _fallen.size() > 8:
		_fallen.pop_front()
	# What she saw (Main tells her only of deaths she witnessed).
	if not monster:
		note_fact("%s saw %s fall in %s." % [_name_of(self), who, _place_words()])
	elif big:
		note_fact("%s saw %s killed in %s." % [_name_of(self), refer(entity), _place_words()])


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
	_take_noises()
	_watch()
	_grow()
	if World.tick % MEMORY_EVERY == 0:
		_remember_sights()
	_calm()
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
			_fight_notable = true
			var mine := whose == "hp_band"
			var event := "%s %s" % ["Your HP" if mine else "%s's HP" % keeper_name(), _hp_change(_seen[whose], now[whose])]
			var body: GridEntity = self if mine else keeper
			var told := "%s %s now" % ["You are" if mine else "%s is" % keeper_name(), health_words(body)]
			if mine and now[whose] == HP_THRESHOLDS.size():
				note_fact("%s was nearly killed in %s." % [_name_of(self), _place_words()])
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
	var new_kind := ""
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and not _known_hostiles.has(entity.get_instance_id()) and senses.sees(entity):
			_known_hostiles[entity.get_instance_id()] = true
			if not _kinds_seen.has(kind_of(entity)):
				# The first of a kind this run: new to her, worth a word.
				_kinds_seen[kind_of(entity)] = true
				new_kind = "%s came into sight, the first %s you have seen here." % [_name_of(entity), kind_of(entity)]
				_fight_notable = true
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
	elif not new_kind.is_empty() and not lapsing and _lapsed_from.is_empty():
		_ask_voice(new_kind)
	if not new_kind.is_empty():
		var kind := new_kind.get_slice("the first ", 1).get_slice(" you have", 0)
		if not grown.facts.any(func(entry: Dictionary) -> bool: return ("first saw %s" % _a(kind)) in str(entry["text"])):
			note_fact("%s first saw %s in %s." % [_name_of(self), _a(kind), _place_words()])
	elif had_deaths and deaths.is_empty():
		_log({"kind": "voice", "companion": String(name), "trigger": " ".join(dead_names),
			"outcome": "not asked", "note": "nothing new: a monster's death, not big, not the first of its kind, not the last"})
	if _silence_due and not fight and World.tick - _fight_ended_tick >= SILENCE_TICKS:
		_silence_due = false
		if _last_speech_tick < _fight_ended_tick:
			_narrate("The fighting is over. It is quiet.")
			if _fight_notable:
				_ask_voice("The fight is over, and you have said nothing since.")
			else:
				_log({"kind": "voice", "companion": String(name), "trigger": "The fight is over.",
					"outcome": "not asked", "note": "nothing new in that fight: no one hurt, nothing big or new"})
		_fight_notable = false
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
			waiting.get("own", true), waiting.get("report", false))


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


## Takes what her senses heard since last tick: a noise she cannot see
## the maker of (NOISE_WORDS' kinds) is kept for her voice and narrated;
## a loud one, while calm, asks her voice (once in NOISE_ASK_TICKS).
func _take_noises() -> void:
	if senses.heard.is_empty() or int(senses.heard.back()["tick"]) <= _heard_upto:
		return
	var loud := ""
	for noise: Dictionary in senses.heard_since(_heard_upto):
		var at: Vector2i = noise["at"]
		if not NOISE_WORDS.has(noise["kind"]) or noise["source"] != null or senses.sees_cell(at):
			continue  # Not hers to tell, or she sees who made it, or where.
		var newest: Dictionary = _noises.back() if not _noises.is_empty() else {}
		if not newest.is_empty() and newest["kind"] == noise["kind"] and World.distance(newest["at"], at) <= 2:
			newest["tick"] = noise["tick"]  # The same fight, still going.
			continue
		_noises.append({"kind": noise["kind"], "at": at, "tick": noise["tick"]})
		if _noises.size() > NOISES_KEPT:
			_noises.pop_front()
		var told := "You hear %s %s, out of sight." % [NOISE_WORDS[noise["kind"]][0], _paces_toward(Vector2(at))]
		_narrate(told)
		if NOISE_WORDS[noise["kind"]][1]:
			loud = told
	_heard_upto = int(senses.heard.back()["tick"])
	if not loud.is_empty() and not in_fight() and World.tick - _noise_asked_tick >= NOISE_ASK_TICKS:
		_noise_asked_tick = World.tick
		_ask_voice(loud)


## What she heard lately and did not see, for her voice: "You heard, out
## of sight: fighting, some way off to the north." "" for nothing.
func heard_words() -> String:
	var told: Array[String] = []
	for noise in _noises:
		if World.tick - int(noise["tick"]) <= NOISE_TOLD_TICKS:
			told.append("%s, %s" % [NOISE_WORDS[noise["kind"]][0], _paces_toward(Vector2(noise["at"]))])
	return "" if told.is_empty() else "You heard, out of sight: %s." % "; ".join(told)


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
## [param report]: she tells how an errand went (what she tells is new).
func _ask_voice(trigger: String, heard := "", always := false, phrase := false, own := true, report := false) -> void:
	if mind == null:
		return
	if (heard.is_empty() or not own) and not always and World.tick - _last_speech_tick < SPEECH_INTERVAL_TICKS:
		return  # She could not say it: the rate limit.
	if not heard_by_anyone():
		_log({"kind": "voice", "companion": String(name), "trigger": trigger, "outcome": "not asked",
			"note": "no player within %d cells to hear her" % HEARING_RANGE})
		return
	if mind.busy("voice"):
		# Her player's words come first; otherwise the newest moment.
		if not heard.is_empty() or always or str(_pending_voice.get("heard", "")).is_empty():
			_pending_voice = {"trigger": trigger, "heard": heard, "always": always, "phrase": phrase, "own": own, "report": report}
		return
	_serial += 1
	_phrase_serials[_serial] = phrase
	if report:
		_report_serials[_serial] = true
	var asked := not heard.is_empty() and own
	# Certainly hers: then a stance with no words still counts.
	_certain_serials[_serial] = asked and addressed_to(heard) == "her"
	var messages := voice_messages(asked, heard)
	if not _offering.is_empty():
		_offered[_serial] = _offering
	var ask := {
		"kind": "voice", "serial": _serial, "trigger": trigger, "messages": messages, "speaker": _name_of(self),
		"system": messages[0]["content"], "user": render(messages.slice(1)),
		"hp": hp, "max_hp": max_hp, "spoken_to": asked, "asked": asked, "heard": heard, "always": always,
	}
	var answer := mind.voice(ask)
	if not answer.is_empty():
		_take_result(_sync_result(ask, answer))


## Asks her voice's model, once, to write her card from her traits
## (CompanionCard.CARD_SYSTEM); until it answers, her plain card stands.
## Not asked when it was written already, or she has no traits or mind.
func write_card() -> void:
	if mind == null or traits.is_empty() or card_by == "model" or mind.busy("card"):
		return
	_serial += 1
	var who := keeper_name()
	var ask := {"kind": "card", "serial": _serial, "trigger": "her card, from her traits",
		"system": CompanionCard.CARD_SYSTEM % who, "user": CompanionCard.facts(traits, who)}
	var answer := mind.card(ask)
	if not answer.is_empty():
		_take_result(_sync_result(ask, answer))


## The written card: taken if it is a paragraph with no speech in it, else
## her card stands.
func _take_card(answer: Dictionary, entry: Dictionary) -> void:
	var written := str(answer.get("card", "")).strip_edges()
	var met := str(answer.get("how_we_met", "")).strip_edges()
	if written.length() < 80 or written.contains("\"") or written.contains("“"):
		entry["outcome"] = "rejected"
		entry["note"] = "not a card (too short, or speech in it); her %s card stands" % card_by
	else:
		card = written
		if not met.is_empty():
			how_we_met = met
		card_by = "model"
		entry["outcome"] = "applied"
		card_written.emit()
	_log(entry)


# --- What becomes true of her (decision 294) ---------------------------------------

## [param text], what she witnessed, as a fact about her; told to her
## transcript and the mind log when new.
func note_fact(text: String, from := "event") -> void:
	var added := grown.add_fact(text, from, keeper_id)
	if added.is_empty():
		return
	Transcript.record(String(name), "", "[Now true of her: %s]" % added["text"])
	_log({"kind": "fact", "companion": String(name), "trigger": from, "outcome": "added", "note": added["text"], "id": added["id"]})
	facts_changed.emit()


## A line of the talk with her player, to be read for what becomes true of her.
func _talked(line: String) -> void:
	talk.append(line)
	if talk.size() > TALK_KEPT:
		talk.pop_front()
	_talk_tick = World.tick
	facts_changed.emit()


## Each tick: a stretch of talk gone quiet is read for what became true
## of her (one ask); over the cap, the oldest of what she witnessed is
## merged into a history (one ask), or with no model to write it, trimmed.
func _grow() -> void:
	if mind == null:
		return
	var theirs := talk.filter(func(line: String) -> bool: return line.begins_with(keeper_name() + ": ")).size()
	var quiet := World.tick - _talk_tick >= CompanionFacts.setting("quiet_seconds", 60) * World.TICK_RATE
	if theirs >= CompanionFacts.setting("talk_lines", 3) and quiet and not mind.busy("facts"):
		var who := keeper_name()
		var me := _name_of(self)
		var ask := {"kind": "facts", "serial": _serial, "trigger": "talk",
			"system": CompanionFacts.EXTRACT_SYSTEM % [me, who, me, who, who], "user": grown.extract_prompt(card, talk)}
		talk.clear()
		facts_changed.emit()
		var answer := mind.facts(ask)
		if not answer.is_empty():
			_take_result(_sync_result(ask, answer))
		return
	var merging := grown.to_merge()
	if merging.is_empty() or mind.busy("facts") or not _merging.is_empty():
		return
	_merging = merging
	var listed: Array[String] = []
	for entry in merging:
		listed.append("- " + str(entry["text"]))
	var ask := {"kind": "facts", "serial": _serial, "trigger": "merge",
		"system": CompanionFacts.MERGE_SYSTEM % _name_of(self), "user": "\n".join(listed)}
	var answer := mind.facts(ask)
	if not answer.is_empty():
		_take_result(_sync_result(ask, answer))
	elif not mind.busy("facts"):
		# No model to write a history: the oldest go.
		_merging = []
		grown.trim()
		facts_changed.emit()


## An extraction or a merge came back (or did not).
func _take_facts(trigger: String, answer: Dictionary, entry: Dictionary) -> void:
	var said: Variant = answer.get("facts", [])
	var held: Variant = answer.get("beliefs", [])
	var added: Array[String] = []
	if trigger == "merge":
		var history := str(said[0]) if said is Array and not said.is_empty() else ""
		if history.is_empty() or not grown.merge(_merging, history, keeper_id):
			grown.trim()
			entry["outcome"] = "trimmed"
		else:
			entry["outcome"] = "merged"
			added.append(history)
		_merging = []
	else:
		for text: Variant in (said if said is Array else []).slice(0, CompanionFacts.PER_CALL):
			var fact := grown.add_fact(str(text), "talk", keeper_id)
			if not fact.is_empty():
				added.append(fact["text"])
				Transcript.record(String(name), "", "[Now true of her: %s]" % fact["text"])
		for text: Variant in (held if held is Array else []).slice(0, CompanionFacts.PER_CALL):
			var belief := grown.add_belief(str(text), keeper_id)
			if not belief.is_empty():
				added.append("(belief) " + belief["text"])
		entry["outcome"] = "added" if not added.is_empty() else ("nothing new" if not answer.is_empty() else "no answer")
	entry["note"] = " | ".join(added)
	_log(entry)
	facts_changed.emit()


## Where she is, for a fact: the level's name ("the castle").
static var _place_names: Dictionary[String, String] = {}


func _place_words() -> String:
	var zone_name := World.zone.name if World.zone != null else ""
	if not _place_names.has(zone_name):
		var shown := str(Level.load_level(zone_name).get("display_name", "")) if Level.exists(zone_name) else ""
		_place_names[zone_name] = shown if not shown.is_empty() else zone_name.replace("_", " ")
	return _place_names[zone_name]


static func _a(word: String) -> String:
	return ("an " if not word.is_empty() and word[0] in "aeiou" else "a ") + word


## Whether she was told to stay where she is: HOLD, standing as her
## player's instruction (Main.travel leaves her behind then).
func stays_put() -> bool:
	return stance == Stance.HOLD and not standing_instruction().is_empty()


## Whether a player is near enough to hear her (HEARING_RANGE, in her
## zone), or her player fallen and waiting to rise (still there, and
## listening): with nobody to hear, her voice is not asked (the world runs
## on without players, and so may she).
func heard_by_anyone() -> bool:
	if _keeper_down:
		return true
	for entity in World.get_entities():
		if entity is Player and entity.spawned and World.distance(tile, entity.tile) <= HEARING_RANGE:
			return true
	return false


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
	_offering = []
	var who := keeper_name()
	var instructed := CARD_INSTRUCTED % [who, who] if not standing_instruction().is_empty() else ""
	var now: Array[String] = [voice_situation(), others_here()]
	if asks_about_items(heard):
		now.append(carried())
	now.append(doing())
	if not works_as.is_empty():
		now.append("While %s is away you stay in this town and work as its %s." % [who, works_as])
	var heard_now := heard_words()
	if not heard_now.is_empty():
		now.append(heard_now)
	var topics := mentioned_topics()
	if not topics.is_empty():
		now.append("You have already mentioned: %s." % ", ".join(topics))
	if not standing_instruction().is_empty():
		now.append("What %s asked of you still stands: %s" % [who, standing_instruction()])
	now.append(run_summary(false))
	var things := perceived()
	var around := perception(things) if surroundings_keys(things) != _around_said or asks_about_surroundings(heard) else ""
	var met := " How you and %s met: %s" % [who, how_we_met] if not how_we_met.is_empty() else ""
	var since := grown.prompt_words()
	if not since.is_empty():
		met += " " + since
	var system := "%s %s%s%s\n\n%s\n\nNow: %s\n\n%s%s" % [identity(), card, met, instructed, VOICE_WORLD, " ".join(now),
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
			_offering = can_do()
			if not _offering.is_empty():
				var listed: Array[String] = []
				for i in _offering.size():
					listed.append("%d: %s" % [i + 1, _offering[i]["words"]])
				system += "\n" + VOICE_CAN_DO % ["\n".join(listed), who]
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
		if messages.back()["role"] == role and role == "assistant":
			# Two of her lines are two replies, never one: a moment between.
			messages.append({"role": "user", "content": "[A moment passes.]"})
			messages.append({"role": role, "content": text})
		elif messages.back()["role"] == role:
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
		Intent.ERRAND:
			action = "on your way to %s" % errand.get("words", "do what you were asked")
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
	if World.outdoor:
		sentences.append("You are outdoors, under the sky, with forest all around the edge of this place.")
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
	var wounds := _wound_words()
	if not wounds.is_empty():
		sentences.append(wounds)
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


## Wounds, for her voice (decision 320), when she or her player is hurt:
## a bandaging under way or mending, and for the rest whether she carries
## a kit (or her player does) and whether it is safe to bandage now
## (World.calm). "" when neither is hurt.
func _wound_words() -> String:
	var who := keeper_name()
	var told: Array[String] = []
	var open_wounds: Array[GridEntity] = []
	for each: GridEntity in [self, keeper]:
		if not _alive(each) or each.hp >= each.max_hp:
			continue
		var whose := "Your" if each == self else "%s's" % who
		if each.mending == 1:
			told.append("%s wounds are being bandaged." % whose)
		elif each.mending == 2:
			told.append("%s wounds are bandaged and mending." % whose)
		else:
			open_wounds.append(each)
	if not open_wounds.is_empty():
		var safe := World.calm(self) and open_wounds.all(func(each: GridEntity) -> bool: return World.calm(each))
		if World.bandage_kit(self) >= 0:
			told.append("You carry a bandaging kit; it is %s." % ("safe to bandage now" if safe
				else "not safe to bandage now: danger is near, or a blow came too recently"))
		elif _alive(keeper) and World.bandage_kit(keeper) >= 0:
			told.append("You have no bandaging kit; %s carries one." % who)
		else:
			told.append("Neither of you carries a bandaging kit.")
	return " ".join(told)


## What she can see around her, for the voice and the stance (the "around
## you" block), as Net.perception has it: "list" (perception_list), "grid"
## (perception_grid) or "both", the grid first; then what the heat and the
## light tell her (field_sentences). "" when there is nothing to tell.
## [param things]: perceived's result, when the caller has it already (it
## looks at every cell in range: worked out once an ask, not once a use).
func perception(things: Variant = null) -> String:
	var seen: Array[Dictionary] = perceived() if things == null else things
	var told := ""
	match Net.perception:
		"grid":
			told = perception_grid()
		"both":
			var listed := perception_list(seen)
			told = perception_grid() + ("\n" + listed if not listed.is_empty() else "")
		_:
			told = perception_list(seen)
	var felt := " ".join(field_sentences(seen))
	if felt.is_empty():
		return told
	return felt if told.is_empty() else told + "\n" + felt


## What she can see (perceived), a line each, nearest first: "- an imp, 2
## paces ahead to your left: between you and Jeff". "" for nothing.
func perception_list(things: Variant = null) -> String:
	var lines: Array[String] = []
	for thing: Dictionary in (perceived() if things == null else things):
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
func surroundings_keys(seen: Variant = null) -> Array[String]:
	var keys: Array[String] = []
	var things: Array[Dictionary] = perceived() if seen == null else seen
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
			found.append(_thing("open door" if door.is_open() else "locked door" if door.state() == "locked" else "closed door", near,
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


## asked_about's patterns, by kind, compiled once.
static var _asked_words: Dictionary[String, RegEx] = {}


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
	if _asked_words.is_empty():
		for kind: String in WORDS:
			_asked_words[kind] = RegEx.create_from_string("\\b(%s)" % WORDS[kind])
	var kinds: Array[String] = []
	for kind: String in WORDS:
		if _asked_words[kind].search(said) != null:
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
	return senses.sees_cell(cell, DARK)


## Whether she sees [param entity] now (Main: a death she witnessed).
func witnessed(entity: GridEntity) -> bool:
	return senses.sees(entity)


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
	key.append_array(["f fire", "~ water", "# wall" if not World.outdoor else "# wall or forest", "D closed door", "d open door", "c crate or cart", "o boulder", "= chest",
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
		_called_off(serial)
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
	if kind == "facts":
		_take_facts(str(result.get("trigger", "")), answer, entry)
		return
	if answer.is_empty():
		entry["outcome"] = "no answer"
		entry["note"] = "%s; %s stands" % [result.get("error", ""), stance_name()]
		_log(entry)
		return
	if kind == "card":
		_take_card(answer, entry)
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
	var report: bool = _report_serials.get(serial, false)
	_report_serials.erase(serial)
	spoken_to = spoken_to or report
	# What she was offered to do: [DO: n] to her player's words picks one,
	# and a promise picks the one it names; a promise of what she cannot do
	# now is not said.
	var offered: Array = _offered.get(serial, []) if asked else []
	_offered.erase(serial)
	var chosen := -1
	var do_text := str(answer.get("do", "")).strip_edges()
	if not offered.is_empty() and do_text.is_valid_int() and int(do_text) >= 1 and int(do_text) <= offered.size():
		chosen = int(do_text) - 1
	elif not do_text.is_empty():
		entry["do_ignored"] = do_text
	var promised := _promises(trim_line(str(answer.get("say", ""))), offered, chosen)
	if chosen == -1:
		chosen = promised["chosen"]
	if not str(promised["dropped"]).is_empty():
		entry["promise_dropped"] = promised["dropped"]
	var raw_line := trim_line(str(promised["line"]))
	# A whole line said back is dropped as such; then what is left of it
	# once cleaned (spoken) is what she says.
	var echo := _echo_of(raw_line)
	# Her things may be spoken of when asked about, told of in a report, or
	# given or fetched.
	var items_told: bool = asks_about_items(str(result.get("heard", ""))) or report or chosen >= 0 and offered[chosen].has("item")
	var line := "" if not echo.is_empty() else trim_line(spoken(raw_line, items_told, spoken_to))
	if echo.is_empty() and line != raw_line:
		entry["say_raw"] = raw_line
	if raw_line.is_empty():
		entry["outcome"] = "silent"
	elif not echo.is_empty():
		entry["outcome"] = "dropped"
		entry["say_dropped"] = raw_line
		entry["note"] = "echoes %s" % echo
	elif line.is_empty():
		entry["outcome"] = "dropped"
		entry["say_dropped"] = raw_line
		entry["note"] = "nothing left once cleaned: said lately, narration, her own things, or not hers to say"
	elif not spoken_to and _plain(line).split(" ", false).size() < FRAGMENT_WORDS and not line.ends_with("!"):
		entry["outcome"] = "dropped"
		entry["say_dropped"] = line
		entry["note"] = "a fragment, unasked"
		line = ""
	elif not _say(line, always):
		entry["outcome"] = "dropped"
		entry["say_dropped"] = line
		entry["note"] = "within %d ticks of her last line" % SPEECH_INTERVAL_TICKS
		line = ""
	entry["say"] = line
	if chosen >= 0:
		entry["do"] = offered[chosen]["words"]
	_log(entry)
	if chosen >= 0:
		_start_errand(offered[chosen], serial)


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
	if not talk.is_empty():
		_talked("%s: %s" % [_name_of(self), line])
	said.emit(line)
	return true


## Whether [param heard] (her player's words to her) asks about what she
## carries.
static func asks_about_items(heard: String) -> bool:
	return not heard.is_empty() and RegEx.create_from_string("(?i)" + ITEM_WORDS).search(_quoted(heard)) != null


## [param line] as she will say it: one reply (its first paragraph, on one
## line); no narration of what she does; no sentence she said in her last
## REPEAT_LINES lines, nor twice in this one, and, unless [param asked]
## (her player's words to her), none that near_repeats one of those, what
## another companion said in the last OTHERS_SAID_TICKS, or the narration
## in her exchange, and no report of a monster falling (EVENT_REPORT); her
## player never spoken of by name, only to; her own things (lantern,
## bandages, her pack) only when [param items_asked]; her player spoken to
## as "you" (their name off the front or the end of a sentence, and a bare
## name gone), unless they are further than CALL_OUT_PACES; anyone else
## spoken to only when they named her lately or, once in
## ADDRESS_OTHER_TICKS, when they are in danger: otherwise those sentences
## go; and no one-word fragment (ONE_WORD_ANSWERS aside). "" if nothing is
## left.
func spoken(line: String, items_asked := false, asked := false) -> String:
	var text := line.strip_edges().get_slice("\n\n", 0).replace("\n", " ")
	text = RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)").sub(text, " ", true)
	var keeper_word := keeper_name()
	var others: Array[String] = []
	for entity in World.get_entities():
		if entity != self and entity != keeper and entity.spawned and (entity is Player or entity is Companion):
			others.append(_name_of(entity))
	var repeated: Dictionary[String, bool] = {}
	for said_line in _said.slice(-REPEAT_LINES):
		for sentence in _sentences(said_line):
			repeated[_plain(sentence)] = true
	# Unasked, a sentence like any of these is not said either.
	var alike: Array[String] = []
	if not asked:
		alike.assign(repeated.keys())
		for heard: Dictionary in _heard:
			if str(heard.get("speaker", keeper_word)) != keeper_word and World.tick - int(heard["tick"]) <= OTHERS_SAID_TICKS:
				for sentence in _sentences(str(heard["text"])):
					alike.append(_plain(sentence))
		for turn: Dictionary in _exchange:
			if turn["role"] == "user" and str(turn.get("speaker", "")).is_empty():
				for sentence in _sentences(str(turn["text"]).trim_prefix("[").trim_suffix("]")):
					alike.append(_plain(sentence))
	var report := event_report(_kinds_seen.keys() + _kinds_fallen.keys())
	var keeper_named := RegEx.create_from_string("(?i)\\b%s\\b" % _escaped(keeper_word))
	var narration := RegEx.create_from_string(NARRATION % RegEx.create_from_string("\\W").sub(_name_of(self), "", true))
	var items := RegEx.create_from_string("(?i)" + OWN_ITEMS)
	var kept: Array[String] = []
	var to := ""
	for raw in _sentences(text):
		var sentence := raw.strip_edges()
		var plain := _plain(sentence)
		# A bare name calls whoever is named for what follows.
		var bare := ""
		for who in [keeper_word] + others:
			if plain == _plain(who):
				bare = who
		if not bare.is_empty():
			to = bare
			continue
		var called := to
		to = ""
		for who in [keeper_word] + others:
			var front := RegEx.create_from_string("(?i)^%s\\s*[,:!]\\s*" % _escaped(who))
			var back := RegEx.create_from_string("(?i),\\s*%s\\s*([.!?]*)$" % _escaped(who))
			var middle := RegEx.create_from_string("(?i),\\s*%s\\s*,\\s*" % _escaped(who))
			if front.search(sentence) != null:
				called = who
				sentence = front.sub(sentence, "")
			elif back.search(sentence) != null:
				called = who
				sentence = back.sub(sentence, "$1")
			elif middle.search(sentence) != null:
				called = who
				sentence = middle.sub(sentence, ", ")
		sentence = sentence.strip_edges()
		if sentence.is_empty() or narration.search(sentence) != null:
			continue
		if not items_asked and items.search(sentence) != null:
			continue
		plain = _plain(sentence)
		if plain.is_empty() or repeated.has(plain):
			continue
		if not asked and (report.search(sentence) != null or near_repeat(plain, alike)):
			continue
		if (called.is_empty() or called == keeper_word) and not keeper_word.is_empty() and keeper_named.search(sentence) != null:
			continue  # Her player, spoken of: she speaks to them, as you.
		if not " " in plain and plain not in ONE_WORD_ANSWERS and not sentence.ends_with("?"):
			continue  # A one-word fragment; a one-word question is an answer.
		repeated[plain] = true
		alike.append(plain)
		if called == keeper_word and _alive(keeper) and World.distance(tile, keeper.tile) > CALL_OUT_PACES:
			sentence = "%s, %s" % [keeper_word, _after_name(sentence, [keeper_word] + others)]
		elif not called.is_empty() and called != keeper_word:
			# An answer to someone who spoke to her is free; anything else to
			# them is a warning, at most once in ADDRESS_OTHER_TICKS.
			if World.tick - int(_spoke_to_her.get(called, -100000)) > SPOKE_TO_HER_TICKS:
				if not _may_warn(called):
					continue
				_addressed[called] = World.tick
			sentence = "%s, %s" % [called, _after_name(sentence, [keeper_word] + others)]
		kept.append(sentence.left(1).to_upper() + sentence.substr(1))
	return " ".join(kept)


## Whether she may speak to [param who] (not her player) unasked: they
## are in danger or badly hurt, and she has not done so within
## ADDRESS_OTHER_TICKS.
func _may_warn(who: String) -> bool:
	if World.tick - int(_addressed.get(who, -100000)) < ADDRESS_OTHER_TICKS:
		return false
	for entity in World.get_entities():
		if entity.spawned and _name_of(entity) == who and (_in_danger(entity) or _badly_hurt(entity)):
			return true
	return false


## [param sentence] put after a name and a comma: its first letter lower
## case, unless its first word is "I" (I'm, I'll) or one of [param names].
func _after_name(sentence: String, names: Array) -> String:
	var found := RegEx.create_from_string("^[A-Za-z]+").search(sentence)
	var first := found.get_string() if found != null else ""
	if first == "I":
		return sentence
	for who: String in names + [_name_of(self)]:
		if not first.is_empty() and first.to_lower() == _plain(who).get_slice(" ", 0):
			return sentence
	return sentence.left(1).to_lower() + sentence.substr(1)


## [param text]'s sentences, each with its stop.
static func _sentences(text: String) -> Array[String]:
	var out: Array[String] = []
	for found in RegEx.create_from_string("[^.!?…]+[.!?…]*").search_all(text):
		var sentence := found.get_string().strip_edges()
		if not sentence.is_empty():
			out.append(sentence)
	return out


static func _escaped(words: String) -> String:
	return RegEx.create_from_string("([\\\\.^$|?*+()\\[\\]{}])").sub(words, "\\$1", true)


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


## Lower case, letters, digits and single spaces; apostrophes, straight
## or curly, gone ("I’ll" and "I'll" are both "ill").
static func _plain(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		if c in "'’‘ʼ`":
			continue
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else " "
	return " ".join(out.split(" ", false))


## Whether [param plain] (a _plain sentence) is near one of [param others]:
## its words, COMMON_WORDS aside, all in one of them (two or more of
## them: one word alone is too little to tell), or sharing NEAR_SHARE of
## the words of both. A sentence of common words alone is near only one
## the same.
static func near_repeat(plain: String, others: Array[String]) -> bool:
	var words := _word_set(plain)
	for other in others:
		if other == plain:
			return true
		var theirs := _word_set(other)
		if words.is_empty() or theirs.is_empty():
			continue
		var shared := 0
		for word: String in words:
			if theirs.has(word):
				shared += 1
		if shared == words.size() and shared >= 2 or float(shared) / (words.size() + theirs.size() - shared) >= NEAR_SHARE:
			return true
	return false


## [param plain]'s words, COMMON_WORDS aside, each without a plural or
## -ing/-ed ending ("doors" "door", "moving" "move" are one).
static func _word_set(plain: String) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for word in plain.split(" ", false):
		if word in COMMON_WORDS:
			continue
		for ending: String in ["ing", "ed", "es", "s", "e"]:
			if word.length() > ending.length() + 2 and word.ends_with(ending):
				word = word.left(word.length() - ending.length())
				break
		out[word] = true
	return out


## A sentence that reports a monster falling or dead ("The imp to the
## north-east is dead.", "Brute is down."): the event log said back, not
## said. [param kinds]: the kinds of monster she knows, with the common
## words for one.
static func event_report(kinds: Array) -> RegEx:
	var names: Array[String] = ["monster", "one", "thing", "beast", "enemy", "foe", "it", "they", "them"]
	for kind: Variant in kinds:
		names.append(_escaped(str(kind).to_lower()))
	var kind := "(%s)(s|es)?" % "|".join(names)
	return RegEx.create_from_string(("(?i)^[^,;]*?\\b%s\\b[^,;]*?\\b((is|are|was|were|lies|lie)\\s+(now\\s+)?"
		+ "(dead|down|fallen|not moving)|fell|died|dropped)\\s*([.!;,]|$)") % kind)


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
	# Bandaging herself, low, with nothing at her: she keeps at it.
	var mending_self: bool = str(errand.get("verb", "")) == "bandage" and errand.get("patient") == self and foe == null
	if low and not mending_self:
		if not errand.is_empty():
			_end_errand("you are badly hurt", false)
		current_intent = Intent.RETREAT
	elif _on_errand():
		current_intent = Intent.ERRAND
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


# --- Acting -------------------------------------------------------------------

func _execute() -> void:
	if current_intent != Intent.RETREAT:
		_retreat_goal = NONE
		_retreat_at = NONE
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
		Intent.ERRAND:
			_errand_step()
		Intent.IDLE, Intent.SHOVE:
			pass


## RETREAT: to the nearest cell with no hostile next to it, near her player
## when such a cell is (safe_cell); with none, she fights the hostile next
## to her rather than stand still. She keeps to the cell she chose while it
## is still safe and no other is better by more than RETREAT_KEEP_MARGIN:
## with the hostiles closing in the best cell changes tick to tick, and,
## taking each, she would run back and forth between two.
func _retreat() -> void:
	if tile != _retreat_at:
		_retreat_heading = tile - _retreat_at if _retreat_at != NONE and World.are_adjacent(tile, _retreat_at) else Vector2i.ZERO
		_retreat_at = tile
	var scores := _safe_cells(_retreat_heading)
	var best := NONE
	for cell: Vector2i in scores:
		if best == NONE or scores[cell] < scores[best]:
			best = cell
	var margin := RETREAT_KEEP_MARGIN if _hostile_within(RETREAT_REACH + 1) else 0.0
	if not scores.has(_retreat_goal) or best != NONE and scores[_retreat_goal] > scores[best] + margin:
		_retreat_goal = best
	var cell := _retreat_goal
	if cell == NONE:
		var foe := _adjacent_hostile()
		if foe != null and World.can_melee(tile, foe.tile):
			World.try_attack(self, foe)
		return
	if cell != tile and not _step_toward(cell, false):
		_retreat_goal = NONE


## The cell RETREAT makes for: of the free, fire-free cells within
## RETREAT_REACH steps that no hostile is next to (her own among them), the
## one with the least of steps / 2 plus the distance to her player, less
## RETREAT_CLEAR_WEIGHT for each tile (up to RETREAT_CLEAR) to the nearest
## hostile. NONE if there is none.
func safe_cell() -> Vector2i:
	var scores := _safe_cells()
	var best := NONE
	for cell: Vector2i in scores:
		if best == NONE or scores[cell] < scores[best]:
			best = cell
	return best


## Each cell safe_cell might take, with its score (lower is better); with
## [param heading], the way she last stepped, a way back costs more.
func _safe_cells(heading := Vector2i.ZERO) -> Dictionary[Vector2i, float]:
	var scores: Dictionary[Vector2i, float] = {}
	var hostiles: Array[Vector2i] = []
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(tile, entity.tile) <= RETREAT_REACH + 1:
			hostiles.append(entity.tile)
	var steps: Dictionary[Vector2i, int] = {tile: 0}
	var first: Dictionary[Vector2i, Vector2i] = {tile: Vector2i.ZERO}
	var frontier: Array[Vector2i] = [tile]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		var clear := RETREAT_CLEAR
		for at in hostiles:
			clear = mini(clear, World.distance(cell, at))
		if clear > 1:
			scores[cell] = steps[cell] * 0.5 + (World.distance(cell, keeper.tile) if _alive(keeper) else 0) \
					- clear * RETREAT_CLEAR_WEIGHT
			if Vector2(first[cell]).dot(Vector2(heading)) < 0.0:
				scores[cell] += RETREAT_TURN_BACK
		if steps[cell] >= RETREAT_REACH:
			continue
		for direction in World.DIRECTIONS:
			var next: Vector2i = cell + direction
			if steps.has(next) or not World.is_free(next) or World.is_burning(next) \
					or World._terrain_blocks_step(cell, direction, true):
				continue
			steps[next] = steps[cell] + 1
			first[next] = direction if cell == tile else first[cell]
			frontier.append(next)
	return scores


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


# --- Errands: what she does when asked ------------------------------------------

## What she can do here and now, nearest first, at most ACTIONS_MAX: each
## {verb ("open", "close", "open_chest", "fetch", "give", "bandage", "look"), words
## (for her voice: "open the closed door, a few paces to the south"), at,
## and its door, chest, item or cell}. Only what she sees: a door not
## broken, a chest, and, with her player in sight (the only one she may
## hand things to: World.reaches), each thing in a chest to bring them and
## each thing she carries to give them; with a bandaging kit, out of
## combat, to bandage herself or her player in sight, if hurt and not
## being bandaged or mending (World.try_bandage, decision 320); and the
## nearest walkable cells she
## cannot see within her sight's range, one a compass point, LOOKS_OFFERED
## of them.
func can_do() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for door: Door in World.get_doors():
		if door.is_broken():
			continue
		var sides := Terrain.edge_cells(door.key)
		var near: Vector2i = sides[0] if _nearer(sides[0], sides[1]) else sides[1]
		if World.distance(tile, near) <= PERCEPTION_RANGE and (_sees(sides[0]) or _sees(sides[1])):
			var verb := "close" if door.is_open() else "open"
			if verb == "open" and not World.may_open(self, door):
				continue  # Locked, and she has no key.
			actions.append({"verb": verb, "door": door, "at": near, "words": "%s the %s door, %s" % [
				verb, "open" if door.is_open() else "closed", _paces_toward(Vector2(sides[0] + sides[1]) / 2.0)]})
	# Things go to her own player only (World.reaches), whom she must see.
	var to_them := _alive(keeper) and World.distance(tile, keeper.tile) <= PERCEPTION_RANGE and senses.sees(keeper)
	for entity in World.get_entities():
		if entity is Chest and entity.spawned and World.distance(tile, entity.tile) <= PERCEPTION_RANGE and _sees(entity.tile):
			var where := _paces_toward(Vector2(entity.tile))
			actions.append({"verb": "open_chest", "chest": entity, "at": entity.tile,
				"words": "open the chest %s and see what is in it" % where})
			var fetched: Dictionary[String, bool] = {}
			for id: String in entity.slots:
				if to_them and not id.is_empty() and not fetched.has(id):
					fetched[id] = true
					actions.append({"verb": "fetch", "item": id, "chest": entity, "at": entity.tile,
						"words": "bring %s the %s from the chest %s" % [keeper_name(), Items.name_of(id), where]})
	if to_them:
		var given: Dictionary[String, bool] = {}
		for id: String in slots:
			if not id.is_empty() and not given.has(id):
				given[id] = true
				actions.append({"verb": "give", "item": id, "at": keeper.tile,
					"words": "give %s your %s" % [keeper_name(), Items.name_of(id)]})
	if World.bandage_kit(self) >= 0 and World.calm(self):
		for patient: GridEntity in [self, keeper if to_them else null]:
			if patient != null and patient.hp < patient.max_hp and patient.mending == 0 and World.calm(patient):
				actions.append({"verb": "bandage", "patient": patient, "at": patient.tile,
					"words": "bandage your own wounds" if patient == self else "bandage %s's wounds" % keeper_name()})
	actions.sort_custom(_nearer_found)
	actions.resize(mini(actions.size(), ACTIONS_MAX - LOOKS_OFFERED))
	var ways: Dictionary[int, bool] = {}
	for cell in _cells_within(SIGHT_RANGE):
		if ways.size() >= LOOKS_OFFERED:
			break
		if cell == tile or not World.is_walkable(cell) or _sees(cell):
			continue
		var way := World.bearing_index(Vector2(cell - tile))
		if ways.has(way):
			continue
		ways[way] = true
		var why := "too dark to see" if World.has_line_of_sight(tile, cell) else "out of your sight"
		actions.append({"verb": "look", "cell": cell, "at": cell,
			"words": "go and look %s, where it is %s, and come back" % [_paces_toward(Vector2(cell)), why]})
	return actions


## The errands (can_do's verbs) a sentence, lower case, speaks of doing.
static func _errand_verbs(text: String) -> Array[String]:
	var has := func(pattern: String) -> bool: return RegEx.create_from_string(pattern).search(text) != null
	var chest: bool = has.call("\\b(chests?|trunk)\\b")
	var door: bool = has.call("\\bdoors?\\b")
	var verbs: Array[String] = []
	if chest and has.call("\\b(open|check|search|look|see|peek)"):
		verbs.append("open_chest")
	if door and has.call("\\bopen"):
		verbs.append("open")
	if door and has.call("\\b(close|shut)"):
		verbs.append("close")
	if not chest and not door and has.call("\\b(look|check|scout|see|peek)") \
			and has.call(COMPASS_WORD + "|\\b(dark|there|ahead|around|corner)\\b"):
		verbs.append("look")
	# Handing over and fetching: only of a thing named (or the chest), so
	# "I'll get them" or "I'll take the imps" is no errand.
	var thing := _item_words("").search(text) != null
	var handing: bool = has.call("\\b(give|hand|pass)")
	if thing and not chest and handing:
		verbs.append("give")
	if not handing and has.call("\\b(bandag|patch\\w* (you|me|myself|yourself|us) up|dress\\w* (your|my|the|those|these) wound|see to (your|my) wound)"):
		verbs.append("bandage")
	if (thing or chest) and not door and has.call("\\b(bring|fetch|get|grab|take)"):
		verbs.append("fetch")
	return verbs


## _item_words' patterns, by item id ("" for any), compiled once.
static var _item_patterns: Dictionary[String, RegEx] = {}


## The words that name item [param id] in a sentence (the starts of the
## words of its name and short name: "bandag", "kit"), or of any item for
## "".
static func _item_words(id: String) -> RegEx:
	if not _item_patterns.has(id):
		var stems: Array[String] = []
		for each: String in ([id] if not id.is_empty() else Items.ids()):
			for word in (Items.name_of(each) + " " + Items.short_of(each)).to_lower().split(" ", false):
				if word.length() >= 3 and word not in ["of", "the", "and"] and word.left(6) not in stems:
					stems.append(word.left(6))
		_item_patterns[id] = RegEx.create_from_string("\\b(%s)" % "|".join(stems) if not stems.is_empty() else "^\\b$")
	return _item_patterns[id]


## [param line] without the sentences that promise one of her errands but
## do not name exactly one thing of [param offered] (or, with [param chosen]
## from [DO: n], that one); {line, chosen: what a promise named, or -1,
## dropped: the sentences left out}.
func _promises(line: String, offered: Array, chosen: int) -> Dictionary:
	var promise := RegEx.create_from_string(PROMISE)
	var compass := RegEx.create_from_string(COMPASS_WORD)
	var kept: Array[String] = []
	var dropped: Array[String] = []
	var named := -1
	for sentence in _sentences(line):
		var text := sentence.to_lower().replace("’", "'")
		var verbs := _errand_verbs(text) if promise.search(text) != null else ([] as Array[String])
		if verbs.is_empty():
			kept.append(sentence)  # No promise, or roleplay: nothing she could do.
			continue
		var way := compass.search(text)
		var matching: Array[int] = []
		for i in offered.size():
			var said_way := compass.search(str(offered[i]["words"]))
			if offered[i]["verb"] in verbs and (way == null or said_way != null and said_way.get_string() == way.get_string()):
				matching.append(i)
		# A thing named narrows it to that thing.
		var named_thing := matching.filter(func(i: int) -> bool:
			return offered[i].has("item") and _item_words(offered[i]["item"]).search(text) != null)
		if not named_thing.is_empty():
			matching.assign(named_thing)
		# Bandaging: herself when she speaks of herself, else her player.
		var bandaging := matching.filter(func(i: int) -> bool: return offered[i]["verb"] == "bandage")
		if bandaging.size() > 1:
			var own := RegEx.create_from_string("\\b(myself|my own|my wounds?|me up)\\b").search(text) != null
			matching.assign(bandaging.filter(func(i: int) -> bool: return (offered[i]["patient"] == self) == own))
		if chosen >= 0 and chosen in matching or chosen == -1 and matching.size() == 1:
			kept.append(sentence)
			if chosen == -1 and named == -1:
				named = matching[0]
		else:
			dropped.append(sentence)
	return {"line": " ".join(kept), "chosen": named, "dropped": " ".join(dropped)}


func _start_errand(action: Dictionary, serial: int) -> void:
	errand = action.duplicate()
	errand["phase"] = "going"
	errand["serial"] = serial
	errand["until"] = World.tick + ERRAND_TICKS
	_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": errand["words"], "outcome": "set off"})


## Her player asked something else of her (ask [param serial]): an errand
## from an older ask is called off.
func _called_off(serial: int) -> void:
	if not errand.is_empty() and serial > int(errand["serial"]):
		_end_errand("%s asked something else of you" % keeper_name(), false)


## Whether she goes on with her errand: none, a monster she sees within
## ERRAND_BREAK, or out of time, and it ends.
func _on_errand() -> bool:
	if errand.is_empty():
		return false
	if World.tick > int(errand["until"]):
		_end_errand("it was taking too long", false)
		return false
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(tile, entity.tile) <= ERRAND_BREAK and senses.sees(entity):
			_end_errand("a monster came near", false)
			return false
	return true


## A step of her errand: going there, doing it, and from a look coming back.
func _errand_step() -> void:
	match str(errand["phase"]):
		"going":
			if _errand_there():
				errand["phase"] = "doing"
				_errand_do()
			elif not _errand_walk():
				_end_errand("there was no way there", true)
		"doing":
			_errand_do()
		"returning":
			if not _alive(keeper) or World.distance(tile, keeper.tile) <= ERRAND_BACK or not _step_toward(keeper.tile, true):
				_report_errand(str(errand["told"]))


func _errand_there() -> bool:
	match str(errand["verb"]):
		"open", "close":
			return tile in Terrain.edge_cells(errand["door"].key)
		"open_chest":
			return World.distance(tile, errand["chest"].tile) == 1
		"fetch":
			return World.reaches(self, errand["chest"])
		"give":
			return World.reaches(self, keeper)
		"bandage":
			var patient: GridEntity = errand["patient"]
			return patient == self or _alive(patient) and World.can_melee(tile, patient.tile)
		_:
			return _sees(errand["cell"])


## A step toward where her errand is done; false if there is no way.
func _errand_walk() -> bool:
	match str(errand["verb"]):
		"open", "close":
			# The door's near side, or its far one if that is taken.
			for side: Vector2i in [errand["at"]] + Terrain.edge_cells(errand["door"].key):
				if not World.find_path(tile, side).is_empty():
					return _step_toward(side, false)
			return false
		"open_chest", "fetch":
			return _alive(errand["chest"]) and _step_toward(errand["chest"].tile, true)
		"give":
			return _alive(keeper) and _step_toward(keeper.tile, true)
		"bandage":
			return _alive(errand["patient"]) and _step_toward(errand["patient"].tile, true)
		_:
			return _step_toward(errand["cell"], true)


## There: the door opened or closed, the chest looked in, the thing taken
## from the chest (then taken to her player) or handed over, the bandaging
## begun (then waited on: done, mending, or broken off), or the place
## looked at.
func _errand_do() -> void:
	match str(errand["verb"]):
		"bandage":
			var patient: GridEntity = errand["patient"]
			var whom := "yourself" if patient == self else keeper_name()
			if errand.get("started", false):
				if patient.mending == 2:
					_report_errand("You bandaged %s; the wounds are mending." % ("your wounds" if patient == self else "%s's wounds" % keeper_name()))
				elif patient.mending == 0:
					_end_errand("the bandaging was broken off", true)
			elif not _alive(patient):
				_end_errand("%s was gone" % whom, true)
			elif patient.hp >= patient.max_hp:
				_end_errand("there was no wound to bandage", true)
			elif World.bandage_kit(self) < 0:
				_end_errand("you had no bandaging kit", true)
			elif not World.calm(self) or not World.calm(patient):
				_end_errand("it was not safe to bandage", true)
			elif World.try_bandage(self, patient):
				errand["started"] = true
				errand["until"] = World.tick + World.BANDAGE_TICKS + ERRAND_TICKS
			else:
				_end_errand("the bandaging could not be begun", true)
		"fetch":
			var chest: Chest = errand["chest"]
			var item: String = errand["item"]
			var from := chest.slots.find(item)
			var into := World.free_slot_for(self, item)
			if from == -1:
				_end_errand("the %s was no longer in the chest" % Items.name_of(item), true)
			elif into == -1:
				_end_errand("you had no room to carry it", true)
			elif World.try_transfer(self, chest, from, self, into):
				errand["verb"] = "give"
				errand["fetched"] = true
				errand["phase"] = "going"
			else:
				_end_errand("you could not take it", true)
		"give":
			var item: String = errand["item"]
			var from := slots.find(item)
			var into := World.free_slot_for(keeper, item) if _alive(keeper) else -1
			if from == -1:
				_end_errand("you no longer had it", true)
			elif into == -1:
				_end_errand("%s had no room for it" % keeper_name(), true)
			elif World.try_transfer(self, self, from, keeper, into):
				_report_errand("You %s %s the %s%s." % ["brought" if errand.get("fetched", false) else "gave", keeper_name(),
					Items.name_of(item), " from the chest" if errand.get("fetched", false) else ""])
			else:
				_end_errand("it could not be handed over", true)
		"open", "close":
			var door: Door = errand["door"]
			var opening: bool = errand["verb"] == "open"
			var sides := Terrain.edge_cells(door.key)
			var where := _paces_toward(Vector2(sides[0] + sides[1]) / 2.0)
			if door.is_broken():
				_end_errand("the door is broken", true)
			elif door.is_open() == opening:
				_report_errand("The door %s is %s already." % [where, "open" if opening else "shut"])
			elif opening and not World.may_open(self, door):
				_end_errand("the door is locked", true)
			elif World.tick >= next_move_tick:
				if World.try_toggle_door(self, door.key):
					_report_errand("You %s the door %s." % ["opened" if opening else "shut", where])
				else:
					_end_errand("the door would not move", true)
		"open_chest":
			var chest: Chest = errand["chest"]
			var things: Array[String] = []
			for id: String in chest.slots:
				if not id.is_empty():
					var word := Items.name_of(id)
					things.append(("an " if word[0] in "aeiou" else "a ") + word)
			var held := "nothing" if things.is_empty() else things[0] if things.size() == 1 \
					else "%s and %s" % [", ".join(things.slice(0, -1)), things.back()]
			if held != "nothing":
				note_fact("%s found %s in a chest in %s." % [_name_of(self), held, _place_words()])
			_report_errand("You looked in the chest %s: it holds %s." % [_paces_toward(Vector2(chest.tile)), held])
		_:
			var cell: Vector2i = errand["cell"]
			var seen: Array[String] = []
			for entity in World.get_entities():
				if entity == self or entity == keeper or not entity.spawned or World.distance(entity.tile, cell) > LOOK_AROUND \
						or not senses.sees(entity):
					continue
				if entity is Monster or entity is Player or entity is Companion:
					seen.append(refer(entity))
				elif entity is Chest:
					seen.append("a chest")
				elif entity.pushable:
					seen.append("a " + object_word(entity))
			errand["told"] = "You went and looked %s, and came back: %s." % [str(errand["words"]).get_slice(", ", 0).trim_prefix("go and look "),
				"nothing there" if seen.is_empty() else "you saw " + ", ".join(seen) + " there"]
			errand["phase"] = "returning"


## Her errand is done: [param told] narrated, and her voice asked to tell it.
func _report_errand(told: String) -> void:
	_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": errand.get("words", ""), "outcome": "done",
		"note": told})
	errand = {}
	_narrate(told)
	_ask_voice(told, "", true, false, true, true)


## Her errand ends undone, because of [param why]; with [param tell] her
## voice is asked to say so (it could not be done), else it is narrated.
func _end_errand(why: String, tell: bool) -> void:
	var told := "You did not %s: %s." % [str(errand.get("words", "do it")).get_slice(", ", 0), why]
	_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": errand.get("words", ""),
		"outcome": "undone", "note": why})
	errand = {}
	_narrate(told)
	if tell:
		_ask_voice(told, "", true, false, true, true)


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
