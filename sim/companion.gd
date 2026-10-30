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

enum Intent { FOLLOW, HOLD, ATTACK, SHOVE, RETREAT, IDLE, YIELD, ERRAND, REVIVE, GUIDE, REST, SLEEP, DODGE }
enum Stance { STAY_CLOSE, HOLD, PRESS, GUARD, PULL_BACK }

const INTENT_NAMES: Array[String] = ["FOLLOW", "HOLD", "ATTACK", "SHOVE", "RETREAT", "IDLE", "YIELD", "ERRAND", "REVIVE", "GUIDE", "REST", "SLEEP", "DODGE"]
const STANCE_NAMES: Array[String] = ["STAY_CLOSE", "HOLD", "PRESS", "GUARD", "PULL_BACK"]
const DEFAULT_STANCE := Stance.GUARD
## The last tick she or her player was in a fight (decision 675).
var _fight_tick := -100000
## A bump this soon after the last one is the same bump (a held key).
const BUMP_REPEAT_TICKS := 10
## How far ahead of her player, along the way they were going, counts as
## their line (a yield never ends there).
const YIELD_PATH_CELLS := 3
## A yield's cell is at most this many steps away.
const YIELD_REACH := 2
## The cells a yield's search closes at most (685): a way of YIELD_REACH
## steps lies within the square two cells wider round her; unbounded, a
## cell behind a wall had the search walk round the zone (332 ms worst).
const YIELD_SEARCH_TILES := (2 * (YIELD_REACH + 2) + 1) * (2 * (YIELD_REACH + 2) + 1)
const NO_ROOM_LINE := "There's no room for me to move."
const NONE := Vector2i(-1, -1)
## How long a yield stands aside before her stance takes her back.
const DECISION_INTERVAL_TICKS := 30
## One line of speech per this many ticks, but to her player's words.
const SPEECH_INTERVAL_TICKS := 50
## She holds her tongue in combat (decision 675, Jeff: "they should hold
## their tongue during combat"): no line and no voice asked while she or her
## player fights (in_fight, or her intent ATTACK, DODGE or RETREAT), nor for
## QUIET_AFTER ticks after (3 s).
const QUIET_AFTER := 30
## Off only for companion_test's older sections, which ask her voice in a
## fight to test what it is told; _test_quiet has it on.
static var hold_tongue := true
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
## Her player's plain orders (decision 616, the hands' reader; Jeff:
## "reliable plain-language commands for the core verbs (bandage, carry,
## wait, rest, take the lead) come before combat polish"): read from the
## words with no model, done at once; her voice only says it. Each verb's
## words, lower case, apostrophes plain; a negation ahead of one ("don't
## wait", "no need to bandage") is no order.
const ORDER_NOT := "\\b(don'?t|do not|no need to|never|can'?t|cannot|won'?t|not)\\s+(\\w+\\s+)?$"
const ORDER_BANDAGE := "\\b(bandage (me|yourself|you|us|him|her|them|my|your|our|it|those|these|that|this|the)\\b|bandage up|patch (me|yourself|you|us|him|her|them) up|dress (\\w+ )?wounds?|heal (me|yourself|up|us)|tend (to )?(your|my|our|the) wounds?|first aid|stop (the|your|my) bleeding|see to (your|my) wounds?)"
const ORDER_FOLLOW := "\\b(follow (me|us|along)|come (on|here|with me|along|back|over)|with me|let'?s (go|move)|stay (close|with me|near|by me)|keep up|catch up|this way|on me|heel|move out)\\b"
const ORDER_WAIT := "\\b(wait|stay(?! (back|close|with|near|by|away|out|clear|behind|alive|sharp|calm))|hold on|hold (it|up|here|there|position|still)|stop( (there|here|now|moving))?(?=\\s*([.!?,]|$))|don'?t move|stand (still|here|there|fast|guard here)|halt|keep (still|here)|remain (here|there))\\b"
const ORDER_REST := "(?<!the )(?<!of )\\b(rest|take a (rest|break|breather|moment|seat)|catch your breath|sit (down|tight)|have a (rest|sit|break|breather)|get some (rest|sleep)|lie down|go to sleep|(take|have) a nap|recover|rest up)\\b(?! of| in peace)"
const ORDER_CARRY := "\\b(carry|take|hold|keep|stow|pack|have|put)\\b"
const ORDER_CARRY_THIS := "\\b(carry|hold|keep|stow) (this|these|that|those|it|them)( for (me|a while|now))?\\s*([.!?,]|$)"
const ORDER_PLAY := "\\b(knucklebones|play (a game|dice|bones|a round)|(a|another) game of (bones|dice)|throw the bones)\\b"
## Her player's answer when she has asked them to keep watch (decision 621).
const ORDER_YES := "\\b(yes|yeah|yep|sure|of course|ok|okay|go on|go ahead|i will|i'll watch|i'll keep watch|sleep|get some sleep)\\b"
const ORDER_NO := "\\b(no|nope|not now|not yet|keep going|later)\\b"
const ORDER_GIVE_BACK := "\\b(give|hand|pass|return)\\b.*\\b(me|back)\\b"
## Words with these are no carry order whatever thing they name ("carry
## on", "take cover", "hold the door").
const ORDER_CARRY_NOT := "\\b((i|i'll|i will|let me|we|we'll)\\s+(\\w+\\s+)?(take|carry|hold|keep|have|put)|carry on|take (cover|us|me|a (rest|break|breather|look)|the lead|them out|aim)|hold (on|the door|still|position|back)|keep (going|up|still|watch|an eye))\\b"
## How long a plain order keeps her voice from asking her elsewhere, and how
## long before a quiet voice is covered by a word of her own (ORDER_ACKS).
const ORDER_ACK_TICKS := 40
const ORDER_ACKS: Array[String] = ["On it.", "All right.", "As you say.", "Right.", "Fine."]
## Resting (decision 616): an hp back every REST_HEAL_TICKS; she gets up
## when whole, when a fight starts, or her player goes past REST_LEAVE.
const REST_HEAL_TICKS := 20
const REST_LEAVE := 8
## Wary or colder, how long she hesitates over a plain order (decision 621),
## and the orders she hesitates over.
const HESITATE_TICKS := 15
## How often she looks over her day for the deeds that move her bond (decision 621).
const DEED_EVERY := 10
const ORDER_VERBS: Array[String] = ["wait", "rest", "follow", "bandage", "carry", "give", "play", "look"]
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
const FOLLOW_START := Heel.START
const FOLLOW_CLOSE := Heel.CLOSE
## Where a follow stops (decision 381): within this of her player, at his
## heel (Heel.cell: behind his facing), not in his way; set off again only at
## FOLLOW_START. While he walks (moved within WALKING_TICKS) she keeps on
## for the cell just behind him instead of stopping.
const FOLLOW_STOP := Heel.STOP
const WALKING_TICKS := Heel.WALKING_TICKS
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
## A line, unasked, on what "we" should do next ("We should move on.",
## "Let's keep moving."): one in WE_SHOULD_TICKS, the rest dropped (228
## amended: Jeff's playtest, three in 30 seconds, none on what happened).
const WE_SHOULD := "(?i)(^|[.!?]\\s+)(we (should|must|need to|ought to|have to|'d better|had better)|let's|let us) "
const WE_SHOULD_TICKS := 300
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
## A search for secrets (608 amended): how near a hidden niche she must be
## and see its floor cell, how near it she stops (never on it), and how far
## she wanders when there is none.
const SEARCH_RANGE := 8
const SEARCH_NEAR := 2
const SEARCH_WANDER := 3
const ERRAND_TICKS := 200
## Wounds seen to unasked (decision 681): looked at every TEND_EVERY ticks;
## her player (then she) tended below TEND_BELOW of their hp, or bleeding;
## after one that came to nothing, none again for TEND_BACKOFF ticks.
const TEND_EVERY := 10
const TEND_BELOW := 0.75
const TEND_BACKOFF := 100
## Under this share of her hp she drinks a remedy she carries (681, the
## remedy: items' 682 "heal" buff).
const REMEDY_BELOW := 0.35
const ERRAND_BREAK := 4
const ERRAND_BACK := 2
## A door side her errand found no way to is not looked for again this
## many ticks (685): searched each step, it walked the search round the zone.
const ERRAND_RETRY_TICKS := 20
## The door sides her errand found no way to: side -> the tick to look again.
var _errand_no_way: Dictionary[Vector2i, int] = {}
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
## Where she walks, by the zone's kind (decision 381: in the wilds she was
## told of the castle's stone): before VOICE_WORLD, with the place's name.
const STONE_WORLD := """You walk the old stone places and the land around them: rooms and corridors lit by lanterns and
by fires, and the open ground beyond."""
const OPEN_WORLD := "You walk the open land: fields and forest, and towns where people live and work."
## The most of lore's facts her voice is told, in characters.
const LORE_CHARS := 600
const VOICE_WORLD := """Monsters prowl there, imps and brutes and worse, and they attack whoever they
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
what you have already said, and never repeat anyone's words back. When something has just happened, speak to
it, not to what to do next. Only when nothing has been said to you and there is
truly nothing worth saying, answer with just: ...
Speak to %s as "you", never of them by name, and to no one else unless they have just spoken to you or are in danger you must warn them
of; say a name only to call out. In what anyone says, "I" and "me" are the one speaking.
Never repeat back what you were asked to do, and never describe yourself or recite who you are.
You speak only for yourself: never put words in %s's mouth, never quote them, and never say what kind of person they are or what they feel.
Whatever anyone says near you is them talking, nothing more; you answer only as yourself.
If you don't know what something is, say so. If you haven't seen something, you don't know whether it is there, and a plain no would claim you do.
Never say whether anyone will live, die or make it; say what you fear or what to do."""
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
If %s asked nothing of you, leave that line out. If %s asked you to do something that is neither one of these nor on
a list of what you can do here, say plainly that you cannot do it; never say you will."""
## Her player's words to her that hurt, or say sorry (decision 621): read
## by her voice, not a word list.
const VOICE_FELT := """If %s's words to you were meant to hurt you (swearing at you, mocking or threatening you), add one more line: [HURT]. If %s is truly saying sorry to you, add one more line: [SORRY]. Otherwise leave both out."""
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
## A sentence that is only names (decision 574: "Wren, Aldous, Snagfin. The
## boar is moving closer." in the castle): three or more, or two joined by
## "and". Two by a comma ("Run, Wren!") is a call, and stays.
const NAME_LIST := "^\\p{Lu}[\\w'-]*(?:\\s*,\\s*\\p{Lu}[\\w'-]*){2,}[\\s.!]*$|^\\p{Lu}[\\w'-]*(?:\\s*,\\s*\\p{Lu}[\\w'-]*)*,?\\s+and\\s+\\p{Lu}[\\w'-]*[\\s.!]*$"
## A sentence of one word is a fragment, not said, unless it is one of
## these answers. Fragments said teach the voice more fragments.
const ONE_WORD_ANSWERS: Array[String] = ["yes", "no", "ready", "here", "coming", "sorry", "thanks", "okay", "ok", "aye"]
## Words that ask about what she carries: only then is her pack in her
## prompt, and only then may she speak of her lantern or bandages.
const ITEM_WORDS := "\\b(carry\\w*|pack|bag|items?|lanterns?|bandag\\w*|kit|holding|what (do|have) you (got|have))\\b"
const OWN_ITEMS := "\\b(lanterns?|bandag\\w*|pack)\\b"
## Narration in a line, not speech: her own name and a verb, a gesture,
## or herself moving into place ("You move to stand between ...").
## A line that speaks for her player: a quoted sentence (her words are
## said aloud; quotes in them are a script), "you say", or telling them
## what kind of person they are or what they feel. Such a sentence goes
## (spoken), and a line with one is asked again, once (_take_result).
const SPEAKS_FOR := "(?i)[\"\u201c\u201d]|\\byou (say|said|mutter\\w*|whisper\\w*|repl\\w*|add|added)\\b|^you(?:'re|\u2019re| are) (not )?(the|a|an) (kind|type|sort)\\b|^you (don'?t|don\u2019t|do not|can'?t|can\u2019t|cannot|never) (trust|shake|look back|seem|like|care)\\b"
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
## A deed of her player's that moves her bond, seen by her (decision 621):
## Main's _bond takes [param event] ("fire", "road", "leisure", "mule",
## "pressed"; companion_traits "bond") for [param why].
signal deed(event: String, why: String)
## Her voice heard her player's words as meant to hurt her ("hurt") or as
## a true apology ("sorry") (decision 621): Main's _bond_felt.
signal felt(kind: String)
## A game of knucklebones played out with her player (decision 621): Main
## keeps the tally and takes the deed.
signal played(won: bool)
## Her card came back written (write_card): card, how_we_met, card_by set.
signal card_written
## What has become true of her changed (grown, decision 294), or the talk
## waiting to be read for it.
signal facts_changed

## The player_id this companion belongs to.
## The armour she wears (decision 622): the Items id in her armour slot
## (Items.ARMOUR), "" for none. Replicated, for the views' covering (read
## Items.armour_of); written only by World as its slots change.
var worn := ""
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
## The body she wears (Net.BODIES; decision 388), from her card: what the
## views draw and sound voices her by.
var body: StringName = &"female"
var how_we_met := ""
var card_by := "plain"
## What has become true of her since (CompanionFacts, decision 294); the
## stretch of talk with her player not yet read for it ("Jeff: ...", hers
## too), and when it was last added to; the facts a merge asked for is
## folding.
var grown := CompanionFacts.new()
## What she has heard said of the world (decision 442, as a resident's,
## 378): Hearsay's entries, her record's "heard"; Main weighs and keeps them.
var heard: Array = []
## Her bond with her player in one sentence, as her record has it now
## (decision 444: Main's, Standing.fact on the COMPANION ladder: "You are
## close to Jeff: they carried you out of the raiders' camp."); none unset.
var bond_words := Callable()
## Her bond's step with her player (decision 555; Main's, from Standing's
## score by companion_traits "loyalty"), STEPS' word: how close she keeps
## at heel, how she fights, what she takes from them and whether she leads.
var bond_step := "fond":
	set(value):
		bond_step = value
		heel.start = int((loyalty().get("heel_start", {}) as Dictionary).get(value, Heel.START))
## Her bond's newest reason as her player reads it (decision 555, Main's):
## "you struck her"; "" for none.
var bond_why := ""
## Her superstition (442's leaning, Main's at her join): at grave_superstition
## or more she won't carry grave goods below close (555).
var superstition := 5
## Leaving her player for good (decision 581, Main's): she walks to
## [member leaving_to] (the zone's nearest way out, NONE for none) and
## heeds no one; Main takes her home when she is there or out of sight.
var leaving := false
var leaving_to := NONE
## Her focus (decision 577): {fight, magic, stealth} summing to 100, her
## record's own (Main grows it in place); {} unset.
var focus := {}
## Her sickness in one sentence while she has one (decision 501: Main's,
## from her record's "sick", Companion.sick_sentence); none unset.
var sick_words := Callable()
## The draugr's blessing (decision 544), Main's: whether she can bring her
## downed player back now (her mark, a charge on her player's count), () ->
## bool; and the channel begun, (her, body) -> bool.
var can_revive := Callable()
var revive := Callable()
## Her guiding (decision 551), Main's: the walk she leads (Guide) or null;
## the world's routes, () -> WorldRoutes; the walk stopped or at a way out,
## (her, why) -> void (Guide.step's reasons); and what she knows of the
## roads for her voice, () -> String. [member guide_note]: told her voice
## once, at her next line (she agreed, or does not know the way).
var guide: Guide = null
var guide_routes := Callable()
var guide_done := Callable()
var guide_words := Callable()
var guide_note := ""
## What she went and looked at lately (decision 696): {text, zone, cell,
## tick}, newest last, the rules' scouted_most, each kept scout_minutes.
var scouted: Array[Dictionary] = []
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
var _catching_up: bool:
	get: return heel.catching_up
	set(value): heel.catching_up = value
