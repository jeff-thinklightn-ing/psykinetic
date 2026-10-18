class_name Weather
extends RefCounted
## The weather, per region, on the world clock (decision 307). Like
## the hour (DayNight) it is a function of World.steps: the day is cut into
## spells (a climate's "spell", a share of a day), each spell's kind picked
## from the region's climate by a hash of the region and the spell, and the
## change from one spell's kind to the next blended over the climate's
## "change" (a share of a spell). So nothing is stepped or saved, and every
## peer works out the same weather from the clock it already has. The one
## exception is the console's override (`weather <kind>`), kept in
## [member overrides], saved and sent with the clock in the "sky" message,
## with the climates themselves (a client uses the server's).
##
## A level names its region (level.json "region", Level.region_of: a lore
## region id); levels/climates.json gives each region its climate, else the
## file's "default". Its numbers are placeholders until lore and Jeff agree
## each region's character.
##
## What the weather does in play (decision 308), outdoors only,
## out from under a roof: cloud dims the sky's light, fog and rain shorten
## sight (sight_factor), rain and wind cover noise (hearing_factor).
##
## In the cold (Season, decision 362) what falls is snow: at's "snow" is the
## share of the rain the cold turns to snow, taken out of "rain"; falling
## snow cuts sight at SNOW_SIGHT, and covers no noise. A climate's "seasons"
## may give a season weights of its own, and its "cold" makes the region
## colder (or, below 0, warmer) than the year.
##
## Weather in the towns (decision 384): storms_between and rain_between
## say what fell between two world steps, for whoever keeps count (the
## towns' wells pull rain_between). On the world tick the server breaks
## roofs with break_roofs: each storm since the last check may break each
## standing roof of every level, by a roll seeded from the storm and the
## roof, so a replay breaks the same ones.

const FILE := "res://levels/climates.json"
## Each kind as how much cloud, rain, fog and wind it brings, 0..1.
const KINDS := {
	"clear": {"cloud": 0.0, "rain": 0.0, "fog": 0.0, "wind": 0.1},
	"overcast": {"cloud": 0.8, "rain": 0.0, "fog": 0.1, "wind": 0.2},
	"rain": {"cloud": 0.9, "rain": 0.7, "fog": 0.15, "wind": 0.3},
	"fog": {"cloud": 0.5, "rain": 0.0, "fog": 0.9, "wind": 0.0},
	"wind": {"cloud": 0.3, "rain": 0.0, "fog": 0.0, "wind": 0.9},
	"storm": {"cloud": 1.0, "rain": 1.0, "fog": 0.3, "wind": 1.0},
}
## A climate's spell and change when it gives none: a quarter day, and a
## tenth of that to change.
const DEFAULT_SPELL := 0.25
const DEFAULT_CHANGE := 0.1
## How much of the day's light full cloud takes (a storm's day stays well
## over Senses.DARK).
const CLOUD_DIM := 0.25
## Roofs and storms (break_roofs): a storm under STORM_MIN breaks none, a
## full one each roof with ROOF_CHANCE; a climate's "storm_min" and
## "roof_chance" override them. After a gap (a server down) storms count
## back at most CATCH_UP days.
const STORM_MIN := 0.6
const ROOF_CHANCE := 0.25
const CATCH_UP := 2.0
## Sight and hearing at full fog, rain and wind: a share of the range each
## takes away.
const FOG_SIGHT := 0.55
const RAIN_SIGHT := 0.25
const SNOW_SIGHT := 0.15
const RAIN_HEARING := 0.3
const WIND_HEARING := 0.25
## Drips under a forest's canopy (drip_at, decision 477): while the rain is
## DRIP_RAIN or more, and after it, fading over DRIP_SECONDS times the
## cover; how far apart the look back steps (seconds).
const DRIP_RAIN := 0.3
const DRIP_SECONDS := 90.0
const DRIP_LOOK := 3.0

