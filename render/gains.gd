class_name Gains
extends Control
## What the player gains, shown as it happens (decision 804; Jeff: "the player
## needs to learn early that they get rewarded for everything they do"). The
## server's "reward" message, one per gain, {track, amount, words, of, at,
## big, step, banner, bar, gold, bars} (Main.reward), comes here (add):
##   - a float: "Umbrage (Regard +1)" (Jeff's form: the thing, then the
##     track's word and amount in brackets), rising over the deed's cell (at) or over the player and fading;
##     the same track and whose within MERGE_SECONDS rolls up the live one's
##     number, so a burst is one float; FLOATS_AT_ONCE at most, the rest wait;
##   - a banner, top centre, for a big gain or a step (a ladder's next rung):
##     its "banner" words (voice's: "Umbrage knows you", "Hollowfell"), else
##     its words, the gain in brackets after; BANNER_SECONDS each, one at a
##     time, queued; a zone's name the arrival card already
##     shows is not shown twice (shown_elsewhere);
##   - a line in the log (the talk panel's Gains), the session's last LOG_KEPT,
##     merged as the floats are, newest last;
##   - sound's cue (ui.reward_*), one per burst, CUE_GAP apart, a little higher
##     as a burst merges.
## Only gains: an amount of 0 or less is never shown (the server drops them
## too). Net.gains_shown: "all"; "quiet" (no banners, the cues softer); "log"
## (the log alone). In a fight (fighting: a blow given or taken lately) the
## floats are smaller and the banners and their cues wait until it is over.
## Each track's word, colour and cue are TRACKS'; one unknown shows in brass
## with no word ("Umbrage (+1)"), so a later emitter needs no new client.

## The tracks (decision 804): label is voice's word (none for gold and item,
## whose "of" is the thing itself: "+12 gold", "+2 hides"), color the float's
## and the log line's, cue sound's slot for an ordinary gain.
const TRACKS := {
	"explore": {"label": "Wayfaring", "color": "#9cc8e0", "cue": "ui.reward_found"},
	"regard": {"label": "Regard", "color": "#ffd27a", "cue": "ui.reward_gain"},
	"bond": {"label": "Bond", "color": "#eaa0a0", "cue": "ui.reward_gain"},
	# A companion's needs (companions' six; Jeff picked Shelter): the need cue, one a frame.
	"leisure": {"label": "Ease", "color": "#a8c870", "cue": "ui.reward_need"},
	"adventure": {"label": "Venture", "color": "#d8a070", "cue": "ui.reward_need"},
	"wonder": {"label": "Wonder", "color": "#b0a0e0", "cue": "ui.reward_need"},
	"faith": {"label": "Faith", "color": "#e8d8a0", "cue": "ui.reward_need"},
	"safety": {"label": "Shelter", "color": "#90b8a8", "cue": "ui.reward_need"},
	"company": {"label": "Company", "color": "#e0b0c8", "cue": "ui.reward_need"},
	"practice": {"label": "Practice", "color": "#c4d0d8", "cue": "ui.reward_gain"},
	"deed": {"label": "Deeds", "color": "#f0b860", "cue": "ui.reward_gain"},
	"catch": {"label": "Catch", "color": "#7cc8c0", "cue": "ui.reward_catch"},
	"gold": {"label": "", "color": "#c79a55", "cue": "ui.reward_coin"},
	"item": {"label": "", "color": "#f4efe6", "cue": "ui.reward_gain"},
}
## A track not in TRACKS.
const OTHER := {"label": "", "color": "#c79a55", "cue": "ui.reward_gain"}
## A thing the server words one way, shown another: Jeff's own capital.
const THINGS := {"a fight won": "Fight Won"}
## The cues over a track's own: a step, a want met (a big deed), and the
## one every slot falls back to before sound's takes are in (SoundKit.has).
const STEP_CUE := "ui.reward_step"
const WANT_CUE := "ui.reward_want"
const FALLBACK_CUE := "ui.reward_gain"
## A companion's need met (sound's soft note, under the gain's): one a frame
## however many needs one deed meets, and only on a frame no other cue was
## asked for (sound: her bond's gain, or a step, is the bigger news, and two
## takes in random keys clash); played at the frame's end (_flush_need).
const NEED_CUE := "ui.reward_need"
const SHOWN := ["all", "quiet", "log"]
## A thing's last word counted as a mass, never pluralised (voice: "+20 food",
## "+2 leather"); any other counted thing's last word is (World._plural:
## "+2 hides", "+2 wood bundles").
const MASS_WORDS := ["dice", "food", "leather", "meat", "wool", "cloth", "ore", "wood", "stone", "fish", "herbs", "grain", "flour", "salt", "iron", "copper", "tin", "silver", "venison", "mutton", "pork"]

