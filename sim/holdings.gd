class_name Holdings
extends RefCounted
## Who holds what: every place in every level (level.json "places", read
## through WorldMap) and the faction holding it now, how strong it is
## there, and since when. The level gives each place's starting holder; the
## server's snapshot keeps the rest ("holdings": to_dict / the saved
## argument). World keeps one (World.holdings); the world tick changes it
## (take, strengthen, weaken), and the world map view shows it.
##
## Held ground is the cells within a held place's radius (a disc). A place
## nobody holds is open ground and counts for no one. Ground two factions'
## places both cover is contested. An area's holder is only a label, the
## faction holding the most worth of its places (contested on a tie, nobody
## with none): it closes nothing.

signal place_taken(id: String, from: String, to: String)
## The faction holding the most worth of an area's places changed.
signal area_changed(area: String, from: String, to: String)
signal strength_changed(id: String, value: int)

var factions: Factions
## () -> int: the World's steps, the clock "since" is kept by (0 if unset).
var clock := Callable()

## Place id ("<area>/<key>") -> {id, area, key, cell, name, kind, radius,
## worth, start (its starting holder)}.
var _places: Dictionary[String, Dictionary] = {}
var _holder: Dictionary[String, String] = {}
var _strength: Dictionary[String, int] = {}
var _since: Dictionary[String, int] = {}
## A fallen camp's id -> the faction that held it (decision 429): taken back
## by it in time (Main._retake_camps); forgotten once anyone holds it.
var _fell_from: Dictionary[String, String] = {}
## The routes kept up with who holds what (attach), held weakly.
var _attached: Array[WeakRef] = []


## The holdings of [param world_map]'s places: their starting holders, then
## [param saved] (to_dict's, from a snapshot) over them, by [param with_factions]
## (levels/factions.json by default), timed by [param with_clock].
func _init(world_map: WorldMap, with_factions: Factions = null, saved := {}, with_clock := Callable()) -> void:
	factions = with_factions if with_factions != null else Factions.read()
	clock = with_clock
	rebind(world_map)
	from_dict(saved)


## The World's steps now.
func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


## Takes up [param world_map]'s places (a level edited, a builder change
## accepted): a place still there keeps its holder, strength and since; a
## new one starts as its level says. Returns the ids no longer there.
func rebind(world_map: WorldMap) -> Array[String]:
	var places: Dictionary[String, Dictionary] = {}
	for area_name: String in world_map.areas:
		var listed: Dictionary = world_map.areas[area_name]["places"]
		for key: String in listed:
			var place: Dictionary = listed[key]
			var id := "%s/%s" % [area_name, key]
			places[id] = {"id": id, "area": area_name, "key": key, "cell": place["cell"], "name": place["name"],
				"kind": place["kind"], "radius": place["radius"], "worth": place["worth"], "start": place["holder"]}
	var gone: Array[String] = []
	for id: String in _places:
		if not places.has(id):
			gone.append(id)
			_holder.erase(id)
			_strength.erase(id)
			_since.erase(id)
	_places = places
	for id: String in _places:
		if not _holder.has(id):
			var start: String = _places[id]["start"]
			_holder[id] = start if factions.has(start) else Factions.NOBODY
			_strength[id] = 1
			_since[id] = now()
	if not gone.is_empty():
		print("[holdings] places gone from the levels: %s" % ", ".join(gone))
	return gone


# --- Reading -------------------------------------------------------------------------

## Every place's id, sorted.
func all_places() -> Array[String]:
	var out: Array[String] = []
	out.assign(_places.keys())
	out.sort()
	return out


## The ids of [param area_name]'s places, sorted.
func places_in(area_name: String) -> Array[String]:
	return all_places().filter(func(id: String) -> bool: return _places[id]["area"] == area_name)


## The ids of the places [param faction] holds, sorted.
func places_of(faction: String) -> Array[String]:
	return all_places().filter(func(id: String) -> bool: return _holder[id] == faction)


## Place [param id]: {id, area, key, cell, name, kind, radius, worth,
## start}; {} if there is none.
func place(id: String) -> Dictionary:
	return _places.get(id, {})


## Who holds [param id] ("nobody" for none, or no such place).
func holder(id: String) -> String:
	return _holder.get(id, Factions.NOBODY)


func strength(id: String) -> int:
	return _strength.get(id, 0)


## The World's step [param id] last changed hands (or was first seen).
func since(id: String) -> int:
	return _since.get(id, 0)