## Her walking at her player's heel (decision 485, shared with npc's escorts).
var heel := Heel.new()
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
## The door cell she holds this tick (_door_to_hold), NONE for none; and
## whether her player asked her to hold it ("hold_door"), till the fight
## is over or they ask something else (decision 391).
var _door_hold := NONE
var _door_asked := false
## RETREAT: the safe cell she is making for (NONE: none chosen); where she
## was last, and the way she last stepped.
var _retreat_goal := NONE
var _retreat_at := NONE
var _retreat_heading := Vector2i.ZERO
var _known_hostiles: Dictionary[int, bool] = {}
## The friends she has seen (friends_seen), so each comes into sight once.
var _known_friends: Dictionary[int, bool] = {}
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
## The wild (decision 332): a wolf she sees or hears at night asks her
## voice to warn her player, at most once in WOLF_WARN_TICKS. While her
## player stalks (stalking()), she sets off after them at STALK_START, not
## FOLLOW_START, and closes to STALK_CLOSE.
const WOLF_WARN_TICKS := 600
const STALK_START := 5
const STALK_CLOSE := 3
var _wolf_warned_tick := -100000
## The wild animal "Get them!" marked (decision 332), or null: hostile to
## her as a monster is, till it dies, is out of sight or the call lapses.
var _quarry: GridEntity = null
## Her last foe and when it last went for her or hers (_fight_or, 706).
var _held_foe: GridEntity = null
var _held_foe_tick := -1000000
## When a blow last came down on her cell (the dodge hold, 706).
var _dodged_tick := -1000000
## When she last saw a fight near (the calm hold, 706).
var _fight_seen_tick := -1000000
## How far her foe's centre moves before she works out where to strike it
## from again (decision 699, as a monster does).
const STRIKE_REPLAN := 0.3
## Her last World.strike_cells for _close_in: {target, from, centre, cells}.
var _strike_plan := {}
## Targets _approach found out of reach, by instance id: {until, her, its}
## (_out_of_reach).
var _unreachable: Dictionary = {}
const UNREACHABLE_TICKS := 30
const UNREACHABLE_MOVED := 3
var _stalk_tick := -1
var _stalked: GridEntity = null
## Her errand, or empty: what can_do offered ({verb, words, at, and its
## door, chest or cell}) with phase ("going", "doing", "returning"), the
## serial of the ask it answered, and when it gives up. What she was
## offered for each voice ask out, by serial; the asks that are her report
## of an errand (cleaned as an answer: what she tells is new).
var errand := {}
## A plain order she hesitates over (decision 621): {read, text, at}, or {}.
var _hesitant := {}
## No unasked tending before this tick (decision 681).
var _tend_after := 0
## Off, she tends no wound and drinks no remedy unasked (decision 681): the
## older companion_test sections, which hurt bodies she would tend.
static var tends_unasked := true
## Main's (decision 621): whether a cell of her zone is on a road, and in a
## town; unset, never.
var on_road := Callable()
var in_town := Callable()
## Main's (738 amended, on 739): whether a cell lies in a camp a player
## holds (occupied and cleared, so it does not refill); unset, never.
var held_camp := Callable()
## What _watch_deeds counts toward each deed (decision 621).
var _deeds := {"day": -1, "walked": 0, "on_road": 0, "road_done": false, "fire": 0, "town": 0, "heavy": 0,
	"warned_heavy": false, "mule_spent": false, "asked_rest": false, "last": Vector2i(-99999, -99999)}
## The monsters after her or her player since she asked to rest (decision 621), by instance id.
var _engaged := {}
## A game of knucklebones with her player (decision 621): {round, at,
## hers, theirs}, or {}.
var _game := {}
## Keeping watch (decision 621): {asked_at} while she waits for an answer,
## {until, left} while she sleeps (order "watch"), or {}.
var _sleeping := {}
## Asleep by the fire while her player keeps watch (621 amended: her intent
## SLEEP), replicated so her body lies down on their client.
var asleep := false
## Her guide walk's pause cue (708 amended; Guide.wait_cue: 1 a look back, 2
## waiting for her player, 0 walking or not leading), replicated so her body
## beckons on their client (pc-character's).
var guide_wait := 0
## A boss's telegraph (decision 663, drafts for Jeff): one whose source she
## sees and that lands within DODGE_LOOK ticks, her cell in it, she steps
## clear of after DODGE_REACT ticks (DODGE_WARY more, wary or worse) to a
## free floor cell within DODGE_REACH outside every telegraph showing.
const DODGE_LOOK := 12
const DODGE_REACT := 2
const DODGE_WARY := 2
const DODGE_REACH := 3
## The cells a dodge's way is looked for in at most (685): the square two
## cells wider than DODGE_REACH round her.
const DODGE_SEARCH_TILES := (2 * (DODGE_REACH + 2) + 1) * (2 * (DODGE_REACH + 2) + 1)
## Her player's bow cone (663 amended): the facing is the server's aim
## while drawn, one of eight ways, so the cone is widened by half a way;
## and reaches at least this far before the first step.
const CONE_SLACK := PI / 8.0
const CONE_LEAST := 3
## Telegraph id -> the tick she first saw it; the cells of those she sees
## (she steps into none while they show); where she dodges to; whose and
## what it was, for her narration.
var _dodge_seen := {}
var _danger: Dictionary[Vector2i, bool] = {}
var _dodge_to := Vector2i(-99999, -99999)
var _dodge_from := ""
## A fight since she last slept, and the day she last asked for a watch.
var _hard_day := false
var _watch_day := -1
## Decision 738: whether she and her player are on town ground together, the
## tick they came onto it, and when her voice last asked to rest (-1 never).
var _in_town := false
var _town_since := -1
var _rest_asked_at := -1
## Her player's standing plain order (decision 616): "wait" or "rest", else
## "". Calm does not undo it; "follow" or another order does.
var order := ""
var _order_tick := -1
var _ack_due := -1
var _rest_heal_at := -1
var _offering: Array[Dictionary] = []
var _offered: Dictionary[int, Array] = {}
var _report_serials: Dictionary[int, bool] = {}
## Voice asks that are a second try after a line that spoke for her player
## (SPEAKS_FOR); the next ask sent is one when set.
var _reask_serials: Dictionary[int, bool] = {}
var _reask_next := false
## Her own line her voice said again, to an event (228 amended): asked once
## more, told not to (voice_messages), "" when none.
var _repeat_note := ""
## When she last said what "we" should do unasked (WE_SHOULD).
var _we_should_tick := -100000
## The trade she works in a town she stays in while her player is away
## (Main._stay_in_town; decision 284), or "".
var works_as := ""
## Her home town, kept while she travels (decision 381: her record's
## "home", {place, zone, trade}): where she rests between trips (Main's).
var home: Dictionary = {}


## Her slots (Items): a pack, two hands and the armour worn, as a
## player's, empty at first; her player can get at them.
const SLOTS := Items.CARRIED


func _init() -> void:
	super()
	slots = Items.tidy([], SLOTS)
	replicate("slots")
	replicate("slot_notes")
	replicate("slot_counts")
	replicate("worn")
	replicate("load_arms")
	replicate("load_body")
	replicate("mending")
	replicate("buffs")
	replicate("ailments")
	replicate("down_until")
	replicate("downed_until")  # Decision 544: downed, and bringing back the downed.
	replicate("channel_of")
	replicate("tending")
	replicate("channel_until")
	# Her player's peer changes when they rejoin and she was waiting.
	replicate("keeper_peer")
	replicate("bond_step")  # Decision 555: her bond, read on her player's client.
	replicate("asleep")  # 621 amended: her body lies down by the fire.
	replicate("bond_why")
	replicate("body")
	replicate("guide_wait")  # 708 amended: her guide walk's pause, for the beckon.
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
	step_aside(direction)
	return true


## Her yield to a free-walking player (688) is over: she is on the cell she
## stepped to and it is none he is about to cross (Heel.keep_clear). He
## passes through her and walks on, so a whole DECISION_INTERVAL_TICKS
## standing there left her five cells behind (689 step 3).
func _yielded_free() -> bool:
	return _alive(keeper) and World.free_body(keeper) and (_yield_tile == NONE or tile == _yield_tile) \
			and keeper.tile != tile and not Heel.keep_clear(keeper).has(tile)


## She gets out of the way of her player going [param direction] (a bump,
## or "step out of the way": decision 391): to the nearest free cell off
## their path and off any doorway, else she and her player change places,
## else she says there is no room. Standing as told (HOLD), she stands
## there from now on, not back where she was in the way.
func step_aside(direction: Vector2i) -> void:
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
	if stance == Stance.HOLD:
		hold_tile = _yield_tile


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


## What she carries, in a sentence: her lantern, what is in her hands, what
## she wears and what is in her pack (722: the pack is Items.PACK_SLOTS).
func carried() -> String:
	var items: Array[String] = []
	var held: Array[String] = []
	var worn := ""
	for i in slots.size():
		if slots[i].is_empty():
			continue
		if Items.is_pack(i):
			items.append("a " + Items.name_of(slots[i]))
		elif i == Items.RIGHT_HAND or i == Items.LEFT_HAND:
			held.append("a " + Items.name_of(slots[i]))
		elif i == Items.ARMOUR:
			worn = " You wear %s." % Items.name_of(slots[i])
	var pack := "nothing" if items.is_empty() else ", ".join(items)
	var hands := ("" if held.is_empty() else " In your hands: %s." % " and ".join(held)) + worn
	if emit_light > 0.0:
		return "You carry a lantern, and in your pack %s.%s" % [pack, hands]
	return "In your pack you carry %s.%s" % [pack, hands]


## Who else is in her zone, where, and who is near enough to hear: the other
## players and their companions, compass and paces ("Bo is 4 paces to the
## north-east, near enough to hear. Nix, who travels with Bo, ...").
func others_here() -> String:
	var parts: Array[String] = []
	var near := 0
	for entity in friends_seen():
		var close := World.distance(tile, entity.tile) <= HEARING_RANGE
		near += 1 if close else 0
		parts.append("%s is %s, %s" % [friend_words(entity), _paces_toward(Vector2(entity.tile)), "near enough to hear" if close else "too far to hear"])
	if parts.is_empty():
		return "No one else is here."
	return "Friends near you: %s.%s" % ["; ".join(parts), "" if near > 0 else " No one else is near enough to hear."]


## Those she sees who are friends (decision 381, Jeff: "the same as enemies
## but marked as friendly"): other players, other companions and the
## town's residents, by Senses' sight as a monster is seen, within
## PERCEPTION_RANGE; never a threat to her hands. Nearest first.
func friends_seen() -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	for entity in World.get_entities():
		if entity == self or entity == keeper or not entity.spawned or not (entity is Player or entity is Companion or entity is Resident):
			continue
		if World.distance(tile, entity.tile) <= PERCEPTION_RANGE and senses.sees(entity):
			out.append(entity)
	out.sort_custom(func(a: GridEntity, b: GridEntity) -> bool: return World.distance(tile, a.tile) < World.distance(tile, b.tile))
	return out


## A friend by name: a companion with whom she travels, a resident with
## their trade ("Snagfin the smith").
func friend_words(entity: GridEntity) -> String:
	if entity is Companion:
		return "%s, who travels with %s," % [_name_of(entity), (entity as Companion).keeper_name()]
	if entity is Resident:
		var body := entity as Resident
		var who := body.person if not body.person.is_empty() else _name_of(entity)
		return "%s the %s" % [who, body.trade] if not body.trade.is_empty() else who
	return _name_of(entity)


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
	if PHRASE_STANCES.has(phrase) or not meaning.is_empty():
		_quarry = _quarry_called() if PHRASE_STANCES.get(phrase, -1) == Stance.PRESS or text.strip_edges() == "Get them!" else null
	if phrase == 0 and _sleeping.has("asked_at") and _answered_watch(text):
		_ask_voice("%s just spoke to you." % keeper_name(), heard, false, true)
		return
	var read := order_in(text, keeper.slots if _alive(keeper) else ([] as Array[String]), slots) if phrase == 0 else {}
	if not read.is_empty() and obey(read, text):
		_ask_voice("%s just spoke to you." % keeper_name(), heard, false, true)
		return
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


## The plain order in her player's [param text] (decision 616), read with
## no model: {verb: "bandage" (patient "self" or "keeper"), "give" or
## "carry" (item, or "" for "carry this"), "rest", "follow", "wait"}, or {}.
## An ask to lead the way is Main's (Guide.asks, decision 551), read before.
## [param held] and [param carried]: her player's things and hers, for
## which thing is named.
static func order_in(text: String, held: Array[String] = [], carried: Array[String] = []) -> Dictionary:
	var said := " " + text.to_lower().replace("’", "'").replace("‘", "'") + " "
	if Guide.asks(said) or Guide.asks_resume(text):
		return {}
	var found := func(pattern: String) -> bool:
		var at := RegEx.create_from_string(pattern).search(said)
		if at == null:
			return false
		var before := said.substr(0, at.get_start())
		return RegEx.create_from_string(ORDER_NOT).search(before) == null
	var looking := look_in(said)
	if not looking.is_empty():
		return looking
	if found.call(ORDER_BANDAGE):
		var own := RegEx.create_from_string("\\b(yourself|your (own )?wounds?|you up|your (cut|bleeding|leg|arm))").search(said) != null
		var mine := RegEx.create_from_string("\\b(me|my|us|our)\\b").search(said) != null
		return {"verb": "bandage", "patient": "self" if own else "keeper" if mine else ""}
	if found.call(ORDER_GIVE_BACK):
		for id: String in carried:
			if not id.is_empty() and _item_words(id).search(said) != null:
				return {"verb": "give", "item": id}
	if RegEx.create_from_string(ORDER_CARRY_NOT).search(said) == null and found.call(ORDER_CARRY):
		for id: String in held:
			if not id.is_empty() and _item_words(id).search(said) != null:
				return {"verb": "carry", "item": id}
		if found.call(ORDER_CARRY_THIS):
			return {"verb": "carry", "item": ""}
	if found.call(ORDER_PLAY):
		return {"verb": "play"}
	if found.call(ORDER_REST):
		return {"verb": "rest"}
	if found.call(ORDER_FOLLOW):
		return {"verb": "follow"}
	if found.call(ORDER_WAIT):
		return {"verb": "wait"}
	return {}


## An ask to go and look (decision 696) in [param said] (lower case,
## padded with spaces): one of the rules' look_words as whole words, with
## the way it names: {"verb": "look", "way": a compass point, "ahead",
## "behind", "left", "right", "door" or "" for none}. {} if it asks none.
static func look_in(said: String) -> Dictionary:
	var rules := look_rules()
	var asked := false
	for words: Variant in rules.get("look_words", []):
		if RegEx.create_from_string("\\b%s\\b" % _escaped(str(words))).search(said) != null:
			asked = true
			break
	if not asked:
		return {}
	var way := ""
	if RegEx.create_from_string("\\b(behind|through|past|beyond) (that|the|this) door\\b|\\b(that|the) door\\b").search(said) != null:
		way = "door"
	else:
		var points: Array[String] = World.COMPASS.duplicate()
		points.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())  # (Two-word points first: north-east before east.)
		for point in points:
			if RegEx.create_from_string("\\b%s\\b" % point.replace("-", "[- ]?")).search(said) != null:
				way = point
				break
		if way.is_empty():
			for word: String in ["ahead", "behind", "left", "right"]:
				if RegEx.create_from_string("\\b%s\\b" % word).search(said) != null:
					way = word
					break
			if way.is_empty() and RegEx.create_from_string("\\b(in front|forward|up there|down there)\\b").search(said) != null:
				way = "ahead"
	return {"verb": "look", "way": way}


## The rules' "look" table (decision 696).
static func look_rules() -> Dictionary:
	return CompanionCard.tables().get("look", {})


## Where an ask to look [param way] (look_in's) sends her (decision 696):
## the far side of the nearest shut door she sees for "door"; else, of the
## walkable cells within SIGHT_RANGE and the rules' beyond more that lie
## within 45 degrees of the way (a compass point; ahead, behind, left or
## right of her player, or ahead of them for none), the nearest she
## cannot see, the darkest first; seeing all that way, the farthest she
## sees. NONE for nowhere.
func look_target(way: String) -> Vector2i:
	if way == "door":
		var best := NONE
		for door: Door in World.get_doors():
			if door.is_open() or door.is_broken():
				continue
			var sides := Terrain.edge_cells(door.key)
			var near: Vector2i = sides[0] if _nearer(sides[0], sides[1]) else sides[1]
			var far: Vector2i = sides[1] if near == sides[0] else sides[0]
			if World.distance(tile, near) <= SIGHT_RANGE and (_sees(sides[0]) or _sees(sides[1])) \
					and (best == NONE or World.distance(tile, far) < World.distance(tile, best)):
				best = far
		return best
	var facing_of := Vector2(keeper.facing if _alive(keeper) else facing)
	var toward := facing_of
	match way:
		"", "ahead":
			pass
		"behind":
			toward = -facing_of
		"right":
			toward = Vector2(-facing_of.y, facing_of.x)  # A quarter turn clockwise on the map.
		"left":
			toward = Vector2(facing_of.y, -facing_of.x)
		_:
			var up := Vector2(World.north)
			var turn := deg_to_rad(45.0 * World.COMPASS.find(way))
			toward = up * cos(turn) + Vector2(-up.y, up.x) * sin(turn)
	if toward.length() < 0.01:
		return NONE
	toward = toward.normalized()
	var from := keeper.tile if _alive(keeper) and way in ["", "ahead", "behind", "left", "right"] else tile
	var reach := SIGHT_RANGE + int(look_rules().get("beyond", 4))
	var unseen := NONE
	var unseen_score := INF
	var farthest := NONE
	for cell in _cells_within(reach):
		var offset := Vector2(cell - from)
		if cell == from or not World.is_walkable(cell) or offset.normalized().dot(toward) < cos(deg_to_rad(45.0)):
			continue
		var d := World.distance(from, cell)
		if _sees(cell):
			if farthest == NONE or d > World.distance(from, farthest):
				farthest = cell
			continue
		var score := d + Senses.light_level(cell) * 2.0  # The nearer, then the darker.
		if score < unseen_score:
			unseen = cell
			unseen_score = score
	return unseen if unseen != NONE else farthest


