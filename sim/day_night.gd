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
## The day: the sun rises in the east, stands highest (to the level's
## south) at 12 and sets in the west; the moon is opposite it. Its path
## follows the season (Season.declination, decision 362): at the
## equinoxes it rises at 6, sets at 18 and stands 45° high at noon; in
## midsummer about 5 to 19 and 60°, in midwinter about 7 to 17 and 30°. Outdoors, out from under a roof, the sim's light is
## daylight(): 1 by day, NIGHT under the moon, between in the twilight
## (decision 291).

const DEFAULT_DAY_MINUTES := 90.0
## The light under the open sky at night: over Senses.GLIMPSE, under
## Senses.DARK, so an unlit body outdoors at night is glimpsed, never seen,
## and a torch or lantern is what shows it (agreed with enemy-ai).
const NIGHT := 0.2
## The world's latitude, degrees: the equinoxes' noon is 90° less it.
const LATITUDE := 45.0
## Daylight is NIGHT with the sun this far below the horizon and full this
## far above it, degrees; smooth between.
const TWILIGHT_LOW := -6.0
const TWILIGHT_HIGH := 12.0
## The zone kinds level.json's "zone" names (Level.zone_of), and the light
## each has where no daylight reaches, 0..1 (a level's "ambient" overrides
## it); outdoors under a roof is lit as indoors (decision 304). Against
## Senses' thresholds: indoors is dim but over DARK (light through doors
## and windows: you are seen), a cave is moonlight's (glimpsed only), a
## dungeon is under GLIMPSE (blind without a light). Every player and
## companion carries a lantern, so nothing is black.
const ZONES: Array[String] = ["outdoors", "indoors", "cave", "dungeon"]
const ZONE_AMBIENT := {"outdoors": 0.4, "indoors": 0.4, "cave": 0.2, "dungeon": 0.1}
## The sky in words, for voices (describe, decision 389). The hour by the
## clock (0 midnight, 12 noon): "dusk", "the middle of the night"; never a
## number.
const HOURS := [[4.0, "the middle of the night"], [5.5, "the small hours before dawn"], [7.0, "dawn"],
	[11.0, "morning"], [13.0, "midday"], [17.0, "afternoon"], [18.0, "evening"], [19.5, "dusk"],
	[22.0, "night"], [24.0, "the middle of the night"]]
## The weather (Weather.KINDS) in words; in the cold, SNOW_WORDS.
const WEATHER_WORDS := {"clear": "the sky is clear", "overcast": "the sky is grey with cloud", "rain": "it is raining",
	"fog": "fog lies thick", "wind": "a strong wind is blowing", "storm": "a storm is raging"}
const SNOW_WORDS := {"rain": "snow is falling", "storm": "snow is blowing in a storm"}
## A season in thirds: early, the middle, late.
const SEASON_WORDS := {"spring": ["early spring", "mid-spring", "late spring"],
	"summer": ["early summer", "midsummer", "late summer"], "autumn": ["early autumn", "mid-autumn", "late autumn"],
	"winter": ["early winter", "midwinter", "late winter"]}
## The light under which it is dark: the night's (Animal.NIGHT_LIGHT).
const DARK_LIGHT := Animal.NIGHT_LIGHT

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
	return elevation_at(fraction(steps), Season.declination(steps))


## The sun's height at the day's [param at] (fraction), degrees, on a day
## of [param tilt] (Season.declination; NAN: today's).
static func elevation_at(at: float, tilt := NAN) -> float:
	return rad_to_deg(asin(clampf(sun_at(at, tilt).y, -1.0, 1.0)))


## The sun's direction at [param steps] (unit, toward it), in the level's
## own cells and up: x east, y up, z south, so the caller turns it to the
## level's north. It rises in the east, crosses the south, sets in the west.
static func sun_direction(steps: float) -> Vector3:
	return sun_at(fraction(steps), Season.declination(steps))


## The sun's direction at the day's [param at] (fraction), as sun_direction,
## on a day of [param tilt] (Season.declination; NAN: today's).
static func sun_at(at: float, tilt := NAN) -> Vector3:
	if is_nan(tilt):
		tilt = Season.declination(now())
	var hour_angle := (at - 0.5) * TAU
	var latitude := deg_to_rad(LATITUDE)
	var declination := deg_to_rad(tilt)
	var up := sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hour_angle)
	var east := -cos(declination) * sin(hour_angle)
	var south := sin(latitude) * cos(declination) * cos(hour_angle) - cos(latitude) * sin(declination)
	return Vector3(east, up, south).normalized()