const MERGE_SECONDS := 1.0
const FLOAT_SECONDS := 1.4
const FLOAT_FADE := 0.4
## How far a float rises over its life, in tiles (1.5 m).
const FLOAT_RISE_TILES := 1.5
## Floats over one another, in lines.
const FLOAT_STACK := 1.1
const FLOATS_AT_ONCE := 3
## A float's size, times the HUD's text (the coordinator on the still: "the
## reward centre" reads small at 1080p).
const FLOAT_SCALE := 1.3
## A float pops in: from POP_FROM of its size up to POP_PEAK in POP_UP
## seconds, then settles to its size in POP_SETTLE.
const POP_FROM := 0.7
const POP_PEAK := 1.25
const POP_UP := 0.08
const POP_SETTLE := 0.14
const FIGHT_SCALE := 0.7
const FIGHT_SECONDS := 4.0
## A body this near (cells): a blow on it, or it hunting or fighting, is a
## fight (Main._in_fight).
const FIGHT_NEAR := 8
## Jeff, 2026-11-06: "banners fade too fast".
const BANNER_SECONDS := 5.0
const BANNER_FADE := 0.4
## The banner's middle, down the screen's height.
const BANNER_AT := 0.18
const LOG_KEPT := 40
const CUE_GAP := 0.25
## Each merge raises the burst's cue this much, up to CUE_HIGHEST.
const CUE_RISE := 0.06
const CUE_HIGHEST := 1.3
const QUIET_DB := -6.0
## Practice in a fight (playtest's bear tour: "Practice, swordplay" eleven
## times in 13 s): an art's rises are held, and float as one when the fight
## is over, or once none has come for HOLD_SECONDS; a whole step (a tenth of
## the bar, Main._practice_gained) floats at once, with what was held.
const HOLD_SECONDS := 10.0

## A line was logged or merged (the talk panel's Gains redraws).
signal logged

## Net.gains_shown's, set by Main.
var shown := "all"
## (at: a cell or null) -> the screen point over it (null: over the local
## player), or null when it is not to be seen.
var anchor_of: Callable
## () -> screen px per tile now.
var tile_px: Callable
## () -> whether a blow was given or taken lately (Main).
var fighting: Callable
## (slot, pitch, volume_db): plays a ui cue (Main: ui_sounds through Sfx).
var play: Callable
## (slot) -> whether sound has takes for it (SoundKit.has).
var has_cue: Callable
## (banner text) -> whether another panel shows it now (the arrival card).
var shown_elsewhere: Callable

## The live floats: {key, track, of, amount, at, born, color, small}.
var floats: Array[Dictionary] = []
## Floats past FLOATS_AT_ONCE, in turn.
var waiting: Array[Dictionary] = []
## The banners to come: {text, color}; the one up is _banner.
var banners: Array[Dictionary] = []
## The log, newest last: {time, key, track, text, words, amount, of, t}.
var lines: Array[Dictionary] = []
## Each cue played (tests): [slot, pitch].
var cues: Array[Array] = []
var _banner := {}
var _last_cue := -100.0
## The frame a need cue waits on (-1 none), and the frame another cue was
## last asked for.
var _need_frame := -1
var _other_frame := -1
var _burst := 0
## Practice held in a fight: art -> {amount, last} (HOLD_SECONDS).
var held: Dictionary = {}
## The floats and the banner drawn the last time (tests): the canvas keeps
## its last drawing until the next, so one more is asked for after the last
## goes (Jeff on v0.1.208: deed texts left faint on the screen till a zone change).
var drawn := 0


