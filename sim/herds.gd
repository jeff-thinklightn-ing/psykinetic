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

## Ground counted for capacity: every sample-th cell each way, standing for
## sample x sample cells.
const DEFAULT_SAMPLE := 4

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
## The keeper's view of the zone World is in: () -> its name, (spec) -> the
## body made or null (World.spawn_spec), (cell, reach) -> a free cell under
## the sky near it, or World.NO_CELL.
var here := Callable()
var spawn := Callable()
var free_near := Callable()

## Group id -> group.
var _groups: Dictionary = {}
## Areas seeded once (area -> true).
var _seeded: Dictionary = {}
var _next := 1
var _at := -1
var _day := -1
## Area -> {cells: Array[Vector2i] (rich samples), weights: Array[float],
## total: float (rich cells, weighted)}: the ground, again each day.
var _ground: Dictionary = {}


func _init(saved := {}, with_areas := {}, with_rules := {}, with_clock := Callable(), with_holdings: Holdings = null) -> void:
	rules = with_rules if not with_rules.is_empty() else Production.read_rules().get("herds", {})
	areas = with_areas
	clock = with_clock
	holdings = with_holdings
	from_dict(saved)


## The areas of [param world_map] as Herds reads them.
static func areas_of(world_map: WorldMap) -> Dictionary:
	var out := {}
	for name: String in world_map.areas:
		out[name] = {"floor": world_map.areas[name]["floor"], "outdoor": world_map.is_outdoor(name)}
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
	return float(_ground_of(area)["total"]) * float(_species(species).get("density", 0.0)) / 1000.0


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


func _ground_of(area: String) -> Dictionary:
	if _ground.has(area):
		return _ground[area]
	var sample := maxi(int(rules.get("sample", DEFAULT_SAMPLE)), 1)
	var out := {"cells": [] as Array[Vector2i], "weights": [] as Array[float], "total": 0.0}
	var floor_cells: Dictionary = areas.get(area, {}).get("floor", {})
	var cells: Array = floor_cells.keys()
	cells.sort()  # In no set order otherwise: the draws must be.
	for cell: Vector2i in cells:
		if cell.x % sample != 0 or cell.y % sample != 0:
			continue
		var weight := rich(area, cell)
		if weight > 0.0:
			out["cells"].append(cell)
			out["weights"].append(weight)
			out["total"] += weight * sample * sample
	_ground[area] = out
	return out


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
		_ground.clear()  # Holdings move: the ground again, once a day.
		for area: String in areas:
			if not _seeded.has(area):
				_seed(area)
		_daily(day)
	if since <= 0:
		return
	var days := minf(float(since) / day_steps, 1.0)
	var all_species: Dictionary = rules.get("species", {})
	for area: String in _areas_with_groups():
		for species: String in all_species:
			_breed(area, species, days)
		for species: String in all_species:
			_hunt(area, species, days)


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
	var hunger := hunters * float(rule.get("eats", 0.0)) * days
	for prey: Variant in rule.get("prey", []):
		for each in groups_in(area, str(prey)):
			if hunger <= 0.0:
				return
			var eaten := minf(float(each["count"]), hunger)
			each["count"] = float(each["count"]) - eaten
			hunger -= eaten


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
			var home: Vector2i = ground["cells"][draw.randi_range(0, ground["cells"].size() - 1)]
			_add_group(area, species, home, count)
			left -= count
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


## A rich cell of [param each]'s area within [param reach] of its home
## (its home if a few draws find none).
func _roam_cell(each: Dictionary, reach: int, draw: RandomNumberGenerator) -> Vector2i:
	var home: Vector2i = each["home"]
	if reach <= 0:
		return home
	var floor_cells: Dictionary = areas.get(str(each["area"]), {}).get("floor", {})
	for attempt in 8:
		var at := home + Vector2i(draw.randi_range(-reach, reach), draw.randi_range(-reach, reach))
		if floor_cells.has(at) and rich(str(each["area"]), at) > 0.0:
			return at
	return home


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


## A body of group [param id] fled into [param to_area] at [param cell]:
## its unit is out of the group of its species nearest there (or a new
## one at the cell). That group's id, for the body's spec.
func moved(id: String, to_area: String, cell: Vector2i) -> String:
	var from: Dictionary = _groups.get(id, {})
	if from.is_empty():
		return id
	from["out"] = maxi(int(from["out"]) - 1, 0)
	var to := _group_for("", to_area, str(from["species"]), cell)
	to["out"] = int(to["out"]) + 1
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
	for record: Dictionary in records:
		var entry: Dictionary = record.get("entry", {})
		var kind := str(entry.get("kind", ""))
		# A level's own animal (a slot) stays the level's.
		if kind == "" or not Animal.is_wild(kind) or not rules.get("species", {}).has(species_of(kind)) 				or int(entry.get("spawn", -1)) >= 0:
			left.append(record)
			continue
		var tile: Variant = Snapshot.vector(entry.get("tile"))
		var each := _group_for(str(entry.get("group", "")), area, species_of(kind), tile if tile is Vector2i else Vector2i.ZERO)
		each["count"] = float(each["count"]) + 1.0
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
	return {"groups": groups, "seeded": _seeded.keys(), "next": _next, "at": _at}


## to_dict's [param saved] over what is here; a group that makes no sense
## is left out with a word.
func from_dict(saved: Dictionary) -> void:
	_next = maxi(int(saved.get("next", 1)), 1)
	_at = int(saved.get("at", -1))
	for area: Variant in saved.get("seeded", []):
		_seeded[str(area)] = true
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
