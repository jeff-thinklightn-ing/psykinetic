class_name Herds
extends RefCounted
## The world's wildlife as herds (decision 367, W3): groups of a species
## (a monsters.json row's "herd": deer, rabbit, boar, wolf) about a home
## cell of an area, kept as counts on the world tick and made into bodies
## only near someone. World keeps one (World.herds), made by Main at boot;
## saved in the snapshot ("herds": to_dict). Server only.
##
## A group is {id, species, area, home, count (kept, a float: breeding comes
## in parts), out (bodies made now), made (how many it has ever made: their
## names)}. An area's capacity for a species is its rich ground (richness,
## maps' to supply: 0..1 a cell) times the species' density; groups breed
## toward it (logistic), wolves thin their prey, and once a day each group
## with no bodies out roams its home a way, a big one splits and an empty
## one is gone. An outdoor area with rich ground is seeded the first time
## the tick sees it, to seed of its capacity.
##
## Bodies (the far tier's keeper, decision 352): recall_near makes a
## group's kept animals near its home as bodies (out_per_group a group,
## out_per_zone an area), each with the group's id ("group") and home;
## retire takes a calm far one back into its count. A death is killed (the
## body's unit leaves for good: hunting depletes), a flight off an edge
## moved. Rules: levels/economy.json "herds".
##
## Taken from (decision 407): each group keeps a reserve (its species' least
## size) nobody but wolves eats into, and one with bodies out is never
## taken from: what a player stalks is the herd before them. Camps
## (Holdings.camps: camp_eats x their size a day) and town hunters
## (hunt_one) share take_share of an area's game above the reserves a day.
## Wolves that eat less than half their hunger starve by starve x the
## shortfall a day.

## Ground counted for capacity: every sample-th cell each way, standing for
## sample x sample cells.
const DEFAULT_SAMPLE := 4
## Sampled cells weighed a tick while an area's ground is built again
## (rules' "ground_per_tick"), and floor cells looked over a tick for the
## samples on its first build: a big area's ground spread over ticks, not
## one (perf's slow-tick line, decision 469).
const DEFAULT_GROUND_PER_TICK := 300
const FLOOR_PER_TICK := 5000
## Draws for a home away from people (397 amended) before giving up.
const HOME_DRAWS := 16

var rules := {}
## Area name -> {floor: {cell: true}, outdoor: bool}, as WorldMap has them.
var areas: Dictionary = {}
## () -> int: the World's steps.
var clock := Callable()
## (area, cell) -> float 0..1: how much game the ground there keeps (maps'
## WorldRichness, decision 368: thinning toward the mine, none on dead
## ground). Unset (tests): 1 outdoors on ground nobody or the town holds
## (holdings), 0 on a faction's.
var richness := Callable()
var holdings: Holdings = null
## () -> the camps that hunt ({id, area, cell, size, faction}); unset,
## holdings' (Holdings.camps). Tests set it.
var camps := Callable()
## The keeper's view of the zone World is in: () -> its name, (spec) -> the
## body made or null (World.spawn_spec), (cell, reach) -> a free cell under
## the sky near it, or World.NO_CELL.
var here := Callable()
var spawn := Callable()
var free_near := Callable()
## (area) -> the bodies in that area's zone, or null when its zone is not
## open (reconcile); unset, World.zones' entities.
var bodies_in := Callable()

## Group id -> group.
var _groups: Dictionary = {}
## Areas seeded once (area -> true).
var _seeded: Dictionary = {}
var _next := 1
var _at := -1
var _day := -1
## Area -> {cells: Array[Vector2i] (rich samples), weights: Array[float],
## total: float (rich cells, weighted)}: the ground, built again each day
## over ticks (_build_grounds), the last one kept till the new is done.
var _ground: Dictionary = {}
## Area -> its sampled floor cells, sorted (the floor never changes).
var _samples: Dictionary = {}
## Area -> the ground being built: {keys (the floor's, while sampling),
## key_at, at (the next sample to weigh), out}.
var _building: Dictionary = {}
## Area -> what camps and hunters may still take from it today (take_share
## of its spare at the day's start).
var _budget: Dictionary = {}
## Camp id -> {want, got} today; and got / want over the last whole day.
var _fed_today: Dictionary = {}
var _fed: Dictionary = {}


