class_name WorldRaids
extends RefCounted
## Raid groups on the world map (decision 328): a hostile camp sends a group
## at a town now and then, the likelier the more the town is threatened; it
## travels the world routes on its faction's layer (held ground is
## physical); where it walks into an area whose zone is awake it becomes
## real raiders (World.raids, enemy-ai's), and comes back here when that zone
## sleeps or it leaves the area; at a town nobody watches it raids by the
## numbers (Towns.raid_arrives) and carries what it took and whom home,
## where its captives are held at the camp (Towns.carried_home). The camps
## also make each town's threat (Towns.threat). A hungry camp (Herds'
## camp_fed) sends sooner, and its group is for food (decision 410; economy's
## raid takes read its want, decision 409). Server only, on the world
## tick, saved in the snapshot. Off until switched on (--raids, or the
## console's raids on): nothing is sent and nothing moves while it is off.

## levels/economy.json raids.groups, these unless it says otherwise.
const DEFAULTS := {
	# A camp's worth that pulls with all its weight; less pulls less.
	"size_full": 10.0,
	# Route steps at which a camp's pull on a town is halved.
	"threat_tiles": 200.0,
	# A camp with no group out sends one at its town with this chance a world
	# tick, times the town's threat.
	"send_chance": 0.05,
	# A group's strength: its camp's worth times this.
	"strength_per_size": 1.0,
	# Route steps a group covers a world tick.
	"steps_per_world_tick": 12.0,
	# A camp that ate less than this share of its food the last day (fed)
	# is hungry: it sends sooner and its group is for food.
	"hungry_below": 0.5,
	# A starving camp's send chance is this many times a fed one's; less
	# hungry, less (a straight line from 1 at hungry_below).
	"hungry_send": 3.0,
}
## What a hungry camp's group is for (its "want"; "" is the usual raid).
const WANT_FOOD := "food"
const RULES := "res://levels/economy.json"

## Going to the town, coming home, or in play (World.raids has it).
const OUT := "out"
const HOME := "home"
const PRESENT := "present"

var on := false
var holdings: Holdings
var towns: Towns
var world_map: WorldMap
## Made the first time it is wanted (raids on): its distance fields are
## built on pool tasks, which a server that quits must not leave running.
var routes: WorldRoutes:
	get:
		if _routes == null:
			_routes = holdings.make_routes(world_map)
		return _routes
var _routes: WorldRoutes
var rules := {}
## Id -> {id, faction, from (camp place id), town, strength, carries:
## {items, captives}, want (WANT_FOOD or ""), state, raided (the town was
## hit), area, cell, walked
## (route steps covered since the route was made), skip_area (the area it
## was handed back from, not entered again until it has left it)}.
var groups: Dictionary[String, Dictionary] = {}
## (area) -> bool: whether that area's zone is awake (Main's).
var live := func(_area: String) -> bool: return false
## World.raids, or a test's stand-in: enter(group, area, arrival, goal) -> int,
## and its raid_left, raid_done and raid_beaten.
var raids: Object
## (camp place id) -> 0..1: how well that camp ate the last day
## (World.herds.camp_fed); a camp nobody says is fed.
var fed := func(_camp_id: String) -> float: return 1.0
## () -> int: the World's steps, for ids.
var clock := func() -> int: return 0
var rng := RandomNumberGenerator.new()
## Group id -> its route (WorldRoutes legs), made again when wanted.
var _legs: Dictionary[String, Array] = {}
## "camp id|town" -> the route steps last measured between them (threat_of,
## while a faction's fields are not in; not saved).
var _steps: Dictionary[String, float] = {}
## (side) -> bool, in place of asking the routes whether that side's fields
## are in (tests).
var fields_in := Callable()


func _init(map: WorldMap, with_holdings: Holdings, with_towns: Towns, saved := {}, with_rules := {}) -> void:
	world_map = map
	holdings = with_holdings
	towns = with_towns
	rules = DEFAULTS.duplicate()
	var read: Variant = with_rules if not with_rules.is_empty() else _read_rules()
	if read is Dictionary:
		rules.merge(read, true)
	from_dict(saved)


static func _read_rules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES)) if FileAccess.file_exists(RULES) else null
	if parsed is Dictionary:
		var groups_rules: Variant = (parsed as Dictionary).get("raids", {}).get("groups", {})
		return groups_rules if groups_rules is Dictionary else {}
	return {}


## Waits for any routes still being made: before the server quits.
func finish() -> void:
	if _routes != null:
		_routes.wait()
	for each in _retired:
		each.wait()
	_retired.clear()


## The world as [param map] has it now (a level regenerated: decision 465):
## the routes made on the old map dropped, made again when next wanted, and
## every group's route with them, each going on from where it is. The old
## routes are retired, not waited for (465 amended: their fields take tens of
## seconds, and waiting froze the box): kept till their tasks stop.
func use_map(map: WorldMap) -> void:
	if _routes != null:
		_routes.retire()
		_retired.append(_routes)
	world_map = map
	_routes = null
	_legs.clear()


