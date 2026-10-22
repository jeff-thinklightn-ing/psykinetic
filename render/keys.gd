class_name Keys
extends RefCounted
## The keys the game's actions are bound to (ui's step 6, decision 453): a
## client-side table, action name -> keycode, the defaults as the game has
## always had them, read from settings.cfg (key_<action>=<key name>) and
## written back by the Options' Controls section ("press a key"). Main and
## the other handlers ask Keys.is(event, "open") in place of a keycode
## test, and Keys.held("stand") for a modifier, so a rebinding
## changes no behaviour; the hints list and the cursor's hint say the bound
## key (Keys.name_of). Esc is never rebound. The walk's four keys (453
## amended: forward, back, left, right; W, S, A, D) are rows like any other,
## read by Main through walk_held as the letters the walk has always taken
## ("wd"), so arrows or ZQSD work once bound; a walk key still at its default
## is also read by its physical place on the keyboard, as before.

const DEFAULTS := {
	"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
	"open": KEY_E, "pack": KEY_I, "pick_up": KEY_F, "drop": KEY_G, "throw": KEY_T,
	"talk": KEY_ENTER, "talk_log": KEY_TAB, "map": KEY_M, "lantern": KEY_L, "reset": KEY_R,
	"options": KEY_O, "hints": KEY_H, "debug": KEY_F3, "fullscreen": KEY_F11, "builder": KEY_K,
	"phrase_1": KEY_1, "phrase_2": KEY_2, "phrase_3": KEY_3, "phrase_4": KEY_4,
	"stand": KEY_SHIFT, "signature": KEY_CTRL, "bandage": KEY_B, "screenshot": KEY_F12, "yes": KEY_Y,
}
## What each action is called in the Options, in the order shown.
const WORDS := {
	"forward": "Walk forward (click scheme: tilt the view up)", "back": "Walk back (click scheme: tilt it down)",
	"left": "Walk left (click scheme: turn)", "right": "Walk right (click scheme: turn)",
	"open": "Open a chest or a door; talk to someone", "pack": "Your pack", "pick_up": "Pick up",
	"drop": "Put down", "throw": "Throw", "talk": "Talk", "talk_log": "Pin the talk box", "map": "Map",
	"lantern": "Lantern", "reset": "Reset the room", "options": "Options", "hints": "The controls list",
	"debug": "Debug text", "fullscreen": "Fullscreen", "builder": "Builder mode",
	"phrase_1": "Quick phrase 1", "phrase_2": "Quick phrase 2", "phrase_3": "Quick phrase 3", "phrase_4": "Quick phrase 4",
	"stand": "Held with a click: swing where you stand, at whatever is there", "signature": "Held with a click: your weapon's own move (a shield bashes)",
	"bandage": "A bandage on the cursor: click yourself or an ally", "screenshot": "Screenshot",
	"yes": "Say yes to an offer that stands",
}
## Enter's other key counts as Enter.
const ALIASES := {KEY_ENTER: [KEY_KP_ENTER]}
## The walk's actions and the letter each has always been to the walk
## (Main.key_vector, --test-walk), in the order the controls list names them.
const WALK := {"forward": "w", "left": "a", "back": "s", "right": "d"}

## action -> keycode, as bound now.
static var bound: Dictionary = DEFAULTS.duplicate()


## Whether [param event] is a press of [param action]'s key (echoes
## excluded unless [param echo]).
static func pressed(event: InputEvent, action: String, echo := false) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or (key.echo and not echo):
		return false
	return matches(key.keycode, action)


## Whether [param keycode] is [param action]'s key or one of its aliases.
static func matches(keycode: int, action: String) -> bool:
	var want := int(bound.get(action, DEFAULTS.get(action, KEY_NONE)))
	return keycode == want or keycode in ALIASES.get(want, [])


## Whether [param action]'s key is held now (a modifier such as stand,
## a walk key). A key still at its default also counts when held by its
## physical place on the keyboard (the walk's W on an AZERTY keyboard, as
## it always did); a rebound one is read by its keycode alone, the key the
## player pressed in the Options.
static func held(action: String) -> bool:
	var want := code(action)
	if Input.is_key_pressed(want):
		return true
	return want == int(DEFAULTS.get(action, KEY_NONE)) and Input.is_physical_key_pressed(want)


## The walk keys held now, as the letters the walk reads ("wd" for
## forward and right), whatever keys they are bound to.
static func walk_held() -> String:
	var held_letters := ""
	for action: String in WALK:
		if held(action):
			held_letters += str(WALK[action])
	return held_letters


## The walk keys' names for the controls list, forward, left, back, right:
## "WASD" while each is one letter, else spaced ("Up Left Down Right").
static func walk_names() -> String:
	var names := PackedStringArray()
	var short := true
	for action: String in WALK:
		var name := name_of(action)
		names.append(name)
		short = short and name.length() == 1
	return "".join(names) if short else " ".join(names)


## Whether [param action]'s key is held as [param event] arrives: the event's
## own modifier flag when the key is Shift, Ctrl or Alt (a test's or a
## replayed event carries them), else the key as held now.
static func held_in(event: InputEvent, action: String) -> bool:
	var want := code(action)
	var mods := event as InputEventWithModifiers
	if mods != null:
		if want == KEY_SHIFT and mods.shift_pressed:
			return true
		if want == KEY_CTRL and mods.ctrl_pressed:
			return true
		if want == KEY_ALT and mods.alt_pressed:
			return true
	return held(action)


## [param action]'s keycode as bound.
static func code(action: String) -> int:
	return int(bound.get(action, DEFAULTS.get(action, KEY_NONE)))


## [param action]'s key as the player reads it ("E", "Tab", "F3").
static func name_of(action: String) -> String:
	return OS.get_keycode_string(code(action))


## [param action] bound to [param keycode]; an action that had that key
## takes this one's old key (a swap), so no key is bound twice.
static func bind(action: String, keycode: int) -> void:
	if not DEFAULTS.has(action) or keycode == KEY_ESCAPE or keycode == KEY_NONE:
		return
	var old := int(bound.get(action, DEFAULTS[action]))
	for other: String in bound:
		if other != action and int(bound[other]) == keycode:
			bound[other] = old
	bound[action] = keycode


static func reset() -> void:
	bound = DEFAULTS.duplicate()


## The bindings from settings lines (key_open=E ...): unknown actions and
## keys are left as they were. 593 renamed attack_friend to stand: its old
## line is read as stand's.
static func read(settings: Dictionary) -> void:
	for action: String in DEFAULTS:
		var given := str(settings.get("key_%s" % action, settings.get("key_attack_friend", "") if action == "stand" else ""))
		if given.is_empty():
			continue
		var found := OS.find_keycode_from_string(given)
		if found != KEY_NONE and found != KEY_ESCAPE:
			bound[action] = found


## The settings lines for every binding that is not the default.
static func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for action: String in DEFAULTS:
		if int(bound.get(action, DEFAULTS[action])) != int(DEFAULTS[action]):
			out.append("key_%s=%s" % [action, name_of(action)])
	return out
