extends RefCounted
## Outdoors the camera turns by itself to keep the player in view (decision
## 801): nothing outside fades for the line to them any more (walls, trees,
## the tall pieces), so when what stands between the camera and them hides
## them (Client3D._player_hidden: their chest and one more of its
## FADE_HEIGHTS) for HIDE_SECONDS, the yaw is tried SEARCH_STEP at a time
## both ways, no further than TURN_MOST from the yaw the player last set
## themselves (the coordinator, 2026-11-06: a big swing turns the world,
## the compass and the walk keys under them), and the camera turns, a sine
## out at about TURN_SPEED, to the nearest one from which they are seen
## whole; of two as near, the one looking more the way they walk. It stays
## there, and does not turn back when they come out. After a turn, or a
## search that found none, it waits COOL_DOWN before trying again. The
## player's own turning (A/D, a middle drag, the overhead key) stops a turn
## at once and holds the camera MANUAL_HOLD after. While they are hidden
## and no turn helps (none within TURN_MOST clears, their own turning holds
## it, or Options' "Camera: keep you in view" is off: Client3D._line_fade),
## nothing fades either (623 amended (5)): their rim shows through what
## hides them. Indoors none of this: what hides them fades as before.

const HIDE_SECONDS := 0.6
const COOL_DOWN := 1.5
const SEARCH_STEP := 15.0
const TURN_MOST := 45.0
## Degrees a second, on average over the turn.
const TURN_SPEED := 120.0
const MANUAL_HOLD := 6.0
## The box turn (decision 801 amended (3)): the same turn for the eye in a building's box (Client3D.eye_boxed_at). First numbers, settled on
## ui-design's joined walks of the Mughouse's lane: a standing player's turn starts after BOX_STAND_HOLD and runs at BOX_STAND_SPEED
## (not a startle); the camera holds a box turn of its own (box_off) till the hand yaw has been clear BOX_BACK_HOLD while the player walks
## well clear of every box (the caller's may_back: none at the door, none while stopped), then eases back at BOX_BACK_SPEED, and never
## undoes a turn the hidden-player search made; a turn to the other side waits BOX_FLIP_COOL after the last ended; the search widens to
## BOX_TURN_MOST when 45 degrees finds none, and a search that found none waits BOX_SEARCH_COOL.
const BOX_STAND_HOLD := 0.3
const BOX_STAND_SPEED := 45.0
const BOX_BACK_HOLD := 1.5
const BOX_BACK_SPEED := 60.0
const BOX_FLIP_COOL := 1.0
const BOX_TURN_MOST := 90.0
const BOX_SEARCH_COOL := 1.0

## How long they have been hidden.
var hidden_for := 0.0
## Seconds left before another search.
var cool := 0.0
## Seconds left of the player's own turning's hold.
var held := 0.0
## A turn under way: from, to (degrees of yaw), how far along (0..1), over
## how long; and the yaw the walk keys go by meanwhile (where it set off).
var turning := false
var from := 0.0
var to := 0.0
var t := 1.0
var seconds := 0.0
var move_yaw := 0.0
## The last search found no yaw that clears them, and they are still hidden.
var stuck := false
## Box turn: how long the eye has been in a box (and, standing, the hold's clock); how long the hand yaw has been clear while the
## camera is off it; the cool before a turn to the other side; the side of the last turn (-1, 0, 1).
var boxed_for := 0.0
var back_clear := 0.0
var flip_cool := 0.0
var last_dir := 0.0
## The camera is off the hand yaw by a box turn of this (not by the hidden-player search's, which it never undoes); the cool of a search
## that found no yaw.
var box_off := false
var search_cool := 0.0


## The player turned the camera themselves: any turn stops where it is.
func manual() -> void:
	held = MANUAL_HOLD
	turning = false
	t = 1.0
	hidden_for = 0.0


## One frame of [param delta] seconds, the player [param hidden] or not,
## the Options' turning [param on]: whether to search for a yaw now.
func step(delta: float, hidden: bool, on: bool) -> bool:
	held = maxf(held - delta, 0.0)
	if turning:
		return false
	cool = maxf(cool - delta, 0.0)
	if not hidden:
		hidden_for = 0.0
		stuck = false
		return false
	hidden_for += delta
	return on and held <= 0.0 and cool <= 0.0 and hidden_for >= HIDE_SECONDS


## Turn from [param now] to [param target], at [param speed] degrees a second on average; [param box]: a box turn (the one turn the
## camera later eases back from).
func start(now: float, target: float, speed := TURN_SPEED, box := false) -> void:
	box_off = box
	turning = true
	stuck = false
	from = now
	to = target
	t = 0.0
	seconds = maxf(absf(target - now) / speed, 0.05)
	move_yaw = now
	last_dir = signf(wrapf(target - now, -180.0, 180.0))


