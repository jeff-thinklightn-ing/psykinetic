class_name Wanderers
extends RefCounted
## A beast drawn to someone fishing (decision 805 amended (2)). Economy
## says when (wanderer_due(pond, player_id, kind, at): a player fishing at a
## pond long enough, once a pond a game day); this brings it. "boar" is one
## boar, "wolf" a pair (WANDER_KINDS). It comes in out of every player's
## sight (just past World.VIEW_TILES from each, on ground with a way to the
## cast cell), walks to the cell they cast from (a march), and is drawn
## (Animal.drawn): a wolf bold whatever the hour, a boar charging what it
## finds instead of bolting, till it is driven off (under half its hp, it
## runs). It is gone, never saved (Snapshot skips an Animal.wanderer) and
## nothing to the herds or the balance:
## - beaten: every one dead, or running and out of everyone's sight;
## - after LINGER_TICKS (90 s) from its coming: any not fighting turn back
##   for the cell they came in at, and go once out of everyone's sight (or
##   there).
## Its drops are its kind's, as any (a boar's meat, hide and tusks).
## One who never strikes back is let be (805 amended (12)): a beast that has
## bitten a body UNANSWERED_BITES times, that body never having struck any
## of its wanderer's beasts, breaks off it and goes the way it came. A
## "wolf" pair comes only to an armed bank (the fisher and every companion
## with them holding or carrying a weapon); to any other, a boar.
## World holds one (World.wanderers), stepped after the raids. Server only.

## Economy's kind -> how many come.
const WANDER_KINDS := {"boar": {"boar": 1}, "wolf": {"wolf": 2}}
## How far past every player's sight it comes in, at most (cells).
const OUT_TILES := 10
## Ticks (10 a second) after its coming before one not fighting gives up.
const LINGER_TICKS := 900
## Its way to the dry cell by the cast: searched this far at most.
const ROUTE_SEARCH_TILES := 6000
## A route's waypoints this many steps apart (as Raids' marches).
const WAYPOINT_EVERY := 6
## How far from the cast its dry goal is looked for (805 amended (12)).
const DRY_TILES := 8
## How many of the nearest dry cells are tried for a way from the one
## fishing (a river's far bank is nearer the cast than hers, at times).
const DRY_TRIES := 12
## Bites a beast lands on a body that has never struck back before it breaks
## off it (805 amended (12), the coordinator's ruling on the pond probe: a
## lone newcomer who stood and never struck back died to the one boar, 7
## bites, in every trial).
const UNANSWERED_BITES := 2
## How near the fisher a companion of theirs counts as at the bank (cells).
const BANK_TILES := 12

const NO_CELL := Vector2i(-99999, -99999)

## Whom economy names: player id -> the spawned Player, or null (Main's).
var player_of: Callable
## Each wanderer in play: id -> {area, pond, kind, beasts, arrival, at,
## start, leaving, back, fought, bites, broke}: fought, the bodies that struck
## one of its beasts (instance id -> true); bites, "beast/body" -> bites on a
## body that never struck back; broke, beast -> {body: true} it broke off.
var _in_play := {}
var _made := 0


## Economy's wanderer_due: [param kind] at pond [param pond], for player
## [param player_id], who cast from [param at]. Its id, "" if none can come
## (an unknown kind, the player gone, no cell out of sight with a way in).
func come(pond: String, player_id: String, kind: String, at: Vector2i) -> String:
	if not Net.is_authority() or not WANDER_KINDS.has(kind) or not player_of.is_valid() or not World.spawn_spec.is_valid():
		return ""
	var player: Variant = player_of.call(player_id)
	if not player is Player or not (player as Player).spawned:
		return ""
	var area := (player as Player).zone
	var zone := _zone(area)
	if zone == null:
		return ""
	if WANDER_KINDS[kind].has("wolf") and not _bank_armed(player as Player):
		# 805 amended (12): the pond probe's wolf pair left a bare companion
		# at 2 and 4 of 20 covering her player's walk away; a pair waits for
		# an armed bank. Economy's roll is unchanged.
		print("[wanderer] %s: a wolf pair waits for an armed bank (someone there bare); a boar comes" % pond)
		kind = "boar"
	if not World.entity_damaged.is_connected(_on_damaged):
		World.entity_damaged.connect(_on_damaged)
	var was := World.zone
	World.enter(zone)
	var id := _start(area, pond, kind, at, (player as Player).tile)
	World.enter(was)
	return id


