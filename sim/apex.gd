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
## Steps after its last blow in the lair, and after the last who struck it
## in this fight was in its lair (780 amended (20)), before it is whole again.
const LAIR_HEAL_STEPS := 300
## Steps between new roaming grounds while out.
const ROAM_STEPS := 1200
## Cells round its roaming ground it wanders.
const ROAM_RADIUS := 6
## Barred from its den by a foe this long on its walk home (Apex.to_den's
## "barred", 780 amended (26)), it turns at bay where it stands; at bay, its
## way home looked at again this often.
const BARRED_TICKS := 10

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
## Kind -> who struck it in this fight, by fighter_key (780 amended (20);
## not saved): one downed or killed since is out of it till they strike again.
static var _fighters: Dictionary = {}
## Kind -> the step one of its fighters was last seen in its lair zone.
static var _fight_seen: Dictionary = {}


## The rows with a "lair" block: kind -> that block. A lair held back
## (Level.SHELVED, 820) holds nobody: its apex is not in the world, in its
## lair or out, till its package opens the lair (780 amended (16)).
static func rows() -> Dictionary:
	var out := {}
	var kinds := Monster.kinds()
	for kind: String in kinds:
		var row: Variant = kinds[kind]
		if row is Dictionary and row.get("lair") is Dictionary and not (row["lair"] as Dictionary).is_empty() 				and not Level.SHELVED.has(str(row["lair"].get("zone", ""))):
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
	_fighters.clear()
	_fight_seen.clear()


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
			_note_fighters(kind, str(row["zone"]))
			if body != null and body.target == null and World.steps - int(rec["attacked"]) >= LAIR_HEAL_STEPS \
					and World.steps - int(_fight_seen.get(kind, -LAIR_HEAL_STEPS)) >= LAIR_HEAL_STEPS:
				body.hp = body.max_hp  # Whole again between fights: none who fought it in its lair for a while (780 amended (20)).
				_fighters.erase(kind)
			if body != null and body.target == null and int(rec.get("escort_down", 0)) > 0 \
					and World.steps >= int(rec.get("escort_whole_at", 0)) and _fight_over(rec, kind):
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


## Its fight over: LAIR_HEAL_STEPS since the later of its last blow taken
## and its escort's last fallen (playtest's boar king run: a boar killed in
## the lair came back the step its lead's target lapsed between foes).
static func _fight_over(rec: Dictionary, kind := "") -> bool:
	var last := maxi(int(rec.get("attacked", -LAIR_HEAL_STEPS)), int(rec.get("escort_fell", -LAIR_HEAL_STEPS)))
	last = maxi(last, int(_fight_seen.get(kind, -LAIR_HEAL_STEPS)))  # And its fighters gone (780 amended (20)).
	return World.steps - last >= LAIR_HEAL_STEPS


## Who [param player] is among an apex's fighters: its player_id, else
## (a test's) its instance.
static func fighter_key(player: GridEntity) -> String:
	var id := str(player.get("player_id")) if "player_id" in player else ""
	return id if id != "" and id != "<null>" else "i%d" % player.get_instance_id()


## Whether one who struck [param kind] in this fight stands in its lair
## zone [param zone_name] now; if so, the step is noted (_fight_seen).
static func _note_fighters(kind: String, zone_name: String) -> void:
	var fought: Dictionary = _fighters.get(kind, {})
	if fought.is_empty():
		return
	var zone: Zone = World.zones.get(zone_name)
	if zone == null:
		return
	var was := World.zone
	World.enter(zone)
	for each in World.sought():
		if each is Player and each.spawned and each.hp > 0 and fought.has(fighter_key(each)):
			_fight_seen[kind] = World.steps
			break
	World.enter(was)


