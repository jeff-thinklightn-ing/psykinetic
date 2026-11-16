class_name FirstSteps
extends RefCounted
## Decision 945 (Jeff, 2026-11-15: "use the companion help the beginner guide
## lost players"; the coordinator's package "the first five minutes"): her
## guide for a newcomer and a lost player, one per companion, live (nothing
## here is saved but [member card], her record's "first_steps").
##
## A newcomer's chain (CHAIN): after her first words (929) she proposes the
## Mughouse's door, then the pond (her wish), then, with a catch in the
## pack, its taker (the store window's pointer, Main.depot_pointer's rule);
## each a yes leads to. Then she offers, one a lull, when the server sees a
## player at a loss (Main._first_steps_signal); asked "where now?" she gives
## two true choices. Every line is a deck's (companion_traits.json
## "first_steps" "decks", voice's words, lore's facts); the server picks the
## place and keeps the offer, so a yes leads whatever the mind would say.
## Off ("on": false) until the package is whole.

## The chain's steps, in order.
const CHAIN: Array[String] = ["mughouse", "pond", "catch"]
## A player asking her where to go: "where now?", "what now?", "I'm lost".
const ASK_WAY := "(?i)\\b(where (now|to|next|should (we|i) go|shall (we|i) go|do (we|i) go)|what now|what (should|shall|do|can) (we|i) do|what'?s there to do|i'?m lost|show me (a)?round)\\b"
## A no to her offer.
const NO := "(?i)^\\W*(no|nah|nope|not now|not yet|no thanks|later|maybe later|another time|i'?d rather not|let'?s not|i'?m fine|i'?m good)\\b"

## The places she offers a player at a loss or asked, in her order of
## choosing (choice.<kind>, go.<kind>), and the words that name each in a
## player's line (an asked offer's second choice taken by naming it).
const PLACES: Array[String] = ["mughouse", "pond", "healer", "temple", "barrow"]
const PLACE_WORDS := {"mughouse": ["mughouse", "inn", "tavern", "ale", "fire"], "pond": ["pond", "fish", "fishing", "pool"],
	"healer": ["healer", "healer's", "medicine man", "hut", "remedies"], "temple": ["temple", "priest"],
	"barrow": ["barrow", "mound", "door"]}

## Tests: 1 on, 0 off, -1 the JSON's "on".
static var forced := -1

## Her record's "first_steps" ({done: [step], ended, noes: {kind: n},
## days: {place: [day]}, bed}); {} for a companion who never had a chain
## (one met before 945): she has no chain, the rest stands.
var card: Dictionary = {}
## Her offer standing: {kind, place, tick, chain: step or "", unasked}; {}
## for none.
var offer: Dictionary = {}
## When the next chain step may be proposed (-1 not yet set).
var next_chain_tick := -1
## Her first words said at (929), for the first step's beat.
var first_words_tick := -1
## Unasked offers' ticks this hour (the rate), the last one's, and how many
## lapsed unanswered in a row (two: none till he moves or speaks).
var unasked_ticks: Array[int] = []
var last_unasked_tick := -100000
var lapses := 0
var lapse_tile := Vector2i(-99999, -99999)
var lapse_spoke := -100000
## A no quiets every unasked offer till this tick.
var quiet_until := -100000
## A first-steps walk her player stepped off: {goal, tick}; {} for none.
var stray: Dictionary = {}
## The deck lines said last, by key (never the same twice running).
var said_last: Dictionary = {}
## Her player came back out of a building (the Mughouse) since its step.
var was_inside := false

## What the server measures, once a second (Main._first_steps_sense).
var trail: Array[Array] = []  # [tick, tile]
var last_new_tick := 0
var cells_since_new := 0
var known := -1
var gold := -1
var zone := ""
var fought := -100000
var still_tile := Vector2i(-99999, -99999)
var still_since := -1
var hurt_since := -1
var hp := -1
## A no's kind quiet while its zone and hour hold ({kind: "zone|hour"}).
var no_where: Dictionary = {}
## The pond the chain's step led to ({} before): its catch step waits there.
var pond: Dictionary = {}
## A rising, from Main._on_returned: {kind, paid, tick}; {} for none.
var rise: Dictionary = {}


static func table() -> Dictionary:
	var t: Variant = CompanionCard.tables().get("first_steps", {})
	return t if t is Dictionary else {}