## World.step, after the raids: each wanderer's end or its turning back.
func step() -> void:
	if _in_play.is_empty():
		return
	var was := World.zone
	for id: String in _in_play.keys():
		var record: Dictionary = _in_play[id]
		var zone := _zone(record["area"])
		if zone == null or not World.zone_awake(zone):
			_end(id, "its zone sleeps")
			continue
		World.enter(zone)
		_step_one(id, record)
	World.enter(was)


## The ids in play, sorted (tests).
func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_in_play.keys())
	out.sort()
	return out


## Wanderer [param id]'s beasts still spawned.
func beasts(id: String) -> Array[Animal]:
	var out: Array[Animal] = []
	if _in_play.has(id):
		for each: Variant in _in_play[id]["beasts"]:
			if is_instance_valid(each) and (each as Animal).spawned:
				out.append(each)
	return out


## Every wanderer gone, no despawns (a test's fresh start).
func clear() -> void:
	_in_play.clear()


# --- Inside -------------------------------------------------------------------------

func _start(area: String, pond: String, kind: String, cast: Vector2i, fisher := NO_CELL) -> String:
	var at := _dry_by(cast, fisher)
	if at == NO_CELL:
		print("[wanderer] none comes to %s: no dry cell she could walk to by the cast at %s" % [pond, cast])
		return ""
	var arrival := _arrival_cell(at)
	if arrival == NO_CELL:
		print("[wanderer] none comes to %s: no cell out of sight with a way to %s" % [pond, at])
		return ""
	_made += 1
	var id := "wanderer:%s:%d" % [pond, _made]
	var route := _route(arrival, at)
	var record := {"area": area, "pond": pond, "kind": kind, "beasts": [], "arrival": arrival, "at": at,
		"start": World.tick, "leaving": false, "fought": {}, "bites": {}, "broke": {}}
	var count := 0
	for each: String in WANDER_KINDS[kind]:
		for i in int(WANDER_KINDS[kind][each]):
			var cell := _free_near(arrival, record["beasts"].map(func(b: Animal) -> Vector2i: return b.tile))
			if cell == NO_CELL:
				continue
			count += 1
			var spec := Level._spec_for("monster_" + each, Level.MONSTER_TYPES)
			if spec.is_empty():
				continue
			spec["name"] = "Wanderer_%s_%d" % [id.validate_node_name(), count]
			spec["tile"] = cell
			spec["home"] = at
			spec["idle"] = {"mode": "march", "route": route.duplicate(), "loop": false}
			(spec["props"] as Dictionary)["wanderer"] = id
			Level.arm(spec)
			var made: Variant = World.spawn_spec.call(spec)
			if made is Animal:
				record["beasts"].append(made)
	if record["beasts"].is_empty():
		return ""
	_in_play[id] = record
	print("[wanderer] %s: %d %s come in at %s for %s (%s)" % [id, record["beasts"].size(), kind, arrival, at, pond])
	return id


