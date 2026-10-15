class_name DayNight
extends RefCounted
## The time of day, on the world clock (decision 290). Nothing here runs on
## its own: the hour is a function of World.steps, so it stops while the
## server is down as the rest of the world does, and every peer works out
## the same sun from the same clock. A client is not sent World.steps with
## the ticks; the server tells it the clock in a "sky" message (on entering
## a zone, every world tick, and whenever the clock is set), and it counts
## on from there at the tick rate.
##
## The day: the sun rises in the east at 6, stands highest (MAX_ELEVATION,
## to the level's south) at 12 and sets in the west at 18; the moon is
## opposite it. Outdoors, out from under a roof, the sim's light is
## daylight(): 1 by day, NIGHT under the moon, between in the twilight
## (decision 291).

const DEFAULT_DAY_MINUTES := 90.0
## The light under the open sky at night: over Senses.GLIMPSE, under
## Senses.DARK, so an unlit body outdoors at night is glimpsed, never seen,
## and a torch or lantern is what shows it (agreed with enemy-ai).
const NIGHT := 0.2
## The sun's height at noon, degrees.
const MAX_ELEVATION := 60.0
## Daylight is NIGHT with the sun this far below the horizon and full this
## far above it, degrees; smooth between.
const TWILIGHT_LOW := -6.0
const TWILIGHT_HIGH := 12.0
## The zone kinds level.json's "zone" names (Level.zone_of), and the light
## each has where no daylight reaches, 0..1 (a level's "ambient" overrides
## it). Outdoors under a roof is lit as indoors.
const ZONES: Array[String] = ["outdoors", "indoors", "cave", "dungeon"]
const ZONE_AMBIENT := {"outdoors": 1.0, "indoors": 1.0, "cave": 1.0, "dungeon": 1.0}

## Steps a day takes.
static var day_steps := int(DEFAULT_DAY_MINUTES * 60.0 * 10.0)
## The day's fraction (0 midnight, 0.5 noon) at the world step anchor.
static var phase := 0.5
static var anchor := 0
## Daylight now (daylight(now())), kept up by World once a tick: what the
## light field adds outdoors, a lookup per cell.
static var light := 1.0
## Client: the world step the server last said, and when it came (ms).
static var _told_steps := -1
static var _told_at := 0


## The world clock now, in steps (with the part of a step gone, for
## drawing): World's own on the server, counted on from the last "sky"
## message on a client.
static func now() -> float:
	if Net.is_authority() or _told_steps < 0:
		return World.steps + World.tick_alpha
	return _told_steps + (Time.get_ticks_msec() - _told_at) * World.TICK_RATE / 1000.0


## The day's fraction at world step [param steps]: 0 midnight, 0.25 dawn,
## 0.5 noon, 0.75 dusk.
static func fraction(steps: float) -> float:
	return fposmod(phase + (steps - anchor) / float(day_steps), 1.0)


## The hour at [param steps], 0..24.
static func hour(steps: float) -> float:
	return fraction(steps) * 24.0


## The sun's height over the horizon at [param steps], degrees (under it
## at night).
static func elevation(steps: float) -> float:
	return elevation_at(fraction(steps))


## The sun's height at the day's [param at] (fraction), degrees.
static func elevation_at(at: float) -> float:
	var turn := (at - 0.25) * TAU
	return rad_to_deg(asin(sin(turn) * sin(deg_to_rad(MAX_ELEVATION))))


## The sun's direction at [param steps] (unit, toward it), in the level's
## own cells and up: x east, y up, z south, so the caller turns it to the
## level's north. It rises in the east, crosses the south, sets in the west.
static func sun_direction(steps: float) -> Vector3:
	return sun_at(fraction(steps))


## The sun's direction at the day's [param at] (fraction), as sun_direction.
static func sun_at(at: float) -> Vector3:
	var turn := (at - 0.25) * TAU
	var tilt := deg_to_rad(MAX_ELEVATION)
	return Vector3(cos(turn), sin(turn) * sin(tilt), sin(turn) * cos(tilt)).normalized()


## The light under the open sky at [param steps]: NIGHT to 1.
static func daylight(steps: float) -> float:
	return NIGHT + (1.0 - NIGHT) * smoothstep(TWILIGHT_LOW, TWILIGHT_HIGH, elevation(steps))


## Keeps [member light] up with the clock (World, once a tick).
static func update() -> void:
	light = daylight(now())


## The clock as the server tells it to clients ("sky"), and as it is saved.
static func to_dict() -> Dictionary:
	return {"day_steps": day_steps, "phase": phase, "anchor": anchor}


## The clock from [param data] (a snapshot's "sky", or a "sky" message
## whose "steps" is the server's World.steps then). Missing keys keep the
## default.
static func from_dict(data: Dictionary) -> void:
	day_steps = maxi(int(data.get("day_steps", day_steps)), 600)
	phase = fposmod(float(data.get("phase", phase)), 1.0)
	anchor = int(data.get("anchor", anchor))
	if data.has("steps"):
		_told_steps = int(data["steps"])
		_told_at = Time.get_ticks_msec()
	update()


## Back to the default clock (a test, a client leaving a server).
static func reset() -> void:
	day_steps = int(DEFAULT_DAY_MINUTES * 60.0 * 10.0)
	phase = 0.5
	anchor = 0
	_told_steps = -1
	light = 1.0


## Server: the hour is [param at] (0..24) from now on.
static func set_hour(at: float) -> void:
	phase = fposmod(at / 24.0, 1.0)
	anchor = World.steps
	update()


## Server: a day takes [param minutes] from now on, the hour kept.
static func set_day_minutes(minutes: float) -> void:
	var steps_now := World.steps
	phase = fraction(steps_now)
	anchor = steps_now
	day_steps = maxi(roundi(minutes * 60.0 * World.TICK_RATE), 600)
	update()


## The light where no daylight reaches in a zone of [param zone] (ZONES).
static func base_ambient(zone: String) -> float:
	return float(ZONE_AMBIENT.get("indoors" if zone == "outdoors" else zone, 1.0))
