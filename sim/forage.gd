class_name Forage
extends RefCounted
## What grows wild to be gathered (decision 502): herbs (items' "herbs",
## the healer's remedies; npc's sickness) laid now and then on the ground
## of an outdoor area with a town, as ordinary ground piles a player picks
## up and banks at the town's store, and the medicine man takes on his way
## (take_near). Server only; World keeps one (World.forage), made by Main
## at boot and moved on by the world tick's first slice.
##
## Once a game day (DayNight.day_steps), in each loaded zone whose area has
## a place the town holds: herbs lying there longer than wither_days since
## they grew are gone ("withered"); then per_day are laid, while fewer than
## most of those grown lie in the area, each on a cell drawn by the area,
## the day and the try: grass (WorldMap's), under the sky, dry walkable
## floor with nothing lying on it and no fire, within reach cells of a
## town-held place and outside every one's ring (the town: ring cells, or
## out to its furthest building within reach and clear cells more), on
## ground nobody holds (a camp's herbs are the camp's). Rules:
## levels/economy.json "forage" (economy's, after this lands): one entry
## per item, {per_day, most, reach, ring, clear, wither_days}.
##
## It keeps nothing of its own: what it laid is in each zone's ground (the
## snapshot's) and the book has when each grew (its "grew" event), so a
## restart withers and counts them as before. A restart on a day already
## laid lays that day again, up to most. A zone not loaded is left be.

const RULES := "res://levels/economy.json"
const GREW := "grew"
## The client draws a pile of these standing, as the first art slot of
## PLANTS there is (Client3D._on_pile_shown).
const HERBS := "herbs"
const PLANTS: Array[String] = ["plant.herb", "plant.fern"]
const DEFAULTS := {"per_day": 4, "most": 10, "reach": 48, "ring": 14, "clear": 4, "wither_days": 3}
## Cells drawn for each one laid before it gives up for the day.
const TRIES := 24

## Item id -> its rules, DEFAULTS filled in.
var rules: Dictionary = {}
var world_map: WorldMap:
	set(value):
		world_map = value
		_rings.clear()
var holdings: Holdings
## () -> int: the World's steps.
var clock := Callable()
var _day := -1
## "area/item" -> each town-held place's ring there, as _ring_of works it out.
var _rings: Dictionary = {}


func _init(map: WorldMap, with_holdings: Holdings, with_rules := {}, with_clock := Callable()) -> void:
	world_map = map
	holdings = with_holdings
	clock = with_clock
	var given: Dictionary = with_rules if not with_rules.is_empty() else read_rules()
	for id: String in given:
		if given[id] is Dictionary:
			var each := DEFAULTS.duplicate()
			each.merge(given[id], true)
			rules[id] = each


static func read_rules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES)) if FileAccess.file_exists(RULES) else null
	var forage: Variant = (parsed as Dictionary).get("forage", {}) if parsed is Dictionary else {}
	return forage if forage is Dictionary else {}


func now() -> int:
	return int(clock.call()) if clock.is_valid() else World.steps


## The world tick: on a new day, each loaded zone's withering and laying.
func tick() -> void:
	var day := now() / maxi(DayNight.day_steps, 1)
	if day == _day:
		return
	_day = day
	daily(day)


## [param day]'s withering and laying, every loaded zone in turn.
func daily(day: int) -> void:
	var was := World.zone
	var names: Array = World.zones.keys()
	names.sort()
	for area: String in names:
		if not world_map.areas.has(area) or not world_map.is_outdoor(area):
			continue
		World.enter(World.zones[area])
		for id: String in rules:
			if Items.exists(id):
				_wither(area, id)
				_lay(area, id, day)
	World.enter(was)


## The cells of the zone World is in with [param id] lying on them that
## grew there: cell -> [uid, ...].
func lying(id: String) -> Dictionary:
	var out := {}
	for cell: Vector2i in World.zone.ground:
		for uid in World.zone.ground[cell]:
			if World.items.id_of(uid) == id and _grew(uid):
				if not out.has(cell):
					out[cell] = []
				out[cell].append(uid)
	return out


func _grew(uid: int) -> bool:
	var events: Array = World.items.history(uid).get("events", [])
	return not events.is_empty() and events[0]["kind"] == GREW