## [param player] downed or killed (World.damage, 780 amended (20)): out of
## every apex's fight till they strike it again, so coming back fresh never
## holds its healing off.
static func forget_fighter(player: GridEntity) -> void:
	if not is_instance_valid(player):
		return
	var key := fighter_key(player)
	for kind: String in _fighters:
		(_fighters[kind] as Dictionary).erase(key)


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
			rec["escort_fell"] = World.steps
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
## starts again, and a walk out is given up. A player who struck it
## [param by] is one of its fighters till it is whole again (780 amended (20)).
static func struck(body: GridEntity, by: GridEntity = null) -> void:
	for kind: String in _bodies:
		if _bodies[kind] == body:
			record(kind)["attacked"] = World.steps
			if by is Player and is_instance_valid(by):
				if not _fighters.has(kind):
					_fighters[kind] = {}
				(_fighters[kind] as Dictionary)[fighter_key(by)] = true
			return


## An apex's body killed (GreatBear._on_died): dead rise_s, then in its lair.
static func died(body: GridEntity) -> void:
	for kind: String in _bodies.keys():
		if _bodies[kind] != body:
			continue
		_bodies.erase(kind)
		_leaving.erase(kind)
		_fighters.erase(kind)  # Its fight over with it (780 amended (20)).
		_fight_seen.erase(kind)
		var rec := record(kind)
		var row: Dictionary = rows().get(kind, {})
		rec["died"] = World.steps
		rec["dead_until"] = World.steps + _steps(row, "rise_s", 1800.0)
		rec["hp"] = -1
		_set_state(kind, "dead", "killed")
		return


## Where [param body] makes its stand (companions' read, for a berth that
## never stands on its way home, its den or the cells beside them; 780
## amended (26)'s follow-up): its den while it is on the den rule (to_den
## holds it: broken off, _wallow_from set), walking home, at its den or at
## bay where a foe barred it; Monster.NO_TILE otherwise, and on the boar
## king's far way (away and alone, no den to keep).
static func homeward(body: GridEntity) -> Vector2i:
	if not is_instance_valid(body) or not body.spawned or body.hp <= 0:
		return Monster.NO_TILE
	if body.get("_wallow_from") == null or bool(body.get("_wallow_far")):
		return Monster.NO_TILE
	var den: Variant = body.get("den")
	return den if den is Vector2i else Monster.NO_TILE


## Its foe on the den rule (780 amended (29), the coordinator's order; while
## homeward gives its den: walking home, at its den, at bay), in place of
## [param seen], its usual pick: whoever struck it last, within its set's
## reach (the body's _set_reach); else [param seen] if it is fighting it,
## else the nearest who is (a player; a companion not broken off, or one who
## has struck it: a striker like anyone); a broken-off companion who has not
## struck it only when nobody else is a foe at all. It ranks foes once its
## own look has found one, and finds none its look has not.
static func den_foe(body: Monster, seen: GridEntity) -> GridEntity:
	if homeward(body) == Monster.NO_TILE:
		return seen
	if seen == null:
		return null  # Its own look finds nobody yet (sight, notice): the order finds nobody either.
	var last := body.struck_by
	if _den_able(last) and (last is Player or last is Companion) \
			and World.distance(body.tile, last.tile) <= int(body.call("_set_reach")) \
			and _den_knows(body, last, World.distance(body.tile, last.tile)):
		return last
	if _den_able(seen) and _den_fighting(body, seen):
		return seen
	var best: GridEntity = null
	var best_d := body.sight_range + 1
	for entity in World.sought():
		if entity == seen or not _den_able(entity) or not _den_fighting(body, entity):
			continue
		var d := World.distance(body.tile, entity.tile)
		if d < best_d and _den_knows(body, entity, d):
			best = entity
			best_d = d
	return best if best != null else seen


## Whether [param body] knows of [param entity], [param d] off, as its own
## look does (Monster._nearest_visible_target): touching it, answering its
## blow just now, or seen (in its cone unless it is its target). The order
## ranks the foes it knows of; it gives it no eyes behind (a striker
## following it home, unseen, is not turned on at once).
static func _den_knows(body: Monster, entity: GridEntity, d: int) -> bool:
	return d <= 1 or body._answering(entity) or body.senses.sees(entity, d, entity != body.target)


## A foe it may take on the den rule: there, up, out of its spawn grace.
static func _den_able(entity: GridEntity) -> bool:
	return entity != null and is_instance_valid(entity) and entity.spawned and entity.hp > 0 \
			and not entity.protected and not World.is_downed(entity)