## One frame of the box turn: 1 to search for a yaw that clears the eye of its box, 2 to ease back to the hand yaw, 0 for nothing.
## [param boxed]: the eye is (or by the player's walk will be) in a box at this yaw; [param hand_boxed]: at the hand yaw; [param standing]:
## the player is still; [param off_hand]: the camera is off the hand yaw. A turn of its own under way, the player's turning
## (held) and the option off all end it. Walking, a boxed eye searches at once; standing, after BOX_STAND_HOLD; a search that found none
## waits BOX_SEARCH_COOL. [param may_back]: the player walks, well clear of every box; only then, and only off the hand yaw by a box turn
## of this (box_off), does the camera ease back.
func box_step(delta: float, boxed: bool, hand_boxed: bool, standing: bool, off_hand: bool, on: bool, may_back := true) -> int:
	flip_cool = maxf(flip_cool - delta, 0.0)
	search_cool = maxf(search_cool - delta, 0.0)
	if not off_hand:
		box_off = false
	if turning or not on or held > 0.0:
		boxed_for = 0.0
		back_clear = 0.0
		return 0
	if boxed:
		back_clear = 0.0
		boxed_for += delta
		if standing and boxed_for < BOX_STAND_HOLD or search_cool > 0.0:
			return 0
		return 1
	boxed_for = 0.0
	if box_off and may_back and off_hand and not hand_boxed:
		back_clear += delta
		if back_clear >= BOX_BACK_HOLD:
			back_clear = 0.0
			return 2
	else:
		back_clear = 0.0
	return 0


## Whether a turn to [param target] from [param now] would flip to the other side of the last box turn inside BOX_FLIP_COOL.
func flips(now: float, target: float) -> bool:
	var dir := signf(wrapf(target - now, -180.0, 180.0))
	return flip_cool > 0.0 and last_dir != 0.0 and dir != 0.0 and dir != last_dir


## A search found nothing: fade what hides them, and try again after COOL_DOWN.
func not_found() -> void:
	stuck = true
	cool = COOL_DOWN


## The turn's yaw after [param delta] more seconds; at its end it rests
## and the cool-down starts.
func advance(delta: float) -> float:
	t = minf(t + delta / seconds, 1.0)
	if t >= 1.0:
		turning = false
		cool = COOL_DOWN
		flip_cool = BOX_FLIP_COOL
		hidden_for = 0.0
		return to
	return lerpf(from, to, sin(t * PI * 0.5))


## Whether what hides them should fade: [param hidden] and no turn of its
## own coming to help.
func no_help(hidden: bool, on: bool) -> bool:
	return hidden and not turning and (not on or stuck or held > 0.0)


## The nearest yaw to [param yaw], SEARCH_STEP apart either way and within
## TURN_MOST of [param hand] (the yaw the player last set), that [param
## clear] (a Callable(yaw) -> bool) says shows them; of the two at the same
## distance, the one whose camera looks more along [param walk] (the way
## they move on the ground, x and z; ZERO: the one turning positive). NAN
## for none.
static func choose(yaw: float, clear: Callable, walk: Vector2, hand: float, most := TURN_MOST) -> float:
	var within := func(degrees: float) -> bool: return absf(wrapf(degrees - hand, -180.0, 180.0)) <= most + 0.01
	for k in range(1, int(2.0 * most / SEARCH_STEP) + 1):
		var up := yaw + k * SEARCH_STEP
		var down := yaw - k * SEARCH_STEP
		var up_clear: bool = within.call(up) and clear.call(up)
		var down_clear: bool = within.call(down) and clear.call(down)
		if up_clear and down_clear:
			if walk.length() > 0.01 and looking(down).dot(walk) > looking(up).dot(walk):
				return down
			return up
		if up_clear:
			return up
		if down_clear:
			return down
	return NAN


## The yaw, SEARCH_STEP apart from [param yaw] either way and within [param most] of [param hand], that [param ok] (Callable(yaw) -> bool)
## says shows the player and whose eye stays out of every box the longest ([param look], Callable(yaw) -> seconds of the walk it is clear
## for), at least [param least] seconds; of equal looks the nearest. NAN for none. The box turn's fallback when no yaw is clear for the
## whole long look: the one that lasts longest, so a walk is not turned a step at a time as the look moves on.
static func choose_longest(yaw: float, look: Callable, ok: Callable, hand: float, most: float, least: float) -> float:
	var best := NAN
	var best_look := least - 0.001
	for k in range(1, int(2.0 * most / SEARCH_STEP) + 1):
		for side in [1.0, -1.0]:
			var degrees: float = yaw + side * k * SEARCH_STEP
			if absf(wrapf(degrees - hand, -180.0, 180.0)) > most + 0.01:
				continue
			var seconds: float = look.call(degrees)
			if seconds > best_look + 0.001 and ok.call(degrees):
				best = degrees
				best_look = seconds
	return best


## The way the camera looks across the ground at [param yaw] (x and z):
## Client3D._camera_offset's flat part, reversed.
static func looking(yaw: float) -> Vector2:
	return -Vector2(1.0, 1.0).normalized().rotated(-deg_to_rad(yaw))
