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
## Sight and hearing at full fog, rain and wind: a share of the range each
## takes away.
const FOG_SIGHT := 0.55
const RAIN_SIGHT := 0.25
const RAIN_HEARING := 0.3
const WIND_HEARING := 0.25

## The climates by region, as levels/climates.json has them (or as the
## server sent them).
static var _climates := {}
## The console's overrides, by region: {kind, from, until} (world steps).
static var overrides := {}


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
	for key: String in data:
		if data[key] is Dictionary:
			_climates[key] = data[key]
	climates()


## Forgets the climates read, and every override (the file read again).
static func reload() -> void:
	_climates = {}
	overrides = {}


static func _climate(region: String) -> Dictionary:
	var all := climates()
	return all.get(region, all["default"])


## The world steps a spell of [param region]'s weather lasts.
static func spell_steps(region: String) -> int:
	return maxi(roundi(float(_climate(region).get("spell", DEFAULT_SPELL)) * DayNight.day_steps), 60)


## The kind of [param region]'s spell number [param spell], by its climate's
## weights and a hash of the two: the same on every peer.
static func kind_of(region: String, spell: int) -> String:
	var weights: Dictionary = _climate(region).get("weights", {})
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
	return amounts


static func _mix(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var out := {}
	for key: String in ["cloud", "rain", "fog", "wind"]:
		out[key] = lerpf(float(a[key]), float(b[key]), weight)
	return out


## How far one sees in [param weather] (at's), a share of one's range.
static func sight_factor(weather: Dictionary) -> float:
	return clampf(1.0 - FOG_SIGHT * weather["fog"] - RAIN_SIGHT * weather["rain"], 0.2, 1.0)


## How far a noise carries in [param weather], a share of its radius.
static func hearing_factor(weather: Dictionary) -> float:
	return clampf(1.0 - RAIN_HEARING * weather["rain"] - WIND_HEARING * weather["wind"], 0.2, 1.0)


## Server: [param region] (or every region, "all") has [param kind] for
## [param minutes] real minutes from now ("auto": the climate's again).
static func set_override(region: String, kind: String, minutes: float) -> void:
	var regions: Array = climates().keys() if region == "all" else [region]
	for each: String in regions:
		if kind == "auto":
			overrides.erase(each)
		else:
			overrides[each] = {"kind": kind, "from": World.steps,
				"until": World.steps + roundi(minutes * 60.0 * World.TICK_RATE)}


## The overrides still running at [param steps] (or ending within a change),
## as saved and sent.
static func live_overrides(steps: int) -> Dictionary:
	var out := {}
	for region: String in overrides:
		if float(overrides[region]["until"]) + spell_steps(region) > steps:
			out[region] = overrides[region]
	return out