func _step_one(id: String, record: Dictionary) -> void:
	var left := beasts(id)
	if left.is_empty():
		_end(id, "beaten")
		return
	var lingered := World.tick - int(record["start"]) >= LINGER_TICKS
	if lingered and not record["leaving"]:
		record["leaving"] = true
		print("[wanderer] %s gives up and turns back" % id)
	for beast in left:
		if record["leaving"] and beast.drawn and beast.target == null:
			beast.drawn = false
		var broke: Dictionary = record["broke"].get(beast.get_instance_id(), {})
		if not broke.is_empty():
			beast._post = Monster.NO_TILE  # Let be wherever they stand (Monster._letting_be).
			if is_instance_valid(beast.target) and broke.has(beast.target.get_instance_id()) \
					and not record["fought"].has(beast.target.get_instance_id()):
				beast.target = null  # Never back to one it broke off this visit.
				beast._foe = null
				beast._calm()
		if beast.drawn:
			continue
		# Driven off or given up: back for the cell it came in at, gone once
		# out of everyone's sight or there. Its way back a march, as it came
		# (805 amended (12)): a walk home in one search (Monster._idle_tick's
		# return) failed from 30 cells on the wilds, and a hurt boar stood
		# 19 cells from her, in sight, till its zone slept. Planned from
		# where it stands once a run is over, again after any later run.
		var back: Dictionary = record.get("back", {})
		if beast.alert == Monster.Alert.FLEEING:
			back.erase(beast.get_instance_id())
		elif not back.has(beast.get_instance_id()):
			back[beast.get_instance_id()] = true
			record["back"] = back
			beast.home = record["arrival"]
			beast.route = _route(beast.tile, record["arrival"])
			beast.route_loop = false
			beast._route_index = 0
			beast._returning = false
			beast.idle = Monster.Idle.MARCH
		if _out_of_sight(beast.tile) or World.distance(beast.tile, record["arrival"]) <= 1:
			World.despawn(beast)
	if beasts(id).is_empty():
		_end(id, "gone" if record["leaving"] else "driven off")


## A blow on one of a wanderer's beasts (its striker fights back), or a
## beast's bite on a body that never has (805 amended (12)): bitten
## UNANSWERED_BITES times by one beast, that beast breaks off it: no longer
## drawn, it lets the body be for the visit and goes the way it came.
func _on_damaged(target: GridEntity, amount: int, source: GridEntity, _cause: StringName) -> void:
	if amount <= 0 or source == null or not is_instance_valid(source) or not is_instance_valid(target):
		return
	if target is Animal and _in_play.has((target as Animal).wanderer):
		_in_play[(target as Animal).wanderer]["fought"][source.get_instance_id()] = true
		return
	if not source is Animal or not _in_play.has((source as Animal).wanderer) or not (source as Animal).drawn:
		return
	var beast := source as Animal
	var record: Dictionary = _in_play[beast.wanderer]
	if record["fought"].has(target.get_instance_id()):
		return
	var key := "%d/%d" % [beast.get_instance_id(), target.get_instance_id()]
	var bites := int(record["bites"].get(key, 0)) + 1
	record["bites"][key] = bites
	if bites < UNANSWERED_BITES:
		return
	beast.drawn = false
	if not record["broke"].has(beast.get_instance_id()):
		record["broke"][beast.get_instance_id()] = {}
	record["broke"][beast.get_instance_id()][target.get_instance_id()] = true
	beast._given_up[target.get_instance_id()] = World.tick + LINGER_TICKS * 2
	beast._post = Monster.NO_TILE
	beast.target = null
	beast._foe = null
	beast._calm()
	print("[wanderer] %s breaks off %s: bitten %d times, never struck back" % [beast.name, World.kind_of(target), bites])


## Whether everyone at [param fisher]'s bank is armed: they and every
## companion of theirs within BANK_TILES, each holding or carrying a weapon.
func _bank_armed(fisher: Player) -> bool:
	if not _armed(fisher):
		return false
	for each in World.get_entities():
		if each is Companion and (each as Companion).keeper == fisher and each.spawned and each.hp > 0 \
				and World.distance(each.tile, fisher.tile) <= BANK_TILES and not _armed(each):
			return false
	return true