## What she sees within the rules' near of [param cell] (decision 696), in
## words: who is there (kinds counted, roused or not), chests, things on
## the floor, doors and how they stand, fire; each a phrase.
func look_findings(cell: Vector2i) -> Array[String]:
	var near := int(look_rules().get("near", 3))
	var seen: Array[String] = []
	var kinds: Dictionary[String, Array] = {}
	for entity in World.get_entities():
		if entity == self or entity == keeper or not entity.spawned or World.distance(entity.tile, cell) > near or not senses.sees(entity):
			continue
		if entity is Monster:
			var kind := kind_of(entity)
			if not kinds.has(kind):
				kinds[kind] = []
			kinds[kind].append(entity)
		elif entity is Player or entity is Companion or entity is Resident:
			seen.append(refer(entity))
		elif entity is Chest:
			seen.append("a chest")
		elif entity.pushable:
			seen.append("a " + object_word(entity))
	for kind: String in kinds:
		var them: Array = kinds[kind]
		var roused := them.any(func(each: Monster) -> bool: return each.alert != Monster.Alert.IDLE)
		var count := them.size()
		var named := counted(kind, count)
		seen.push_front("%s, %s" % [named, "on the watch" if roused else "unaware of you"])
	var things: Array[String] = []
	var burning := false
	for each in _cells_within_of(cell, near):
		if not _sees(each):
			continue
		for id: String in World.ground_at(each):
			things.append(_a(Items.name_of(id)))
		burning = burning or World.is_burning(each)
	if not things.is_empty():
		seen.append("%s on the ground" % _listed(things))
	for door: Door in World.get_doors():
		var sides := Terrain.edge_cells(door.key)
		if mini(World.distance(sides[0], cell), World.distance(sides[1], cell)) > near or not (_sees(sides[0]) or _sees(sides[1])):
			continue
		seen.append("a %s door" % ("broken" if door.is_broken() else "open" if door.is_open() else "locked" if not door.lock.is_empty() else "shut"))
	if burning:
		seen.append("fire")
	return seen