## Routes let go of whose tasks may still run (use_map, 465 amended); each
## dropped on a world tick once they have stopped.
var _retired: Array[WorldRoutes] = []


func _drop_retired() -> void:
	_retired = _retired.filter(func(each: WorldRoutes) -> bool: return each.busy())


## World.raids' signals, so groups come back from play.
func hook(with_raids: Object) -> void:
	raids = with_raids
	if raids == null:
		return
	for pair: Array in [["raid_left", _on_left], ["raid_done", _on_done], ["raid_beaten", _on_beaten]]:
		if raids.has_signal(pair[0]) and not raids.is_connected(pair[0], pair[1]):
			raids.connect(pair[0], pair[1])


## Switched on or off; on, it makes the towns' threat too.
func set_on(value: bool) -> void:
	on = value
	if towns != null:
		towns.threat = threat_of if on else Callable()


## The camps that can raid: places of kind "camp" a faction holds, {id,
## area, cell, size (its worth), faction}.
func camps() -> Array[Dictionary]:
	return holdings.camps()


## The towns a camp of [param faction] would raid: Towns' towns whose place
## a faction hostile to it holds.
func targets(faction: String) -> Array[String]:
	var out: Array[String] = []
	if towns == null:
		return out
	for town: String in towns.to_dict():
		var holder := holdings.holder(town)
		if holder != "" and holdings.factions.hostile(faction, holder):
			out.append(town)
	return out


## How threatened [param town] is, 0..1, by the hostile camps round it: one
## less the chance none comes, each camp pulling by its size, less the
## further its route.
func threat_of(town: String) -> float:
	var calm := 1.0
	for camp in camps():
		if town not in targets(camp["faction"]):
			continue
		var steps := _distance(camp, town)
		if steps < 0.0:
			continue
		var pull := clampf(camp["size"] / float(rules["size_full"]), 0.0, 1.0) / (1.0 + steps / float(rules["threat_tiles"]))
		calm *= 1.0 - pull
	return clampf(1.0 - calm, 0.0, 1.0)


## Route steps from [param camp] to [param town]'s place for the camp's
## faction; -1 for no route. While that side's fields are not in, the steps
## last measured (-1 if none yet: no threat from it, as Holdings.ranked
## counts such routes as none).
func _distance(camp: Dictionary, town: String) -> float:
	var side: String = holdings.factions.side(camp["faction"])
	var key := "%s|%s" % [camp["id"], town]
	if not routes_in(side):
		return _steps.get(key, -1.0)
	var place := holdings.place(town)
	var legs := routes.route(camp["area"], camp["cell"], place["area"], place["cell"], side)
	var steps := -1.0
	if not legs.is_empty():
		steps = 0.0
		for leg: Dictionary in legs:
			steps += float(leg["steps"])
	_steps[key] = steps
	return steps


## Whether [param side]'s distance fields are in (465 amended (2)): until
## they are, a route asked of them walks the world on the main thread, so
## no camp sends and no group moves on that side; routes that make no fields
## are always in.
func routes_in(side: String) -> bool:
	if fields_in.is_valid():
		return bool(fields_in.call(side))
	return not routes.makes_fields() or routes.is_ready(side)


## Everything a world tick does: sending, then each group's move. Nothing
## while off.
func world_tick() -> void:
	_drop_retired()
	if not on:
		return
	_send_some()
	for id: String in groups.keys():
		if groups.has(id):
			_move(id)


func _send_some() -> void:
	var busy_camps := {}
	var busy_towns := {}
	for group: Dictionary in groups.values():
		busy_camps[group["from"]] = true
		busy_towns[group["town"]] = true
	for camp in camps():
		if busy_camps.has(camp["id"]) or not routes_in(holdings.factions.side(camp["faction"])):
			continue
		var best := ""
		var best_threat := 0.0
		for town in targets(camp["faction"]):
			if busy_towns.has(town):
				continue
			var threat := threat_of(town)
			if threat > best_threat:
				best = town
				best_threat = threat
		if best != "" and rng.randf() < send_chance(camp["id"], best_threat):
			send(camp["id"], best)
			busy_towns[best] = true


## The chance a world tick that camp [param camp_id], with no group out,
## sends one at a town of [param threat]: send_chance times the threat,
## times more the hungrier the camp (hungry_send when it ate nothing).
func send_chance(camp_id: String, threat: float) -> float:
	return minf(1.0, threat * float(rules["send_chance"]) * hunger_factor(float(fed.call(camp_id))))