## Whether [param body] holds or carries a weapon (an item tagged "weapon").
static func _armed(body: GridEntity) -> bool:
	for id: String in body.slots:
		if not id.is_empty() and Items.has_tag(id, "weapon"):
			return true
	return false


func _end(id: String, why: String) -> void:
	var record: Dictionary = _in_play[id]
	var was := World.zone
	var zone := _zone(record["area"])
	if zone != null:
		World.enter(zone)
		for each in beasts(id):
			World.despawn(each)
	World.enter(was)
	_in_play.erase(id)
	print("[wanderer] %s ends: %s" % [id, why])


## Zone [param area], or null (as Raids finds a wave's).
static func _zone(area: String) -> Zone:
	return World.zones.get(area, World.zone if World.zone != null and World.zone.name == area else null)


## Whether [param cell] is past every player's sight (World in its zone).
func _out_of_sight(cell: Vector2i) -> bool:
	for each in World.sought():
		if each is Player and World.distance(each.tile, cell) <= World.VIEW_TILES:
			return false
	return true


## The wanderer's goal for a cast at [param cast] (805 amended (12); items'
## blind tour of v0.1.210: none ever came, "no cell out of sight with a way
## to" at every water, since economy's cast cell is the water's and
## find_path ends on no unwalkable cell): the cast cell if it is walkable,
## else the walkable cell nearest it within DRY_TILES that the one fishing,
## at [param fisher], can walk to (her own cell counts), so a river's far
## bank is passed over for hers. Any water alike: pond, pool or river.
## NO_CELL if none.
func _dry_by(cast: Vector2i, fisher := NO_CELL) -> Vector2i:
	if World.is_walkable(cast):
		return cast
	var dry: Array[Vector2i] = []
	for dy in range(-DRY_TILES, DRY_TILES + 1):
		for dx in range(-DRY_TILES, DRY_TILES + 1):
			var cell := cast + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and World.is_walkable(cell):
				dry.append(cell)
	dry.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - cast).length_squared()
		var db := (b - cast).length_squared()
		return da < db or da == db and (a.y < b.y or a.y == b.y and a.x < b.x))
	for cell in dry.slice(0, DRY_TRIES):
		if fisher == NO_CELL or cell == fisher or not World.find_path(fisher, cell, true, null, ROUTE_SEARCH_TILES).is_empty():
			return cell
	return NO_CELL


## A walkable free cell just past every player's sight with a way to
## [param at]: rings out from VIEW_TILES + 2, round from a direction drawn
## by the pond; NO_CELL if none.
func _arrival_cell(at: Vector2i) -> Vector2i:
	var draw := RandomNumberGenerator.new()
	draw.seed = hash("%s/%d" % [at, _made])
	var turn := draw.randf() * TAU
	for far in range(World.VIEW_TILES + 2, World.VIEW_TILES + 2 + OUT_TILES):
		var steps := far * 8  # About a cell apart round the ring.
		for i in steps:
			var angle := turn + TAU * i / steps
			var cell := at + Vector2i(roundi(cos(angle) * far), roundi(sin(angle) * far))
			if not World.is_walkable(cell) or not World.is_free(cell) or World.is_burning(cell) or not _out_of_sight(cell):
				continue
			if World.find_path(cell, at, true, null, ROUTE_SEARCH_TILES, true).is_empty():
				continue
			return cell
	return NO_CELL


## A free walkable cell at or beside [param near], not in [param taken].
func _free_near(near: Vector2i, taken: Array) -> Vector2i:
	for ring in 3:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var cell := near + Vector2i(dx, dy)
				if cell not in taken and World.is_walkable(cell) and World.is_free(cell):
					return cell
	return NO_CELL


## The march's waypoints from [param from] to [param to].
func _route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var path := World.find_path(from, to, true, null, ROUTE_SEARCH_TILES, true)
	for i in range(WAYPOINT_EVERY - 1, path.size() - 1, WAYPOINT_EVERY):
		out.append(path[i])
	out.append(to)
	return out