## The climates by region, as levels/climates.json has them (or as the
## server sent them).
static var _climates := {}
## The console's overrides, by region: {kind, from, until} (world steps).
static var overrides := {}
## Server: the world step up to which storms have broken roofs
## (break_roofs), saved with the sky; -1 for never.
static var storms_checked := -1
## drip_at's look back, by region: [the DRIP_LOOK it was for, seconds since
## the rain was last DRIP_RAIN].
static var _rain_ago := {}


## The climates, read on first use.
static func climates() -> Dictionary:
	if _climates.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if data is Dictionary:
			for key: String in data:
				if not key.begins_with("_") and data[key] is Dictionary:
					_climates[key] = data[key]
		if not _climates.has("default"):
			_climates["default"] = {"weights": {"clear": 1.0}}
	return _climates


## Uses [param data] for the climates (a "sky" message's, or a test's).
static func use(data: Dictionary) -> void:
	_climates = {}
	_rain_ago = {}
	for key: String in data:
		if data[key] is Dictionary:
			_climates[key] = data[key]
	climates()


## Forgets the climates read, and every override (the file read again).
static func reload() -> void:
	_climates = {}
	_rain_ago = {}
	overrides = {}
	storms_checked = -1


static func _climate(region: String) -> Dictionary:
	var all := climates()
	return all.get(region, all["default"])


## [param region]'s climate (its own, else the default's).
static func climate_of(region: String) -> Dictionary:
	return _climate(region)


## The world steps a spell of [param region]'s weather lasts.
static func spell_steps(region: String) -> int:
	return maxi(roundi(float(_climate(region).get("spell", DEFAULT_SPELL)) * DayNight.day_steps), 60)


## The kind of [param region]'s spell number [param spell], by its climate's
## weights and a hash of the two: the same on every peer.
static func kind_of(region: String, spell: int) -> String:
	var climate := _climate(region)
	var weights: Dictionary = climate.get("weights", {})
	# The season the spell begins in may have weights of its own.
	var by_season: Variant = climate.get("seasons", {})
	if by_season is Dictionary and not by_season.is_empty():
		var season: Variant = by_season.get(Season.name_at(spell * spell_steps(region)), {})
		if season is Dictionary and season.get("weights") is Dictionary:
			weights = season["weights"]
	var total := 0.0
	for kind: String in weights:
		if KINDS.has(kind):
			total += maxf(float(weights[kind]), 0.0)
	if total <= 0.0:
		return "clear"
	var roll := _unit("%s:%d" % [region, spell]) * total
	for kind: String in weights:
		if not KINDS.has(kind):
			continue
		roll -= maxf(float(weights[kind]), 0.0)
		if roll < 0.0:
			return kind
	return "clear"


## A number in [0, 1) from [param key], the same everywhere.
static func _unit(key: String) -> float:
	return float(key.md5_buffer().decode_u32(0)) / 4294967296.0


## [param region]'s weather at world step [param steps]: {"kind": the
## spell's (or the override's), "cloud", "rain", "fog", "wind" (0..1,
## blended through a change), "wind_dir" (Vector2, the way it blows, in the
## level's own cells: x east, y south)}.
static func at(region: String, steps: float) -> Dictionary:
	var spell := spell_steps(region)
	var change := maxf(float(_climate(region).get("change", DEFAULT_CHANGE)) * spell, 1.0)
	var index := floori(steps / spell)
	var into := steps - index * spell
	var kind := kind_of(region, index)
	var before := kind_of(region, index - 1)
	var blend := smoothstep(0.0, change, into)
	var amounts := _mix(KINDS[before], KINDS[kind], blend)
	if blend < 0.5:
		kind = before
	var turn := lerp_angle(_unit("%s:%d:wind" % [region, index - 1]) * TAU, _unit("%s:%d:wind" % [region, index]) * TAU, blend)
	var override: Dictionary = overrides.get(region, {})
	if not override.is_empty() and KINDS.has(override.get("kind")) and steps >= float(override["from"]):
		# Into the override's kind from the spell's over a change, and back
		# out of it over a change once it ends.
		var weight := smoothstep(0.0, change, steps - float(override["from"]))
		if steps >= float(override["until"]):
			weight = 1.0 - smoothstep(0.0, change, steps - float(override["until"]))
		amounts = _mix(amounts, KINDS[override["kind"]], weight)
		if weight > 0.5:
			kind = override["kind"]
	amounts["kind"] = kind
	amounts["wind_dir"] = Vector2.from_angle(turn)
	# In the cold what falls is snow.
	var snow: float = amounts["rain"] * Season.snowfall(Season.cold_at(region, Season.year_fraction(steps)))
	amounts["snow"] = snow
	amounts["rain"] -= snow
	return amounts