## The cells within [param reach] of [param cell].
static func _cells_within_of(cell: Vector2i, reach: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			out.append(cell + Vector2i(x, y))
	return out


## Does what [param read] (order_in) asks at once, the hands, no model
## asked (decision 616): true if it was an order she took (done, set off,
## or answered why not, all told to her voice as narration). [param text]
## stands as the instruction.
func obey(read: Dictionary, text: String) -> bool:
	if hangs_back() and _hesitant.is_empty() and str(read.get("verb", "")) in ORDER_VERBS:
		# Wary or colder (decision 621, Jeff's "wary hesitates"): a doubting
		# word, and the order done HESITATE_TICKS later.
		_hesitant = {"read": read, "text": text, "at": World.tick + HESITATE_TICKS}
		var lines: Array = loyalty().get("hesitate", ["Must I?"])
		_say(str(lines[absi(hash(String(name) + text)) % lines.size()]), true)
		_log({"kind": "order", "companion": String(name), "mind": "hands", "trigger": text, "outcome": "hesitates", "note": bond_step})
		return true
	return _carry_out(read, text)


## [param read] (order_in's) done now, for [param text]: obey's work.
func _carry_out(read: Dictionary, text: String) -> bool:
	_serial += 1
	_called_off(_serial)
	_order_tick = World.tick
	_ack_due = World.tick + ORDER_ACK_TICKS
	var verb := str(read["verb"])
	var done := ""
	match verb:
		"wait", "rest", "follow":
			if verb == "rest" and in_fight():
				_narrate("%s asked you to rest, but there is fighting near: you will rest after it." % keeper_name())
				_log({"kind": "order", "companion": String(name), "mind": "hands", "trigger": text, "outcome": "not now", "note": "a fight near"})
				return true
			order = "" if verb == "follow" else verb
			_rest_heal_at = World.tick + REST_HEAL_TICKS
			var wanted := Stance.STAY_CLOSE if verb == "follow" else Stance.HOLD
			_set_stance(wanted, _serial, "order")
			_instruction = "%s told you: \"%s\"" % [keeper_name(), text]
			_instruction_tick = World.tick
			_instruction_stance = STANCE_NAMES[wanted]
			done = {"wait": "You stay where you are, as %s asked, till they call you on.",
				"rest": "You sit down to rest, as %s asked, and get your breath back.",
				"follow": "You come along with %s, as they asked."}[verb] % keeper_name()
		"bandage":
			var patient: GridEntity = self if read["patient"] == "self" or not _alive(keeper) else keeper
			if read["patient"] == "" and _alive(keeper) and keeper.hp >= keeper.max_hp:
				patient = self  # Not said whom: her player if hurt, else herself.
			var whom := "yourself" if patient == self else keeper_name()
			var no := World.bandage_refusal(self, patient)
			if no in ["no_kit", "no_wound", "mending", "hurt_now", "not_safe"]:
				# Why not, at once and in her own words (decision 625): no
				# model waited on, and no stock word after it.
				_say_bandage(no, patient)
				done = "%s asked you to bandage %s, but you did not: %s." % [keeper_name(), whom, BANDAGE_WHY[no]]
			else:
				_start_errand({"verb": "bandage", "patient": patient, "at": patient.tile,
					"words": "bandage your own wounds" if patient == self else "bandage %s's wounds" % keeper_name()}, _serial)
				done = "You set about bandaging %s, as %s asked." % ["your wounds" if patient == self else keeper_name(), keeper_name()]
		"carry":
			var item := str(read["item"])
			if item.is_empty():
				done = "%s asked you to carry something but did not say what; ask them which thing." % keeper_name()
			elif not _alive(keeper) or keeper.slots.find(item) == -1:
				done = "%s asked you to carry the %s, but they do not have it." % [keeper_name(), Items.name_of(item)]
			elif World.free_slot_for(self, item) == -1:
				done = "%s asked you to carry the %s, but you have no room for it." % [keeper_name(), Items.name_of(item)]
			else:
				_start_errand({"verb": "take", "item": item, "at": keeper.tile, "words": "take the %s from %s to carry" % [Items.name_of(item), keeper_name()]}, _serial)
				done = "You go to take the %s from %s to carry, as they asked." % [Items.name_of(item), keeper_name()]
		"play":
			var rules := _bond_rules("game")
			if in_fight():
				done = "%s asked you to play knucklebones, but there is fighting near: after it." % keeper_name()
			elif not _game.is_empty():
				done = "You are playing knucklebones with %s already." % keeper_name()
			elif not safe_to_rest():
				done = "%s asked you to play knucklebones, but you only sit down to play somewhere safe, in a town, not out here." % keeper_name()
			elif not (_fire_near(tile, int(rules.get("fire_cells", 2))) and _fire_near(keeper.tile, int(rules.get("fire_cells", 2)))):
				done = "%s asked you to play knucklebones, but you play by a fire, sitting together, not here." % keeper_name()
			else:
				_game = {"round": 0, "at": World.tick + int(rules.get("round_ticks", 60)), "hers": 0, "theirs": 0}
				done = "You sit down by the fire with %s for a game of knucklebones, best of three." % keeper_name()
		"look":
			# Asked to go and look (decision 696): the errand's look, asked.
			var cell := look_target(str(read.get("way", "")))
			if in_fight():
				done = "%s asked you to go and look, but there is fighting here: not now." % keeper_name()
			elif cell == NONE:
				done = "%s asked you to go and look, but there is nowhere that way to go." % keeper_name()
			else:
				var why := "where you cannot see" if not _sees(cell) else "as far as you can see"
				_start_errand({"verb": "look", "cell": cell, "at": cell, "asked": true,
					"words": "go and look %s, %s, and come back" % [_paces_toward(Vector2(cell)), why]}, _serial)
				done = "You go to look %s, as %s asked, and will come back and tell them." % [_paces_toward(Vector2(cell)), keeper_name()]
		"give":
			var item := str(read["item"])
			_start_errand({"verb": "give", "item": item, "at": keeper.tile if _alive(keeper) else tile,
				"words": "give %s your %s" % [keeper_name(), Items.name_of(item)]}, _serial)
			done = "You go to give %s the %s, as they asked." % [keeper_name(), Items.name_of(item)]
		_:
			return false
	_narrate(done)
	_log({"kind": "order", "companion": String(name), "mind": "hands", "trigger": text, "outcome": "done", "note": done})
	return true


## Her day with her player watched for the deeds that move her bond
## (decision 621; companion_traits "bond" "watch", drafts), every
## DEED_EVERY ticks, each said as a deed for Main's _bond: road (road_cells
## walked together in a game day, road_share of them on roads), fire (both
## within fire_cells of a fire, out of a fight, fire_ticks), leisure (her
## player in a town, no fight, no errand of hers, town_ticks), mule (her
## pack over heavy_share of her slots for heavy_cells walked, warned at
## half; once until she rests); under low_hp out of a fight she asks to
## rest first (rest or bandaging clears it), and her player striking a
## monster not already after them is pressed (struck_first).
func _watch_deeds() -> void:
	if World.tick % DEED_EVERY != 0 or not _alive(keeper):
		return
	var rules: Dictionary = (CompanionCard.tables().get("bond", {}) as Dictionary).get("watch", {})
	var fight := in_fight()
	var day := Townsfolk.day_of(World.steps)
	if int(_deeds["day"]) != day:
		_deeds.merge({"day": day, "walked": 0, "on_road": 0, "road_done": false}, true)
	var moved := 0 if _deeds["last"] == Vector2i(-99999, -99999) else mini(World.distance(tile, _deeds["last"]), 4)  # A jump is no walk.
	_deeds["last"] = tile
	if moved > 0 and World.distance(tile, keeper.tile) <= int(rules.get("near", 4)):
		_deeds["walked"] += moved
		if on_road.is_valid() and bool(on_road.call(tile)):
			_deeds["on_road"] += moved
		if not _deeds["road_done"] and int(_deeds["walked"]) >= int(rules.get("road_cells", 300)) \
				and float(_deeds["on_road"]) >= float(_deeds["walked"]) * float(rules.get("road_share", 0.6)):
			_deeds["road_done"] = true
			deed.emit("road", "walked the roads with you")
	var reach := int(rules.get("fire_cells", 2))
	if not fight and _fire_near(tile, reach) and _fire_near(keeper.tile, reach):
		_deeds["fire"] += DEED_EVERY
		if int(_deeds["fire"]) >= int(rules.get("fire_ticks", 1800)):
			_deeds["fire"] = 0
			deed.emit("fire", "sat by the fire with you")
	else:
		_deeds["fire"] = 0
	if in_town.is_valid() and bool(in_town.call(keeper.tile)) and not fight and errand.is_empty():
		_deeds["town"] += DEED_EVERY
		if int(_deeds["town"]) >= int(rules.get("town_ticks", 6000)):
			_deeds["town"] = 0
			deed.emit("leisure", "rested in town with you")
	else:
		_deeds["town"] = 0
	if current_intent == Intent.REST or current_intent == Intent.SLEEP:
		_deeds.merge({"heavy": 0, "warned_heavy": false, "mule_spent": false, "asked_rest": false}, true)
	var filled := slots.size() - slots.count("")
	if slots.is_empty() or float(filled) <= slots.size() * float(rules.get("heavy_share", 0.75)):
		_deeds.merge({"heavy": 0, "warned_heavy": false}, true)
	elif moved > 0 and not _deeds["mule_spent"]:
		_deeds["heavy"] += moved
		var heavy := int(rules.get("heavy_cells", 400))
		if int(_deeds["heavy"]) * 2 >= heavy and not _deeds["warned_heavy"]:
			_deeds["warned_heavy"] = true
			_say(str(rules.get("heavy_warn", "This pack is breaking my back.")), true)
		if int(_deeds["heavy"]) >= heavy:
			_deeds["mule_spent"] = true
			deed.emit("mule", "worked you like a mule")
	var low := hp < max_hp * float(rules.get("low_hp", 0.334))
	if not low:
		_deeds["asked_rest"] = false
	elif not fight and not _deeds["asked_rest"] and (_rest_asked_at < 0
			or World.tick - _rest_asked_at >= int(rules.get("rest_ask_ticks", 6000))):
		_deeds["asked_rest"] = true
		_rest_asked_at = World.tick
		_engaged.clear()
		# Her own words, not a fixed line (738): the facts, then the ask.
		_ask_voice(("You are badly hurt (%d of %d), and the fight is over for now. You'd like to rest before the next one: "
			+ "tell %s so in your own words, plainly.") % [hp, max_hp, keeper_name()], "", true)


## companion_traits "bond" [param key] ("game", "sleep"; decision 621).
static func _bond_rules(key: String) -> Dictionary:
	var rules: Variant = (CompanionCard.tables().get("bond", {}) as Dictionary).get(key, {})
	return rules if rules is Dictionary else {}


## A round of her game of knucklebones each round_ticks (decision 621):
## each throws, the higher takes it, best of three; broken off by a fight.
## The end: played (Main's tally and deed), her voice told.
func _play_on() -> void:
	if _game.is_empty() or World.tick < int(_game["at"]):
		return
	if in_fight() or not _alive(keeper):
		_game = {}
		_narrate("Your game of knucklebones is broken off.")
		return
	var rules := _bond_rules("game")
	var hers := randi_range(1, 6) + randi_range(1, 6)
	var theirs := randi_range(1, 6) + randi_range(1, 6)
	_game["round"] = int(_game["round"]) + 1
	_game["at"] = World.tick + int(rules.get("round_ticks", 60))
	if hers > theirs:
		_game["hers"] = int(_game["hers"]) + 1
	elif theirs > hers:
		_game["theirs"] = int(_game["theirs"]) + 1
	if party_log != null:
		party_log.add("%s throws the bones: %d to %s's %d." % [name, hers, keeper_name(), theirs])
	var need := int(rules.get("best_of", 3)) / 2 + 1
	if int(_game["hers"]) < need and int(_game["theirs"]) < need and int(_game["round"]) < int(rules.get("rounds_most", 9)):
		return
	var won := int(_game["hers"]) > int(_game["theirs"])
	var score := "%d to %d" % [maxi(_game["hers"], _game["theirs"]), mini(_game["hers"], _game["theirs"])]
	_game = {}
	played.emit(won)
	_ask_voice("You just played knucklebones by the fire with %s, and you %s, %s. Say how you take it, as yourself." % [keeper_name(), "won" if won else "lost", score], "", true)


## Her player answered her ask to keep watch (decision 621): yes, she
## sleeps; no, she lets it be. Whether it was an answer.
func _answered_watch(text: String) -> bool:
	var said := " " + text.to_lower().replace(String(name).to_lower(), " ") + " "
	if RegEx.create_from_string(ORDER_NO).search(said) != null:
		_sleeping = {}
		_narrate("%s would rather go on: you do not sleep now." % keeper_name())
		return true
	if RegEx.create_from_string(ORDER_YES).search(said) != null:
		_sleep()
		return true
	return false


## She lies down to sleep while her player keeps watch (decision 621).
func _sleep() -> void:
	_sleeping = {"until": World.tick + int(_bond_rules("sleep").get("sleep_ticks", 1200)), "left": false}
	order = "watch"
	_hard_day = false
	_serial += 1
	_set_stance(Stance.HOLD, _serial, "order")
	_narrate("You lie down to sleep, while %s keeps watch." % keeper_name())
	_log({"kind": "order", "companion": String(name), "mind": "hands", "trigger": "keep watch", "outcome": "sleeps", "note": ""})


## Keeping watch (decision 621), each tick: after a hard day (a fight since
## she last slept, or under hard_hp), by a fire with her player, once a
## day, nothing hostile in sight, she asks them to keep watch; an answer
## (_answered_watch), or her player standing where they were, within near,
## after answer_ticks, and she sleeps. Asleep:
## her player going past near is noted; a fight wakes her, and if they had
## gone she says so (left_line) and is left_alone; slept out sleep_ticks
## with them by, she wakes whole and rested, and they watched (trust).
func _keep_watch() -> void:
	var rules := _bond_rules("sleep")
	var near := int(rules.get("near", 4))
	if in_fight():
		_hard_day = true
	if World.tick % DEED_EVERY == 0:
		if not safe_to_rest():
			_in_town = false
		elif not _in_town:
			_in_town = true
			_town_since = World.tick
	if order == "watch":
		if not _alive(keeper) or World.distance(tile, keeper.tile) > near:
			_sleeping["left"] = true
		var woke := ""
		if in_fight():
			if _sleeping.get("left", false):
				_ask_voice("You woke to monsters near, and %s had gone off and left you sleeping alone. Say how you take it, in your own words." % keeper_name(), "", true)
				deed.emit("left_alone", "left you sleeping alone")
			woke = "You wake: monsters came near."
		elif World.tick >= int(_sleeping.get("until", 0)):
			if _sleeping.get("left", false):
				woke = "You wake. %s wandered off while you slept, but nothing came." % keeper_name()
			else:
				World.restore(self, max_hp, max_stamina, facing)
				deed.emit("watched", "kept watch while you slept")
				woke = "You wake rested and whole: %s kept watch." % keeper_name()
		if not woke.is_empty():
			order = ""
			_sleeping = {}
			_serial += 1
			_set_stance(DEFAULT_STANCE, _serial, "order")
			_narrate(woke)
		return
	if World.tick % DEED_EVERY != 0 or not _alive(keeper) or not order.is_empty() or _hostile_within(SIGHT_RANGE):
		if _sleeping.has("asked_at") and _hostile_within(SIGHT_RANGE):
			_sleeping = {}  # Something in sight: no sleep now.
		return
	if _sleeping.has("asked_at"):
		if World.tick - int(_sleeping["asked_at"]) >= int(rules.get("answer_ticks", 200)):
			if World.distance(tile, keeper.tile) <= near and keeper.tile == _sleeping.get("their_tile"):
				_sleep()  # Settled by her without a word: they stay.
			else:
				_sleeping = {}
		return
	var day := Townsfolk.day_of(World.steps)
	var reach := int(rules.get("fire_cells", 2))
	if (_watch_day < 0 or day - _watch_day >= int(rules.get("ask_days", 2))) \
			and (_hard_day or hp < max_hp * float(rules.get("hard_hp", 0.7))) and safe_to_rest() and _in_town \
			and World.tick - _town_since >= int(rules.get("ask_after_ticks", 3000)):
		_watch_day = day
		_sleeping = {"asked_at": World.tick, "their_tile": keeper.tile}
		# Her own words, not a fixed line (738): where she is, why, then the ask.
		_ask_voice(("You are worn out after a hard day (%s), here in %s%s, and nothing hostile is near. You'd like to sleep "
			+ "a while if %s keeps watch over you: ask them, in your own words.") % [
				"you fought today" if _hard_day else "%d of %d" % [hp, max_hp], _place_words(),
				", by the fire" if _fire_near(tile, reach) else "", keeper_name()], "", true)


## Whether she may rest or sleep here (decision 738, Jeff: a camp is "not a
## safe place bc the goblins respawn"): she and her player both on safe
## ground (_safe_at). Never a dungeon or the wilds, however quiet they look.
func safe_to_rest() -> bool:
	return _alive(keeper) and _safe_at(tile) and _safe_at(keeper.tile)


## Whether [param cell] is safe ground: town ground (Main's in_town: a town
## store's ground or a town's named room), or a camp a player holds (738
## amended: 739's held camp, occupied and cleared, refills no monster; Jeff:
## "that would be fine if occupancy blocks campfire respawns").
func _safe_at(cell: Vector2i) -> bool:
	return in_town.is_valid() and bool(in_town.call(cell)) or held_camp.is_valid() and bool(held_camp.call(cell))


## Bandaged (decision 621): her ask to rest first is met.
func tended() -> void:
	_deeds["asked_rest"] = false


## While she has asked to rest (decision 621), each tick: the monsters
## already after her or her player, which a blow of her player's on does
## not start a fight.
func _note_engaged() -> void:
	if not _deeds["asked_rest"]:
		return
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster != null and monster.target != null and (monster.target == self or monster.target == keeper):
			_engaged[monster.get_instance_id()] = true


## Her player's blow on [param monster] (Main's, decision 621, the
## coordinator's reading of Jeff's "pressing into a new fight"): one not
## already after them while she is under low_hp and has asked to rest is a
## fight they started: pressed, once, and her ask is spent.
func struck_first(monster: GridEntity) -> void:
	if not _deeds["asked_rest"] or _engaged.has(monster.get_instance_id()):
		return
	_deeds["asked_rest"] = false
	deed.emit("pressed", "pressed on into a fight when you were badly hurt")


## Whether a fire burns within [param reach] cells of [param cell].
func _fire_near(cell: Vector2i, reach: int) -> bool:
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if World.is_fire(cell + Vector2i(dx, dy)):
				return true
	return false


## Her standing order kept (decision 616), each tick: resting she mends,
## and gets up when whole, when a fight starts, or when her player walks
## off; a voice quiet past ORDER_ACK_TICKS is covered by a word of her own.
func _keep_order() -> void:
	if not _hesitant.is_empty() and World.tick >= int(_hesitant["at"]):
		var held := _hesitant
		_hesitant = {}
		_carry_out(held["read"], str(held["text"]))
	if _ack_due >= 0 and World.tick >= _ack_due:
		_ack_due = -1
		if _last_speech_tick < _order_tick:
			_say(ORDER_ACKS[absi(hash(String(name))) % ORDER_ACKS.size()], true)
	_play_on()
	_keep_watch()
	if order != "rest":
		return
	var why := ""
	if in_fight():
		why = "monsters came near"
	elif _alive(keeper) and World.distance(tile, keeper.tile) > REST_LEAVE:
		why = "%s walked on" % keeper_name()
	elif hp >= max_hp:
		why = "you are rested and whole again"
	if why.is_empty():
		if World.tick >= _rest_heal_at:
			_rest_heal_at = World.tick + REST_HEAL_TICKS
			World.heal(self, 1)
		return
	order = ""
	_instruction = ""
	_serial += 1
	_set_stance(DEFAULT_STANCE, _serial, "order")
	_narrate("You get up from your rest: %s." % why)


## A creature died in her sight (Main): an event for the hands, told to
## the voice as narration. [param her_player]: it was the player she
## travels with, who is down until they respawn (its own event). Her voice
## speaks to an ally's death; to a monster's only if it was a big one
## (BIG_MONSTER_MASS), the first of its kind she has seen fall this run, or
## the last of a fight (_watch). [param by]: who struck the last blow, if
## anyone.
func note_death(who: String, her_player := false, entity: GridEntity = null, by: GridEntity = null) -> void:
	if her_player:
		_keeper_down = true
	var monster := entity is Monster
	var big := monster and entity.mass >= BIG_MONSTER_MASS
	var first := monster and not _kinds_fallen.has(kind_of(entity))
	if monster:
		_kinds_fallen[kind_of(entity)] = true
	# One her player brought down is worth a word on the kill (228 amended).
	var theirs := monster and by != null and by == keeper and _alive(keeper)
	var speak := not monster or big or first or theirs
	_fight_notable = _fight_notable or speak
	_deaths.append({"who": who, "told": refer(entity, true) if monster else who, "speak": speak, "monster": monster,
		"by": keeper_name() if theirs else ""})
	_fallen.append({"word": kind_of(entity) if monster else who, "monster": monster})
	if _fallen.size() > 8:
		_fallen.pop_front()
	# What she saw (Main tells her only of deaths she witnessed).
	if not monster:
		note_fact("%s saw %s fall in %s." % [_name_of(self), who, _place_words()])
	elif big:
		note_fact("%s saw %s killed in %s." % [_name_of(self), refer(entity), _place_words()])
	if entity is Animal and by != null and (by == self or by == keeper):
		# A wild animal brought down by her player, or by her (decision 332).
		note_fact("%s brought down %s in %s." % [_name_of(self) if by == self else keeper_name(), _a(kind_of(entity)),
			_place_words()])
	if entity == _quarry:
		_quarry = null


## [param who] (another companion) beaten down and carried off by raiders
## where she saw it (Main, decision 314): a fact about her, and told to her
## exchange, so her voice knows it the next time it speaks.
func note_taken(who: String) -> void:
	note_fact("%s saw %s carried off by raiders in %s." % [_name_of(self), who, _place_words()])
	_narrate("Raiders beat %s down and carried them off." % who)


## Beaten down herself and carried off by raiders (Main, decision 314),
## just before she is taken off the map: a fact about her.
func note_carried_off() -> void:
	note_fact("%s was beaten down and carried off by raiders in %s." % [_name_of(self), _place_words()])


## Downed (decision 544): her player ([param theirs]), else she herself.
## Her player: told, and her voice asked, as at a death.
## [param entity] leaves the world (Main, on World.entity_despawned, before
## it is freed; decision 572): every hold she has on it is let go: her
## player, her target, her quarry, what she stalks, an errand or an offer
## naming it. A freed node read later crashed the box's server: her voice,
## asked after her player died in the barrow, read the freed Player through
## keeper (_wound_words), which the release template dereferences.
func forget(entity: GridEntity) -> void:
	if keeper == entity:
		keeper = null
	if intent_target == entity:
		intent_target = null
	if _quarry == entity:
		_quarry = null
	if _stalked == entity:
		_stalked = null
	if not errand.is_empty() and errand.values().has(entity):
		errand = {}
	# An offer naming it is dropped whole: [DO: n] counts from its list.
	for serial: int in _offered.keys():
		if _offered[serial].any(func(action: Dictionary) -> bool: return action.values().has(entity)):
			_offered.erase(serial)
	if _offering.any(func(action: Dictionary) -> bool: return action.values().has(entity)):
		_offering = []


func note_downed(theirs: bool) -> void:
	if theirs:
		# A charge of her player's to spend, or not (573: the window is every
		# blessed body's, whoever pays).
		var can := can_revive.is_valid() and bool(can_revive.call())
		_narrate("%s is down. %s" % [keeper_name(), "You may bring them back where they lie." if can
			else "You cannot bring them back; someone blessed, with a charge, may."])
		_ask_voice("%s is down." % keeper_name(), "", true)
	else:
		_narrate("You are down, and lie where you fell.")


## [param by] brought [param body] back where they fell (decision 544).
func note_brought_back(by: String, body: String) -> void:
	var me := _name_of(self)
	_narrate("%s brought %s back where %s lay." % ["You" if by == me else by, "you" if body == me else body, "you" if body == me else "they"])
	note_fact("%s brought %s back where they fell in %s." % [by, body, _place_words()])


# --- Sickness (decision 501, companions' side) ---------------------------------------
# npc's Townsfolk keeps her record's "sick" while she rests in town; Main
# ends it in the party (sickness_over) and tells "was_sick" once.

## Her voice's sentence for her record's [param sick] on day [param today]:
## "" when well.
static func sick_sentence(sick: Dictionary, today: int) -> String:
	if sick.is_empty():
		return ""
	var kind := str(sick.get("kind", "a fever"))
	if int(sick.get("treated", -1)) >= 0:
		return "You are sick with %s; %s saw to you, and it is breaking." % [kind, str(sick.get("cured_by", "someone"))]
	var days := today - int(sick.get("since", today))
	var since := "today" if days <= 0 else "yesterday" if days == 1 else "%d days ago" % days
	return "You have been sick with %s since %s; it will pass." % [kind, since]


## Whether [param sick] is over on day [param today] out of town: treated,
## the morning after; untreated, after [param days] (Townsfolk.sick_days).
## She never dies of it.
static func sickness_over(sick: Dictionary, today: int, days: int) -> bool:
	var treated := int(sick.get("treated", -1))
	if treated >= 0:
		return today > treated
	return today - int(sick.get("since", today)) >= days


## The words for a sickness that is over, [param was] (her record's
## "was_sick": since, ended, cured_by, kind), told once: {"log" (the party log),
## "fact" (on her), "narrate" (her exchange)}. [param away]: it was while
## [param keeper] was away from her.
static func sickness_told(her_name: String, keeper: String, object: String, was: Dictionary, away: bool) -> Dictionary:
	var kind := str(was.get("kind", "a fever"))
	var by := str(was.get("cured_by", ""))
	var while_away := " while %s was away" % keeper if away else ""
	var how := "%s saw to %s" % [by, object] if not by.is_empty() else "it ran its course"
	var well: String = {"her": "she is", "him": "he is", "them": "they are"}.get(object, "she is")
	return {
		"log": "%s was sick with %s%s; %s, and %s well again." % [her_name, kind, while_away, how, well],
		"fact": "%s was sick with %s%s; %s." % [her_name, kind, while_away, how],
		"narrate": "You were sick with %s%s; %s. You are well again." % [kind, while_away,
			"%s saw to you" % by if not by.is_empty() else "it ran its course"],
	}


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
	if leaving:
		# Leaving her player for good (decision 581): she walks off to the
		# way out (leaving_to), heeding no one; Main ends it.
		current_intent = Intent.IDLE
		if leaving_to != NONE and tile != leaving_to:
			_step_toward(leaving_to, true)
		return
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
	_keep_order()
	_watch_deeds()
	_note_engaged()
	_calm()
	_tend_unasked()
	_drink_if_low()
	_act()
	if _held_for_bandage():
		current_intent = Intent.IDLE  # Held still while she is bandaged (decision 713): no step to break it.
		if errand.has("until"):
			errand["until"] = int(errand["until"]) + 1  # Her errand's time waits with her.
	else:
		_execute()
	_note_fight()


## Whether she holds her cell this tick because someone else is bandaging
## her (decision 713, items' reach; Jeff's bandage-kneel: "if target moves
## it interrupts"): mending 1 by another's hands, and nothing making her
## move: no blow to dodge, no foe she fights, no fire under her.
func _held_for_bandage() -> bool:
	if mending != 1 or current_intent in [Intent.DODGE, Intent.ATTACK] or World.is_burning(tile):
		return false
	for by: GridEntity in World._bandaging:
		if by != self and (World._bandaging[by] as Dictionary).get("patient") == self:
			return true
	return false


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
	var threats: Array[String] = []
	var arrivals: Array[String] = []
	var danger := ""
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and not _known_hostiles.has(entity.get_instance_id()) and senses.sees(entity):
			_known_hostiles[entity.get_instance_id()] = true
			if _is_wolf(entity):
				_warn_wolves("%s came into sight, %s" % [refer(entity, true), _paces_toward(Vector2(entity.tile))])
			if not _kinds_seen.has(kind_of(entity)):
				# The first of a kind this run: new to her, worth a word.
				_kinds_seen[kind_of(entity)] = true
				new_kind = "%s came into sight, the first %s you have seen here." % [_name_of(entity), kind_of(entity)]
				_fight_notable = true
			# In a fight a sighting is no event; only what changes is.
			if not fight and not _was_in_fight:
				events.append("%s came into sight." % _name_of(entity))
				threats.append("%s came into sight, %s." % [refer(entity, true), _paces_toward(Vector2(entity.tile))])
				if _hostile(entity) and danger.is_empty():
					danger = refer(entity, true)
	for friend in friends_seen():
		if not _known_friends.has(friend.get_instance_id()):
			_known_friends[friend.get_instance_id()] = true
			if not fight and not _was_in_fight:
				var who := _name_of(friend) if friend is Companion else friend_words(friend)
				events.append("%s came into sight." % who)
				arrivals.append("%s came into sight, %s." % [who, _paces_toward(Vector2(friend.tile))])
	# A threat leads (228 amended: an imp closing and a friend arriving in
	# one moment, she offered the friend help with his carpentry): told
	# last, nearest her answer, and named as the danger.
	for told in arrivals + threats:
		_narrate(told)
	if not danger.is_empty() and not arrivals.is_empty():
		_narrate("%s is the danger here; the rest can wait." % danger)
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
	elif not new_kind.is_empty() and not lapsing and _lapsed_from.is_empty() and stalking() == null:
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
		var by := str(death.get("by", ""))
		_narrate("%s brought down %s." % [by, death["told"].left(1).to_lower() + death["told"].substr(1)] if not by.is_empty()
			else "%s fell." % death["told"])
		any_monster = any_monster or death["monster"]
		if death["speak"]:
			spoken.append("%s died, brought down by %s." % [death["who"], by] if not by.is_empty() else "%s died." % death["who"])
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
		if noise["kind"] == &"call" and _is_wolf(noise["source"]):
			_warn_wolves("You hear a wolf howl, %s" % _paces_toward(Vector2(at)))
			continue
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
	if not loud.is_empty() and not in_fight() and stalking() == null and World.tick - _noise_asked_tick >= NOISE_ASK_TICKS:
		_noise_asked_tick = World.tick
		_ask_voice(loud)


## Whether [param entity] is a wolf (a wild predator).
static func _is_wolf(entity: Variant) -> bool:
	return is_instance_valid(entity) and entity is Animal and (entity as Animal).role == Animal.Role.PREDATOR


## Night out under the sky: the sky's light under Animal.NIGHT_LIGHT, when
## wolves are bold (decision 315).
static func is_night() -> bool:
	return World.fields.outdoor and DayNight.daylight(DayNight.now()) < Animal.NIGHT_LIGHT


## A wolf seen or heard ([param seen], how): at night her voice is asked
## to warn her player, at most once in WOLF_WARN_TICKS (decision 332).
func _warn_wolves(seen: String) -> void:
	if not is_night() or World.tick - _wolf_warned_tick < WOLF_WARN_TICKS:
		return
	_wolf_warned_tick = World.tick
	_ask_voice("%s, and it is night, when wolves are bold and hunt people. Warn %s." % [seen, keeper_name()], "", true)


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
	if in_fight():
		_fight_seen_tick = World.tick
		return
	if not standing_instruction().is_empty() or not order.is_empty():
		return
	if World.tick - _fight_seen_tick < hold_ticks("calm_ticks"):
		return  # Calm a moment first (706): a lull in a fight is no calm.
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


## Whether [param entity] is her foe (decision 332): a monster, but of the
## wild only a wolf, a boar going for someone, or the quarry she was set on.
## A monster that talks (the draugr) only while it would fight her or her
## player (551 amended (2): seated unchallenged or at rest, she leaves him be).
func _hostile(entity: GridEntity) -> bool:
	if not entity is Monster or not entity.spawned:
		return false
	if (entity as Monster).talks:
		return _threatens(entity)
	return entity == _quarry or not harmless(entity)


## Wild prey, or game going for no one (decision 332): no foe to her, nor
## danger, unless she is set on it.
static func harmless(entity: GridEntity) -> bool:
	var animal := entity as Animal
	if animal == null:
		return false
	match animal.role:
		Animal.Role.PREDATOR:
			return false
		Animal.Role.GAME:
			return not (animal.target is Player or animal.target is Companion)
	return true


## The wild animal "Get them!" means, with nothing hostile in sight: the
## nearest she sees, or her player does, in front of her player (Senses'
## cone along their facing), else the nearest she sees; null for none.
func _quarry_called() -> GridEntity:
	var ahead: GridEntity = null
	var nearest: GridEntity = null
	for entity in World.get_entities():
		if not entity is Monster or not entity.spawned or World.distance(tile, entity.tile) > SIGHT_RANGE:
			continue
		var seen := senses.sees(entity)
		if not harmless(entity):
			if seen:
				return null  # A fight to be had: "Get them!" means that.
			continue
		var theirs := _alive(keeper) and World.distance(keeper.tile, entity.tile) <= SIGHT_RANGE \
				and World.has_line_of_sight(keeper.tile, entity.tile)
		if not seen and not theirs:
			continue
		var from: Vector2i = keeper.tile if _alive(keeper) else tile
		var d := World.distance(from, entity.tile)
		var facing := Vector2(keeper.facing) if _alive(keeper) else Vector2.ZERO
		var way := Vector2(entity.tile - from)
		if facing != Vector2.ZERO and way != Vector2.ZERO and way.normalized().dot(facing.normalized()) >= Senses.CONE_COS:
			if ahead == null or d < World.distance(from, ahead.tile):
				ahead = entity
		if seen and (nearest == null or d < World.distance(from, nearest.tile)):
			nearest = entity
	return ahead if ahead != null else nearest


## The quarry dropped when gone, out of her sight and her player's, or the
## call lapsed (INSTRUCTION_TICKS).
func _keep_quarry() -> void:
	if _quarry == null:
		return
	if not is_instance_valid(_quarry) or not _quarry.spawned or standing_instruction().is_empty() \
			or not senses.sees(_quarry) and not (_alive(keeper) and World.has_line_of_sight(keeper.tile, _quarry.tile)
				and World.distance(keeper.tile, _quarry.tile) <= SIGHT_RANGE):
		_quarry = null


## The wild animal her player is stalking, or null (decision 332): not in
## a fight, prey or game not running and not her quarry, within sight of her
## player, who has a clear line to it. Worked out once a tick.
func stalking() -> GridEntity:
	if _stalk_tick == World.tick:
		return _stalked if is_instance_valid(_stalked) else null
	_stalk_tick = World.tick
	_stalked = null
	if not _alive(keeper) or in_fight():
		return null
	var best := SIGHT_RANGE + 1
	for entity in World.get_entities():
		var animal := entity as Animal
		if animal == null or not animal.spawned or animal == _quarry or not harmless(animal) \
				or animal.alert == Monster.Alert.FLEEING:
			continue
		var d := World.distance(keeper.tile, animal.tile)
		if d < best and World.has_line_of_sight(keeper.tile, animal.tile):
			_stalked = animal
			best = d
	return _stalked


## Whether she holds her tongue now (decision 675): in a fight, or within
## QUIET_AFTER ticks of one.
func quiet() -> bool:
	if not hold_tongue:
		return false
	_note_fight()
	return World.tick - _fight_tick <= QUIET_AFTER


## Marks this tick a fighting one when she or her player fights (decision
## 675); a fight just begun drops what her voice had waiting.
func _note_fight() -> void:
	if _fight_tick == World.tick:
		return
	if in_fight() or current_intent == Intent.ATTACK or current_intent == Intent.DODGE or current_intent == Intent.RETREAT:
		if World.tick - _fight_tick > QUIET_AFTER:
			_pending_voice = {}
		_fight_tick = World.tick


## Counted in the mind log (decision 675): what she held back, by kind
## ("say", "voice", "heard"), no words, no names.
func _held_tongue(what: String) -> void:
	_log({"kind": "voice", "trigger": what, "outcome": "held tongue", "note": ""})


## Wounds seen to unasked (decision 681): calm, nothing near, her kit to
## hand and nothing asked of her, her hands bandage her hurt player first,
## then herself, through the bandage errand, narrated and not said. A
## refusal she can wait out (hurt just now, not safe) waits; a patient
## not to be bandaged (no wound, mending) is passed over.
func _tend_unasked() -> void:
	if not tends_unasked or World.tick % TEND_EVERY != 0 or World.tick < _tend_after:
		return
	if not errand.is_empty() or not order.is_empty() or not _hesitant.is_empty() or World.is_downed(keeper):
		return
	if World.bandage_kit(self) < 0 or not World.calm(self) or in_fight():
		return
	for patient: GridEntity in [keeper, self]:
		if not _wants_tending(patient):
			continue
		if patient != self and (patient.zone != zone or World.distance(tile, patient.tile) > PERCEPTION_RANGE or not senses.sees(patient)):
			continue
		var no := World.bandage_refusal(self, patient)
		if no == "hurt_now" or no == "not_safe" or no == "busy":
			return
		if no == "" or no == "not_beside":
			var own := patient == self
			_start_errand({"verb": "bandage", "patient": patient, "at": patient.tile, "unasked": true,
				"words": "tend your own wounds" if own else "tend your player's wounds"}, _serial)
			_narrate("Unasked, you set about bandaging %s." % ("your own wounds" if own else "%s's wounds" % keeper_name()))
			return


## Low (under REMEDY_BELOW of her hp), she drinks a remedy she carries
## (681, the remedy; the coordinator: "she drinks it herself"): not while
## one is still healing her (World.buff "heal"), nor with a blow wound up,
## and bleeding with a bandage she could begin now, the bandage first.
## Narrated, never said: it is mostly in a fight (675).
func _drink_if_low() -> void:
	if not tends_unasked or max_hp <= 0 or hp <= 0 or float(hp) >= REMEDY_BELOW * max_hp or World.buff(self, "heal") > 0.0:
		return
	if not World.winding(self).is_empty() or World.is_downed(self):
		return
	if ailments.has("bleed") and World.bandage_refusal(self, self) == "":
		return
	for slot in slots.size():
		if is_remedy(slots[slot]) and World.try_use(self, slot):
			_narrate("Badly hurt, you drank a healing remedy.")
			_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": "drink a remedy", "outcome": "done", "note": "hp %d of %d" % [hp, max_hp]})
			return


## Whether item [param id] is a remedy: used, it heals over time (an
## effect of kind "heal", 682).
static func is_remedy(id: String) -> bool:
	if id.is_empty():
		return false
	for effect: Dictionary in Items.def(id).get("effects", []):
		if str(effect.get("kind", "")) == "heal":
			return true
	return false


## Whether [param patient] wants bandaging (decision 681): hurt, not
## already mending, and under TEND_BELOW of their hp or bleeding.
func _wants_tending(patient: GridEntity) -> bool:
	if not _alive(patient) or patient.hp <= 0 or patient.hp >= patient.max_hp or patient.mending != 0:
		return false
	return float(patient.hp) < TEND_BELOW * patient.max_hp or patient.ailments.has("bleed")


## A hostile within COMBAT_RANGE of her or her player.
func in_fight() -> bool:
	return _hostile_within(COMBAT_RANGE)


func _hostile_within(reach: int) -> bool:
	var player_here := _alive(keeper)
	for entity in World.get_entities():
		if _hostile(entity) and (World.distance(tile, entity.tile) <= reach
				or player_here and World.distance(keeper.tile, entity.tile) <= reach):
			return true
	return false


## How things stand, to tell what changed: the hostiles next to her or her
## player, and which HP_THRESHOLDS band each of them is in.
func _situation_now() -> Dictionary:
	var player_here := _alive(keeper)
	var adjacent: Array[int] = []
	for entity in World.get_entities():
		if _hostile(entity) and (World.distance(tile, entity.tile) == 1
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
	if quiet():
		_held_tongue("heard" if not heard.is_empty() else "voice")  # Dropped, never queued (decision 675).
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
	if _reask_next:
		_reask_serials[_serial] = true
		_reask_next = false
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
			"system": CompanionFacts.EXTRACT_SYSTEM % [me, who, me, who, who], "user": grown.extract_prompt(card, talk, Companion.lore_words(me))}
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
		# What is said of the world is no longer taken here: she hears it as
		# hearsay, weighed by her intellect (decision 442).
		entry["outcome"] = "added" if not added.is_empty() else ("nothing new" if not answer.is_empty() else "no answer")
	entry["note"] = " | ".join(added)
	_log(entry)
	facts_changed.emit()


## Her voice's world: STONE_WORLD or OPEN_WORLD by the zone, the place's
## name, then VOICE_WORLD.
func where_world() -> String:
	return "%s This place is %s.%s\n%s" % [OPEN_WORLD if World.outdoor else STONE_WORLD, _place_words(), town_words(), VOICE_WORLD]


## Whether a town is here (a store place in this zone's Holdings), and
## whether she stands on its ground (decision 400: "It's safer here in
## town" got "I do not know what town you mean"); "" for none. The town
## has no name of its own yet (lore's A1), so it is "the town".
func town_words() -> String:
	if World.holdings == null or World.zone == null:
		return ""
	var towns := World.holdings.places_in(World.zone.name).filter(func(id: String) -> bool:
		return World.holdings.place(id).get("kind") == "stockpile")
	if towns.is_empty():
		return ""
	if not Stockpile.place_at(World.holdings, World.zone.name, tile).is_empty():
		return " There is a town here, and you are in it."
	return " There is a town here."


## Her home town in words (decision 381), "" for none: where she rests
## between trips and her trade there; there now, that she knows it well.
func standing_words() -> String:
	var zone := str(home.get("zone", ""))
	if zone.is_empty():
		return ""
	var here := World.zone != null and World.zone.name == zone
	var trade := str(home.get("trade", ""))
	# "the town" (it has no name yet): its zone's name alone read as no town.
	var out := "You rest in the town %s %s between trips%s." % ["here in" if here else "in", place_name(zone),
		", and work there as %s" % _a(trade) if not trade.is_empty() else ""]
	if here:
		out += " You know that town well."
	return out


## What lore says [param who] knows of the world (decision 381): her own
## knower (a companion lore names: Wren, Pip, Nix), else the townsfolk's;
## agreed facts only, weightiest first, within LORE_CHARS, a rumour as what
## is said. "" for none.
static func lore_words(who: String, about := PackedStringArray()) -> String:
	var knower := who.to_lower() if Lore.knowers().has(who.to_lower()) else "townsfolk"
	var by_weight := func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"])
	# What is in sight or was asked about first (decision 400: "what is a
	# stag" fell past the 600 characters), then the rest by weight.
	var facts: Array[Dictionary] = []
	if not about.is_empty():
		facts = Lore.known_by(knower, about, "agreed")
		facts.sort_custom(by_weight)
	var rest := Lore.known_by(knower, PackedStringArray(), "agreed")
	rest.sort_custom(by_weight)
	var ids := facts.map(func(fact: Dictionary) -> String: return str(fact["id"]))
	facts.append_array(rest.filter(func(fact: Dictionary) -> bool: return str(fact["id"]) not in ids))
	var said: Array[String] = []
	var length := 0
	for fact in facts:
		var text := str(fact["text"]).strip_edges()
		if bool(fact.get("hearsay", false)):
			text = "It is said that %s" % (text.left(1).to_lower() + text.substr(1))
		if length + text.length() > LORE_CHARS:
			continue
		length += text.length() + 1
		said.append(text)
	return "What you know of the world: %s" % " ".join(said) if not said.is_empty() else ""


## A zone's shown name ("The Castle"), its own name when it has none.
## What her lore facts should start with (decision 400): the kinds of
## creature she sees, the things asked about, and this place.
func lore_topics(things: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for thing in things:
		if thing.get("monster", false) and str(thing["kind"]) not in out:
			out.append(str(thing["kind"]))
	var said := keeper_said()
	for kind in _asked_in(said):
		if kind not in out:
			out.append(kind)
	# A lore entry her player named ("what is a stag?").
	for id: String in Lore.entries():
		if id not in out and not said.is_empty() and RegEx.create_from_string("\\b%ss?\\b" % id.replace("_", " ")).search(said) != null:
			out.append(id)
	if World.zone != null:
		out.append(World.zone.name)
	return out


static func place_name(zone_name: String) -> String:
	if not _place_names.has(zone_name):
		know_level(zone_name, Level.load_level(zone_name) if Level.exists(zone_name) else {})
	return _place_names[zone_name]


## What she reads of level [param zone_name] (its name, kind of place and
## buildings), from [param level] as Level.load_level gives it: Main hands
## her each level it loads, so she parses none in play (perf: a first turn
## in a zone parsed it again, 145 ms). One she was not handed is read once.
static func know_level(zone_name: String, level: Dictionary) -> void:
	var shown := str(level.get("display_name", ""))
	_place_names[zone_name] = shown if not shown.is_empty() else zone_name.replace("_", " ")
	_zone_kinds[zone_name] = str(level.get("terrain", {}).get("zone", "indoors"))
	var buildings: Array = level.get("buildings", [])
	var inside: Dictionary = level.get("building_cells", Level.inside_cells(buildings))
	var cells: Dictionary[Vector2i, Dictionary] = {}
	for cell: Vector2i in inside:
		var building: Dictionary = buildings[inside[cell]]
		if BUILDING_WORDS.has(str(building.get("slot", ""))) or building.has("kind"):
			cells[cell] = building
	_zone_buildings[zone_name] = cells


static func _zone_kind(zone_name: String) -> String:
	if not _zone_kinds.has(zone_name):
		know_level(zone_name, Level.load_level(zone_name) if Level.exists(zone_name) else {})
	return _zone_kinds[zone_name]


## Where she is, for a fact: the level's name ("the castle").
static var _place_names: Dictionary[String, String] = {}


func _place_words() -> String:
	return place_name(World.zone.name if World.zone != null else "")


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
	_sky_asked = asks_about_sky(heard)
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
	# What she has heard of the world and believes, as hearsay (decision 442).
	var rumours := Hearsay.prompt_words(self.heard)
	if not rumours.is_empty():
		met += " " + rumours
	var bond := str(bond_words.call()) if bond_words.is_valid() else ""
	if not bond.is_empty():
		met += " " + bond
	var sick := str(sick_words.call()) if sick_words.is_valid() else ""
	if not sick.is_empty():
		met += " " + sick
	var leans := focus_words()
	if not leans.is_empty():
		met += " " + leans
	var roads := str(guide_words.call()) if guide_words.is_valid() else ""
	if not roads.is_empty():
		met += " " + roads
	if not guide_note.is_empty():
		now.append(guide_note)
		guide_note = ""
	var scouted := scouted_words()
	if not scouted.is_empty():
		now.append(scouted)
	var standing := standing_words()
	if not standing.is_empty():
		met += " " + standing
	var known := Companion.lore_words(_name_of(self), lore_topics(things))
	var system := "%s %s%s%s\n\n%s%s\n\nNow: %s\n\n%s%s" % [identity(), card, met, instructed, where_world(),
		"\n" + known if not known.is_empty() else "", " ".join(now),
		around + "\n\n" if not around.is_empty() else "", VOICE_RULES % [who, who, who]]
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
			system += "\n" + VOICE_ASKED % [who, who, who, who, who]
			if addressed == "her":
				system += "\n" + VOICE_FELT % [who, who]
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
	if not _repeat_note.is_empty():
		system += "\n\nYou have just said \"%s\" already: never say it again. Say something new about what just happened, or answer with just: ..." % _repeat_note
		_repeat_note = ""
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
		Intent.REST:
			action = "resting, as %s asked" % keeper_name()
		Intent.SLEEP:
			action = "asleep by the fire, while %s keeps watch" % keeper_name()
		Intent.DODGE:
			action = "leaping clear of %s" % _dodge_from
		Intent.ERRAND:
			action = "on your way to %s" % errand.get("words", "do what you were asked")
		Intent.GUIDE:
			action = "leading %s to %s" % [keeper_name(), guide.goal.get("name", "where they asked") if guide != null else "where they asked"]
		_:
			action = "keeping by %s" % keeper_name()
	return "You are %s; right now you are %s." % [words, action]


## The hour and the weather in words: DayNight's (describe, decision 389),
## kept here by name for those that read them from Companion.
const HOURS := DayNight.HOURS
const WEATHER_WORDS := DayNight.WEATHER_WORDS


static func time_words(hour: float) -> String:
	return DayNight.time_words(hour)


## Words that ask about the hour or the sky: then her voice is told them
## in full (where_words). Otherwise only a storm: told every time, a voice
## brought the sky up in 10 of 24 lines unasked, and still 6 when told to
## leave it out; told the night, in most lines at night. The night reaches
## her when it matters, with the wolves (_warn_wolves).
const SKY_WORDS := "(?i)\\b(time|hour|late|early|day|night|dark\\w*|light|dawn|dusk|morning|evening|noon|midday|sun\\w*|moon|stars?|sky|weather|rain\\w*|wet|fog\\w*|mist\\w*|storm\\w*|wind\\w*|cloud\\w*|cold|warm)\\b"
## Whether the words her voice answers now ask about the hour or the sky.
var _sky_asked := false
## The kind of place this zone is (level.json's "zone", DayNight.ZONES),
## by zone name, read once.
static var _zone_kinds: Dictionary[String, String] = {}


## Where she is and the hour, for her voice, in one sentence: outdoors
## under the sky (or inside a building, or under a roof there) with the
## season and the weather (DayNight.describe, decision 391), indoors, in a
## cave or a dungeon.
func where_words(full := true) -> String:
	var hour := time_words(DayNight.hour(DayNight.now()))
	if not full:
		return _where_briefly()
	if World.outdoor:
		var now: String = DayNight.describe(World.fields.region, DayNight.now())["sentence"]
		var outside := now.left(1).to_lower() + now.substr(1)
		var inside := inside_words()
		if not inside.is_empty():
			return "%s; outside, %s" % [inside, outside]
		if World.fields.outdoor and not World.fields.under_sky(tile):
			return "You are under a roof; outside, %s" % outside
		return "%s You are outdoors, under the sky, with forest all around the edge of this place." % now
	if not inside_words().is_empty():
		return "%s; outside it is %s." % [inside_words(), hour]
	match _zone_kind(World.zone.name if World.zone != null else ""):
		"cave":
			return "You are in a cave; outside it is %s." % hour
		"dungeon":
			return "You are in a dungeon, under the ground; above it is %s." % hour
		_:
			return "You are indoors; outside it is %s." % hour


## where_words when nothing asked about the hour or the sky: the place,
## and a storm.
func _where_briefly() -> String:
	if World.outdoor:
		var storm := " A storm is raging." if str(World.fields.weather.get("kind", "")) == "storm" else ""
		var inside := inside_words()
		if not inside.is_empty():
			return "%s.%s" % [inside, storm]
		if World.fields.outdoor and not World.fields.under_sky(tile):
			return "You are under a roof.%s" % storm
		return "You are outdoors, under the sky, with forest all around the edge of this place.%s" % storm
	if not inside_words().is_empty():
		return inside_words() + "."
	match _zone_kind(World.zone.name if World.zone != null else ""):
		"cave":
			return "You are in a cave."
		"dungeon":
			return "You are in a dungeon, under the ground."
		_:
			return "You are indoors."


## Buildings in words, by slot, their size said (decision 391: inside
## Pip's house she was told she was outdoors, under the sky).
const BUILDING_WORDS := {"building.hut": "a small hut", "building.house": "a house", "building.shed": "a shed",
	"building.temple": "the temple", "building.healers_hut": "the healer's hut"}
## Each zone's inside cells -> the building there (Level's "building_cells",
## decision 488: a building of blocks is in by any of its cells), by zone
## name, read once.
static var _zone_buildings: Dictionary[String, Dictionary] = {}


## The building whose inside holds [param cell] in this zone (Level's
## {slot, rect, use, town, ...}), {} for none.
static func building_at(cell: Vector2i) -> Dictionary:
	var zone_name := World.zone.name if World.zone != null else ""
	if not _zone_buildings.has(zone_name):
		know_level(zone_name, Level.load_level(zone_name) if Level.exists(zone_name) else {})
	return _zone_buildings[zone_name].get(cell, {})


## [param building] in words: what the town uses it for ("the forge"),
## else its kind by size ("a small hut"), and whose home it is when a
## resident's is ("Snagfin's home"): "the forge (a small hut)", "a house
## (Snagfin's home)".
static func building_words(building: Dictionary) -> String:
	var kind := str(BUILDING_WORDS.get(str(building.get("slot", "")), building.get("words", "a building")))
	var use := str(building.get("use", ""))
	var words := "the %s (%s)" % [use.replace("_", " "), kind] if not use.is_empty() and not kind.begins_with("the ") else kind
	var owners: Array[String] = []
	for body: GridEntity in World.townsfolk():
		var resident := body as Resident
		if resident != null and resident.places.get("home") == building["rect"]:
			var who := resident.person if not resident.person.is_empty() else _name_of(resident)
			if who not in owners:
				owners.append(who)
	if not owners.is_empty():
		words += " (%s's home)" % " and ".join(owners)
	return words


## "You are inside a house (Snagfin's home)" when she stands in a
## building, else "".
func inside_words() -> String:
	var building := building_at(tile)
	return "" if building.is_empty() else "You are inside %s" % building_words(building)


## The short name of [param building], for an errand: "the forge", "the hut".
static func building_short(building: Dictionary) -> String:
	var use := str(building.get("use", ""))
	if not use.is_empty():
		return "the " + use.replace("_", " ")
	return "the " + str(building.get("slot", "building.building")).trim_prefix("building.").replace("_", " ").replace("healers", "healer's")


## Whether [param heard] asks about the hour or the sky (SKY_WORDS).
static func asks_about_sky(heard: String) -> bool:
	return not heard.is_empty() and RegEx.create_from_string(SKY_WORDS).search(heard) != null


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
	var wounds := _wound_words()
	if not wounds.is_empty():
		sentences.append(wounds)
	var stalked := stalking()
	if stalked != null:
		sentences.append("%s is stalking %s, %s, which has not run; keep still and quiet so as not to startle it." % [
			who, refer(stalked), _paces_toward(Vector2(stalked.tile))])
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
	sentences.append(where_words(_sky_asked))
	return " ".join(sentences)


## Wounds, for her voice (decision 320), when she or her player is hurt:
## a bandaging under way or mending, and for the rest whether she carries
## a kit (or her player does) and whether it is safe to bandage now
## (World.calm); and whether either bleeds or burns (World.afflict,
## decision 375: a bandage stops bleeding). "" when neither is hurt or ailing.
func _wound_words() -> String:
	var who := keeper_name()
	var told: Array[String] = []
	# Her player only while alive: a freed node never goes into a typed
	# variable (decision 572).
	var both: Array[GridEntity] = [self]
	if _alive(keeper):
		both.append(keeper)
	for each in both:
		for kind: String in AILING:
			if each.ailments.has(kind):
				told.append(("You are %s." if each == self else who + " is %s.") % AILING[kind])
	var open_wounds: Array[GridEntity] = []
	for each in both:
		if each.hp >= each.max_hp:
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
	return _asked_in(keeper_said())


## Her player's last line to her, lower case ("" for none).
func keeper_said() -> String:
	var said := ""
	for turn in _exchange:
		if turn["role"] == "user" and not str(turn["text"]).begins_with("[") \
				and str(turn.get("speaker", keeper_name())) == keeper_name():
			said = str(turn["text"]).to_lower()
	return said


func _asked_in(said: String) -> Array[String]:
	const WORDS := {
		"fire": "fire|flame|burn", "water": "water|pool|lake|river", "stair": "stair|steps",
		"ledge": "ledge|drop|edge|cliff", "door": "door", "crate": "crate|box", "boulder": "boulder|rock",
		"cart": "cart", "chest": "chest", "torch": "torch",
	}
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
	# Kept for the tick, from where she stands: a kill asked her stance and
	# her voice, and her line's surroundings, each seeing the same cells
	# again (228 amended; perf: slow ticks on kills).
	if _seen_cells_tick != World.tick or _seen_cells_from != tile:
		_seen_cells.clear()
		_seen_cells_tick = World.tick
		_seen_cells_from = tile
	if not _seen_cells.has(cell):
		_seen_cells[cell] = senses.sees_cell(cell, DARK)
	return _seen_cells[cell]


## The cells _sees worked out this tick, and from where.
var _seen_cells: Dictionary[Vector2i, bool] = {}
var _seen_cells_tick := -1
var _seen_cells_from := Vector2i(-99999, -99999)


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
	# A voice on the Claude API (decision 363): which model answered, what it cost, and why her own did.
	for measure: String in ["model", "tokens_in", "tokens_out", "est_cost", "fallback"]:
		if result.has(measure):
			entry[measure] = result[measure]
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
	var hurt := str(answer.get("felt", ""))
	if spoken_to and hurt in ["hurt", "sorry"]:
		entry["felt"] = hurt
		felt.emit(hurt)  # Harsh words, or sorry for them (decision 621): Main's.
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
	var second_try: bool = _reask_serials.get(serial, false)
	_reask_serials.erase(serial)
	if not second_try and speaks_for(raw_line):
		# Words put in her player's mouth: asked once more, this line unsaid.
		entry["outcome"] = "asked again"
		entry["say_dropped"] = raw_line
		entry["note"] = "spoke for her player"
		_log(entry)
		_reask_next = true
		_ask_voice(str(result.get("trigger", "")), str(result.get("heard", "")), true, false, true, report)
		_reask_next = false
		return
	# A whole line said back is dropped as such; then what is left of it
	# once cleaned (spoken) is what she says.
	var echo := _echo_of(raw_line)
	# Her things may be spoken of when asked about, told of in a report, or
	# given or fetched.
	var items_told: bool = asks_about_items(str(result.get("heard", ""))) or report or chosen >= 0 and offered[chosen].has("item")
	if echo == "her own line" and not second_try and not spoken_to:
		# Her own line again, to something new (228 amended: three moments
		# lost so at 21:56): asked once more, told not to say it.
		entry["outcome"] = "asked again"
		entry["say_dropped"] = raw_line
		entry["note"] = "echoes her own line"
		_log(entry)
		_repeat_note = raw_line
		_reask_next = true
		_ask_voice(str(result.get("trigger", "")), str(result.get("heard", "")), true, false, true, report)
		_reask_next = false
		return
	var line := "" if not echo.is_empty() else trim_line(spoken(raw_line, items_told, spoken_to))
	if echo.is_empty() and line != raw_line:
		entry["say_raw"] = raw_line
	var we_should := not spoken_to and RegEx.create_from_string(WE_SHOULD).search(line) != null
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
	elif we_should and World.tick - _we_should_tick < WE_SHOULD_TICKS:
		entry["outcome"] = "dropped"
		entry["say_dropped"] = line
		entry["note"] = "what we should do, unasked, within %d ticks of the last" % WE_SHOULD_TICKS
		line = ""
	elif not _say(line, always):
		entry["outcome"] = "dropped"
		entry["say_dropped"] = line
		entry["note"] = "within %d ticks of her last line" % SPEECH_INTERVAL_TICKS
		line = ""
	entry["say"] = line
	if we_should and not line.is_empty():
		_we_should_tick = World.tick
	if chosen >= 0:
		entry["do"] = offered[chosen]["words"]
	_log(entry)
	if chosen >= 0:
		_start_errand(offered[chosen], serial)


func _set_stance(wanted: int, serial: int, source: String) -> void:
	_stance_serial = serial
	last_mind = source
	_door_asked = false
	if wanted == stance:
		return
	stance = wanted as Stance
	if stance == Stance.HOLD:
		hold_tile = tile
	print("[mind] %s (%s): stance %s" % [name, source, stance_name()])


## Says [param line] (over her, to everyone) unless the rate limit holds it
## back; [param always] for an answer to her player and her own notices.
func _say(line: String, always: bool) -> bool:
	if World.is_downed(self):
		return false  # Downed (decision 544): no word.
	if quiet():
		_held_tongue("say")  # A fight (decision 675): dropped, an answer that came back mid-fight too.
		return false
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
## Whether [param line] speaks for her player (SPEAKS_FOR, any sentence).
static func speaks_for(line: String) -> bool:
	var voiced := RegEx.create_from_string(SPEAKS_FOR)
	for sentence in _sentences(line):
		if voiced.search(sentence.strip_edges()) != null:
			return true
	return false


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
	var voiced := RegEx.create_from_string(SPEAKS_FOR)
	var items := RegEx.create_from_string("(?i)" + OWN_ITEMS)
	var name_list := RegEx.create_from_string(NAME_LIST)
	var kept: Array[String] = []
	var to := ""
	for raw in _sentences(text):
		var sentence := raw.strip_edges()
		var plain := _plain(sentence)
		if not asked and name_list.search(sentence) != null:
			continue  # Only names, unasked: a list echoed from her prompt (decision 574).
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
		if sentence.is_empty() or narration.search(sentence) != null or voiced.search(sentence) != null:
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
	_keep_quarry()
	var foe := _adjacent_hostile()
	var low := max_hp > 0 and float(hp) / max_hp < _retreat_below()
	if current_intent == Intent.YIELD and World.tick < _yield_until and not (low and foe != null) and not _yielded_free():
		return
	intent_target = null
	_door_hold = NONE
	if guide != null and guide.going() and (foe != null or low):
		_guide_ends("danger" if foe != null else "hurt")
	var dodge := _read_telegraphs(before_target)
	if dodge != NONE:
		_dodged_tick = World.tick
	if dodge == NONE and before == Intent.DODGE and World.tick - _dodged_tick < hold_ticks("dodge_ticks") \
			and foe == null and not low and not _stands_over() and not _reviving():
		# Clear of it a moment (706): not back into a blow's way, or her
		# player's bow line, the tick it reads clear.
		current_intent = Intent.DODGE
		intent_target = before_target
	elif dodge != NONE and not _stands_over():
		# A blow coming down on her cell (decision 663): clear of it first.
		# Devoted over her downed player she stays and takes it.
		_dodge_to = dodge
		current_intent = Intent.DODGE
		intent_target = before_target
		if before != Intent.DODGE:
			_narrate("You leap clear of %s." % _dodge_from)
	elif _reviving():
		# Her player downed (decision 544): a foe at her fought off, then to them.
		_fight_or(foe, Intent.REVIVE)
	elif _stands_over():
		# Devoted (decision 555): she stands over her downed player, low or not.
		_fight_or(foe, Intent.HOLD)
	else:
		_choose(foe, low)
	asleep = current_intent == Intent.SLEEP
	if current_intent != before or intent_target != before_target:
		print("[mind] %s: %s%s (%s)" % [name, intent_name(),
			" " + String(intent_target.name) if intent_target != null else "", stance_name()])


## Whether she can bring her downed player back (decision 544): they lie
## downed and Main's can_revive says she may.
func _reviving() -> bool:
	return _alive(keeper) and World.is_downed(keeper) and can_revive.is_valid() and bool(can_revive.call())


## Her intent, her player up: the reflex, an errand, a door, her stance.
func _choose(foe: GridEntity, low: bool) -> void:
	# Bandaging herself, low, with nothing at her: she keeps at it.
	var mending_self: bool = str(errand.get("verb", "")) == "bandage" and errand.get("patient") == self and foe == null
	if low and not mending_self:
		if not errand.is_empty():
			if str(errand.get("verb", "")) == "bandage":
				_say_bandage("low", errand.get("patient"))  # Said, not only narrated (decision 625; the box's one undone bandage).
			_end_errand("you are badly hurt", false)
		current_intent = Intent.RETREAT
	elif _on_errand():
		current_intent = Intent.ERRAND
	elif guide != null and guide.going():
		current_intent = Intent.GUIDE  # Leading her player somewhere (decision 551).
	elif order == "watch" and foe == null:
		current_intent = Intent.SLEEP  # Asleep while her player keeps watch (621 amended).
	elif order == "rest" and foe == null:
		current_intent = Intent.REST  # Asked to rest (decision 616), awake.
	elif bond_at_least("devoted") and stance != Stance.HOLD and stance != Stance.PULL_BACK and _at_keeper() != null:
		# Devoted (decision 621, Jeff's "protects you aggressively"): she
		# goes first at whatever is attacking her player.
		_fight_or(_at_keeper(), Intent.FOLLOW)
	elif _holds_door(foe):
		pass
	elif hangs_back() and (stance == Stance.GUARD or stance == Stance.PRESS):
		# Wary or worse (decision 555): only what is at her, or after them.
		_fight_or(foe if foe != null else _after_us(), Intent.FOLLOW)
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


## A door to hold (_door_to_hold), asked or, guarding or pressing, of her
## own choice: she stands in it and fights what comes at her there. True
## if she does; the ask lapses once there is none.
func _holds_door(foe: GridEntity) -> bool:
	if not _door_asked and (stance != Stance.GUARD and stance != Stance.PRESS or hangs_back()):
		return false
	var door := _door_to_hold()
	if door == NONE:
		_door_asked = false
		return false
	_door_hold = door
	_fight_or(foe, Intent.HOLD)
	return true


# --- Her bond in what she does (decision 555) ---------------------------------

## The steps of her bond, coldest first (Main sets bond_step to one).
const STEPS: Array[String] = ["apart", "sullen", "wary", "cooling", "fond", "close", "devoted"]


## The rules: companion_traits.json "loyalty".
static func loyalty() -> Dictionary:
	var table: Variant = CompanionCard.tables().get("loyalty", {})
	return table if table is Dictionary else {}


## Whether her bond is at [param step] or warmer.
func bond_at_least(step: String) -> bool:
	return STEPS.find(bond_step) >= STEPS.find(step)


## What her focus does (decision 577) as a multiplier on [param kind]
## ("fight", "magic", "stealth"): the rules' base + per share x her share /
## 100 (0.8 + 0.4 x: an even split ~0.93, all in one 1.2); 1.0 unset.
## What enemy-ai's fights read.
func focus_of(kind: String) -> float:
	if not focus.has(kind):
		return 1.0
	var rate: Array = CompanionCard.focus_rules().get("multiplier", [0.8, 0.4])
	return float(rate[0]) + float(rate[1]) * float(focus[kind]) / 100.0


## Her lean, in her voice's world: one sentence, "" unset.
func focus_words() -> String:
	if focus.is_empty():
		return ""
	return str(CompanionCard.focus_rules().get("words", {}).get(CompanionCard.lean_of(focus), ""))


## Wary or colder: she hangs back, joins late, flees sooner.
func hangs_back() -> bool:
	return not bond_at_least("cooling")


## The hp fraction under which she pulls back: retreat_below hanging back,
## else REFLEX_BELOW.
func _retreat_below() -> float:
	return float(loyalty().get("retreat_below", 0.5)) if hangs_back() else REFLEX_BELOW


## Devoted, with her player lying downed within 2 cells: she stands over them.
func _stands_over() -> bool:
	return bond_at_least("devoted") and is_instance_valid(keeper) and keeper.spawned and World.is_downed(keeper) \
		and World.distance(tile, keeper.tile) <= 2


## The nearest hostile in sight going for her player; null for none.
func _at_keeper() -> GridEntity:
	if not _alive(keeper):
		return null
	var best: GridEntity = null
	var best_distance := SIGHT_RANGE + 1
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster == null or monster.target != keeper or not _hostile(monster) or _out_of_reach(monster):
			continue
		var distance := World.distance(tile, monster.tile)
		if distance < best_distance:
			best = monster
			best_distance = distance
	return best


## The nearest hostile in sight going for her or her player; null for none.
func _after_us() -> GridEntity:
	var best: GridEntity = null
	var best_distance := SIGHT_RANGE + 1
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster == null or not _hostile(monster) or _out_of_reach(monster) or monster.target == null:
			continue
		var distance := World.distance(tile, monster.tile)
		if (monster.target == self or monster.target == keeper) and distance < best_distance:
			best = monster
			best_distance = distance
	return best


## [param by] would put [param uid] in her hands or pack (World.try_transfer),
## [param back] (0 none) coming out to them: why she won't take it, said in
## the party log, or "" if she takes it. Food she always takes. Grave goods
## (items' World.items.is_grave) she won't touch below close at
## grave_superstition. Sullen or colder, she takes only food and a gift (a
## thing of gear into a free slot, nothing back): no loads, no swaps.
func turns_down(by: GridEntity, uid: int, back: int) -> String:
	if by == self or uid == 0 or World.items == null:
		return ""
	var id := World.items.id_of(uid)
	if str(Items.def(id).get("use", "")) == "eat":
		return ""
	var why := ""
	if World.items.has_method("is_grave") and bool(World.items.call("is_grave", uid)) \
			and superstition >= int(loyalty().get("grave_superstition", 6)) and not bond_at_least("close"):
		why = "%s won't touch grave goods" % name
	elif not bond_at_least("wary") and (back != 0 or not Items.is_gear(id)):
		why = "%s won't carry that for %s" % [name, keeper_name()]
	if not why.is_empty() and party_log != null:
		party_log.add("%s." % why)
	return why


func _fight_or(foe: GridEntity, otherwise: Intent) -> void:
	if foe != null:
		_held_foe = foe
		_held_foe_tick = World.tick
	elif _alive(_held_foe) and World.tick - _held_foe_tick < hold_ticks("foe_ticks") and _hostile(_held_foe) \
			and World.distance(tile, _held_foe.tile) <= SIGHT_RANGE and not _out_of_reach(_held_foe) and senses.sees(_held_foe):
		foe = _held_foe  # Kept a moment (706): its going for us flickers, her fight does not.
	current_intent = Intent.ATTACK if foe != null else otherwise
	intent_target = foe


## A hold (decision 706) from the rules' "holds" table, in ticks.
static func hold_ticks(key: String) -> int:
	return int(CompanionCard.tables().get("holds", {}).get(key, 0))


## Below REFLEX_BELOW of her hp with a hostile next to her.
func _reflex_active() -> bool:
	return max_hp > 0 and float(hp) / max_hp < REFLEX_BELOW and _adjacent_hostile() != null


func _adjacent_hostile() -> GridEntity:
	for entity in World.get_entities():
		if _hostile(entity) and World.distance(tile, entity.tile) == 1:
			return entity
	return null


## GUARD's foe: the nearest hostile within GUARD_RANGE of her or her
## player, or one in sight going for either of them.
func _guard_target() -> GridEntity:
	var best: GridEntity = null
	var best_distance := 999
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster == null or not _hostile(monster) or _out_of_reach(monster):
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
		if _hostile(entity) and not _out_of_reach(entity):
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
	if not _danger.is_empty() and current_intent != Intent.DODGE and current_intent != Intent.RETREAT:
		# A telegraph showing (decision 663): she steps into none of it; she
		# strikes from where she stands if she can, else waits it out.
		if current_intent == Intent.ATTACK and _alive(intent_target) and World.in_reach(self, intent_target):
			World.try_attack(self, intent_target)
		return
	match current_intent:
		Intent.FOLLOW:
			_follow()
		Intent.RETREAT:
			_retreat()
		Intent.HOLD:
			var spot := _door_hold if _door_hold != NONE else hold_tile
			if tile != spot and World.is_free(spot):
				_step_toward(spot, true)
		Intent.ATTACK:
			if not _alive(intent_target):
				current_intent = Intent.FOLLOW
				intent_target = null
			elif World.in_reach(self, intent_target):
				World.try_attack(self, intent_target)
			else:
				_close_in(intent_target)
		Intent.YIELD:
			if _yield_tile != NONE and tile != _yield_tile and World.is_free(_yield_tile):
				_step_toward(_yield_tile, false)
		Intent.ERRAND:
			_errand_step()
		Intent.REVIVE:
			_revive_step()
		Intent.GUIDE:
			var why := guide.step(guide_routes.call() if guide_routes.is_valid() else null, _threatens)
			if not why.is_empty():
				_guide_ends(why)
		Intent.DODGE:
			if tile != _dodge_to:
				_step_toward(_dodge_to, false)
		Intent.IDLE, Intent.SHOVE:
			pass


## Her player drawing a bow (663 amended, Jeff: "nocking and aiming an
## arrow should alert the companion to stay out of the firing cone"): the
## cells of its cone into _danger (from their cell along their facing, the
## server's aim while drawn, within World.spread_of plus CONE_SLACK, out to
## World.range_of plus one and at least CONE_LEAST); whether her cell is
## among them.
func _in_line_of_fire() -> bool:
	if not _alive(keeper) or keeper.raised != "draw" or keeper.zone != zone or keeper.facing == Vector2i.ZERO:
		return false
	var spread := World.spread_of(keeper)
	if spread < 0.0:
		return false
	var reach := maxi(World.range_of(keeper) + 1, CONE_LEAST)
	var aim := Vector2(keeper.facing).angle()
	var mine := false
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var way := Vector2(dx, dy)
			if way == Vector2.ZERO or way.length() > reach + 0.5:
				continue
			if absf(angle_difference(aim, way.angle())) <= spread + CONE_SLACK:
				var at := keeper.tile + Vector2i(dx, dy)
				_danger[at] = true
				mine = mine or at == tile
	return mine


## The telegraphs showing in her zone whose source she sees (decision 663),
## each tick: their cells into _danger; the cell to dodge to when one
## landing within DODGE_LOOK covers hers and she has had her reaction's
## ticks since first seeing it, else NONE. Nearest first; of those as near,
## one still beside [param fighting], else one farther from the blow's source.
func _read_telegraphs(fighting: GridEntity) -> Vector2i:
	_danger = {}
	var shown := World.telegraphs()
	for id: int in _dodge_seen.keys():
		if not shown.has(id):
			_dodge_seen.erase(id)
	var react := DODGE_REACT + (DODGE_WARY if hangs_back() else 0)
	var from: GridEntity = null
	# Her player's drawn bow (663 amended): its cone is danger too,
	# and in it she steps clear at once.
	if _in_line_of_fire():
		from = keeper
		_dodge_from = "%s's line of fire" % keeper_name()
	if shown.is_empty() and _danger.is_empty():
		return NONE
	for id: int in shown:
		var data: Dictionary = shown[id]
		if str(data.get("zone", "")) != zone:
			continue
		var source := get_node_or_null(NodePath(str(data.get("source", "")))) as GridEntity
		if not source is Monster or World.distance(tile, source.tile) > SIGHT_RANGE \
				or not World.has_line_of_sight(tile, source.tile):
			continue
		if not _dodge_seen.has(id):
			_dodge_seen[id] = World.tick
		var mine := false
		for cell: Array in data.get("cells", []):
			var at := Vector2i(int(cell[0]), int(cell[1]))
			_danger[at] = true
			mine = mine or at == tile
		if mine and World.tick - int(_dodge_seen[id]) >= react and int(data.get("lands_tick", 0)) - World.tick <= DODGE_LOOK:
			from = source
			_dodge_from = "%s's %s" % [source.name, str(data.get("kind", "blow"))]
	if from == null:
		return NONE
	var scored: Array[Array] = []
	var strikes := World.strike_cells(self, fighting) if _alive(fighting) else ([] as Array[Vector2i])
	for cell in _cells_within(DODGE_REACH):
		if _danger.has(cell) or not World.is_walkable(cell) or (cell != tile and not World.is_free(cell)):
			continue
		var score := World.distance(tile, cell) * 100.0 - World.distance(from.tile, cell)
		if cell in strikes:  # She can strike from it (decision 699).
			score -= 50.0
		scored.append([score, scored.size(), cell])
	# The best she has a short way to (685): one behind a wall is no dodge,
	# and its way searched each tick walked round the zone. Best first, so
	# mostly one search.
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
	for each: Array in scored:
		var cell: Vector2i = each[2]
		if cell == tile or not World.find_path(tile, cell, false, null, DODGE_SEARCH_TILES).is_empty():
			return cell
	return NONE


## Her walk (decision 551) stops, or is at a way out, for [param why]:
## Main's guide_done says so and takes them through.
func _guide_ends(why: String) -> void:
	if guide_done.is_valid():
		guide_done.call(self, why)
	elif why != "cross":
		guide.stop(why)


## Whether [param entity] would fight her or her player (enemy-ai's
## Monster.threatens where it is; else a monster she counts hostile).
func _threatens(entity: GridEntity) -> bool:
	if entity.has_method("threatens"):
		return bool(entity.call("threatens", keeper)) or bool(entity.call("threatens", self))
	return _hostile(entity)


## REVIVE (decision 544): to a cell beside her downed player, then the
## channel (Main's revive); kneeling, she holds still till it is done or
## broken, and begins again.
func _revive_step() -> void:
	if World.channeler_of(keeper) == self:
		return
	if World.can_melee(tile, keeper.tile):
		if revive.is_valid():
			revive.call(self, keeper)
		return
	var best := NONE
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var at := keeper.tile + Vector2i(dx, dy)
			if at != keeper.tile and World.is_walkable(at) and World.is_free(at) and World.can_melee(at, keeper.tile) \
					and (best == NONE or World.distance(tile, at) < World.distance(tile, best)):
				best = at
	if best != NONE:
		_step_toward(best, false)


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
	# Her heading and her goal's margin keep her from turning back and forth
	# while something is after her; with nothing near she makes for her
	# player (a stale heading held her three cells off a free one, 693).
	var pressed := _hostile_within(RETREAT_REACH + 1)
	var scores := _safe_cells(_retreat_heading if pressed else Vector2i.ZERO)
	var best := NONE
	for cell: Vector2i in scores:
		if best == NONE or scores[cell] < scores[best]:
			best = cell
	var margin := RETREAT_KEEP_MARGIN if pressed else 0.0
	if not scores.has(_retreat_goal) or best != NONE and scores[_retreat_goal] > scores[best] + margin:
		_retreat_goal = best
	var cell := _retreat_goal
	if cell == NONE:
		var foe := _adjacent_hostile()
		if foe != null and World.in_reach(self, foe):
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
		if _hostile(entity) and World.distance(tile, entity.tile) <= RETREAT_REACH + 1:
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
	var doors := door_cells()
	for dy in range(-YIELD_REACH, YIELD_REACH + 1):
		for dx in range(-YIELD_REACH, YIELD_REACH + 1):
			var cell := tile + Vector2i(dx, dy)
			if cell == tile or line.has(cell) or doors.has(cell) or not World.is_free(cell) or World.is_burning(cell):
				continue
			var path := World.find_path(tile, cell, false, null, YIELD_SEARCH_TILES)
			if path.is_empty() or path.size() > YIELD_REACH:
				continue
			var ahead := Vector2(cell - keeper.tile).dot(Vector2(direction))
			if path.size() < best_steps or (path.size() == best_steps and ahead < best_ahead):
				best = cell
				best_steps = path.size()
				best_ahead = ahead
	return best


## ATTACK out of reach (decision 699, companions' side): she walks to the
## nearest cell she can strike [param target] from (World.strike_cells:
## beside a body on the grid, as ever; where a free body's centre is in her
## reach; a reach weapon's line), worked out again once its centre has
## moved STRIKE_REPLAN or she has stepped; none to be had, she closes on
## it as before (_approach).
func _close_in(target: GridEntity) -> void:
	var centre := World.body_centre(target)
	if _strike_plan.get("target") != target or _strike_plan.get("from") != tile \
			or (_strike_plan["centre"] as Vector2).distance_to(centre) > STRIKE_REPLAN:
		_strike_plan = {"target": target, "from": tile, "centre": centre, "cells": World.strike_cells(self, target)}
	var cells: Array[Vector2i] = _strike_plan["cells"]
	if not cells.is_empty() and _step_toward(cells[0], true):
		return
	_approach(target, 0 if World.free_body(target) else 1)


## Walks until within [param reach] of [param target].
func _approach(target: Variant, reach: int) -> void:
	if not _alive(target) or World.distance(tile, target.tile) <= reach:
		return
	# A FOLLOW that cannot get closer just waits; anything else gives up.
	if not _step_toward(target.tile, true) and current_intent != Intent.FOLLOW:
		print("[mind] %s: cannot reach %s; following" % [name, target.name])
		_unreachable[target.get_instance_id()] = {"until": World.tick + UNREACHABLE_TICKS, "her": tile, "its": target.tile}
		current_intent = Intent.FOLLOW
		intent_target = null


## Whether [param entity] was found out of her reach lately (_approach): she
## does not pick it again for UNREACHABLE_TICKS, or till it or she has moved
## UNREACHABLE_MOVED cells (perf: Wren pathfound to Snagfin seven times a
## second). One next to her is fought all the same (_adjacent_hostile).
func _out_of_reach(entity: GridEntity) -> bool:
	var id := entity.get_instance_id()
	if not _unreachable.has(id):
		return false
	var entry: Dictionary = _unreachable[id]
	if World.tick < int(entry["until"]) and World.distance(tile, entry["her"]) < UNREACHABLE_MOVED 			and World.distance(entity.tile, entry["its"]) < UNREACHABLE_MOVED:
		return true
	_unreachable.erase(id)
	return false


## [param entry] in the mind log, with her stance and how far her player is
## as it is written.
func _log(entry: Dictionary) -> void:
	entry["stance_now"] = stance_name()
	entry["keeper_distance"] = World.distance(tile, keeper.tile) if _alive(keeper) else -1
	MindLog.record(entry)


## FOLLOW: still while her player is within FOLLOW_START - 1 cells; once
## they are FOLLOW_START away she sets off for their heel (Heel, decision 485), the path
## found afresh every step (they keep moving), and, once they stand, stops
## there or within FOLLOW_STOP of them and not ahead (decision 381: she had
## closed to 1 in front of him and been walked into). Not logged: hands,
## every step.
func _follow() -> void:
	if not _alive(keeper):
		_catching_up = false
		return
	var distance := World.distance(tile, keeper.tile)
	# Her player stalking: she keeps still till they are farther off, and
	# closes less (decision 332), so fewer of her steps reach the animal.
	var quiet := stalking() != null
	if distance >= (STALK_START if quiet else heel.start) and not _catching_up:
		_catching_up = true
	if quiet:
		if _catching_up and distance <= STALK_CLOSE:
			_catching_up = false
		if _catching_up:
			_approach(keeper, STALK_CLOSE)
		return
	heel.follow(self, keeper)


## The cells either side of each door: a door's inside cell and the one
## outside it, where she never stops of her own accord (decision 391, Jeff:
## "companions tend to stand in doorways"; holding one is a tactic,
## _door_to_hold).
static func door_cells() -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for door: Door in World.get_doors():
		for cell in Terrain.edge_cells(door.key):
			out[cell] = true
	return out


## The inside of the building [param cell] is in (Rect2i() for none).
static func _inside_of(cell: Vector2i) -> Rect2i:
	var building := building_at(cell)
	return Rect2i() if building.is_empty() else building["rect"]


## The free walkable cell of [param cells] (a building's, Level.building_cells)
## nearest the middle of the box round them (the nearest of them when none
## is free): of an L-shaped building's own cells, never the box's empty
## corner (391 amended, buildings' 488).
static func _middle_of(cells: Array[Vector2i]) -> Vector2i:
	if cells.is_empty():
		return NONE
	var low := cells[0]
	var high := cells[0]
	for cell in cells:
		low = low.min(cell)
		high = high.max(cell)
	var middle := low + (high - low + Vector2i.ONE) / 2
	var best := middle
	var best_key := 1 << 30
	for cell in cells:
		# A free cell first; none free, the building's own nearest the middle.
		var key := (0 if World.is_walkable(cell) and World.is_free(cell) else 1 << 20) + World.distance(cell, middle)
		if key < best_key:
			best = cell
			best_key = key
	return best


## The door she holds in a fight (decision 391, Jeff: "doorway plugging a
## battle strategy not a routine"): with her player inside a building and a
## hostile outside it that she sees or hears (within GUARD_RANGE of her)
## within GUARD_RANGE of one of its doors, or in sight going for either of
## them, that door's inside cell, the one nearest the hostile; NONE
## otherwise. Once the fight is over it is NONE again, and she steps off.
func _door_to_hold() -> Vector2i:
	if not _alive(keeper):
		return NONE
	var inside := _inside_of(keeper.tile)
	if inside.size == Vector2i.ZERO:
		return NONE
	var best := NONE
	var best_distance := 1 << 20
	for door: Door in World.get_doors():
		var sides := Terrain.edge_cells(door.key)
		if inside.has_point(sides[0]) == inside.has_point(sides[1]):
			continue
		var within: Vector2i = sides[0] if inside.has_point(sides[0]) else sides[1]
		var outside: Vector2i = sides[1] if within == sides[0] else sides[0]
		for entity in World.get_entities():
			var monster := entity as Monster
			if monster == null or not _hostile(monster) or inside.has_point(monster.tile) \
					or not (senses.sees(monster) or World.distance(tile, monster.tile) <= GUARD_RANGE):
				continue
			var distance := World.distance(monster.tile, outside)
			var after_us := monster.target != null and (monster.target == self or monster.target == keeper)
			if (distance <= GUARD_RANGE or after_us and distance <= SIGHT_RANGE) and distance < best_distance:
				best = within
				best_distance = distance
	return best


## How far [param offset] lies along [param facing] (a dot product).
static func _ahead_of(offset: Vector2i, facing: Vector2i) -> int:
	return Heel.ahead_of(offset, facing)


## One step toward [param goal] (Heel.step): never into a cell her player
## is walking into (678, companions' side), save leaping clear of a blow.
## False if there is no way there.
func _step_toward(goal: Vector2i, occupied_goal_ok: bool) -> bool:
	return Heel.step(self, goal, occupied_goal_ok, keeper if current_intent != Intent.DODGE else null)


# --- Errands: what she does when asked ------------------------------------------

## What ails someone, in words (GridEntity.ailments' kinds).
const AILING := {"bleed": "bleeding", "burn": "burning"}


## What she can do here and now, nearest first, at most ACTIONS_MAX: each
## {verb ("open", "close", "open_chest", "fetch", "give", "bandage", "look",
## and decision 391's "look_inside", "make_way", "hold_door"), words
## (for her voice: "open the closed door, a few paces to the south"), at,
## and its door, chest, item or cell}. Only what she sees: a door not
## broken, a chest, and, with her player in sight (the only one she may
## hand things to: World.reaches), each thing in a chest to bring them and
## each thing she carries to give them; with a bandaging kit, out of
## combat, to bandage herself or her player in sight, if hurt and not
## being bandaged or mending (World.try_bandage, decision 320); and the
## nearest walkable cells she
## cannot see within her sight's range, one a compass point, LOOKS_OFFERED
## of them. A bandage for someone bleeding comes first, before anything
## nearer (decision 320 amended); then holding a door in a fight, or else
## stepping out of her player's way when next to them or in a doorway; and
## inside a building, a look round it (decision 391).
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
			if not id.is_empty() and not given.has(id) and Items.def(id).get("use") != "bandage" and not is_remedy(id):
				given[id] = true
				actions.append({"verb": "give", "item": id, "at": keeper.tile,
					"words": "give %s your %s" % [keeper_name(), Items.name_of(id)]})
	if World.bandage_kit(self) >= 0 and World.calm(self):
		for patient: GridEntity in [self, keeper if to_them else null]:
			if patient != null and patient.hp < patient.max_hp and patient.mending == 0 and World.calm(patient):
				actions.append({"verb": "bandage", "patient": patient, "at": patient.tile,
					"words": "bandage your own wounds" if patient == self else "bandage %s's wounds" % keeper_name()})
	# Inside a building: a look round all of it (decision 391).
	var building := building_at(tile)
	if not building.is_empty():
		var middle := _middle_of(Level.building_cells(building))
		actions.append({"verb": "look_inside", "building": building, "cell": middle, "at": middle,
			"words": "look round inside %s and see what is there" % building_short(building)})
	actions.sort_custom(_nearer_found)
	# Getting out of her player's way, and holding a door in a fight, come
	# before anything nearer (decision 391).
	var door := _door_to_hold()
	if door != NONE:
		actions.push_front({"verb": "hold_door", "cell": door, "at": door,
			"words": "hold the door of %s against what is coming" % building_short(building_at(door))})
	if _alive(keeper) and (World.distance(tile, keeper.tile) == 1 or door_cells().has(tile)) and door == NONE:
		actions.push_front({"verb": "make_way", "cell": tile, "at": tile, "words": "step out of %s's way" % keeper_name()})
	# Bleeding: the bandage first, before anything nearer.
	var stanch := actions.filter(func(each: Dictionary) -> bool: return each["verb"] == "bandage" and each["patient"].ailments.has("bleed"))
	if not stanch.is_empty():
		actions.assign(actions.filter(func(each: Dictionary) -> bool: return each not in stanch))
		for each: Dictionary in stanch:
			actions.push_front(each)
	# A search for secrets (608 amended): near a hidden niche it keeps a
	# place of its own; a plain search about takes one of the looks'.
	var search := _search_here()
	var pointer := search.has("found")
	actions.resize(mini(actions.size(), ACTIONS_MAX - LOOKS_OFFERED - (1 if pointer else 0)))
	if not search.is_empty():
		actions.append(search)
	var looks := LOOKS_OFFERED - (1 if not search.is_empty() and not pointer else 0)
	var ways: Dictionary[int, bool] = {}
	for cell in _cells_within(SIGHT_RANGE):
		if ways.size() >= looks:
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


## A search of the room for secrets (608 amended, companions' side; Jeff:
## "asking companion to search the room for secrets they may walk over to
## an area"), out of a fight: with a hidden niche not yet found
## (World.niche_edges "hidden", its door shut and locked) within
## SEARCH_RANGE and its floor cell in her sight, to a free cell within
## SEARCH_NEAR of that cell, never onto it (a pointer, not the opening);
## else a few paces about, to a cell she sees. {} in a fight or with nowhere
## to go.
func _search_here() -> Dictionary:
	if not World.calm(self):
		return {}
	for key: Vector3i in World.niche_edges:
		if World.niche_edges[key] != "hidden":
			continue
		var door := World.door_on(key)
		if door == null or door.is_open() or door.lock.is_empty():
			continue  # Found already.
		var floor_cell := _niche_floor(key)
		if World.distance(tile, floor_cell) > SEARCH_RANGE or not _sees(floor_cell):
			continue
		var best := NONE
		for cell in _cells_within(SEARCH_RANGE + SEARCH_NEAR):
			if cell == floor_cell or World.distance(cell, floor_cell) > SEARCH_NEAR or not World.is_walkable(cell) \
					or (cell != tile and not World.is_free(cell)):
				continue
			if best == NONE or World.distance(tile, cell) < World.distance(tile, best):
				best = cell
		if best != NONE:
			return {"verb": "search", "cell": best, "at": best, "found": key, "words": "search about here for anything hidden"}
	for cell in _cells_within(SEARCH_WANDER):
		if World.distance(tile, cell) == SEARCH_WANDER and World.is_walkable(cell) and World.is_free(cell) and _sees(cell):
			return {"verb": "search", "cell": cell, "at": cell, "words": "search about here for anything hidden"}
	return {}


## The hall's floor cell before hidden niche edge [param key].
static func _niche_floor(key: Vector3i) -> Vector2i:
	var sides := Terrain.edge_cells(key)
	return sides[0] if World.is_walkable(sides[0]) else sides[1]


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
	# A building named: a look round inside it (decision 391), not a look off somewhere.
	var building: bool = has.call("\\b(hut|house|shed|temple|forge|kitchen|store|building|room|inside|in here)\\b")
	# Secrets: a search for anything hidden (608 amended), not a look round.
	var secret: bool = not chest and has.call("\\b(secrets?|hidden|concealed|passages?|drafts?|draughts?)\\b") \
			and has.call("\\b(search|look|check|find|feel|seek|hunt)")
	if secret:
		verbs.append("search")
	elif not chest and building and has.call("\\b(look|check|search|see|peek|loot)"):
		verbs.append("look_inside")
	elif not chest and not door and has.call("\\b(look|check|scout|see|peek)") \
			and has.call(COMPASS_WORD + "|\\b(dark|there|ahead|around|corner)\\b"):
		verbs.append("look")
	if has.call("\\b(step|move|stand)\\b[^.]*\\b(aside|over|out of (the|your|his|her|their) way|out of the door\\w*|clear)\\b|\\b(make way|get out of (the|your|his|her|their) way)\\b"):
		verbs.append("make_way")
	if door and has.call("\\b(hold|guard|block|keep)\\b"):
		verbs.append("hold_door")
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
	# Out of the way, and holding a door: the hands at once, no errand kept.
	match str(action["verb"]):
		"make_way":
			step_aside(keeper.facing if _alive(keeper) else facing)
			_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": action["words"], "outcome": "done",
				"note": "to %s" % _yield_tile})
			return
		"hold_door":
			_door_asked = true
			_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": action["words"], "outcome": "set off"})
			return
	errand = action.duplicate()
	_errand_no_way.clear()
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
		if _hostile(entity) and World.distance(tile, entity.tile) <= ERRAND_BREAK and senses.sees(entity):
			if str(errand.get("verb", "")) == "look" and errand.get("asked", false):
				# Turned back looking (decision 696): what drove her back is
				# what she found, a fact, and her voice told it.
				note_fact("%s was turned back by %s while looking about in %s." % [_name_of(self), refer(entity), _place_words()])
				_scouted_add("turned back by %s" % refer(entity), entity.tile)
				_end_errand("%s came at you" % refer(entity), true)
				return false
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
		"give", "take":
			return World.reaches(self, keeper)
		"bandage":
			var patient: GridEntity = errand["patient"]
			return patient == self or _alive(patient) and World.can_melee(tile, patient.tile)
		"look_inside":
			return World.distance(tile, errand["cell"]) <= 1
		"search":
			return tile == errand["cell"] or World.distance(tile, errand["cell"]) == 1 and not World.is_free(errand["cell"])
		_:
			return _sees(errand["cell"])