func _init() -> void:
	name = "Gains"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## The float's, the log's words for [param track] [param amount] of [param of]
## (Jeff, 2026-11-06: the thing first, the track and amount in brackets):
## "Umbrage (Regard +1)", "Fight Won (Deeds +1)", "Deeds +1", "+12 gold",
## "+2 hides".
static func text_of(track: String, amount: float, of: String) -> String:
	if track == "gold":
		return _number(amount) + " gold"
	if track == "item":
		return _number(amount) + " " + counted(of, amount)
	var thing := thing_of(of)
	return gain_of(track, amount) if thing.is_empty() else thing + " (" + gain_of(track, amount) + ")"


## [param track]'s word and [param amount]: "Regard +1"; "+1" for a track
## with no word.
static func gain_of(track: String, amount: float) -> String:
	var label := str(TRACKS.get(track, OTHER)["label"])
	return _number(amount) if label.is_empty() else label + " " + _number(amount)


## [param of] as a float or the log shows it (voice's label rule): THINGS'
## own, else a leading a, an or the dropped and the first letter capitalised,
## a name keeping its own ("a hill cat": "Hill cat"; "swordplay":
## "Swordplay").
static func thing_of(of: String) -> String:
	var thing := of.strip_edges()
	if THINGS.has(thing):
		return str(THINGS[thing])
	for article: String in ["a ", "an ", "the "]:
		if thing.to_lower().begins_with(article) and thing.length() > article.length():
			thing = thing.substr(article.length())
			break
	return thing.left(1).to_upper() + thing.substr(1)


static func _number(amount: float) -> String:
	return "+" + (str(int(amount)) if is_equal_approx(amount, roundf(amount)) else String.num(amount, 1))


## [param thing] counted [param amount]: its head word pluralised past one
## (the last, or the one before "of": "bundles of wood"), unless a mass
## (MASS_WORDS) or already plural (ending in s: "amber beads", "boots").
static func counted(thing: String, amount: float) -> String:
	var words := thing.split(" ")
	var head := words.find("of") - 1 if words.find("of") > 0 else words.size() - 1
	var word := words[head]
	if amount <= 1.0 or word.is_empty() or word.to_lower() in MASS_WORDS or word.ends_with("s"):
		return thing
	words[head] = World._plural(word)
	return " ".join(words)


static func color_of(track: String) -> Color:
	return Color.html(str(TRACKS.get(track, OTHER)["color"]))


