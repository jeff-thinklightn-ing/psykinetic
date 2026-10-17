class_name Season
extends RefCounted
## The seasons, on the world clock (decision 362). Like the hour (DayNight)
## and the weather (Weather), the season is a function of World.steps:
## nothing is stepped, and every peer works out the same year from the
## clock it has. The year starts with spring: 0 spring, 0.25 summer, 0.5
## autumn, 0.75 winter, each season_days days long. Its state (where in the
## year the clock was at year_anchor, and season_days) rides DayNight's: saved
## in the snapshot's "sky", sent in the "sky" message.
##
## What a season does: the sun's path (declination: a winter noon low and its
## days short, DayNight), the land's colour (green, turn: the `season` shader
## uniform the 3D view sets for terrain and scatter), and the cold, from
## which precipitation falls as snow (Weather.at's "snow") and snow lies
## (cover). A region's climate (levels/climates.json "cold") makes it colder
## or warmer. Snow is visual, but for falling snow's cut to sight
## (Weather.sight_factor).

const NAMES: Array[String] = ["spring", "summer", "autumn", "winter"]
const DEFAULT_SEASON_DAYS := 7
## The sun's swing either side of the equinoxes' path, degrees: noon at
## 60° in midsummer, 30° in midwinter (DayNight.LATITUDE puts the
## equinoxes' noon at 45°).
const DECLINATION := 15.0
## Each season's land: green (foliage 0..1) and turn (autumn colour 0..1),
## blended across the boundaries.
const LOOK := {
	"spring": {"green": 0.85, "turn": 0.0},
	"summer": {"green": 1.0, "turn": 0.0},
	"autumn": {"green": 0.55, "turn": 1.0},
	"winter": {"green": 0.25, "turn": 0.3},
}
## The cold (0..1) over which precipitation turns to snow, and over which
## snow comes to lie and cover the ground.
const SNOW_FALLS := Vector2(0.62, 0.78)
const SNOW_LIES := Vector2(0.8, 0.95)

## Days a season lasts.
static var season_days := DEFAULT_SEASON_DAYS
## The year's fraction at the world step year_anchor. A new world starts in
## mid-spring.
static var year_phase := 0.125
static var year_anchor := 0


## The steps a year takes.
static func year_steps() -> float:
	return float(DayNight.day_steps) * 4.0 * season_days


## The year's fraction at world step [param steps]: 0 spring, 0.25 summer,
## 0.5 autumn, 0.75 winter.
static func year_fraction(steps: float) -> float:
	return fposmod(year_phase + (steps - year_anchor) / year_steps(), 1.0)


## The sun's declination at [param steps], degrees: up in summer, down in
## winter, 0 at the equinoxes (the middle of spring and of autumn).
static func declination(steps: float) -> float:
	return DECLINATION * sin((year_fraction(steps) - 0.125) * TAU)


## The cold at the year's [param at] (fraction), 0..1: 1 in midwinter, 0 in
## midsummer, with [param region]'s climate's "cold" added.
static func cold_at(region: String, at: float) -> float:
	var base := 0.5 + 0.5 * cos((at - 0.875) * TAU)
	return clampf(base + float(Weather.climate_of(region).get("cold", 0.0)), 0.0, 1.0)


## [param region]'s season at world step [param steps]: {"name": the
## season it is, "spring", "summer", "autumn", "winter" (weights summing to
## 1, blended over half a day either side of a boundary), "green", "turn"
## (the land's colour, LOOK), "cold" (0..1), "snow" (how much of the ground
## snow covers, 0..1)}.
static func at(region: String, steps: float) -> Dictionary:
	var year := year_fraction(steps)
	var out := weights(year)
	var green := 0.0
	var turn := 0.0
	for name: String in NAMES:
		green += LOOK[name]["green"] * out[name]
		turn += LOOK[name]["turn"] * out[name]
	var cold := cold_at(region, year)
	out["name"] = NAMES[floori(year * 4.0) % 4]
	out["green"] = green
	out["turn"] = turn
	out["cold"] = cold
	out["snow"] = smoothstep(SNOW_LIES.x, SNOW_LIES.y, cold)
	return out


## The seasons' weights at the year's [param at]: the season it is, blended
## into the next over a day either side of the boundary.
static func weights(at: float) -> Dictionary:
	var out := {}
	for name: String in NAMES:
		out[name] = 0.0
	var place := at * 4.0
	var index := floori(place) % 4
	var into := place - floori(place)
	var half := 0.5 / season_days
	var leaving := smoothstep(1.0 - half, 1.0, into)
	var arriving := 1.0 - smoothstep(0.0, half, into)
	var before := (index + 3) % 4
	var after := (index + 1) % 4
	# Into a season, the last one fades out; near its end, the next fades in.
	var weight_before := arriving * 0.5
	var weight_after := leaving * 0.5
	out[NAMES[index]] = 1.0 - weight_before - weight_after
	out[NAMES[before]] += weight_before
	out[NAMES[after]] += weight_after
	return out


## The name of the season at world step [param steps].
static func name_at(steps: float) -> String:
	return NAMES[floori(year_fraction(steps) * 4.0) % 4]


## The share of precipitation that falls as snow at [param cold].
static func snowfall(cold: float) -> float:
	return smoothstep(SNOW_FALLS.x, SNOW_FALLS.y, cold)


## Server: it is the middle of [param name] (NAMES) from now on.
static func set_season(name: String) -> void:
	year_phase = (NAMES.find(name) + 0.5) / 4.0
	year_anchor = World.steps


## Server: a season takes [param days] from now on, the year's place kept.
static func set_season_days(days: int) -> void:
	rebase()
	season_days = maxi(days, 1)


## Keeps the year where it is now before the length of a day or a season
## changes (DayNight.set_day_minutes, set_season_days).
static func rebase() -> void:
	year_phase = year_fraction(World.steps)
	year_anchor = World.steps


## The year's state, with DayNight's (to_dict).
static func to_dict() -> Dictionary:
	return {"season_days": season_days, "year_phase": year_phase, "year_anchor": year_anchor}


## The year from [param data]; missing keys keep the default.
static func from_dict(data: Dictionary) -> void:
	season_days = maxi(int(data.get("season_days", season_days)), 1)
	year_phase = fposmod(float(data.get("year_phase", year_phase)), 1.0)
	year_anchor = int(data.get("year_anchor", year_anchor))


static func reset() -> void:
	season_days = DEFAULT_SEASON_DAYS
	year_phase = 0.125
	year_anchor = 0