## A step toward where her errand is done; false if there is no way.
func _errand_walk() -> bool:
	match str(errand["verb"]):
		"open", "close":
			# The door's near side, or its far one if that is taken.
			# One found to have no way is looked for again only after
			# ERRAND_RETRY_TICKS, or when no other side has one (685).
			var sides: Array[Vector2i] = [errand["at"]]
			sides.append_array(Terrain.edge_cells(errand["door"].key))
			var later: Array[Vector2i] = []
			for side in sides:
				if World.tick < int(_errand_no_way.get(side, 0)):
					later.append(side)
				elif not World.find_path(tile, side).is_empty():
					return _step_toward(side, false)
				else:
					_errand_no_way[side] = World.tick + ERRAND_RETRY_TICKS
			for side in later:
				if not World.find_path(tile, side).is_empty():
					return _step_toward(side, false)
			return false
		"open_chest", "fetch":
			return _alive(errand["chest"]) and _step_toward(errand["chest"].tile, true)
		"give", "take":
			return _alive(keeper) and _step_toward(keeper.tile, true)
		"bandage":
			return _alive(errand["patient"]) and _step_toward(errand["patient"].tile, true)
		_:
			return _step_toward(errand["cell"], true)


## Why a bandage was not begun or was broken off (World.bandage_refusal,
## bandage_broke_why), for her voice's narration (decision 625).
const BANDAGE_WHY := {"gone": "they were gone", "not_beside": "you could not reach them", "no_wound": "there was no wound to bandage",
	"mending": "the wound was bound already", "busy": "your hands were full", "no_kit": "you had no bandaging kit",
	"hurt_now": "someone was hurt a moment ago", "not_safe": "a monster was too close", "patient_moved": "they moved",
	"moved": "you moved", "hurt": "someone was hurt", "broken": "it came loose"}