## The faction holding the most worth of [param area_name]'s places;
## "contested" when two tie for most, "nobody" when no faction holds any.
func area_holder(area_name: String) -> String:
	var worth: Dictionary[String, int] = {}
	for id in places_in(area_name):
		if _holder[id] != Factions.NOBODY:
			worth[_holder[id]] = worth.get(_holder[id], 0) + int(_places[id]["worth"])
	var best := Factions.NOBODY
	var most := -1
	for faction: String in worth:
		if worth[faction] > most:
			best = faction
			most = worth[faction]
		elif worth[faction] == most:
			best = Factions.CONTESTED
	return best


## Who holds [param cell] of [param area_name]: the faction whose held
## places' radii cover it, "contested" when two factions' do, "nobody" when
## none does (or only places nobody holds).
func ground(area_name: String, cell: Vector2i) -> String:
	var found := Factions.NOBODY
	for id in places_in(area_name):
		var faction: String = _holder[id]
		if faction == Factions.NOBODY or faction == found or not covers(id, cell):
			continue
		if found != Factions.NOBODY:
			if not factions.same_side(found, faction):
				return Factions.CONTESTED
			faction = factions.side(faction)  # Allies' ground is their lead's (decision 416).
		found = faction
	return found


## Every camp (a place of kind "camp") a faction holds, of
## [param faction] only if given: {id, area, cell, size (its worth),
## faction}. Raid groups set out from them (WorldRaids); Herds keeps game
## off them.
func camps(faction := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in all_places():
		var place := place(id)
		var holder := holder(id)
		if place.get("kind") == "camp" and holder != Factions.NOBODY and holder != "" and (faction.is_empty() or holder == faction):
			out.append({"id": id, "area": place["area"], "cell": place["cell"], "size": float(place.get("worth", 1)), "faction": holder})
	return out


## The place of one of [param kinds] nearest [param cell] of
## [param area_name] by walking steps over [param routes] (its open layer:
## held ground walked), "" if none can be walked to: where the fallen come
## back (economy; decision 372, kinds "temple" and "healers_hut"). On the
## server, World.raid_groups.routes. With no routes, the nearest in the same
## area as the crow flies.
func nearest(kinds: Array[String], area_name: String, cell: Vector2i, routes: WorldRoutes = null) -> String:
	var best := ""
	var best_steps := INF
	for id in all_places():
		var place: Dictionary = _places[id]
		if place["kind"] not in kinds:
			continue
		var steps := INF
		if routes != null:
			var legs := routes.route(area_name, cell, place["area"], place["cell"])
			if legs.is_empty():
				continue
			steps = WorldRoutes.CROSSING * (legs.size() - 1)
			for leg: Dictionary in legs:
				steps += float(leg["steps"])
		elif place["area"] == area_name:
			steps = Vector2(place["cell"] - cell).length()
		if steps < best_steps:
			best = id
			best_steps = steps
	return best


## Whether place [param id]'s ground takes in [param cell] (its area's).
func covers(id: String, cell: Vector2i) -> bool:
	var place_cell: Vector2i = _places[id]["cell"]
	var radius: int = _places[id]["radius"]
	return (cell - place_cell).length_squared() <= radius * radius


## The cells of [param area_name] [param faction] may not walk: every cell a
## place held by another faction covers (contested ground among them), each
## with the id of a place holding it.
func blocked_cells(area_name: String, faction: String) -> Dictionary[Vector2i, String]:
	var out: Dictionary[Vector2i, String] = {}
	for id in places_in(area_name):
		var held: String = _holder[id]
		if held == Factions.NOBODY or factions.same_side(held, faction):
			continue  # Nobody's, its own or an ally's (decision 416).
		var centre: Vector2i = _places[id]["cell"]
		var radius: int = _places[id]["radius"]
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius and not out.has(centre + Vector2i(dx, dy)):
					out[centre + Vector2i(dx, dy)] = id
	return out


# --- Routes --------------------------------------------------------------------------

## What each side may not walk, area by area, as WorldRoutes takes it:
## faction -> area -> {cell: place id}, for [param world_map]'s areas. A
## layer a side, its lead's (an ally walks where its lead does, decision
## 416: route with Factions.side).
func obstacles(world_map: WorldMap) -> Dictionary:
	var out := {}
	for faction in factions.names().filter(func(id: String) -> bool: return factions.side(id) == id):
		var areas := {}
		for area_name: String in world_map.areas:
			areas[area_name] = blocked_cells(area_name, faction)
		out[faction] = areas
	return out


## Routes over [param world_map] that keep to held ground as it is now and
## as it changes (attach): a layer per faction.
func make_routes(world_map: WorldMap) -> WorldRoutes:
	var routes := WorldRoutes.new(world_map, true, true, obstacles(world_map))
	attach(routes)
	return routes


## Keeps [param routes]' obstacles up with who holds what: now, and on every
## place taken (only that place's area is made again). The routes are held
## weakly: once they are freed, this stops. Any number may be attached, one
## after another (raids given a regenerated map: decision 465).
func attach(routes: WorldRoutes) -> void:
	for faction in routes.factions():
		for area_name in _areas():
			routes.set_obstacles(faction, area_name, blocked_cells(area_name, faction))
	_attached = _attached.filter(func(held: WeakRef) -> bool: return held.get_ref() != null)
	_attached.append(weakref(routes))
	# A bound method, not a lambda: a lambda here would hold this Holdings
	# in its own signal, and neither would ever be freed.
	if not place_taken.is_connected(_retake_routes):
		place_taken.connect(_retake_routes)


func _retake_routes(id: String, _from: String, _to: String) -> void:
	var area_name: String = _places[id]["area"]
	for held: WeakRef in _attached:
		var live: WorldRoutes = held.get_ref()
		if live == null:
			continue
		for faction in live.factions():
			live.set_obstacles(faction, area_name, blocked_cells(area_name, faction))


## The areas with places, sorted.
func _areas() -> Array[String]:
	var out: Array[String] = []
	for id: String in _places:
		if _places[id]["area"] not in out:
			out.append(_places[id]["area"])
	out.sort()
	return out


# --- Changing ------------------------------------------------------------------------

## [param faction] takes place [param id], at [param with_strength]. False
## (nothing changes) for no such place, no such faction, or one that holds
## it already. Emits place_taken, and area_changed if the area's holder
## changes with it.
func take(id: String, faction: String, with_strength := 1) -> bool:
	if not _places.has(id) or not factions.has(faction) or _holder[id] == faction:
		return false
	var area_name: String = _places[id]["area"]
	var area_before := area_holder(area_name)
	var from: String = _holder[id]
	_holder[id] = faction
	_strength[id] = maxi(with_strength, 0)
	_since[id] = now()
	if faction == Factions.NOBODY and from != Factions.NOBODY and _places[id].get("kind") == "camp":
		_fell_from[id] = from
	elif faction != Factions.NOBODY:
		_fell_from.erase(id)
	place_taken.emit(id, from, faction)
	strength_changed.emit(id, _strength[id])
	var area_after := area_holder(area_name)
	if area_after != area_before:
		area_changed.emit(area_name, area_before, area_after)
	return true


## [param id] grows [param amount] stronger. Its strength after.
func strengthen(id: String, amount := 1) -> int:
	return _set_strength(id, strength(id) + amount)


## [param id] grows [param amount] weaker, to 0 at least: still held, but
## any take beats it. Its strength after.
func weaken(id: String, amount := 1) -> int:
	return _set_strength(id, maxi(strength(id) - amount, 0))


func _set_strength(id: String, value: int) -> int:
	if not _places.has(id):
		return 0
	if value != _strength[id]:
		_strength[id] = value
		strength_changed.emit(id, value)
	return value


# --- Saving --------------------------------------------------------------------------

## For the snapshot: place id -> {holder, strength, age (World steps since
## it changed hands)}. An age, not a step, so it reads right whatever the
## clock starts at.
func to_dict() -> Dictionary:
	var out := {}
	for id in all_places():
		out[id] = {"holder": _holder[id], "strength": _strength[id], "age": now() - _since[id]}
		if _fell_from.has(id):
			out[id]["fell_from"] = _fell_from[id]
	return out


## The camps that fell and are nobody's still (decision 429): {id, faction
## (who held it), age (World steps since it fell)}, sorted by id.
func fallen_camps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(_fell_from.keys())
	ids.sort()
	for id in ids:
		out.append({"id": id, "faction": _fell_from[id], "age": now() - _since[id]})
	return out


## to_dict's [param saved] over what is here: places no longer in the
## levels, and factions there are not, are left out with a word.
func from_dict(saved: Dictionary) -> void:
	for id: Variant in saved:
		var entry: Variant = saved[id]
		if not _places.has(str(id)) or not entry is Dictionary:
			print("[holdings] the snapshot's %s is no place in the levels; left out" % [id])
			continue
		var faction := str(entry.get("holder", Factions.NOBODY))
		if not factions.has(faction):
			print("[holdings] the snapshot has %s held by %s, which is no faction; left as it was" % [id, faction])
			continue
		_holder[str(id)] = faction
		_strength[str(id)] = maxi(int(entry.get("strength", 1)), 0)
		_since[str(id)] = now() - maxi(int(entry.get("age", 0)), 0)
		var fell := str(entry.get("fell_from", ""))
		if faction == Factions.NOBODY and factions.all.has(fell):
			_fell_from[str(id)] = fell
