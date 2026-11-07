class_name Apex
extends RefCounted
## An apex creature's lair and its land (decision 780 amended (13); the
## coordinator's approval of apex_lairs_design.md, 11-03, and its 11-04
## ruling: a cheap check every few seconds, never inside a monster's turn).
## Each kind whose row has a "lair" block is one creature in the world, one
## record (World.apexes, saved), in one of three states:
## - "lair": found at its den in its lair zone (its marker there is its den;
##   Main never spawns that marker as a level entity), spawned whenever the
##   zone is awake, healed to full between fights. Left unattacked
##   venture_after_s (counted from the later of its last attack and its
##   death), within its hours and fighting nobody, it goes out.
## - "out": in its land (the row's first "land" zone), out of the cave's
##   mouth, roaming within "range" of it and off the safe paths by
##   "path_margin". It falls back when fought down to fall_back_hp, when its
##   hours end, or after out_most_s.
## - "dead": killed anywhere, it lies dead rise_s, then is in its lair.
## Going either way it walks to the door if a player in its zone sees it,
## else it simply changes state. The body itself is never saved: the record
## lays it afresh.
##
## Its escort (780 amended (15), the old grey's pack; the row's "escort"
## {kind, count, follow}): laid with it wherever it is laid, about it, each
## following it (Animal.escort_lead) and fighting its target; gone with it
## through its door. One killed stays dead (the record's "escort_down")
## till it is back in its lair rise_s after its fall-back, or risen from
## its death: clearing the pack lasts. Out, its escort down to
## "fall_back_escort", it is beaten back. Never saved, as the body.
## Beaten back (its hp or its escort), World.apex_beaten is emitted once
## (companions' "apex_beaten").

## World steps between checks (5 s); a body walking to its door is looked at
## every step.
const CHECK_STEPS := 50
## Steps a walk to the door may take before it simply goes (a crowd in the way).
const LEAVE_MOST_STEPS := 600
## Steps after its last blow in the lair before it is whole again.
const LAIR_HEAL_STEPS := 300
## Steps between new roaming grounds while out.
const ROAM_STEPS := 1200
## Cells round its roaming ground it wanders.
const ROAM_RADIUS := 6

## Kind -> its living body (not saved).
static var _bodies: Dictionary = {}
## Kind -> the walk under way: {"to": state, "since": steps, "why": String}.
static var _leaving: Dictionary = {}
## Kind -> its places, read once from the two levels: den, lair_door,
## land_door, roam (Array[Vector2i]).
static var _places: Dictionary = {}
## Kind -> the step it last took a new roaming ground.
static var _roamed: Dictionary = {}
## Kind -> its escort's living bodies (not saved).
static var _escorts: Dictionary = {}


## The rows with a "lair" block: kind -> that block.
static func rows() -> Dictionary:
	var out := {}
	var kinds := Monster.kinds()
	for kind: String in kinds:
		var row: Variant = kinds[kind]
		if row is Dictionary and row.get("lair") is Dictionary and not (row["lair"] as Dictionary).is_empty():
			out[kind] = row["lair"]
	return out


## Whether the level marker [param spec] in zone [param zone_name] is an
## apex's den (Main spawns it not; the record does).
static func holds_marker(spec: Dictionary, zone_name: String) -> bool:
	if not spec.has("spawn"):
		return false
	var lair: Variant = Monster.kinds().get(str(spec.get("kind", "")), {}).get("lair")
	return lair is Dictionary and not (lair as Dictionary).is_empty() and str(lair.get("zone", "")) == zone_name


## Whether [param entity] is an apex's body (never saved, never retired).
static func is_body(entity: GridEntity) -> bool:
	if entity == null:
		return false
	if _bodies.values().has(entity):
		return true
	for kind: String in _escorts:
		if (_escorts[kind] as Array).has(entity):
			return true
	return false


## Every record and body forgotten (a test's fresh start); no despawns.
static func clear() -> void:
	_bodies.clear()
	_leaving.clear()
	_places.clear()
	_roamed.clear()
	_escorts.clear()