static func _mix(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var out := {}
	for key: String in ["cloud", "rain", "fog", "wind"]:
		out[key] = lerpf(float(a[key]), float(b[key]), weight)
	return out


## How far one sees in [param weather] (at's), a share of one's range.
static func sight_factor(weather: Dictionary) -> float:
	return clampf(1.0 - FOG_SIGHT * weather["fog"] - RAIN_SIGHT * weather["rain"] - SNOW_SIGHT * weather.get("snow", 0.0), 0.2, 1.0)


## How far a noise carries in [param weather], a share of its radius.
static func hearing_factor(weather: Dictionary) -> float:
	return clampf(1.0 - RAIN_HEARING * weather["rain"] - WIND_HEARING * weather["wind"], 0.2, 1.0)


## Server: [param region] (or every region, "all") has [param kind] for
## [param minutes] real minutes from now ("auto": the climate's again),
## coming in over a change, or [param already] in (--weather).
static func set_override(region: String, kind: String, minutes: float, already := false) -> void:
	_rain_ago = {}
	var regions: Array = climates().keys() if region == "all" else [region]
	for each: String in regions:
		if kind == "auto":
			overrides.erase(each)
		else:
			overrides[each] = {"kind": kind, "from": World.steps - (spell_steps(each) if already else 0),
				"until": World.steps + roundi(minutes * 60.0 * World.TICK_RATE)}


## The overrides still running at [param steps] (or ending within a change),
## as saved and sent.
static func live_overrides(steps: int) -> Dictionary:
	var out := {}
	for region: String in overrides:
		if float(overrides[region]["until"]) + spell_steps(region) > steps:
			out[region] = overrides[region]
	return out


## The storms whose peak falls in [[param from], [param to]) world steps in
## [param region]: [{id, strength (0..1: what falls, rain and snow, times
## the wind, at the peak), at (the peak's step)}], oldest first. A climate's
## storm spell peaks in its middle ("storm:<region>:<spell>"), unless an
## override holds then; a storm override peaks once it has fully come in
## ("storm:<region>:override:<from>").
static func storms_between(region: String, from: float, to: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if to <= from:
		return out
	var spell := spell_steps(region)
	var change := maxf(float(_climate(region).get("change", DEFAULT_CHANGE)) * spell, 1.0)
	var override: Dictionary = overrides.get(region, {})
	var index := ceili((from - spell * 0.5) / spell)
	while index * spell + spell * 0.5 < to:
		var peak := index * spell + spell * 0.5
		var overridden := not override.is_empty() and peak >= float(override["from"]) and peak < float(override["until"]) + change
		if not overridden and kind_of(region, index) == "storm":
			out.append({"id": "storm:%s:%d" % [region, index], "strength": _strength(region, peak), "at": peak})
		index += 1
	if not override.is_empty() and override.get("kind") == "storm":
		var peak := minf(float(override["from"]) + change, float(override["until"]))
		if peak >= from and peak < to:
			out.append({"id": "storm:%s:override:%d" % [region, int(override["from"])], "strength": _strength(region, peak), "at": peak})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
	return out


static func _strength(region: String, steps: float) -> float:
	var here := at(region, steps)
	return clampf((here["rain"] + here.get("snow", 0.0)) * here["wind"], 0.0, 1.0)


## The rain that fell in [param region] from world step [param from] to
## [param to], in days of full rain (rain 0..1 times days), sampled every
## World.WORLD_TICK_STEPS; snow is not counted (it lies).
static func rain_between(region: String, from: float, to: float) -> float:
	var total := 0.0
	var step := float(World.WORLD_TICK_STEPS)
	var t := from
	while t < to:
		var span := minf(step, to - t)
		total += float(at(region, t + span * 0.5)["rain"]) * span
		t += span
	return total / DayNight.day_steps


## Server, on the world tick: every storm since the last check (at most
## CATCH_UP days back) breaks each standing roof of each level in
## [param areas] (WorldMap.areas: "roofs", "region") with the level's
## climate's chance, through World.damage_roof. Returns what broke:
## [{level, index, storm}].
static func break_roofs(areas: Dictionary, to: int) -> Array[Dictionary]:
	var broke: Array[Dictionary] = []
	var from := maxf(float(storms_checked), to - CATCH_UP * DayNight.day_steps) if storms_checked >= 0 else float(to)
	storms_checked = to
	if to <= from:
		return broke
	var by_region := {}
	for level: String in areas:
		var roofs: Array = areas[level].get("roofs", [])
		if roofs.is_empty():
			continue
		var region := str(areas[level].get("region", Level.DEFAULT_REGION))
		if not by_region.has(region):
			by_region[region] = storms_between(region, from, to)
		var climate := _climate(region)
		var least := float(climate.get("storm_min", STORM_MIN))
		var chance := float(climate.get("roof_chance", ROOF_CHANCE))
		for storm: Dictionary in by_region[region]:
			var odds := chance * smoothstep(least, 1.0, storm["strength"])
			if odds <= 0.0:
				continue
			for index in roofs.size():
				if _unit("%s:%s:%d" % [storm["id"], level, index]) < odds and World.damage_roof(level, index):
					broke.append({"level": level, "index": index, "storm": storm["id"]})
	return broke


## How hard it drips under a canopy of [param cover] (Fields.canopy_at)
## in [param region] at world step [param steps], 0..1 (decision 477): the
## cover while the rain is DRIP_RAIN or more; after it, the cover fading
## to nothing over DRIP_SECONDS times the cover, so a full roof drips
## longest and an open cell not at all. Snow does not drip (at's "rain"
## leaves it out). A function of the clock, as at is: the drawn drops and
## the drips' sound read the same.
static func drip_at(region: String, steps: float, cover: float) -> float:
	if cover <= 0.0:
		return 0.0
	var ago := _seconds_since_rain(region, steps)
	var lasts := DRIP_SECONDS * cover
	return cover * clampf(1.0 - ago / lasts, 0.0, 1.0)


## Seconds since the rain in [param region] was last DRIP_RAIN or more
## (0 while it is), looking back DRIP_LOOK at a time up to DRIP_SECONDS
## (INF past that); kept per region for the look it was worked out at.
static func _seconds_since_rain(region: String, steps: float) -> float:
	var look := floorf(steps / (DRIP_LOOK * World.TICK_RATE))
	var kept: Array = _rain_ago.get(region, [])
	if not kept.is_empty() and kept[0] == look:
		return kept[1]
	var ago := INF
	var at_look := look * DRIP_LOOK * World.TICK_RATE
	var back := 0.0
	while back <= DRIP_SECONDS + DRIP_LOOK:
		if float(at(region, at_look - back * World.TICK_RATE)["rain"]) >= DRIP_RAIN:
			ago = back
			break
		back += DRIP_LOOK
	_rain_ago[region] = [look, ago]
	return ago
