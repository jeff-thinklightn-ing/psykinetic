extends RefCounted
## What the camera follows: the local player as drawn, except that a jump
## (a correction, a slide cut short, a stair's step up) is not passed on in
## one frame. The camera keeps its place and the gap closes over
## SETTLE_SECONDS, while every smooth movement passes straight through:
## a walk or a knockback's slide is followed with no lag, so a slide ends
## with the camera on it, not after. A jump of CUT_TILES or more (a respawn,
## a change of zone) is taken at once: nothing to ease across.

## The gap's time constant: after three of these (180 ms) 5% is left
## (a gap of more than a tile or so takes longer: CLOSE_TILES_PER_SECOND).
const SETTLE_SECONDS := 0.06
## A frame's movement over this, plus what the fastest slide (a push, half
## a tile a tick: 5 tiles a second) moves in the frame, is a jump.
const JUMP_TILES := 0.2
const FASTEST_TILES_PER_SECOND := 6.0
const CUT_TILES := 8.0
## The gap closes no faster than this: a sixth of a tile a frame at 60 fps.
const CLOSE_TILES_PER_SECOND := 10.0

var _last := Vector3.ZERO
var _started := false
## Where the camera is held from the followed point; eases to zero.
var _offset := Vector3.ZERO


## The point to aim at this frame, following [param at] (tiles, 3D).
func follow(at: Vector3, delta: float) -> Vector3:
	if not _started:
		_started = true
		_last = at
		return at
	var moved := at - _last
	_last = at
	if moved.length() >= CUT_TILES:
		_offset = Vector3.ZERO
	elif moved.length() > JUMP_TILES + FASTEST_TILES_PER_SECOND * delta:
		_offset -= moved
	# Closing exponentially, but never faster than CLOSE_TILES_PER_SECOND:
	# a big gap's first frames would otherwise be a jump of their own.
	var gap := _offset.length()
	if gap > 0.0:
		var left := maxf(gap * exp(-delta / SETTLE_SECONDS), gap - CLOSE_TILES_PER_SECOND * delta)
		_offset *= left / gap
	return at + _offset