## [param kind]'s record, made the first time (in its lair, its wait to go
## out starting now).
static func record(kind: String) -> Dictionary:
	if not World.apexes.has(kind):
		World.apexes[kind] = {"state": "lair", "since": World.steps, "attacked": World.steps, "died": -1,
				"dead_until": 0, "hp": -1}
	return World.apexes[kind]


## [param kind]'s living body, or null.
static func body_of(kind: String) -> Monster:
	var body: Variant = _bodies.get(kind)
	if body is Monster and is_instance_valid(body) and (body as Monster).spawned:
		return body
	_bodies.erase(kind)
	return null


## World.step, each step: every apex's check (CHECK_STEPS apart, every step
## while one walks to its door).
static func step() -> void:
	if not Net.is_authority() or not World.spawn_spec.is_valid():
		return
	var all := rows()
	for kind: String in all:
		if _escorts.has(kind):
			_tend_escort(kind)
		if World.steps % CHECK_STEPS == 0 or _leaving.has(kind):
			_check(kind, all[kind])


static func _check(kind: String, row: Dictionary) -> void:
	var places := _places_of(kind, row)
	if places.is_empty():
		return
	var rec := record(kind)
	var body := body_of(kind)
	if _leaving.has(kind):
		_tend_leaving(kind, row, body)
		return
	match str(rec["state"]):
		"dead":
			if World.steps >= int(rec["dead_until"]):
				_set_state(kind, "lair", "risen")
		"lair":
			if body == null:
				body = _lay(kind, row, str(row["zone"]), places["den"])
			if body != null and body.target == null and World.steps - int(rec["attacked"]) >= LAIR_HEAL_STEPS:
				body.hp = body.max_hp  # Whole again between fights.
			if body != null and body.target == null and int(rec.get("escort_down", 0)) > 0 \
					and World.steps >= int(rec.get("escort_whole_at", 0)):
				rec["escort_down"] = 0  # Its pack whole again in its lair.
				_lay_escort(kind, body)
			if _may_venture(rec, row, body):
				_go(kind, row, body, "out", "ventures", places["lair_door"])
		"out":
			if body == null:
				body = _lay(kind, row, _land(row), places["land_door"])
				if body != null and (body as Object).get("apex_out") != null:
					body.set("apex_out", true)
			if body != null:
				rec["hp"] = body.hp
				_roam(kind, body, places)
			var why := _fall_back_why(kind, rec, row, body)
			if why != "":
				_go(kind, row, body, "lair", why, places["land_door"])


## Unattacked venture_after_s since the later of its last blow and its death,
## within its hours, fighting nobody.
static func _may_venture(rec: Dictionary, row: Dictionary, body: Monster) -> bool:
	var since := int(rec["attacked"]) if int(rec["died"]) < 0 else maxi(int(rec["attacked"]), int(rec["died"]))
	if World.steps - since < _steps(row, "venture_after_s", 1800.0):
		return false
	if not _in_hours(row):
		return false
	if int(rec.get("escort_down", 0)) > 0:
		return false  # Its pack not whole yet (780 amended (15)): it waits in its lair.
	return body == null or body.target == null


## Why it goes home now, or "": beaten down to fall_back_hp (fighting or
## not), else, fighting nobody, its hours over or out out_most_s.
static func _fall_back_why(kind: String, rec: Dictionary, row: Dictionary, body: Monster) -> String:
	if body != null and body.hp <= roundi(float(row.get("fall_back_hp", 0.4)) * body.max_hp):
		return "beaten back"
	if body != null and row.has("fall_back_escort") and not escort_row(kind).is_empty() \
			and living_escort(kind) <= int(row["fall_back_escort"]):
		return "beaten back"  # Its pack cleared (780 amended (15)): Jeff's "push him back by clearing".
	if body != null and body.target != null:
		return ""
	if not _in_hours(row):
		return "its hours over"
	if World.steps - int(rec["since"]) >= _steps(row, "out_most_s", 2400.0):
		return "out long"
	return ""