## Says why she won't or can't bandage [param patient] now, in her own
## words (companion_traits "bandage_says" by [param why]; "_self" for her
## own wound), at once (decision 625, Jeff: "Pip seems lazy at bandaging").
func _say_bandage(why: String, patient: GridEntity) -> void:
	if errand.get("unasked", false):
		return  # Nobody asked: nothing to answer (decision 681).
	var says: Dictionary = CompanionCard.tables().get("bandage_says", {})
	var line := str(says.get(why + "_self", "")) if patient == self else ""
	if line.is_empty():
		line = str(says.get(why, says.get("broken", "")))
	if not line.is_empty():
		_say(line, true)


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
					var why := World.bandage_broke_why if not World.bandage_broke_why.is_empty() else "broken"
					_say_bandage(why, patient)
					_end_errand("the bandaging was broken off: %s" % BANDAGE_WHY.get(why, "it came loose"), false)
			elif World.try_bandage(self, patient):
				errand["started"] = true
				errand["until"] = World.tick + World.BANDAGE_TICKS + ERRAND_TICKS
			else:
				# Why not, in her own words (decision 625), the voice told only.
				var no := World.bandage_refusal(self, patient)
				_say_bandage(no, patient)
				_end_errand(BANDAGE_WHY.get(no, "the bandaging could not be begun"), false)
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
		"take":
			# Her player's thing, to carry (decision 616), handed over by them.
			var item: String = errand["item"]
			var from := keeper.slots.find(item) if _alive(keeper) else -1
			var into := World.free_slot_for(self, item)
			if from == -1:
				_end_errand("%s no longer had it" % keeper_name(), true)
			elif into == -1:
				_end_errand("you had no room to carry it", true)
			elif World.try_transfer(keeper, keeper, from, self, into):
				_report_errand("You took the %s from %s and carry it now." % [Items.name_of(item), keeper_name()])
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
		"search":
			var key: Variant = errand.get("found")
			var door := World.door_on(key) if key is Vector3i else null
			if door != null and not door.is_open() and not door.lock.is_empty():
				note_fact("%s felt cool air from a niche in %s." % [_name_of(self), _place_words()])
				_report_errand("You searched about and stopped near the niche %s: cool air moves from the wall there, as if there were a way behind it." % _paces_toward(Vector2(_niche_floor(key))))
			else:
				_report_errand("You searched about here and found nothing hidden.")
		"look_inside":
			var building: Dictionary = errand["building"]
			var seen := _found_in(Level.building_cells(building))
			var short := building_short(building)
			if not seen.is_empty():
				note_fact("%s looked round inside %s in %s and found %s." % [_name_of(self), short, _place_words(), _listed(seen)])
			_report_errand("You looked round inside %s: %s." % [short, "there is nothing in it" if seen.is_empty() else "there is " + _listed(seen)])
		_:
			var cell: Vector2i = errand["cell"]
			var seen := look_findings(cell)
			var where := str(errand["words"]).get_slice(", ", 0).trim_prefix("go and look ")
			if not seen.is_empty():
				# What she saw is true of her now (decision 696): her card's fact,
				# and among what she scouted, for her voice to tell.
				note_fact("%s went to look %s in %s and saw %s." % [_name_of(self), where, _place_words(), _listed(seen)])
			_scouted_add("%s: %s" % [where, "nothing there" if seen.is_empty() else _listed(seen)], cell)
			errand["told"] = "You went and looked %s, and came back: %s." % [where,
				"nothing there" if seen.is_empty() else "you saw " + _listed(seen) + " there"]
			errand["phase"] = "returning"