func _wither(area: String, id: String) -> void:
	var days := float(rules[id]["wither_days"])
	var found := lying(id)
	for cell: Vector2i in found:
		for uid: int in found[cell]:
			if float(now() - int(World.items.history(uid)["made"])) / maxi(DayNight.day_steps, 1) < days:
				continue
			var index := World.ground_uids(cell).find(uid)
			if index >= 0:
				World.items.end(World.take_from_ground(cell, index), "withered", "", area, cell)


func _lay(area: String, id: String, day: int) -> void:
	var rule: Dictionary = rules[id]
	var count := 0
	for uids: Array in lying(id).values():
		count += uids.size()
	var wanted := mini(int(rule["per_day"]), int(rule["most"]) - count)
	if wanted <= 0:
		return
	var towns := towns_in(area)
	if towns.is_empty():
		return
	var draw := RandomNumberGenerator.new()
	draw.seed = hash("%s/%s/%d" % [area, id, day])
	var reach := int(rule["reach"])
	for i in wanted:
		for t in TRIES:
			var town := towns[draw.randi_range(0, towns.size() - 1)]
			var cell := town + Vector2i(draw.randi_range(-reach, reach), draw.randi_range(-reach, reach))
			if fits(area, cell, towns, rule):
				var uid := World.items.mint(id, GREW, "wild", area, cell)
				World.put_on_ground(uid, cell)
				break


## The cells of [param area]'s places the town holds.
func towns_in(area: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for place_id in holdings.places_in(area):
		if holdings.holder(place_id) == WorldRichness.TOWN:
			out.append(holdings.place(place_id)["cell"])
	return out


## How far round [param town] (a town-held place of [param area]) the town
## goes under [param rule]: its ring, or out to the furthest cell of a
## building within its reach and clear more.
func ring_of(area: String, town: Vector2i, rule: Dictionary) -> float:
	var key := "%s/%s/%s" % [area, town, rule]
	if _rings.has(key):
		return _rings[key]
	var ring := float(rule["ring"])
	for building: Dictionary in world_map.areas[area].get("buildings", []):
		if not building.has("rect") and not building.has("blocks"):
			continue
		var cells := Level.building_cells(building)
		var furthest := 0.0
		var near := false
		for each in cells:
			var away := Vector2(each - town).length()
			furthest = maxf(furthest, away)
			near = near or away <= float(rule["reach"])
		if near:
			ring = maxf(ring, furthest + float(rule["clear"]))
	_rings[key] = ring
	return ring


## Whether [param id]'s rules ([param rule]) let it grow on [param cell] of
## [param area] (the zone World is in), [param towns] its town-held places.
func fits(area: String, cell: Vector2i, towns: Array[Vector2i], rule: Dictionary) -> bool:
	var area_map: Dictionary = world_map.areas[area]
	var size: Vector2i = area_map["size"]
	if not Rect2i(Vector2i.ZERO, size).has_point(cell) or area_map["grass"][cell.y * size.x + cell.x] == 0:
		return false
	var near := false
	for town in towns:
		var away := Vector2(cell - town).length()
		if away <= ring_of(area, town, rule):
			return false
		near = near or away <= float(rule["reach"])
	if not near or not World.is_walkable(cell) or World.is_water(cell) or World.is_fire(cell) or World.zone.ground.has(cell):
		return false
	if World.richness != null and not World.richness.under_sky(area, cell):
		return false
	return holdings.ground(area, cell) == Factions.NOBODY


## Takes one [param id] (herbs by default) lying within [param reach] of
## [param cell] in [param area]'s zone off the ground, the nearest: its uid,
## held by nobody yet (the caller banks or carries it); 0 if none or the
## zone is not loaded. For the medicine man's rounds (npc's, decision 404).
func take_near(area: String, cell: Vector2i, reach := 1, id := HERBS) -> int:
	if not World.zones.has(area):
		return 0
	var was := World.enter(World.zones[area])
	var best := World.NO_CELL
	var best_away := INF
	for at: Vector2i in World.zone.ground:
		var away := Vector2(at - cell).length()
		if away <= reach and away < best_away and World.ground_at(at).has(id):
			best = at
			best_away = away
	var uid := 0
	if best != World.NO_CELL:
		uid = World.take_from_ground(best, Array(World.ground_at(best)).rfind(id))
	World.enter(was)
	return uid