## A "reward" message's gain shown; false when it is no gain (an amount of 0
## or less, no track).
func add(data: Dictionary) -> bool:
	var track := str(data.get("track", ""))
	var amount := float(data.get("amount", 0)) if data.get("amount") is float or data.get("amount") is int else 0.0
	if track.is_empty() or not amount > 0.0:
		return false
	var of := str(data.get("of", ""))
	var key := track + "|" + of
	var now := _now()
	if track == "practice" and data.get("folded") != true:
		var kept: Dictionary = held.get(of, {})
		if data.get("whole") != true and _fighting():
			held[of] = {"amount": float(kept.get("amount", 0.0)) + amount, "last": now}
			return true
		amount += float(kept.get("amount", 0.0))  # A step: what was held floats with it.
		held.erase(of)
	var at: Variant = Snapshot.vector(data.get("at"))
	var words := str(data.get("words", ""))
	# Lines worded by the server, not counted here (playtest's reward tour):
	# things handed in, by their own count ("+10 ore", not the town's name).
	# No gold owed any more (826: every sale paid in full).
	var fixed := ""
	if track == "item" and not str(data.get("counted", "")).is_empty():
		fixed = "+" + str(data["counted"])
	if not fixed.is_empty():
		key = track + "|=" + fixed
	var merged := false
	var line: Dictionary = lines.back() if not lines.is_empty() else {}
	if not line.is_empty() and line["key"] == key and now - float(line["t"]) < MERGE_SECONDS:
		line["amount"] = float(line["amount"]) + amount
		line["text"] = fixed if not fixed.is_empty() else text_of(track, line["amount"], of)
		if not words.is_empty():
			line["words"] = words
		line["t"] = now
	else:
		lines.append({"time": Time.get_time_string_from_system().substr(0, 8), "key": key, "track": track, "of": of,
			"amount": amount, "text": fixed if not fixed.is_empty() else text_of(track, amount, of), "words": words, "t": now})
		while lines.size() > LOG_KEPT:
			lines.pop_front()
	var in_fight := _fighting()
	if shown != "log":
		for live: Dictionary in floats + waiting:
			if live["key"] == key and now - float(live["merged"]) < MERGE_SECONDS:
				live["amount"] = float(live["amount"]) + amount
				live["merged"] = now
				merged = true
				break
		if not merged:
			var made := {"key": key, "track": track, "of": of, "amount": amount, "at": at, "born": now, "merged": now,
				"color": color_of(track), "small": in_fight}
			if not fixed.is_empty():
				made["text"] = fixed
			if floats.size() < FLOATS_AT_ONCE:
				floats.append(made)
			else:
				waiting.append(made)
	var step := str(data.get("step", ""))
	var big: bool = data.get("big") == true or not step.is_empty()
	if big and shown == "all":
		var text := str(data.get("banner", "")).strip_edges()
		if text.is_empty():
			text = words
		var elsewhere := shown_elsewhere.is_valid() and bool(shown_elsewhere.call(text))
		if not text.is_empty() and not elsewhere and not banners.any(func(each: Dictionary) -> bool: return each["bare"] == text) \
				and str(_banner.get("bare", "")) != text:
			# Its own words whole, the gain in brackets after (not gold's or an item's).
			var line_up := text if track in ["gold", "item"] else text + " (" + gain_of(track, amount) + ")"
			banners.append({"text": line_up, "bare": text, "color": color_of(track)})
	if shown != "log":
		var slot: String = str(TRACKS.get(track, OTHER)["cue"])
		if not step.is_empty():
			slot = STEP_CUE
		elif track == "deed" and big:
			slot = WANT_CUE
		# In a fight only a step sounds; the rest of the burst is the float.
		if not in_fight or not step.is_empty():
			_cue(slot, merged, now)
	logged.emit()
	queue_redraw()
	return true


## The float's text now (tests, _draw).
func float_text(live: Dictionary) -> String:
	if live.has("text"):
		return str(live["text"])
	return text_of(live["track"], live["amount"], live["of"])


## The banner up now, "" for none (tests).
func banner_shown() -> String:
	return str(_banner.get("text", ""))


func _cue(slot: String, merged: bool, now: float) -> void:
	if slot == NEED_CUE:
		_need_frame = Engine.get_process_frames()  # Waits for the frame's end.
		return
	_other_frame = Engine.get_process_frames()
	if now - _last_cue < CUE_GAP:
		return
	_burst = _burst + 1 if merged else 0
	_last_cue = now
	_play(slot)


## The need cue waiting, once its frame is over (the next _process): played
## unless another cue was asked for that frame.
func _flush_need() -> void:
	if _need_frame < 0 or _need_frame >= Engine.get_process_frames():
		return
	var frame := _need_frame
	_need_frame = -1
	if frame != _other_frame:
		_play(NEED_CUE)


