class_name Keys
extends RefCounted
## The keys the game's actions are bound to (ui's step 6, decision 453): a
## client-side table, action name -> keycode, the defaults as the game has
## always had them, read from settings.cfg (key_<action>=<key name>) and
## written back by the Options' Controls section ("press a key"). Main and
## the other handlers ask Keys.is(event, "open") in place of a keycode
## test, and Keys.held("attack_friend") for a modifier, so a rebinding
## changes no behaviour; the hints list and the cursor's hint say the bound
## key (Keys.name_of). Esc is never rebound; the WASD walk keys stay as they
## are in this pass (the walk reads the letters themselves).

const DEFAULTS := {
	"open": KEY_E, "pack": KEY_I, "pick_up": KEY_F, "drop": KEY_G, "throw": KEY_T,
	"talk": KEY_ENTER, "talk_log": KEY_TAB, "map": KEY_M, "lantern": KEY_L, "reset": KEY_R,
	"options": KEY_O, "hints": KEY_H, "debug": KEY_F3, "fullscreen": KEY_F11, "builder": KEY_B,
	"phrase_1": KEY_1, "phrase_2": KEY_2, "phrase_3": KEY_3, "phrase_4": KEY_4,
	"attack_friend": KEY_SHIFT, "screenshot": KEY_F12,
}
## What each action is called in the Options, in the order shown.
const WORDS := {
	"open": "Open a chest or a door; talk to someone", "pack": "Your pack", "pick_up": "Pick up",
	"drop": "Put down", "throw": "Throw", "talk": "Talk", "talk_log": "Pin the talk box", "map": "Map",
	"lantern": "Lantern", "reset": "Reset the room", "options": "Options", "hints": "The controls list",
	"debug": "Debug text", "fullscreen": "Fullscreen", "builder": "Builder mode",
	"phrase_1": "Quick phrase 1", "phrase_2": "Quick phrase 2", "phrase_3": "Quick phrase 3", "phrase_4": "Quick phrase 4",
	"attack_friend": "Held with a click: attack a friend", "screenshot": "Screenshot",
}
## Enter's other key counts as Enter.
const ALIASES := {KEY_ENTER: [KEY_KP_ENTER]}

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


## Whether [param action]'s key is held now (a modifier such as attack_friend).
static func held(action: String) -> bool:
	return Input.is_key_pressed(int(bound.get(action, DEFAULTS.get(action, KEY_NONE))))


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
## keys are left as they were.
static func read(settings: Dictionary) -> void:
	for action: String in DEFAULTS:
		var given := str(settings.get("key_%s" % action, ""))
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
