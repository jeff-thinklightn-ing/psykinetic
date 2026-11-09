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


## Turn from [param now] to [param target].
func start(now: float, target: float) -> void:
	turning = true
	stuck = false
	from = now
	to = target
	t = 0.0
	seconds = maxf(absf(target - now) / TURN_SPEED, 0.05)
	move_yaw = now


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
static func choose(yaw: float, clear: Callable, walk: Vector2, hand: float) -> float:
	var within := func(degrees: float) -> bool: return absf(wrapf(degrees - hand, -180.0, 180.0)) <= TURN_MOST + 0.01
	for k in range(1, int(2.0 * TURN_MOST / SEARCH_STEP) + 1):
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


## The way the camera looks across the ground at [param yaw] (x and z):
## Client3D._camera_offset's flat part, reversed.
static func looking(yaw: float) -> Vector2:
	return -Vector2(1.0, 1.0).normalized().rotated(-deg_to_rad(yaw))