## Its state to [param to] ([param why]): through the door at [param door]
## if a player in its zone sees it, else at once.
static func _go(kind: String, _row: Dictionary, body: Monster, to: String, why: String, door: Vector2i) -> void:
	if why == "beaten back" and body != null:
		World.apex_beaten.emit(kind, body, body.tile)  # Companions' "apex_beaten" (780 amended (15)).
	if body != null and _seen(body):
		_leaving[kind] = {"to": to, "since": World.steps, "why": why}
		body.set("apex_goal", door)
		if body.has_method("_roar"):
			body.call("_roar", why)
		print("[apex] %s %s: walks to its door %s from %s (%d/%d)" % [kind, why, door, body.tile, body.hp, body.max_hp])
		return
	if body != null:
		_despawn(kind, body)
	_set_state(kind, to, why)


## A walk to the door: there (or too long at it), it goes; a venture given
## up when it is struck on the way.
static func _tend_leaving(kind: String, row: Dictionary, body: Monster) -> void:
	var walk: Dictionary = _leaving[kind]
	if body == null:
		_leaving.erase(kind)
		_set_state(kind, walk["to"], walk["why"])
		return
	var to: String = walk["to"]
	if to == "out" and not _may_venture(record(kind), row, body):
		_leaving.erase(kind)
		body.set("apex_goal", Monster.NO_TILE)
		print("[apex] %s stays (struck on its way out) at %s" % [kind, body.tile])
		return
	var door: Vector2i = body.get("apex_goal")
	if World.distance(body.tile, door) <= 1 or World.steps - int(walk["since"]) >= LEAVE_MOST_STEPS:
		_leaving.erase(kind)
		_despawn(kind, body)
		_set_state(kind, to, walk["why"])


static func _set_state(kind: String, to: String, why: String) -> void:
	var rec := record(kind)
	var was := str(rec["state"])
	rec["state"] = to
	rec["since"] = World.steps
	if to == "lair" and was == "dead":
		rec["escort_down"] = 0  # Risen: its pack whole with it.
	elif to == "lair":
		rec["escort_whole_at"] = World.steps + _steps(rows().get(kind, {}), "rise_s", 1800.0)
	var row: Dictionary = rows().get(kind, {})
	print("[apex] %s %s: %s -> %s (%s)" % [kind, why, was, to, str(row.get("zone", "")) if to == "lair" else _land(row)])


## A body for [param kind] in [param zone_name] at [param at] (the nearest
## free cell), the zone awake; null if not yet.
static func _lay(kind: String, _row: Dictionary, zone_name: String, at: Vector2i) -> Monster:
	var zone: Zone = World.zones.get(zone_name)
	if zone == null or not World.zone_awake(zone):
		return null
	var was := World.zone
	World.enter(zone)
	var made: Monster = null
	var cell := _free_near(at)
	var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
	if cell != World.NO_CELL and not spec.is_empty():
		spec["name"] = ("Apex_" + kind).validate_node_name()
		spec["tile"] = cell
		spec["home"] = cell
		var body: Variant = World.spawn_spec.call(spec)
		if body is Monster:
			made = body
			_bodies[kind] = made
			var rec := record(kind)
			if str(rec["state"]) == "out" and int(rec["hp"]) > 0:
				made.hp = mini(int(rec["hp"]), made.max_hp)
			print("[apex] %s in %s at %s (%d/%d)" % [kind, zone_name, cell, made.hp, made.max_hp])
			_lay_escort_here(kind, made)
	World.enter(was)
	return made


static func _free_near(at: Vector2i) -> Vector2i:
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := at + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and World.is_walkable(cell) and World.is_free(cell):
					return cell
	return World.NO_CELL


static func _despawn(kind: String, body: Monster) -> void:
	_bodies.erase(kind)
	for each: Variant in _escorts.get(kind, []):
		if is_instance_valid(each) and (each as GridEntity).spawned:
			World.despawn(each)  # Through its door with it.
	_escorts.erase(kind)
	World.despawn(body)


## [param kind]'s row's "escort" block, {} for none.
static func escort_row(kind: String) -> Dictionary:
	var escort: Variant = Monster.kinds().get(kind, {}).get("escort")
	return escort if escort is Dictionary else {}


## How many of [param kind]'s escort live.
static func living_escort(kind: String) -> int:
	var n := 0
	for each: Variant in _escorts.get(kind, []):
		if is_instance_valid(each) and (each as GridEntity).spawned and (each as GridEntity).hp > 0:
			n += 1
	return n