## The light under the open sky at [param steps]: NIGHT to 1.
static func daylight(steps: float) -> float:
	return daylight_at(fraction(steps), Season.declination(steps))


## The light under the open sky at the day's [param at] (fraction), on a
## day of [param tilt] (NAN: today's).
static func daylight_at(at: float, tilt := NAN) -> float:
	return NIGHT + (1.0 - NIGHT) * smoothstep(TWILIGHT_LOW, TWILIGHT_HIGH, elevation_at(at, tilt))


## Keeps [member light] up with the clock (World, once a tick).
static func update() -> void:
	light = daylight(now())


## The clock as the server tells it to clients ("sky"), and as it is saved.
static func to_dict() -> Dictionary:
	var data := {"day_steps": day_steps, "phase": phase, "anchor": anchor}
	data.merge(Season.to_dict())
	return data


## The clock from [param data] (a snapshot's "sky", or a "sky" message
## whose "steps" is the server's World.steps then). Missing keys keep the
## default.
static func from_dict(data: Dictionary) -> void:
	day_steps = maxi(int(data.get("day_steps", day_steps)), 600)
	phase = fposmod(float(data.get("phase", phase)), 1.0)
	anchor = int(data.get("anchor", anchor))
	Season.from_dict(data)
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
	Season.reset()


## Server: the hour is [param at] (0..24) from now on.
static func set_hour(at: float) -> void:
	phase = fposmod(at / 24.0, 1.0)
	anchor = World.steps
	update()


## Server: a day takes [param minutes] from now on, the hour kept.
static func set_day_minutes(minutes: float) -> void:
	var steps_now := World.steps
	Season.rebase()
	phase = fraction(steps_now)
	anchor = steps_now
	day_steps = maxi(roundi(minutes * 60.0 * World.TICK_RATE), 600)
	update()


## The light where no daylight reaches in a zone of [param zone] (ZONES).
static func base_ambient(zone: String) -> float:
	return float(ZONE_AMBIENT.get("indoors" if zone == "outdoors" else zone, ZONE_AMBIENT["indoors"]))


## The hour [param hour] (0..24) in words (HOURS).
static func time_words(hour: float) -> String:
	for each: Array in HOURS:
		if hour < float(each[0]):
			return each[1]
	return HOURS.back()[1]


## The sky over [param region] at world step [param steps] in plain facts,
## for a voice's "now" (decision 389): {"hour": time_words, "season": its
## name, "season_words": "midwinter", "late autumn", "weather": the
## weather in words (snow's in the cold), "ground": "snow lies on the
## ground" or "", "dark": whether it is night-dark under the open sky,
## "storm": whether a storm blows (snow's too), "sentence": all of it in
## one line}. Where one is (indoors, under a roof) is the caller's.
static func describe(region: String, steps: float) -> Dictionary:
	var season := Season.at(region, steps)
	var weather := Weather.at(region, steps)
	var kind := str(weather["kind"])
	var words := str(WEATHER_WORDS.get(kind, ""))
	var snowing: bool = weather.get("snow", 0.0) > weather["rain"] and SNOW_WORDS.has(kind)
	if snowing:
		words = SNOW_WORDS[kind]
	var name := str(season["name"])
	var third := clampi(floori(fposmod(Season.year_fraction(steps) * 4.0, 1.0) * 3.0), 0, 2)
	var ground := "snow lies on the ground" if season["snow"] > 0.5 else ""
	var hour_words := time_words(hour(steps))
	var sentence := "It is %s in %s" % [hour_words, SEASON_WORDS[name][third]]
	if words != "":
		sentence += "; " + words
	if ground != "":
		sentence += (", and " if words != "" else "; ") + ground
	return {"hour": hour_words, "season": name, "season_words": SEASON_WORDS[name][third], "weather": words, "ground": ground,
		"dark": daylight(steps) < DARK_LIGHT, "storm": kind == "storm", "sentence": sentence + "."}