## How many times a camp that ate [param ate] (0..1) sends sooner: 1 at or
## above hungry_below, up to hungry_send at nothing.
func hunger_factor(ate: float) -> float:
	var below := float(rules["hungry_below"])
	if below <= 0.0 or ate >= below:
		return 1.0
	return 1.0 + (float(rules["hungry_send"]) - 1.0) * (1.0 - clampf(ate, 0.0, 1.0) / below)


## Whether camp [param camp_id] is hungry: ate less than hungry_below.
func hungry(camp_id: String) -> bool:
	return float(fed.call(camp_id)) < float(rules["hungry_below"])


## A group sent from camp [param camp_id] at [param town] now: its id, or ""
## if there is no such camp or town, or no route.
func send(camp_id: String, town: String) -> String:
	var camp: Dictionary = {}
	for each in camps():
		if each["id"] == camp_id:
			camp = each
	if camp.is_empty() or holdings.place(town).is_empty():
		return ""
	var id := "raid:%s:%d" % [camp_id, int(clock.call())]
	var want := WANT_FOOD if hungry(camp_id) else ""
	groups[id] = {"id": id, "faction": camp["faction"], "from": camp_id, "town": town,
		"strength": camp["size"] * float(rules["strength_per_size"]), "carries": {"items": [], "captives": []},
		"want": want, "state": OUT, "raided": false, "area": camp["area"], "cell": camp["cell"], "walked": 0.0, "skip_area": ""}
	if _route(id).is_empty():
		groups.erase(id)
		return ""
	print("[raids] %s sets out from %s for %s, strength %.1f%s" % [id, camp_id, town, groups[id]["strength"],
		" hungry (fed %.2f), for food" % float(fed.call(camp_id)) if want == WANT_FOOD else ""])
	return id


## Where [param id] is going: the town's place, or home to its camp.
func _goal(id: String) -> Dictionary:
	var group := groups[id]
	return holdings.place(group["from"] if group["state"] == HOME else group["town"])


## [param id]'s route from where it is to its goal, made again.
func _route(id: String) -> Array:
	var group := groups[id]
	var goal := _goal(id)
	var legs: Array = routes.route(group["area"], group["cell"], goal["area"], goal["cell"], holdings.factions.side(group["faction"])) if not goal.is_empty() else []
	_legs[id] = legs
	group["walked"] = 0.0
	return legs


func _move(id: String) -> void:
	var group := groups[id]
	if group["state"] == PRESENT:
		return  # Raiders in play: World.raids has it.
	if not routes_in(holdings.factions.side(group["faction"])):
		return  # Holds where it is, its plan kept, till its side's fields are in.
	var legs: Array = _legs.get(id, [])
	if legs.is_empty():
		legs = _route(id)
		if legs.is_empty():
			print("[raids] %s has no way on from %s %s: it breaks up" % [id, group["area"], group["cell"]])
			_end(id)
			return
	group["walked"] = float(group["walked"]) + float(rules["steps_per_world_tick"])
	var typed: Array[Dictionary] = []
	typed.assign(legs)
	var at := routes.along(typed, group["walked"], holdings.factions.side(group["faction"]))
	group["area"] = at["area"]
	group["cell"] = at["cell"]
	if group["skip_area"] != "" and at["area"] != group["skip_area"]:
		group["skip_area"] = ""
	if raids != null and at["area"] != group["skip_area"] and bool(live.call(at["area"])):
		_enter(id, at)
		return
	if at["done"]:
		_arrive(id, legs[-1])


## Into play: real raiders in an awake zone, marching on the town if it is
## there, else for the cell where the route leaves the area.
func _enter(id: String, at: Dictionary) -> void:
	var group := groups[id]
	var goal := Raids.NO_CELL
	var legs: Array = _legs.get(id, [])
	var leg: Dictionary = legs[int(at["leg"])] if int(at["leg"]) < legs.size() else {}
	var target := _goal(id)
	if group["state"] == HOME or target.get("area") != at["area"]:
		goal = leg.get("to", Raids.NO_CELL)
	var handed := {"id": id, "faction": group["faction"], "strength": group["strength"], "town": group["town"],
		"from": group["from"], "carries": group["carries"], "want": group.get("want", "")}
	var spawned: int = raids.enter(handed, at["area"], at["cell"], goal)
	group["state_before"] = group["state"]
	group["state"] = PRESENT
	print("[raids] %s walks into %s at %s: %d raiders in play" % [id, at["area"], at["cell"], spawned])