func _init(saved := {}, with_areas := {}, with_rules := {}, with_clock := Callable(), with_holdings: Holdings = null) -> void:
	rules = with_rules if not with_rules.is_empty() else Production.read_rules().get("herds", {})
	areas = with_areas
	clock = with_clock
	holdings = with_holdings
	from_dict(saved)
	cull_barred()


## The areas of [param world_map] as Herds reads them.
static func areas_of(world_map: WorldMap) -> Dictionary:
	var out := {}
	for name: String in world_map.areas:
		var area: Dictionary = world_map.areas[name]
		# Where people are: its places' cells and its link pads (397 amended).
		var peopled: Array[Vector2i] = []
		for place: Variant in area.get("places", {}).values():
			if place is Dictionary and place.get("cell") is Vector2i:
				peopled.append(place["cell"])
		for link: Variant in area.get("links", []):
			if link is Dictionary and link.get("tile") is Vector2i:
				peopled.append(link["tile"])
		out[name] = {"floor": area["floor"], "outdoor": world_map.is_outdoor(name), "herds": area.get("herds", {}),
			"peopled": peopled}
	return out


func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


func _species(species: String) -> Dictionary:
	return rules.get("species", {}).get(species, {})


## The species (herd) of monster kind [param kind]: its row's "herd".
static func species_of(kind: String) -> String:
	return str(Animal.kinds().get(kind, {}).get("herd", kind))


# --- Reading ------------------------------------------------------------------

## A group by id; {} if none.
func group(id: String) -> Dictionary:
	return _groups.get(id, {})