func _play(slot: String) -> void:
	var chosen := slot
	if has_cue.is_valid() and not bool(has_cue.call(chosen)):
		chosen = FALLBACK_CUE
		if not bool(has_cue.call(chosen)):
			return
	var pitch := minf(1.0 + CUE_RISE * _burst, CUE_HIGHEST)
	cues.append([chosen, pitch])
	if play.is_valid():
		play.call(chosen, pitch, QUIET_DB if shown == "quiet" else 0.0)


## A float's pop at [param age] seconds: a quick swell, then its size (1).
static func pop(age: float) -> float:
	if age < POP_UP:
		return lerpf(POP_FROM, POP_PEAK, age / POP_UP)
	if age < POP_UP + POP_SETTLE:
		return lerpf(POP_PEAK, 1.0, (age - POP_UP) / POP_SETTLE)
	return 1.0


func _fighting() -> bool:
	return fighting.is_valid() and bool(fighting.call())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	_flush_need()
	var now := _now()
	var in_fight := _fighting()  # Asked each frame, so a fall in hit points is seen.
	var showing := not floats.is_empty() or not _banner.is_empty() or drawn > 0
	for art: String in held.keys():
		if not in_fight or now - float(held[art]["last"]) >= HOLD_SECONDS:
			var amount := float(held[art]["amount"])
			held.erase(art)
			add({"track": "practice", "amount": amount, "of": art, "folded": true})
	floats = floats.filter(func(live: Dictionary) -> bool: return now - float(live["born"]) < FLOAT_SECONDS)
	while floats.size() < FLOATS_AT_ONCE and not waiting.is_empty():
		var next: Dictionary = waiting.pop_front()
		next["born"] = now
		floats.append(next)
	if not _banner.is_empty() and now - float(_banner["born"]) >= BANNER_SECONDS:
		_banner = {}
	if _banner.is_empty() and not banners.is_empty() and not in_fight:
		_banner = banners.pop_front()
		_banner["born"] = now
	# Drawn again while anything shows, and once more after the last of it
	# goes, so its last faint frame never stays on the canvas.
	if showing or not floats.is_empty() or not _banner.is_empty():
		queue_redraw()


func _draw() -> void:
	var now := _now()
	drawn = 0
	var font := UiTheme.font("serif_bold")
	var outline := UiTheme.color("outline")
	var px := float(tile_px.call()) if tile_px.is_valid() else SpeechBubbles.REFERENCE_TILE_PX
	var size_hud := UiTheme.size("hud")
	var stacked := {}
	for live: Dictionary in floats:
		var where: Variant = anchor_of.call(live["at"]) if anchor_of.is_valid() else null
		if where is not Vector2:
			continue
		var age := now - float(live["born"])
		var alpha := clampf((FLOAT_SECONDS - age) / FLOAT_FADE, 0.0, 1.0)
		var font_size := maxi(int(size_hud * FLOAT_SCALE * (FIGHT_SCALE if live["small"] else 1.0) * pop(age)), 1)
		var spot := str(live["at"])
		var row := int(stacked.get(spot, 0))
		stacked[spot] = row + 1
		var text := float_text(live)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at: Vector2 = where - Vector2(width / 2.0, px * FLOAT_RISE_TILES * age / FLOAT_SECONDS + row * font_size * FLOAT_STACK)
		var color: Color = live["color"]
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.constant("outline") * 2,
			Color(outline, outline.a * alpha))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, alpha))
		drawn += 1
	if not _banner.is_empty():
		var age := now - float(_banner["born"])
		var alpha := clampf(minf(age / BANNER_FADE, (BANNER_SECONDS - age) / BANNER_FADE), 0.0, 1.0)
		var big_font := UiTheme.font("serif_bold")
		var font_size := UiTheme.size("title")
		var text := str(_banner["text"])
		var width := big_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := Vector2((size.x - width) / 2.0, size.y * BANNER_AT)
		var color: Color = _banner["color"]
		draw_string_outline(big_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.constant("outline") * 3,
			Color(outline, outline.a * alpha))
		draw_string(big_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, alpha))
		drawn += 1
