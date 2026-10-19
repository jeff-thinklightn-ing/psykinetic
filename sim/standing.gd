class_name Standing
## What one of the town's people thinks of a player (decision 443), and
## what a companion feels for hers (companions' 444): a score per player
## kept on a card, moved only by the world's own events, never by a model.
## On any Dictionary that holds "standing" (a resident's card, 398, or a
## companion's record): "standing": {player_id: {"score": int, "met": the
## step of their first words, "since": the step of the last change, "why":
## the last few reasons, plain clauses without the player's name ("brought
## Bram home"), newest last, "own": whether any reason is their own event
## (not hearsay)}}. The words come from the score through a ladder:
## RESIDENT (stranger: no entry; wronged: -3 and down; known: -2..2;
## trusted: 3 and up) or COMPANION (fond to start; wary; close; devoted
## from 6). Residents' cards are swept for decay by Townsfolk; a
## companion's record only by companions, while she is apart from her
## player. Numbers in levels/residents.json "standing".

const FILE := "res://levels/residents.json"
const DEFAULTS := {"trusted": 3, "wronged": -3, "top": 6, "most": 10, "heard_most": 2, "why_kept": 3, "decay_days": 10,
	"met": 3, "rescue": 4, "lapsed": -2, "errand_lapsed": -1, "kin_home": 4, "loan_quarter": 1, "loan_cleared": 2,
	"word": 2, "gift": 1, "gift_favourite": 2, "raid": 1, "heard": 1, "fetch": 1, "walked_home": 3, "song": 1, "healed": 3}
## A ladder: the word for each step, and the sentence frame for each word
## (the player's name goes in; the newest reason follows after a colon).
const RESIDENT := {
	"words": {"none": "stranger", "low": "wronged", "middle": "known", "high": "trusted", "top": "trusted"},
	"frames": {"wronged": "%s wronged you", "known": "You have met %s before", "trusted": "You trust %s"}}
const COMPANION := {
	"words": {"none": "fond", "low": "wary", "middle": "fond", "high": "close", "top": "devoted"},
	"frames": {"wary": "You are wary of %s", "fond": "You are fond of %s", "close": "You are close to %s", "devoted": "You are devoted to %s"}}

static var _settings := {}


static func settings() -> Dictionary:
	if _settings.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_settings = DEFAULTS.duplicate()
		if data is Dictionary and data.get("standing") is Dictionary:
			_settings.merge(data["standing"], true)
	return _settings


## Uses [param given] in place of the file's "standing" ({} to read it again): tests.
static func use_settings(given: Dictionary) -> void:
	_settings = {}
	if not given.is_empty():
		_settings = DEFAULTS.duplicate()
		_settings.merge(given, true)


static func setting(key: String) -> int:
	return int(settings().get(key, DEFAULTS.get(key, 0)))


## [param player_id]'s entry on [param card], a copy; {} for a stranger.
static func entry(card: Dictionary, player_id: String) -> Dictionary:
	var all: Variant = card.get("standing", {})
	if all is Dictionary and all.get(player_id) is Dictionary:
		return all[player_id].duplicate(true)
	return {}


static func score(card: Dictionary, player_id: String) -> int:
	return int(entry(card, player_id).get("score", 0))


## Their first words with [param player_id] at [param step]: the entry made
## at 0 (known). Whether it was the first time.
static func met(card: Dictionary, player_id: String, step: int) -> bool:
	if player_id.is_empty() or not entry(card, player_id).is_empty():
		return false
	card.get_or_add("standing", {})[player_id] = {"score": 0, "met": step, "since": step, "why": [], "own": false}
	return true


## Whether [param step] is the step of their first words.
static func first_words(card: Dictionary, player_id: String, step: int) -> bool:
	var it := entry(card, player_id)
	return not it.is_empty() and int(it.get("met", -1)) == step


## [param player_id]'s score on [param card] moved by [param delta] for
## [param why] (a plain clause, no name: "brought Bram home") at [param
## step], within -most..most; the entry after. An event of their own.
static func bump(card: Dictionary, player_id: String, delta: int, why: String, step: int) -> Dictionary:
	if player_id.is_empty():
		return {}
	met(card, player_id, step)
	var it: Dictionary = card["standing"][player_id]
	var most := setting("most")
	it["score"] = clampi(int(it.get("score", 0)) + delta, -most, most)
	it["since"] = step
	it["own"] = true
	_remember(it, why)
	return it.duplicate(true)


## Hearsay of [param player_id] from [param from] at [param step], leaning
## [param sign] (+1 or -1): moves the score only for one with no event of
## their own with that player, and never past heard_most either way.
## Whether it moved.
static func heard(card: Dictionary, player_id: String, sign: int, why: String, from: String, step: int) -> bool:
	if player_id.is_empty() or sign == 0:
		return false
	var it := entry(card, player_id)
	if bool(it.get("own", false)):
		return false
	met(card, player_id, step)
	it = card["standing"][player_id]
	var limit := setting("heard_most")
	var moved := clampi(int(it.get("score", 0)) + signi(sign) * setting("heard"), -limit, limit)
	if moved == int(it.get("score", 0)):
		return false
	it["score"] = moved
	it["since"] = step
	_remember(it, "%s says %s" % [from, why] if not from.is_empty() else why)
	return true


static func _remember(it: Dictionary, why: String) -> void:
	var reasons: Array = it.get("why", [])
	if not why.strip_edges().is_empty():
		reasons.append(why.strip_edges().trim_suffix("."))
	while reasons.size() > setting("why_kept"):
		reasons.pop_front()
	it["why"] = reasons


## The word for [param player_id] on [param card], by [param ladder].
static func words(card: Dictionary, player_id: String, ladder: Dictionary = RESIDENT) -> String:
	var it := entry(card, player_id)
	var table: Dictionary = ladder.get("words", RESIDENT["words"])
	if it.is_empty():
		return str(table.get("none", ""))
	var value := int(it.get("score", 0))
	if value >= setting("top"):
		return str(table.get("top", table.get("high", "")))
	if value >= setting("trusted"):
		return str(table.get("high", ""))
	if value <= setting("wronged"):
		return str(table.get("low", ""))
	return str(table.get("middle", ""))


## The one sentence the voice is told of [param player_name] (id [param
## player_id]): the frame for the word, then the newest reason, as "they":
## "You trust Jeff: they brought Bram home." "" for a stranger (no frame).
static func fact(card: Dictionary, player_id: String, player_name: String, ladder: Dictionary = RESIDENT) -> String:
	var word := words(card, player_id, ladder)
	var frames: Dictionary = ladder.get("frames", {})
	if word.is_empty() or not frames.has(word):
		return ""
	var reasons: Array = entry(card, player_id).get("why", [])
	var why := str(reasons.back()) if not reasons.is_empty() else ""
	var opening: String = frames[word] % player_name
	if why.is_empty():
		return opening + "."
	return "%s: %s." % [opening, why if why.begins_with(player_name) or why.contains(" says ") else "they " + why]


## Every entry on [param card] older than decay_days (since its last
## change) moves one step toward 0 at [param step]: the player ids moved.
static func decay(card: Dictionary, step: int) -> Array[String]:
	var moved: Array[String] = []
	var all: Variant = card.get("standing", {})
	if not all is Dictionary:
		return moved
	var period := setting("decay_days") * maxi(DayNight.day_steps, 1)
	for player_id: String in all:
		var it: Dictionary = all[player_id]
		var value := int(it.get("score", 0))
		if value == 0 or step - int(it.get("since", step)) < period:
			continue
		it["score"] = value - signi(value)
		it["since"] = step
		moved.append(player_id)
	return moved