## Whether [param entity] fights [param body] (den_foe): a player; a
## player's companion not broken off (Companion.broken_off), or one who has
## struck it (the body's _den_struck), broken off or not.
static func _den_fighting(body: Monster, entity: GridEntity) -> bool:
	if entity is Player:
		return true
	if not (entity is Companion and (entity as Companion).keeper != null):
		return false
	var struck: Variant = body.get("_den_struck")
	if struck is Dictionary and (struck as Dictionary).has(entity.get_instance_id()):
		return true
	return not (entity as Companion).broken_off()


## The den rule (780 amended (16), the boar king's wallow; 780 amended (26):
## shared with the great bear and the old grey). Under [param below] of its
## hp in its lair (out, Apex's beaten back takes it home first) it never
## flees: no new fight, it walks to [param den], biting back at
## [param biter] when beside it, never chasing nor charging; at its den
## (within opts "near"), cornered, it fights as ever, its whole set. A foe by
## its den (within 3) when it breaks off: with opts "far" (the king) it goes
## away and alone instead, the far way, opts "clear" off them; without, it
## fights on where it stands. With opts "at_bay_after" over 0, struck that
## often on the walk it turns at bay where it stands. With opts
## "bite_per_blow" (the bear and the grey, 780 amended (26)) it bites back
## once for each blow on it that lands on the walk, never more than one
## owed, with its own told move (the body's _den_bite: the bear's swipe, the
## grey's led bite); without (the king's, till his switch-on) at its cadence,
## untold. With opts "barred" (the bear and the grey) its own (_own) never
## bar its way home: it changes places with one in its way (_past_own); a
## foe who bars it (_barred) BARRED_TICKS on end corners it, at bay where it
## stands with its whole set, till its way home is open again. Its state rides the body's own _wallow_from and _wallow_far (and
## _wallow_hits, _wallow_seen with "at_bay_after"; _wallow_owed,
## _wallow_owed_seen with "bite_per_blow"); opts "log" names its log lines.
## A boss's stand (806 amended (14), Monster.stands: Brand) keeps the same rule
## on its own ground, its home for its den, with Monster.STAND_RULE.
## True while it holds the body.
static func to_den(body: Monster, below: float, den: Vector2i, biter: GridEntity, opts: Dictionary = {}) -> bool:
	var at_bay_after := int(opts.get("at_bay_after", 0))
	if body.get("apex_out") == true or body.hp <= 0 or float(body.hp) >= below * float(body.max_hp):
		body.set("_wallow_from", null)
		body.set("_wallow_far", false)
		if at_bay_after > 0:
			body.set("_wallow_hits", 0)
		if bool(opts.get("barred", false)):
			body.set("_wallow_barred", -1)
			body.set("_wallow_at_bay", false)
			body.set("_wallow_bay_hard", false)
		var struck: Variant = body.get("_den_struck")
		if struck is Dictionary and body.hp >= body.max_hp:
			(struck as Dictionary).clear()  # Whole again: its fight's strikers forgotten (780 amended (29)).
		return false
	var near := int(opts.get("near", 1))
	var far_way := bool(opts.get("far", false))
	var log_as := str(opts.get("log", "wallow"))
	var stored: Variant = body.get("_wallow_from")
	if body.target != null and stored == null:
		if not far_way and (World.distance(body.tile, den) <= near or World.distance(body.target.tile, den) <= 3):
			return false  # By its den already, or a foe there: it fights on, cornered.
		# Where to: its den, unless the foe stands by it (within 3), when
		# going home is no retreat: away and alone instead, the far way.
		stored = body.target
		body.set("_wallow_from", stored)
		body.set("_wallow_far", far_way and World.distance(body.target.tile, den) <= 3)
		if at_bay_after > 0:
			body.set("_wallow_hits", 0)
			body.set("_wallow_seen", body.struck_tick)
		body.set("_wallow_tick", World.tick)  # Its pack's (Animal._escort_target); none on the king's.
		if bool(opts.get("barred", false)):
			body.set("_wallow_barred", -1)
			body.set("_wallow_at_bay", false)
			body.set("_wallow_bay_hard", false)
		if bool(opts.get("bite_per_blow", false)):
			body.set("_wallow_owed", false)  # Blows on the walk owe bites, not the one before it.
			body.set("_wallow_owed_seen", body.struck_tick)
		body.call("_log_move", log_as, "breaks off" + (", the far way (a foe by his den)" if bool(body.get("_wallow_far")) else ""))
	var far := bool(body.get("_wallow_far"))
	var foe: GridEntity = null
	if is_instance_valid(stored) and (stored as GridEntity).spawned and (stored as GridEntity).hp > 0:
		foe = stored as GridEntity
	if not far and World.distance(body.tile, den) <= near:
		return false  # At its den: cornered, it fights.
	if bool(opts.get("barred", false)) and bool(body.get("_wallow_at_bay")):
		# Barred from its den, cornered: at bay where it stands, its whole
		# set, till its way home is open again (looked at every BARRED_TICKS).
		# Refused a step its way read open for (780 amended (30)), till it
		# also has nobody to fight: no flicking between a fight and a wall.
		if World.tick < int(body.get("_wallow_barred")) + BARRED_TICKS or _barred(body, den) \
				or bool(body.get("_wallow_bay_hard")) and body.target != null:
			if World.tick >= int(body.get("_wallow_barred")) + BARRED_TICKS:
				body.set("_wallow_barred", World.tick)
			return false
		body.set("_wallow_at_bay", false)
		body.set("_wallow_bay_hard", false)
		body.set("_wallow_barred", -1)
		body.call("_log_move", log_as, "goes on home, its way open")
	if far and foe != null and World.distance(body.tile, foe.tile) <= 1 and body.call("_away_from", foe, true) == Vector2i.ZERO:
		return false  # The far way, and no step away: cornered, it fights.
	if at_bay_after > 0 and stored != null:
		if body.struck_tick > int(body.get("_wallow_seen")):
			body.set("_wallow_seen", body.struck_tick)
			body.set("_wallow_hits", int(body.get("_wallow_hits")) + 1)
			if int(body.get("_wallow_hits")) == at_bay_after:
				body.call("_log_move", log_as, "turns at bay, struck %d times on the way" % at_bay_after)
		if int(body.get("_wallow_hits")) >= at_bay_after:
			return false  # Pressed on the way: at bay where it stands.
	var per_blow := bool(opts.get("bite_per_blow", false))
	if per_blow and not World.winding(body).is_empty():
		return true  # Its told bite under way: it stands through its lead.
	body.target = null
	body.set("_foe", null)  # An animal's charge (a stand's monster has none).
	body._drop_windup()
	if World.is_stunned(body):
		return true
	var by := biter
	if per_blow:
		# One bite owed for each blow on it that lands (780 amended (26)),
		# never more than one: its own told move, begun as in its fight
		# (_den_bite), that she can step out of; begun, it is paid, landed
		# or not.
		if body.struck_tick > int(body.get("_wallow_owed_seen")):
			body.set("_wallow_owed_seen", body.struck_tick)
			body.set("_wallow_owed", true)
		if bool(body.get("_wallow_owed")) and by != null and is_instance_valid(by) and by.spawned and by.hp > 0 \
				and World.distance(body.tile, by.tile) <= 1 and World.tick >= body.next_attack_tick \
				and bool(body.call("_den_bite", by)):
			body.set("_wallow_owed", false)
			body.call("_log_move", log_as, "bites back, told")
			return true
	elif by != null and is_instance_valid(by) and by.spawned and by.hp > 0 and World.distance(body.tile, by.tile) <= 1 \
			and World.tick >= body.next_attack_tick:
		body._world_set_facing(Senses.way_toward(body.tile, by.tile))
		var was := by.hp
		if World.try_attack(body, by):
			body.next_attack_tick = World.tick + World.attack_ticks_of(body)
			body.call("_log_move", log_as, "bites back")
			if by.hp < was:
				# Untold (the king's wallow, till his switch-on): the tours'
				# tripwire line, as GreatBear._blow's.
				print("[apex] %s blow %s %d at %s (%d/%d)" % [body.call("_kind"), World.kind_of(by), was - by.hp, body.tile, body.hp, body.max_hp])
			return true
	if World.tick >= body.next_move_tick:
		body.move_ticks = body._pace
		if far:
			# Each step away from them, within its roam of its den, never nearer
			# (never through their reach); "clear" off, it stands, alone.
			if foe != null and World.distance(body.tile, foe.tile) < int(opts.get("clear", 6)):
				var way: Vector2i = body.call("_away_from", foe, true)
				if way != Vector2i.ZERO:
					World.try_move(body, way)
		elif body._idle_step(den, GreatBear.WALK_SEARCH_TILES):
			if bool(opts.get("barred", false)):
				body.set("_wallow_barred", -1)
		elif not (bool(opts.get("barred", false)) and _past_own(body, den)):
			body.next_move_tick = World.tick + 5
			if bool(opts.get("barred", false)):
				# Its step home failing (780 amended (26)): barred by a foe (in
				# a two-wide way, she or her companion), or refused for anything
				# else (a link's cell, a body's edge; 780 amended (30)):
				# BARRED_TICKS of it and it is cornered.
				if int(body.get("_wallow_barred")) < 0:
					body.set("_wallow_barred", World.tick)
				elif World.tick - int(body.get("_wallow_barred")) >= BARRED_TICKS:
					body.set("_wallow_at_bay", true)
					body.set("_wallow_bay_hard", not _barred(body, den))
					body.set("_wallow_barred", World.tick)
					body.call("_log_move", log_as, "turns at bay, its way home barred")
	return true