## Its escort as it should be now (its count less those down) laid about
## [param body], in its zone.
static func _lay_escort(kind: String, body: Monster) -> void:
	var zone: Zone = World.zones.get(body.zone)
	if zone == null:
		return
	var was := World.zone
	World.enter(zone)
	_lay_escort_here(kind, body)
	World.enter(was)


## _lay_escort with World already in [param body]'s zone.
static func _lay_escort_here(kind: String, body: Monster) -> void:
	var escort := escort_row(kind)
	if escort.is_empty():
		return
	var count: Variant = escort.get("count", [0, 0])
	var full := int(count[0]) if count is Array and not (count as Array).is_empty() else int(count)
	var list: Array = _escorts.get(kind, [])
	_escorts[kind] = list
	var want := full - int(record(kind).get("escort_down", 0)) - living_escort(kind)
	var spec_of := Level._spec_for("monster_" + str(escort.get("kind", "wolf")), Level.MONSTER_TYPES)
	if spec_of.is_empty():
		return
	for i in maxi(0, want):
		var cell := _free_near(body.tile)
		if cell == World.NO_CELL:
			break
		var spec := spec_of.duplicate(true)
		spec["name"] = ("Apex_%s_escort_%d" % [kind, World.steps * 10 + i]).validate_node_name()
		spec["tile"] = cell
		spec["home"] = cell
		var made: Variant = World.spawn_spec.call(spec)
		if made is Animal:
			(made as Animal).escort_lead = body
			(made as Animal).escort_follow = int(escort.get("follow", 4))
			list.append(made)
	print("[apex] %s escort %d of %d about %s" % [kind, living_escort(kind), full, body.tile])


## Each step: an escort killed is down (stays dead, the record's
## "escort_down"); its lead dead, those fighting nobody are gone.
static func _tend_escort(kind: String) -> void:
	var list: Array = _escorts[kind]
	var lead := body_of(kind)
	var rec := record(kind)
	for each: Variant in list.duplicate():
		if not is_instance_valid(each) or not (each as GridEntity).spawned or (each as GridEntity).hp <= 0:
			list.erase(each)
			rec["escort_down"] = int(rec.get("escort_down", 0)) + 1
			print("[apex] %s escort down, %d live" % [kind, living_escort(kind)])
		elif lead == null and (each as Monster).target == null:
			list.erase(each)
			World.despawn(each)  # Its lead fallen, its fight over: gone.
	if list.is_empty() and lead == null:
		_escorts.erase(kind)


## Whether a player in its zone sees [param body] (within VIEW_TILES, a clear
## line).
static func _seen(body: Monster) -> bool:
	var zone: Zone = World.zones.get(body.zone)
	if zone == null:
		return false
	var was := World.zone
	World.enter(zone)
	var seen := false
	for each in World.sought():
		if each is Player and (each as Player).spawned and World.distance(each.tile, body.tile) <= World.VIEW_TILES \
				and World.has_line_of_sight(each.tile, body.tile):
			seen = true
			break
	World.enter(was)
	return seen


## Out: now and then a new roaming ground (its home and den), off the safe
## paths, while it fights nobody.
static func _roam(kind: String, body: Monster, places: Dictionary) -> void:
	if body.target != null or body.get("apex_goal") != Monster.NO_TILE:
		return
	if World.steps - int(_roamed.get(kind, -ROAM_STEPS)) < ROAM_STEPS:
		return
	var roam: Array = places["roam"]
	if roam.is_empty():
		return
	_roamed[kind] = World.steps
	var at: Vector2i = roam[(World.steps + body.id * 7) % roam.size()]
	body.home = at
	if (body as Object).get("den") != null:
		body.set("den", at)
	body.wander_radius = ROAM_RADIUS


static func _land(row: Dictionary) -> String:
	var land: Variant = row.get("land", [])
	return str(land[0]) if land is Array and not land.is_empty() else ""


static func _in_hours(row: Dictionary) -> bool:
	var hours: Variant = row.get("hours", [0, 24])
	var hour := DayNight.hour(DayNight.now())
	return hours is Array and hours.size() == 2 and hour >= float(hours[0]) and hour < float(hours[1])