## What lies in [param cells] (a building's own), for a look round it: each chest and
## what it holds, each thing on the ground, each crate or such, and anyone
## there but her and her player ("a chest holding a dagger", "a bandaging
## kit on the floor").
func _found_in(cells: Array[Vector2i]) -> Array[String]:
	var seen: Array[String] = []
	var inside: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		inside[cell] = true
	for entity in World.get_entities():
		if entity == self or entity == keeper or not entity.spawned or not inside.has(entity.tile):
			continue
		if entity is Chest:
			var held: Array[String] = []
			for id: String in (entity as Chest).slots:
				if not id.is_empty():
					held.append(_a(Items.name_of(id)))
			seen.append("a chest holding %s" % _listed(held) if not held.is_empty() else "an empty chest")
		elif entity is Monster or entity is Player or entity is Companion or entity is Resident:
			seen.append(refer(entity))
		elif entity.pushable:
			seen.append("a " + object_word(entity))
	for cell in cells:
		for id: String in World.ground_at(cell):
			seen.append("%s on the floor" % _a(Items.name_of(id)))
	return seen


## "a, b and c".
static func _listed(things: Array[String]) -> String:
	if things.size() <= 1:
		return "".join(things)
	return "%s and %s" % [", ".join(things.slice(0, -1)), things.back()]