## Whether the package is switched on.
static func on() -> bool:
	return forced == 1 if forced >= 0 else table().get("on", false) == true


## A rule's draft number ("rules").
static func rule(key: String, otherwise: float) -> float:
	var rules: Variant = table().get("rules", {})
	return float((rules as Dictionary).get(key, otherwise)) if rules is Dictionary else otherwise


## The ticks of a rule given in seconds.
static func ticks(key: String, otherwise: float) -> int:
	return roundi(rule(key, otherwise) * World.TICK_RATE)


## Deck [param key]'s lines for [param temperament]: its own list joined
## to the default's, or the default's alone.
static func lines(key: String, temperament: String) -> Array:
	var decks: Variant = table().get("decks", {})
	var deck: Variant = (decks as Dictionary).get(key) if decks is Dictionary else null
	if deck is Array:
		return deck
	if deck is String:
		return [deck]
	if not deck is Dictionary:
		return []
	var out: Array = (deck.get("default", []) as Array).duplicate() if deck.get("default") is Array else []
	if deck.get(temperament) is Array:
		out.append_array(deck[temperament])
	return out


## A line of deck [param key] for [param temperament], never the one said
## last of it; "" for an empty deck. [param pick] seeds which.
func line(key: String, temperament: String, pick: int) -> String:
	var all := lines(key, temperament)
	if all.is_empty():
		return ""
	var options := all.filter(func(each: Variant) -> bool: return str(each) != str(said_last.get(key, ""))) if all.size() > 1 else all
	var chosen := str(options[posmod(pick, options.size())])
	said_last[key] = chosen
	return chosen


## The chain's next step not yet done or passed; "" when it ended.
func next_step() -> String:
	if card.is_empty() or card.get("ended", false) == true:
		return ""
	var done: Array = card.get("done", [])
	for step: String in CHAIN:
		if not step in done:
			return step
	return ""


## Whether her chain still runs (a newcomer's, not ended).
func chain_running() -> bool:
	return not next_step().is_empty()


## Step [param step] done or passed: the next one's turn.
func pass_step(step: String) -> void:
	var done: Array = card.get_or_add("done", [])
	if not step in done:
		done.append(step)


func end_chain() -> void:
	if not card.is_empty():
		card["ended"] = true


## The noes said to offers of [param kind].
func noes(kind: String) -> int:
	return int((card.get("noes", {}) as Dictionary).get(kind, 0)) if card.get("noes") is Dictionary else 0


func add_no(kind: String) -> void:
	var all: Dictionary = card.get_or_add("noes", {})
	all[kind] = int(all.get(kind, 0)) + 1


## Asked (945): an offer kind's two noes are forgotten.
func clear_noes() -> void:
	card.erase("noes")


## The game days [param place] was reached on (at most three kept).
func days_at(place: String) -> Array:
	var days: Variant = (card.get("days", {}) as Dictionary).get(place, []) if card.get("days") is Dictionary else []
	return days if days is Array else []


## [param place] reached on game day [param day].
func reached(place: String, day: int) -> void:
	if card.is_empty():
		card["done"] = []
		card["ended"] = true  # A companion met before 945: no chain (nor its end told), her notices kept.
		card["told"] = true
	var all: Dictionary = card.get_or_add("days", {})
	var days: Array = all.get_or_add(place, [])
	if not day in days:
		days.append(day)
		while days.size() > 3:
			days.pop_front()


func reached_today(place: String, day: int) -> bool:
	return day in days_at(place)


## Whether [param text] names place [param kind] (PLACE_WORDS).
static func names(text: String, kind: String) -> bool:
	var said := " %s " % Guide._plain(text)
	for word: String in PLACE_WORDS.get(kind, []):
		if " %s " % Guide._plain(word) in said:
			return true
	return false


## The chain's end once told (that they can ask her where to).
func end_told() -> bool:
	return card.get("told") == true


## Her asked answer (945): [param joiner] (an asked / asked_one line) with
## [param clauses] (choice.* clauses, lower case), the line's first letter
## capitalised (voice: "The Mughouse, ... Or the pond", but "I'd say the
## Mughouse", never a clause capitalised mid-line).
static func joined(joiner: String, clauses: Array[String]) -> String:
	var line := joiner % (clauses.slice(0, 2) if joiner.count("%s") > 1 else [clauses[0]])
	return line.left(1).to_upper() + line.substr(1)