## Its next cell on its way to [param den] with its own planned through
## (_own: they are no bar to it, 780 amended (26)); every other body blocks,
## as in any monster's way. Monster.NO_TILE when it has none: barred.
static func _next_home(body: Monster, den: Vector2i) -> Vector2i:
	var lifted: Dictionary[Vector2i, GridEntity] = {}
	for each: GridEntity in _own(body):
		if World._occupancy.get(each.tile) == each:
			lifted[each.tile] = each
			World._occupancy.erase(each.tile)
	var way := World.find_path(body.tile, den, true, null, GreatBear.WALK_SEARCH_TILES, false, {}, body.opens_doors_now())
	for cell: Vector2i in lifted:
		World._occupancy[cell] = lifted[cell]  # Put back at once: only this search plans through them.
	return way[0] if not way.is_empty() and World.distance(body.tile, way[0]) == 1 else Monster.NO_TILE


## Its own about it, that never bar its way home: its escort (Animal.
## escort_lead) and, the grey's, his pack (OldWolf.pack).
static func _own(body: Monster) -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	if body.has_method("pack"):
		for each: Monster in body.call("pack"):
			out.append(each)
	for each in World.monsters():
		if each is Animal and (each as Animal).escort_lead == body and each.spawned and each.hp > 0 and not each in out:
			out.append(each)
	return out


## On its walk home its own in its way (780 amended (26), the coordinator's
## ruling: an apex is never blocked by his escorts): they change places
## (World.swap_places, its rules: beside it, never across a wall, a closed
## door or a corner), at its pace; the one it passes ends on its old cell,
## never anywhere else. True if it went.
static func _past_own(body: Monster, den: Vector2i) -> bool:
	var next := _next_home(body, den)
	if next == Monster.NO_TILE:
		return false
	var there: Variant = World._occupancy.get(next)
	if there == null:
		return World.try_move(body, next - body.tile)  # Its way round them is open: that way.
	if not (there is GridEntity and there in _own(body)):
		return false
	return World.swap_places(body, there as GridEntity, body._pace)


## Whether its way home is barred: no way past every body but its own (a
## player or her companion in a two-wide way, another beast), or none at all.
static func _barred(body: Monster, den: Vector2i) -> bool:
	return _next_home(body, den) == Monster.NO_TILE
