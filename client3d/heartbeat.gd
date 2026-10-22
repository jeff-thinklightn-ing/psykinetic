extends Node
## The local player's heart while they lie Mortally Wounded (587, sound's
## side): one beat of sfx.heartbeat (flat, on the UI bus) every 60 /
## Player.heart seconds (120, 80, 40 a minute as Slow Heart steps it), each
## step heard at the next beat, over the rest of the mix ducked DUCK_DB
## (Sfx.set_duck: every bus but UI). Client only: it reads the replicated
## heart, nothing else.
##
## The heart back to 0 ends it. Up again (the player there with hp above 0,
## a revive): no last beat, the mix eased back. Bled out or dead (the
## player gone from the roster, or at 0 hp): one last beat, then SILENCE_DB
## for SILENCE_SECONDS, then the mix eased back.

## How far the rest of the mix sits under the heart.
const DUCK_DB := -14.0
## After the last beat: the mix this far down, for this long.
const SILENCE_DB := -60.0
const SILENCE_SECONDS := 2.0
## dB a second the duck eases at, down and back up.
const DUCK_DOWN_RATE := 40.0
const DUCK_UP_RATE := 10.0

## The view (Client3D): its local player's heart is read each frame.
var view: Node = null
## The heart last heard (beats a minute; 0 not beating).
var heart := 0
## Seconds to the next beat while beating.
var until_beat := 0.0
## Seconds of silence left after a last beat.
var silence_left := 0.0
## The duck now (dB, 0 or less), eased toward its target.
var duck := 0.0
## Beats played, for tests: "beat" or "last" each.
var beats: Array[String] = []


func _process(delta: float) -> void:
	var player: Player = view._local_player() if view != null else null
	step(delta, player.heart if player != null else 0, player != null and player.hp > 0)


## One frame of [param delta] s with the local player's heart at
## [param now] (0 not downed) and [param alive] (there, hp above 0).
func step(delta: float, now: int, alive: bool) -> void:
	if now > 0:
		if heart <= 0:
			until_beat = 0.0  # Downed: the first beat at once.
		else:
			until_beat = minf(until_beat, 60.0 / now)  # A step heard at the next beat.
		heart = now
		silence_left = 0.0
		until_beat -= delta
		if until_beat <= 0.0:
			_beat("beat")
			until_beat += 60.0 / heart
	elif heart > 0:
		heart = 0
		if not alive:
			_beat("last")
			silence_left = SILENCE_SECONDS
	else:
		silence_left = maxf(silence_left - delta, 0.0)
	var target := DUCK_DB if heart > 0 else (SILENCE_DB if silence_left > 0.0 else 0.0)
	var rate := DUCK_DOWN_RATE if target < duck else DUCK_UP_RATE
	var eased := move_toward(duck, target, rate * delta)
	if eased != duck or Sfx.duck_db != eased:
		duck = eased
		Sfx.set_duck(duck)


func _beat(kind: String) -> void:
	beats.append(kind)
	if view != null and view.sfx != null:
		view.sfx.play_flat("sfx.heartbeat")


## The mix back as set as this goes.
func _exit_tree() -> void:
	if duck != 0.0:
		Sfx.set_duck(0.0)