## [param area]'s groups ([param species]'s only, if given), by id.
func groups_in(area: String, species := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _groups:
		var each: Dictionary = _groups[id]
		if each["area"] == area and (species == "" or each["species"] == species):
			out.append(each)
	return out


## [param area]'s animals of [param species]: kept and out.
func total(area: String, species: String) -> float:
	var sum := 0.0
	for each in groups_in(area, species):
		sum += float(each["count"]) + int(each["out"])
	return sum


## How many of [param species] [param area]'s ground keeps.
func capacity(area: String, species: String) -> float:
	return float(_ground_of(area)["total"]) * float(_species(species).get("density", 0.0)) / 1000.0 * multiplier(area, species)


## How much more of [param species] [param area] keeps than the rules'
## density (its level's "herds": "all" times the species' own, each 1 if
## not given; decision 367 amended: maps' forest, 464).
func multiplier(area: String, species: String) -> float:
	var given: Dictionary = areas.get(area, {}).get("herds", {})
	return maxf(float(given.get("all", 1.0)), 0.0) * maxf(float(given.get(species, 1.0)), 0.0)


## Whether [param area] keeps no [param species] at all (397 amended; Jeff:
## "no packs in the wilds level"): its level's "herds" sets it to 0.
func barred(area: String, species: String) -> bool:
	return multiplier(area, species) <= 0.0


## Whether [param species] may make its home at [param cell] of [param area]
## (397 amended): not barred there, and at least its rule's keep_off cells
## (Chebyshev) from every place and link pad of the area.
func may_home(area: String, species: String, cell: Vector2i) -> bool:
	if barred(area, species):
		return false
	var keep_off := int(_species(species).get("keep_off", 0))
	if keep_off <= 0:
		return true
	for at: Vector2i in areas.get(area, {}).get("peopled", []):
		if maxi(absi(at.x - cell.x), absi(at.y - cell.y)) < keep_off:
			return false
	return true


## [param area]'s groups of a species it no longer keeps (barred) dropped,
## with a line (397 amended: the box's wilds wolves at the next deploy).
## How many groups went.
func cull_barred() -> int:
	var gone := {}
	var ids: Array = _groups.keys()
	ids.sort()
	for id: String in ids:
		var each: Dictionary = _groups[id]
		if barred(str(each["area"]), str(each["species"])):
			var key := "%s %s" % [each["species"], each["area"]]
			gone[key] = int(gone.get(key, 0)) + 1
			_groups.erase(id)
	for key: String in gone:
		print("[herds] culled %d %s groups in %s: the level keeps none" % [gone[key], key.get_slice(" ", 0), key.get_slice(" ", 1)])
	return gone.values().reduce(func(sum: int, n: int) -> int: return sum + n, 0)


## Whether a saved body of [param spec] (a herd animal: its "group") is one
## [param area] no longer keeps (397 amended): not spawned again.
func culls(area: String, spec: Dictionary) -> bool:
	return spec.has("group") and barred(area, species_of(str(spec.get("kind", ""))))


## How much game [param cell] of [param area] keeps (richness, or the
## default till maps sets it).
func rich(area: String, cell: Vector2i) -> float:
	if richness.is_valid():
		return clampf(float(richness.call(area, cell)), 0.0, 1.0)
	if not bool(areas.get(area, {}).get("outdoor", false)):
		return 0.0
	if holdings != null and holdings.ground(area, cell) not in [Factions.NOBODY, "town"]:
		return 0.0
	return 1.0


## [param area]'s ground: the last one built, else (asked before the tick
## built any: a test, a tool) built now, all at once.
func _ground_of(area: String) -> Dictionary:
	if _ground.has(area):
		return _ground[area]
	_building.erase(area)
	while not _build_ground(area, 1 << 30):
		pass
	return _ground[area]


## Starts [param area]'s ground again, the one it has kept meanwhile.
func _rebuild(area: String) -> void:
	_building[area] = {"keys": [], "key_at": 0, "at": 0,
		"out": {"cells": [] as Array[Vector2i], "weights": [] as Array[float], "total": 0.0}}


## Builds [param area]'s ground by up to [param budget] samples weighed
## (and FLOOR_PER_TICK x budget / the default floor cells looked over for
## its samples, once); true when it is done and in _ground.
func _build_ground(area: String, budget: int) -> bool:
	if not _building.has(area):
		_rebuild(area)
	var build: Dictionary = _building[area]
	var sample := maxi(int(rules.get("sample", DEFAULT_SAMPLE)), 1)
	if not _samples.has(area):
		if build["keys"].is_empty() and int(build["key_at"]) == 0:
			build["keys"] = areas.get(area, {}).get("floor", {}).keys()
			build["found"] = [] as Array[Vector2i]
		var keys: Array = build["keys"]
		var from := int(build["key_at"])
		var to := mini(keys.size(), from + maxi(FLOOR_PER_TICK * budget / DEFAULT_GROUND_PER_TICK, 1))
		for index in range(from, to):
			var cell: Vector2i = keys[index]
			if cell.x % sample == 0 and cell.y % sample == 0:
				build["found"].append(cell)
		build["key_at"] = to
		if to < keys.size():
			return false
		var found: Array[Vector2i] = build["found"]
		found.sort()  # In no set order otherwise: the draws must be.
		_samples[area] = found
		build.erase("keys")
		build.erase("found")
		return false
	var cells: Array[Vector2i] = _samples[area]
	var out: Dictionary = build["out"]
	var at := int(build["at"])
	var stop := mini(cells.size(), at + budget)
	for index in range(at, stop):
		var cell := cells[index]
		var weight := rich(area, cell)
		if weight > 0.0:
			out["cells"].append(cell)
			out["weights"].append(weight)
			out["total"] += weight * sample * sample
	build["at"] = stop
	if stop < cells.size():
		return false
	_ground[area] = out
	_building.erase(area)
	return true


## Each area's ground built on by this tick's share, areas in order: a
## floor still to sample takes the tick; an area is seeded when its first
## ground is done.
func _build_grounds() -> void:
	var left := maxi(int(rules.get("ground_per_tick", DEFAULT_GROUND_PER_TICK)), 1)
	var building: Array = _building.keys()
	building.sort()
	for area: String in building:
		var sampled := _samples.has(area)
		var from := int(_building[area]["at"])
		if _build_ground(area, left) and not _seeded.has(area):
			_seed(area)
		if not sampled:
			return
		var weighed_to := int(_building[area]["at"]) if _building.has(area) else int(_samples[area].size())
		left -= maxi(weighed_to - from, 1)
		if left <= 0:
			return


# --- The world tick -------------------------------------------------------------

## Moves the herds on by the time since the last call (World's world tick):
## breeding, wolves eating, and on a new day seeding, roaming and splitting.
func tick() -> void:
	var steps := now()
	var since := 0 if _at < 0 else steps - _at
	_at = steps
	var day_steps := maxi(DayNight.day_steps, 1)
	var day := steps / day_steps
	if day != _day:
		_day = day
		for area: String in areas:
			_rebuild(area)  # Holdings move: the ground again, once a day.
		_daily(day)
		_new_budgets()
	_build_grounds()
	if since <= 0:
		return
	var days := minf(float(since) / day_steps, 1.0)
	var all_species: Dictionary = rules.get("species", {})
	for area: String in _areas_with_groups():
		if not _ground.has(area):
			continue  # Not weighed yet: capacity 0 would shrink them (perf).
		for species: String in all_species:
			_breed(area, species, days)
		for species: String in all_species:
			_hunt(area, species, days)
	_camps_eat(days)


func _areas_with_groups() -> Array[String]:
	var out: Array[String] = []
	for id: String in _groups:
		var area: String = _groups[id]["area"]
		if area not in out:
			out.append(area)
	out.sort()
	return out


## [param area]'s [param species] grow toward its capacity, logistically,
## by its breed a day, shared over its groups by what they keep.
func _breed(area: String, species: String, days: float) -> void:
	var cap := capacity(area, species)
	var groups := groups_in(area, species)
	var have := total(area, species)
	if groups.is_empty() or have <= 0.0:
		return
	var grow := float(_species(species).get("breed", 0.0)) * have * (1.0 - have / cap if cap > 0.0 else -1.0) * days
	var kept := 0.0
	for each in groups:
		kept += float(each["count"])
	if kept <= 0.0:
		return
	for each in groups:
		each["count"] = maxf(float(each["count"]) + grow * float(each["count"]) / kept, 0.0)


## [param area]'s predators of [param species] eat its rules' "eats" a day
## each from its "prey" species' kept counts, the first first.
func _hunt(area: String, species: String, days: float) -> void:
	var rule := _species(species)
	var hunters := total(area, species)
	if hunters <= 0.0 or rule.get("prey", []).is_empty():
		return
	var wanted := hunters * float(rule.get("eats", 0.0)) * days
	var hunger := wanted
	for prey: Variant in rule.get("prey", []):
		for each in groups_in(area, str(prey)):
			if hunger <= 0.0:
				return
			var eaten := minf(float(each["count"]), hunger)
			each["count"] = float(each["count"]) - eaten
			hunger -= eaten
	# Less than half their hunger met: they starve by the shortfall.
	if wanted > 0.0 and hunger > wanted * 0.5:
		var lost := float(rules.get("starve", 0.1)) * (hunger / wanted) * hunters * days
		var kept := 0.0
		for each in groups_in(area, species):
			kept += float(each["count"])
		if kept <= 0.0:
			return
		for each in groups_in(area, species):
			each["count"] = maxf(float(each["count"]) - lost * float(each["count"]) / kept, 0.0)


# --- Taken by camps and hunters (decision 407) --------------------------------------

## What [param each] can give camps and hunters: its count above its
## species' reserve (least size); none while it has bodies out.
func spare(each: Dictionary) -> float:
	if int(each["out"]) > 0:
		return 0.0
	var size: Array = _species(str(each["species"])).get("size", [1, 1])
	return maxf(float(each["count"]) - float(size[0]), 0.0)


## Each area's budget for the day (take_share of its spare now), and each
## camp's last whole day's feeding.
func _new_budgets() -> void:
	_budget.clear()
	for area in _areas_with_groups():
		var sum := 0.0
		for each in groups_in(area):
			sum += spare(each)
		_budget[area] = sum * float(rules.get("take_share", 0.25))
	for id: String in _fed_today:
		var day: Dictionary = _fed_today[id]
		_fed[id] = clampf(float(day["got"]) / float(day["want"]), 0.0, 1.0) if float(day["want"]) > 0.0 else 1.0
	_fed_today.clear()


## [param area]'s [param species] groups with something to spare, nearest
## [param near] first.
func _nearest_spare(area: String, species: String, near: Vector2i, least: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for each in groups_in(area, species):
		if spare(each) >= least:
			out.append(each)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Vector2(a["home"] - near).length()
		var db := Vector2(b["home"] - near).length()
		return da < db or da == db and str(a["id"]) < str(b["id"]))
	return out


## Up to [param amount] taken from [param area]'s [param species] above the
## reserves and within today's budget, the groups nearest [param near]
## first: how much.
func _take(area: String, species: String, near: Vector2i, amount: float) -> float:
	var got := 0.0
	for each in _nearest_spare(area, species, near, 0.0001):
		var room := minf(amount - got, float(_budget.get(area, 0.0)))
		if room <= 0.0:
			break
		var bite := minf(spare(each), room)
		each["count"] = float(each["count"]) - bite
		_budget[area] = float(_budget.get(area, 0.0)) - bite
		got += bite
	return got


## Each camp (Holdings.camps: area, cell, size, faction) eats camp_eats x
## its size a day of its area's game, in camp_prey's order.
func _camps_eat(days: float) -> void:
	var all: Array = camps.call() if camps.is_valid() else (holdings.camps() if holdings != null else [])
	for camp: Dictionary in all:
		var want := float(rules.get("camp_eats", 0.5)) * float(camp["size"]) * days
		if want <= 0.0:
			continue
		var got := 0.0
		for prey: Variant in rules.get("camp_prey", []):
			got += _take(str(camp["area"]), str(prey), camp["cell"], want - got)
		var day: Dictionary = _fed_today.get(camp["id"], {"want": 0.0, "got": 0.0})
		day["want"] = float(day["want"]) + want
		day["got"] = float(day["got"]) + got
		_fed_today[camp["id"]] = day


## How well camp [param id] ate over the last whole day, 0..1 (1 before a
## day has passed): a hook for maps (a hungry camp raiding for food).
func camp_fed(id: String) -> float:
	return float(_fed.get(id, 1.0))


## A town hunter's catch in [param area], near [param near]: one animal of
## the hunter_prey species with the most to spare, from its nearest group
## above the reserves, within today's budget. Its kind (a stag or a deer,
## by the mix), or "" if there is no game to take.
func hunt_one(area: String, near: Vector2i) -> String:
	if float(_budget.get(area, 0.0)) < 1.0:
		return ""
	var best := ""
	var most := 0.0
	for prey: Variant in rules.get("hunter_prey", []):
		var sum := 0.0
		for each in groups_in(area, str(prey)):
			sum += floorf(spare(each))
		if sum > most:
			best = str(prey)
			most = sum
	if best.is_empty():
		return ""
	var each: Dictionary = _nearest_spare(area, best, near, 1.0)[0]
	each["count"] = float(each["count"]) - 1.0
	each["made"] = int(each["made"]) + 1
	_budget[area] = float(_budget[area]) - 1.0
	return _kind_for(best, "%s_%d" % [each["id"], int(each["made"])])


## [param area] given its first groups: each species to seed of its
## capacity, in groups of its size about rich cells drawn by the area.
func _seed(area: String) -> void:
	_seeded[area] = true
	var ground := _ground_of(area)
	if ground["cells"].is_empty():
		return
	var draw := RandomNumberGenerator.new()
	var all_species: Dictionary = rules.get("species", {})
	var names: Array = all_species.keys()
	names.sort()
	for species: String in names:
		draw.seed = hash("%s/%s/seed" % [area, species])
		var left := floorf(capacity(area, species) * float(rules.get("seed", 0.5)))
		var size: Array = _species(species).get("size", [1, 1])
		while left >= 1.0:
			var count := minf(float(draw.randi_range(int(size[0]), int(size[-1]))), left)
			left -= count
			# A home away from people (397 amended): a few draws, else none.
			for attempt in HOME_DRAWS:
				var home: Vector2i = ground["cells"][draw.randi_range(0, ground["cells"].size() - 1)]
				if may_home(area, species, home):
					_add_group(area, species, home, count)
					break
	var made := groups_in(area).size()
	if made > 0:
		print("[herds] %s seeded: %d groups, %s" % [area, made, ", ".join(names.map(func(s: String) -> String:
			return "%s %d" % [s, roundi(total(area, s))]))])


func _add_group(area: String, species: String, home: Vector2i, count: float) -> Dictionary:
	var id := "%s_%s_%d" % [area, species, _next]
	_next += 1
	var made := {"id": id, "species": species, "area": area, "home": home, "count": count, "out": 0, "made": 0}
	_groups[id] = made
	return made


## Once a day: an empty group is gone, a big one splits, and each with no
## bodies out roams its home to a rich cell up to its species' roam away.
func _daily(day: int) -> void:
	for area: String in _areas_with_groups():
		for each in groups_in(area):
			if int(each["out"]) > 0:
				reconcile(area)
				break
	var ids: Array = _groups.keys()
	ids.sort()
	var draw := RandomNumberGenerator.new()
	for id: String in ids:
		var each: Dictionary = _groups[id]
		if int(each["out"]) > 0:
			continue
		if float(each["count"]) < 0.5:
			_groups.erase(id)
			continue
		draw.seed = hash("%s/%d" % [id, day])
		var rule := _species(str(each["species"]))
		var reach := int(rule.get("roam", 0))
		var size: Array = rule.get("size", [1, 1])
		var biggest := float(size[-1])
		if float(each["count"]) > biggest * 1.5:
			var part := floorf(float(each["count"]) / 2.0)
			each["count"] = float(each["count"]) - part
			_add_group(str(each["area"]), str(each["species"]), _roam_cell(each, reach, draw), part)
		each["home"] = _roam_cell(each, reach, draw)
		if not may_home(str(each["area"]), str(each["species"]), each["home"]):
			_rehome(each, draw)
	# Each area's count, for release's grep (397 amended (2)): no names.
	for area: String in _areas_with_groups():
		var kept := 0.0
		var out := 0
		for each in groups_in(area):
			kept += float(each["count"])
			out += int(each["out"])
		print("[herds] %s: %d groups, kept %d, out %d" % [area, groups_in(area).size(), roundi(kept), out])


## A rich cell of [param each]'s area within [param reach] of its home
## where it may make its home (its home if a few draws find none).
func _roam_cell(each: Dictionary, reach: int, draw: RandomNumberGenerator) -> Vector2i:
	var home: Vector2i = each["home"]
	if reach <= 0:
		return home
	var floor_cells: Dictionary = areas.get(str(each["area"]), {}).get("floor", {})
	for attempt in 8:
		var at := home + Vector2i(draw.randi_range(-reach, reach), draw.randi_range(-reach, reach))
		if floor_cells.has(at) and rich(str(each["area"]), at) > 0.0 and may_home(str(each["area"]), str(each["species"]), at):
			return at
	return home


## [param each], homed too near people (a group of before 397 amended, or
## one that fled to a pad), moved to a rich cell of its area away from them,
## if a few draws find one.
func _rehome(each: Dictionary, draw: RandomNumberGenerator) -> void:
	if not _ground.has(str(each["area"])):
		return  # Its ground not built yet: tomorrow.
	var cells: Array = _ground[str(each["area"])]["cells"]
	if cells.is_empty():
		return
	for attempt in HOME_DRAWS:
		var at: Vector2i = cells[draw.randi_range(0, cells.size() - 1)]
		if may_home(str(each["area"]), str(each["species"]), at):
			each["home"] = at
			return


# --- Bodies: the far tier's keeper (decision 352) ---------------------------------

## Whether [param monster] is one of the herds' (an Animal with a group).
func takes(monster: Object) -> bool:
	return monster is Animal and (monster as Animal).spawn_spec.has("group")


## [param monster], calm and far, back into its group's count (its
## species' nearest in its zone, or a new one there, if its group is gone).
func retire(monster: Object) -> void:
	var animal := monster as Animal
	var spec := animal.spawn_spec
	var each := _group_for(str(spec.get("group", "")), str(spec.get("zone", _here())), species_of(str(spec.get("kind", ""))), animal.tile)
	each["out"] = maxi(int(each["out"]) - 1, 0)
	each["count"] = float(each["count"]) + 1.0


## The groups of the zone World is in whose home is within [param reach]
## of [param at] made into bodies about their homes: out_per_group a group
## at most, out_per_zone the zone.
func recall_near(at: Vector2i, reach: int) -> void:
	if not spawn.is_valid():
		return
	var area := _here()
	var groups := groups_in(area)
	var room := int(rules.get("out_per_zone", 24))
	for each in groups:
		room -= int(each["out"])
	for each in groups:
		var home: Vector2i = each["home"]
		if room <= 0:
			return
		if maxi(absi(home.x - at.x), absi(home.y - at.y)) > reach:
			continue
		while room > 0 and float(each["count"]) >= 1.0 and int(each["out"]) < int(rules.get("out_per_group", 6)):
			if not _make_body(each):
				break
			room -= 1


## [param area]'s groups' out made what its bodies are (397 amended (2);
## Jeff: "after removing wolf packs from the wilds there were 0 animals
## now"): a body that left by no retire, kill or flight (a room reset, a
## regeneration, a saved body not made again at a restart, any despawn)
## kept its out for ever, and an area with out_per_zone of them made no
## body again. What is out beyond the area's bodies now goes back into its
## group's count. Zones never close once open (boot opens every saved
## one), so a body is only ever in an open zone: an area whose zone is not
## open gives all its out back. At each day's start (_daily), before the
## day's budget, so hunters and camps have them that day. How many came back.
func reconcile(area: String) -> int:
	var live := {}
	var list: Variant = bodies_in.call(area) if bodies_in.is_valid() else _bodies_in(area)
	for body: Variant in list if list is Array else []:
		if is_instance_valid(body) and takes(body) and (body as Animal).spawned:
			var id := str((body as Animal).spawn_spec.get("group", ""))
			live[id] = int(live.get(id, 0)) + 1
	var back := 0
	for each in groups_in(area):
		var extra := int(each["out"]) - int(live.get(each["id"], 0))
		if extra > 0:
			each["out"] = int(each["out"]) - extra
			each["count"] = float(each["count"]) + extra
			back += extra
	if back > 0:
		print("[herds] %s: %d leaked bodies back" % [area, back])
	return back


## The bodies in [param area]'s open zone (World's own list for the zone it
## is in: a zone's entities are kept only while World is elsewhere), null
## when it is not open.
static func _bodies_in(area: String) -> Variant:
	if World.zone != null and World.zone.name == area:
		return World.entities()
	return (World.zones[area] as Zone).entities if World.zones.has(area) else null


## One of [param each]'s kept animals made a body near its home: false
## (nothing made) if there is no room there.
func _make_body(each: Dictionary) -> bool:
	var home: Vector2i = each["home"]
	var tile: Vector2i = free_near.call(home, 4) if free_near.is_valid() else home
	if tile == World.NO_CELL:
		return false
	var name := "%s_%d" % [each["id"], int(each["made"]) + 1]
	var kind := _kind_for(str(each["species"]), name)
	var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
	if spec.is_empty():
		return false
	spec["name"] = name
	spec["tile"] = tile
	spec["home"] = home
	spec["group"] = str(each["id"])
	if spawn.call(spec) == null:
		return false
	each["made"] = int(each["made"]) + 1
	each["count"] = float(each["count"]) - 1.0
	each["out"] = int(each["out"]) + 1
	return true


## The kind a body of [param species] named [param name] is, by its mix
## (a stag one in five deer), drawn by the name.
func _kind_for(species: String, name: String) -> String:
	var mix: Dictionary = _species(species).get("mix", {species: 1})
	var kinds: Array = mix.keys()
	kinds.sort()
	var sum := 0.0
	for kind: String in kinds:
		sum += maxf(float(mix[kind]), 0.0)
	var roll := float(name.md5_buffer().decode_u32(0)) / 4294967296.0 * sum
	for kind: String in kinds:
		roll -= maxf(float(mix[kind]), 0.0)
		if roll < 0.0:
			return kind
	return species


## A body of group [param id] ([param kind]) died: its unit is gone for good.
func killed(id: String, _kind := "") -> void:
	if _groups.has(id):
		_groups[id]["out"] = maxi(int(_groups[id]["out"]) - 1, 0)


## A body of group [param id] fled into [param to_area] at [param cell]
## (and is gone from here: Main despawns it, kept): its unit is kept in the
## group of its species nearest there (or a new one at the cell), to be
## made again there near someone. That group's id.
func moved(id: String, to_area: String, cell: Vector2i) -> String:
	var from: Dictionary = _groups.get(id, {})
	if from.is_empty():
		return id
	from["out"] = maxi(int(from["out"]) - 1, 0)
	if barred(to_area, str(from["species"])):
		return ""  # Gone: that level keeps none (397 amended).
	var to := _group_for("", to_area, str(from["species"]), cell)
	to["count"] = float(to["count"]) + 1.0
	return str(to["id"])


## Group [param id] if there is one; else [param species]' group in
## [param area] nearest [param cell] within twice its roam; else a new one
## there, empty.
func _group_for(id: String, area: String, species: String, cell: Vector2i) -> Dictionary:
	if _groups.has(id):
		return _groups[id]
	var best := {}
	var reach := int(_species(species).get("roam", 0)) * 2
	for each in groups_in(area, species):
		var home: Vector2i = each["home"]
		var far := maxi(absi(home.x - cell.x), absi(home.y - cell.y))
		if far <= reach:
			reach = far
			best = each
	return best if not best.is_empty() else _add_group(area, species, cell, 0.0)


## [param records] (a zone's far tier records, World.record_list) with the
## wild animals among them folded into [param area]'s groups: what is left.
func fold_records(area: String, records: Array) -> Array:
	var left := []
	var culled := 0
	for record: Dictionary in records:
		var entry: Dictionary = record.get("entry", {})
		var kind := str(entry.get("kind", ""))
		# A level's own animal (a slot) stays the level's.
		if kind == "" or not Animal.is_wild(kind) or not rules.get("species", {}).has(species_of(kind)) 				or int(entry.get("spawn", -1)) >= 0:
			left.append(record)
			continue
		if barred(area, species_of(kind)):
			culled += 1  # The level keeps none now (397 amended).
			continue
		var tile: Variant = Snapshot.vector(entry.get("tile"))
		var each := _group_for(str(entry.get("group", "")), area, species_of(kind), tile if tile is Vector2i else Vector2i.ZERO)
		each["count"] = float(each["count"]) + 1.0
		if each["id"] == str(entry.get("group", "")):
			# Its group's body come back as a record: no longer out, as retire's (397
			# amended (2); else reconcile counts it back a second time).
			each["out"] = maxi(int(each["out"]) - 1, 0)
	if culled > 0:
		print("[herds] culled %d far records in %s: the level keeps none of their kind" % [culled, area])
	return left


func _here() -> String:
	return str(here.call()) if here.is_valid() else ""


# --- Saving -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var groups := {}
	for id: String in _groups:
		var each: Dictionary = _groups[id].duplicate()
		var home: Vector2i = each["home"]
		each["home"] = [home.x, home.y]
		groups[id] = each
	return {"groups": groups, "seeded": _seeded.keys(), "next": _next, "at": _at, "fed": _fed.duplicate()}


## to_dict's [param saved] over what is here; a group that makes no sense
## is left out with a word.
func from_dict(saved: Dictionary) -> void:
	_next = maxi(int(saved.get("next", 1)), 1)
	_at = int(saved.get("at", -1))
	for area: Variant in saved.get("seeded", []):
		_seeded[str(area)] = true
	var fed: Variant = saved.get("fed", {})
	if fed is Dictionary:
		for id: Variant in fed:
			_fed[str(id)] = clampf(float(fed[id]), 0.0, 1.0)
	var groups: Variant = saved.get("groups", {})
	if not groups is Dictionary:
		return
	for id: Variant in groups:
		var raw: Variant = groups[id]
		var home: Variant = Snapshot.vector(raw.get("home")) if raw is Dictionary else null
		if not raw is Dictionary or home == null or str(raw.get("species", "")) == "" or str(raw.get("area", "")) == "":
			print("[herds] the snapshot's group %s makes no sense; left out" % [id])
			continue
		_groups[str(id)] = {"id": str(id), "species": str(raw["species"]), "area": str(raw["area"]), "home": home,
			"count": maxf(float(raw.get("count", 0.0)), 0.0), "out": maxi(int(raw.get("out", 0)), 0),
			"made": maxi(int(raw.get("made", 0)), 0)}