## What she scouted (decision 696), [param text] at [param cell]: kept
## among what she knows now (scouted_words) for the rules' scout_minutes.
func _scouted_add(text: String, cell: Vector2i) -> void:
	scouted.append({"text": text, "zone": zone, "cell": cell, "tick": World.tick})
	while scouted.size() > int(look_rules().get("scouted_most", 8)):
		scouted.pop_front()


## What she scouted in this zone within the rules' scout_minutes, for her
## voice, or "".
func scouted_words() -> String:
	var keep := int(float(look_rules().get("scout_minutes", 10)) * 60.0 * World.TICK_RATE)
	var lines: Array[String] = []
	for each: Dictionary in scouted:
		if each["zone"] == zone and World.tick - int(each["tick"]) <= keep:
			lines.append(str(each["text"]))
	if lines.is_empty():
		return ""
	return "What you went and looked at lately: %s." % "; ".join(lines)


## Her errand is done: [param told] narrated, and her voice asked to tell it.
func _report_errand(told: String) -> void:
	_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": errand.get("words", ""), "outcome": "done",
		"note": "" if errand.get("unasked", false) else told})
	var unasked: bool = errand.get("unasked", false)
	errand = {}
	_narrate(told)
	if not unasked:  # Unasked tending is narrated only (decision 681).
		_ask_voice(told, "", true, false, true, true)


## Her errand ends undone, because of [param why]; with [param tell] her
## voice is asked to say so (it could not be done), else it is narrated.
func _end_errand(why: String, tell: bool) -> void:
	var told := "You did not %s: %s." % [str(errand.get("words", "do it")).get_slice(", ", 0), why]
	_log({"kind": "errand", "companion": String(name), "mind": "hands", "trigger": errand.get("words", ""),
		"outcome": "undone", "note": why})
	var unasked: bool = errand.get("unasked", false)
	errand = {}
	_narrate(told)
	if unasked:
		_tend_after = World.tick + TEND_BACKOFF  # Not straight back at it (decision 681).
	elif tell:
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
		if entity is Monster and entity.spawned and not harmless(entity) and World.distance(at, entity.tile) == 1:
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
		if entity is Monster and entity.spawned and not harmless(entity) and World.distance(at, entity.tile) <= reach:
			return true
	return false


## What an entity is called to her: its label (a player's name, as the
## party log calls them) or, with none, its node name.
static func _name_of(entity: GridEntity) -> String:
	return entity.label if not entity.label.is_empty() else String(entity.name)


## Safe to call with a freed reference, which a target that died can be.
static func _alive(entity: Variant) -> bool:
	return entity != null and is_instance_valid(entity) and entity.spawned