static func _steps(row: Dictionary, key: String, default: float) -> int:
	return roundi(float(row.get(key, default)) * World.TICK_RATE)


## Its den, the doors either side (each the arrival cell from the other) and
## its roaming grounds, from its lair's and its land's levels, once; {} if
## either is missing.
static func _places_of(kind: String, row: Dictionary) -> Dictionary:
	if _places.has(kind):
		return _places[kind]
	var lair_name := str(row.get("zone", ""))
	var land_name := _land(row)
	if not Level.exists(lair_name) or not Level.exists(land_name):
		_places[kind] = {}
		return {}
	var lair := Level.load_level(lair_name)
	var land := Level.load_level(land_name)
	var den := World.NO_CELL
	for spec: Dictionary in lair.get("entities", []):
		if str(spec.get("kind", "")) == kind:
			den = spec["tile"]
	var lair_door: Variant = lair.get("spawn_points", {}).get("from_" + land_name)
	var land_door: Variant = land.get("spawn_points", {}).get("from_" + lair_name)
	if den == World.NO_CELL or not lair_door is Vector2i or not land_door is Vector2i:
		push_warning("Apex: %s has no den, or no door in %s or %s" % [kind, lair_name, land_name])
		_places[kind] = {}
		return {}
	var roam: Array = roaming_grounds(land, land_door, int(row.get("range", 40)), int(row.get("path_margin", 6)))
	var pad_margin := float(row.get("pad_margin", 0))
	if pad_margin > 0.0:
		# Off the land's other links' pads (780 amended (15)): the old grey
		# keeps clear of the castle's and the wilds' arrivals.
		for link: Dictionary in land.get("links", []):
			if str(link.get("to_map", "")) == lair_name:
				continue
			var at: Variant = link.get("tile", link.get("at"))  # A loaded level's "tile", a config's "at".
			var pad: Vector2i = at if at is Vector2i else (Vector2i(int(at[0]), int(at[1])) if at is Array and (at as Array).size() == 2 else World.NO_CELL)
			if pad != World.NO_CELL:
				roam = roam.filter(func(cell: Vector2i) -> bool: return Vector2(cell - pad).length() > pad_margin)
	_places[kind] = {"den": den, "lair_door": lair_door, "land_door": land_door, "roam": roam}
	return _places[kind]


## The cells of [param level] within [param reach] of [param from] (but not
## within ROAM_RADIUS of it, the mouth's front), each more than
## [param margin] from a safe path (Level.safe_paths), every 3rd cell.
static func roaming_grounds(level: Dictionary, from: Vector2i, reach: int, margin: int) -> Array[Vector2i]:
	var terrain: Dictionary = level["terrain"]
	var near_path: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in Level.safe_paths(terrain):
		if maxi(absi(cell.x - from.x), absi(cell.y - from.y)) > reach + margin:
			continue
		for dy in range(-margin, margin + 1):
			for dx in range(-margin, margin + 1):
				near_path[cell + Vector2i(dx, dy)] = true
	var out: Array[Vector2i] = []
	for cell: Vector2i in terrain["floor"]:
		var off := maxi(absi(cell.x - from.x), absi(cell.y - from.y))
		if off > reach or off <= ROAM_RADIUS or near_path.has(cell) or (cell.x + cell.y) % 3 != 0:
			continue
		out.append(cell)
	out.sort()
	return out


## A blow on an apex's body (GreatBear.note_struck): its wait to go out
## starts again, and a walk out is given up.
static func struck(body: GridEntity) -> void:
	for kind: String in _bodies:
		if _bodies[kind] == body:
			record(kind)["attacked"] = World.steps
			return


## An apex's body killed (GreatBear._on_died): dead rise_s, then in its lair.
static func died(body: GridEntity) -> void:
	for kind: String in _bodies.keys():
		if _bodies[kind] != body:
			continue
		_bodies.erase(kind)
		_leaving.erase(kind)
		var rec := record(kind)
		var row: Dictionary = rows().get(kind, {})
		rec["died"] = World.steps
		rec["dead_until"] = World.steps + _steps(row, "rise_s", 1800.0)
		rec["hp"] = -1
		_set_state(kind, "dead", "killed")
		return