func _arrive(id: String, last: Dictionary) -> void:
	var group := groups[id]
	if last.has("meets") and last["meets"] != (group["from"] if group["state"] == HOME else group["town"]):
		# Ground another holds is in the way and there is no way round.
		print("[raids] %s is stopped by %s's ground: it turns back" % [id, last["meets"]])
		if group["state"] == HOME:
			_stow(id)  # It makes its way home in the end, what it took with it.
			_end(id)
		else:
			group["state"] = HOME
			_route(id)
		return
	if group["state"] == HOME and not holdings.factions.same_side(group["faction"], holdings.holder(group["from"])):
		# Home to a camp its side no longer holds (decision 429): the group
		# breaks up, its captives go free (Towns.free_held, decision 428) and
		# what it took is left at the camp for whoever finds it.
		var freed: Array[String] = towns.free_held(id) if towns != null else []
		print("[raids] %s comes home to %s, fallen: it breaks up, freeing %s" % [id, group["from"], freed])
		_stow(id)
		_end(id)
		return
	if group["state"] == HOME:
		# Its captives held at the camp; a companion taken in play gets her
		# entry here (Towns.carried_home, decision 331).
		towns.carried_home(group["town"], id, group["faction"], group["carries"].get("captives", []), group["from"])
		print("[raids] %s is home at %s with %s" % [id, group["from"], group["carries"]])
		_stow(id)
		_end(id)
		return
	# At a town nobody watches: by the numbers.
	var report := towns.raid_arrives(group["town"], {"id": id, "faction": group["faction"], "strength": group["strength"], "from": group["from"],
		"want": group.get("want", "")})
	group["raided"] = true
	group["carries"] = _carried(report, group["carries"])
	print("[raids] %s raids %s unseen: %s" % [id, group["town"], "fought off" if report.get("repelled", false) else "takes %s" % [report.get("took", {})]])
	group["state"] = HOME
	_route(id)


## What a group carries after a raid's [param report], on top of [param had].
static func _carried(report: Dictionary, had: Dictionary) -> Dictionary:
	var items: Array = had.get("items", []).duplicate()
	items.append_array(report.get("took", {}).get("items", []))
	var captives: Array = had.get("captives", []).duplicate()
	for captive: Dictionary in report.get("captives", []):
		captives.append(captive.get("id", ""))
	var out := {"items": items, "captives": captives}
	for key: String in report.get("took", {}):
		if key != "items":
			out[key] = report["took"][key]
	return out


## What group [param id] carried home (decision 348): each thing it took
## (ItemBook uids, "raid:<id>" till now) is placed at its camp,
## "camp:<place>", with a "carried home" note, so it outlives the group;
## the camp's pile is economy's to build on.
func _stow(id: String) -> void:
	var group := groups[id]
	var book := towns.production.book()
	for uid: Variant in group["carries"].get("items", []):
		if book.has(int(uid)):
			book.place(int(uid), "camp:%s" % group["from"])
			book.note(int(uid), "carried home", "by %s (%s) to %s" % [group["faction"], id, group["from"]])


func _end(id: String) -> void:
	groups.erase(id)
	_legs.erase(id)


# --- Back from play (World.raids' signals) ---------------------------------------

func _on_left(id: String, strength: float, area: String, cell: Vector2i, carries: Dictionary) -> void:
	if not groups.has(id):
		return
	var group := groups[id]
	group["strength"] = strength
	group["carries"] = carries
	group["area"] = area
	group["cell"] = cell
	group["state"] = HOME if group["raided"] else str(group.get("state_before", OUT))
	group["skip_area"] = area
	_route(id)
	print("[raids] %s is back on the world map at %s %s, strength %.1f" % [id, area, cell, strength])


func _on_done(id: String, report: Dictionary) -> void:
	if groups.has(id):
		groups[id]["raided"] = true
		print("[raids] %s raided %s in play: %s" % [id, report.get("town", "?"), "fought off" if report.get("repelled", false) else "took %s" % [report.get("took", {})]])


func _on_beaten(id: String, area: String, cell: Vector2i) -> void:
	if groups.has(id):
		print("[raids] %s is beaten at %s %s" % [id, area, cell])
		_end(id)


# --- Saved ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for id: String in groups:
		var group: Dictionary = groups[id].duplicate(true)
		group["cell"] = [group["cell"].x, group["cell"].y]
		out[id] = group
	return {"on": on, "groups": out}


## A group in play when it was saved (raiders are not) goes on from where it
## was last seen.
func from_dict(saved: Dictionary) -> void:
	groups.clear()
	_legs.clear()
	var saved_groups: Variant = saved.get("groups", {})
	if saved_groups is Dictionary:
		for id: String in saved_groups:
			var group: Dictionary = (saved_groups[id] as Dictionary).duplicate(true)
			var cell: Variant = group.get("cell", [0, 0])
			group["cell"] = Vector2i(int(cell[0]), int(cell[1])) if cell is Array and cell.size() == 2 else Vector2i.ZERO
			if group.get("state") == PRESENT:
				group["state"] = HOME if group.get("raided", false) else str(group.get("state_before", OUT))
			group["walked"] = 0.0
			group["skip_area"] = ""
			groups[id] = group
	set_on(bool(saved.get("on", false)))
