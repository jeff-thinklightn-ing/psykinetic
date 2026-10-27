class_name Guide
extends RefCounted
## A companion leading her player somewhere she knows (decision 551; Jeff's
## companion_rewards.md: "a companion who has been to a place can guide
## you there"). What she knows is her record's "roads": the areas she has
## stood in with her player and the places she came within SIGHT of
## (WorldNews' fog, her own), and the dangers she lived through there,
## each an area's, with a weight, beside what she heard of the roads
## (RoadKnowledge, npc's). Phase 2: asked, she refuses a road whose dangers
## reach her nerve (temperament, bond, company), naming the worst, and
## offers to go as far as the last place short of them.
## The walk is on the world's real routes (WorldRoutes): she walks each
## leg's cells and her player's body follows at her heel (Heel's cell, set
## as their move order each tick), at their own pace, in real time; at a
## way out of the area, Main takes them both through (travel). Their own
## step, move, strike or use, a danger she sees, a blow on either, her
## player low, either downed, or no way on, and the walk stops and hands
## control back; within keep_minutes "lead on" takes it up again. Server
## only. One Guide a walk, held by Main by her player's id (her body is
## made afresh in each zone).

## How near a place's cell she comes to know it (WorldNews.SIGHT's 7, not
## read from it: WorldNews loads PlayerRecord, which loads Companion, which
## loads this).
const SIGHT := 7
const NONE := Vector2i(-1, -1)
## A map edge's way out, by side.
const SIDES := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}
## What ends a walk, in words for her voice and the party log, by reason.
const STOPS := {
	"arrived": "you have brought %s there",
	"moved": "%s went their own way",
	"danger": "you saw danger ahead and stopped",
	"struck": "a blow fell and you stopped",
	"hurt": "%s is badly hurt",
	"downed": "one of you went down",
	"lost": "%s is not with you",
	"no_way": "there is no way on from here",
	"unsafe": "it isn't safe ahead",
}

## Where she leads: {key ("area/key" for a place, the area's name for an
## area), kind ("place" | "area"), name, area, cell}.
var goal: Dictionary = {}
var pet: Companion
var leader: Player
## When the walk stopped (World.steps), and why ("" while it goes on).
var stopped_at := -1
var stopped := ""
## The leg being walked and its cells still ahead of her.
var _leg: Dictionary = {}
var _cells: Array[Vector2i] = []
## The way out the walk is at (WorldMap.ways' entry), the leg's end cell
## there, and whether Main is taking them through it (after the tick: she
## waits).
var crossing: Dictionary = {}
var crossing_at := NONE
var crossing_now := false
## The cell last given the leader as their move order, and the hp seen.
var _ordered := NONE
## A free body's route to her heel goes to its client this way (695: under
## free walk only the client steers its body, as a click's route): called
## with the path (cells, from the one after its own to the heel), empty when
## the walk ends, and this walk. Main sets it; unset, none is sent.
var send_route := Callable()
var _hp := Vector2i(-1, -1)
## Whether the walk came into this area by a way and has not stopped since:
## leaving it by a way then is a safe passage (RoadKnowledge.passed).
var clean := false


## The rules (companion_traits.json "guide").
static func rules() -> Dictionary:
	var table: Variant = CompanionCard.tables().get("guide", {})
	return table if table is Dictionary else {}


static func setting(key: String, otherwise: float) -> float:
	return float(rules().get(key, otherwise))


# --- What she knows -------------------------------------------------------------

## Her roads on [param card] (record.companion): {areas, places, dangers},
## made when missing.
static func roads_of(card: Dictionary) -> Dictionary:
	var roads: Variant = card.get("roads")
	if not roads is Dictionary:
		roads = {}
		card["roads"] = roads
	for key: String in ["areas", "places", "dangers"]:
		if not roads.get(key) is Array:
			roads[key] = []
	return roads


## She stands at [param cell] in [param area] with her player: the area and
## every place of [param places] ({id, cell}) within SIGHT become known.
## True if anything did.
static func observe(card: Dictionary, area: String, cell: Vector2i, places: Array) -> bool:
	var roads := roads_of(card)
	var changed := false
	if not area.is_empty() and not roads["areas"].has(area):
		roads["areas"].append(area)
		changed = true
	for place: Dictionary in places:
		var d: Vector2i = place["cell"] - cell
		if not roads["places"].has(place["id"]) and d.x * d.x + d.y * d.y <= SIGHT * SIGHT:
			roads["places"].append(place["id"])
			changed = true
	return changed


## What she lived through in [param area] ("downed", "taken", "fell",
## "hurt"), on [param day], as a danger of it: its weight from the rules;
## one a day an area and kind (the same day's again is no new one). The
## entry, or {} for none.
static func note_danger(card: Dictionary, area: String, why: String, day: int, place := "") -> Dictionary:
	if area.is_empty():
		return {}
	var dangers: Array = roads_of(card)["dangers"]
	for each: Dictionary in dangers:
		if each.get("area") == area and each.get("why") == why and int(each.get("day", -1)) == day:
			return {}
	var weights: Variant = rules().get("weights", {})
	var entry := {"area": area, "place": place, "why": why, "from": "lived", "day": day,
		"weight": int((weights as Dictionary).get(why, 1)) if weights is Dictionary else 1}
	dangers.append(entry)
	return entry


## How much danger on a road she will walk into (phase 2): her boldness by
## temperament (rules boldness, else boldness_default), her bond with
## [param player_id] (Standing's COMPANION word, rules bond), and
## [param company] other players beside them (rules company each).
static func nerve(card: Dictionary, player_id: String, company: int) -> float:
	var bold: Variant = rules().get("boldness", {})
	var temper := str((card.get("traits", {}) as Dictionary).get("temperament", "")) if card.get("traits") is Dictionary else ""
	var value := float((bold as Dictionary).get(temper, setting("boldness_default", 3.0))) if bold is Dictionary else setting("boldness_default", 3.0)
	var bond: Variant = rules().get("bond", {})
	if bond is Dictionary:
		value += float((bond as Dictionary).get(Standing.words(card, player_id, Standing.COMPANION), 0))
	return value + company * setting("company", 1.0)


## The areas a walk from [param area] at [param cell] to [param to]
## (destinations') crosses, in order, each {area, to: the cell it leaves
## by, or the goal's}: [param routes]' route when they are in, else here
## and there.
static func road_of(routes: WorldRoutes, area: String, cell: Vector2i, to: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if routes != null and routes.is_ready(WorldRoutes.OPEN):
		for leg in routes.route(area, cell, to["area"], to["cell"]):
			if out.is_empty() or out[-1]["area"] != leg["area"]:
				out.append({"area": str(leg["area"]), "to": leg["to"]})
			else:
				out[-1]["to"] = leg["to"]
	if out.is_empty() or out[-1]["area"] != to["area"]:
		if out.is_empty() and area != to["area"]:
			out.append({"area": area, "to": cell})
		out.append({"area": str(to["area"]), "to": to["cell"]})
	return out


## Whether she will walk [param road] (road_of's) with [param player_id]
## on [param day]: {} if so; else {reason (RoadKnowledge's clause), worst,
## as_far (the destination of [param known] she would still lead to, the
## nearest to the way into the first area too dangerous, {} for none)}.
## Refused when the dangers on it (RoadKnowledge.weigh) reach her nerve.
static func refusal(card: Dictionary, player_id: String, road: Array[Dictionary], company: int, day: int,
		holdings: Holdings, known: Array[Dictionary], world_map: WorldMap = null) -> Dictionary:
	var areas: Array = road.map(func(each: Dictionary) -> String: return each["area"])
	var can := nerve(card, player_id, company)
	var weighed := RoadKnowledge.weigh(card, areas, day, holdings, rules())
	if float(weighed["weight"]) <= 0.0 or float(weighed["weight"]) < can:
		return {}
	# As far as she would go: the last area before the dangers ahead of it
	# reach her nerve, and the place there nearest its way on.
	var as_far := {}
	for i in road.size():
		if float(RoadKnowledge.weigh(card, areas.slice(0, i + 1), day, holdings, rules())["weight"]) < can:
			continue
		if i == 0:
			break  # The danger is here: nowhere short of it.
		var last: Dictionary = road[i - 1]
		var best := 1 << 30
		for each in known:
			if each["area"] == last["area"] and World.distance(each["cell"], last["to"]) < best:
				best = World.distance(each["cell"], last["to"])
				as_far = each
		break
	return {"reason": RoadKnowledge.reason(weighed["worst"], day, world_map), "worst": weighed["worst"], "as_far": as_far}


## The places and areas she can lead to, from her roads: a named place she
## has seen (Holdings' [param holdings]) and an area of [param world_map]
## she has stood in, with a start to arrive at. Each {key, kind, name,
## area, cell}; places first, then areas, each by name.
static func destinations(card: Dictionary, holdings: Holdings, world_map: WorldMap) -> Array[Dictionary]:
	var roads := roads_of(card)
	var places: Array[Dictionary] = []
	var areas: Array[Dictionary] = []
	if holdings != null:
		for id: Variant in roads["places"]:
			var place := holdings.place(str(id))
			if not place.is_empty() and not str(place["name"]).is_empty():
				places.append({"key": place["id"], "kind": "place", "name": str(place["name"]), "area": place["area"], "cell": place["cell"]})
	if world_map != null:
		for name: Variant in roads["areas"]:
			var area: Dictionary = world_map.areas.get(str(name), {})
			var cell := _arrival_of(area)
			if cell != NONE:
				areas.append({"key": str(name), "kind": "area", "name": str(area.get("display_name", name)), "area": str(name), "cell": cell})
	var by_name := func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"]
	places.sort_custom(by_name)
	areas.sort_custom(by_name)
	return places + areas


## Where a walk to [param area] (WorldMap's) ends: its first start, else a
## spawn point; NONE if it has neither.
static func _arrival_of(area: Dictionary) -> Vector2i:
	var starts: Array = area.get("starts", [])
	if not starts.is_empty():
		return starts[0]
	var spawns: Dictionary = area.get("spawn_points", {})
	for key: String in spawns:
		return spawns[key]
	return NONE


## The destination of [param known] (destinations) that [param text] names,
## the longest name found as whole words ("the" before it or not); {} if
## none.
static func named_in(text: String, known: Array[Dictionary]) -> Dictionary:
	var said := " %s " % _plain(text)
	var best: Dictionary = {}
	for each in known:
		var name := _plain(str(each["name"]))
		if name.begins_with("the "):
			name = name.substr(4)
		if not name.is_empty() and " %s " % name in said and name.length() > _plain(str(best.get("name", ""))).length():
			best = each
	return best


## [param text] in lower case, its punctuation as spaces, single-spaced.
static func _plain(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if c.is_valid_identifier() or c.is_valid_int() or c == "'" else " "
	return " ".join(out.split(" ", false))


## The words that ask her to lead the way to somewhere named, or ("" for
## the place) to take a stopped walk up again.
const ASK := "(?i)\\b(take|lead|guide|show|bring|walk)\\s+(me|us)\\b.*\\b(to|towards?)\\b|\\b(lead|show)\\s+(me\\s+|us\\s+)?the\\s+way\\b|\\bwhich\\s+way\\s+to\\b|\\b(you\\s+lead|take\\s+the\\s+lead|lead\\s+(us|me|on\\s+to))\\b"
const RESUME := "(?i)^\\W*(lead on|go on|lead the way|carry on|keep going|onwards?)\\W*$"


## Whether [param text] asks her to lead somewhere.
static func asks(text: String) -> bool:
	return RegEx.create_from_string(ASK).search(text) != null


## Whether [param text] asks her to take the walk up again.
static func asks_resume(text: String) -> bool:
	return RegEx.create_from_string(RESUME).search(text) != null


# --- The walk ----------------------------------------------------------------------

func _init(to: Dictionary) -> void:
	goal = to


## The walk takes [param with_pet] and [param with_leader]'s bodies (made
## afresh in each zone).
func bind(with_pet: Companion, with_leader: Player) -> void:
	pet = with_pet
	leader = with_leader
	_leg = {}
	_cells.clear()
	_ordered = NONE
	_hp = Vector2i(-1, -1)
	clean = crossing_now and going()
	crossing_now = false


## Whether the walk goes on.
func going() -> bool:
	return stopped.is_empty()


## The walk stops for [param why]: the leader's order it gave dropped.
func stop(why: String) -> void:
	if not stopped.is_empty():
		return
	stopped = why
	stopped_at = World.steps
	clean = false
	_leg = {}
	_cells.clear()
	if is_instance_valid(leader) and leader.spawned and leader.has_move_order and leader.move_order == _ordered:
		leader.has_move_order = false
	if _ordered != NONE and why != "arrived" and is_instance_valid(leader) and World.free_body(leader) and send_route.is_valid():
		send_route.call([], self)  # Stopped: their client stops steering it (arrived, they finish the last one).
	_ordered = NONE


## Taken up again after a stop: going, a fresh route from where she is.
func resume() -> void:
	stopped = ""
	stopped_at = -1
	_leg = {}
	_cells.clear()


## Whether a stopped walk may still be taken up again (keep_minutes).
func keeps() -> bool:
	return stopped != "arrived" and stopped_at >= 0 \
		and World.steps - stopped_at <= roundi(setting("keep_minutes", 5.0) * 60.0 * World.TICK_RATE)


## One tick of the walk, from her own tick (Intent.GUIDE): "" while it goes
## on; else why it must stop ("arrived", "moved", "danger", "struck",
## "hurt", "downed", "lost", "no_way"), or "cross" with the way out
## ([member crossing]) for Main to take them through. [param routes]:
## the world's routes; [param threat] (entity) -> bool: whether something
## would fight them.
func step(routes: WorldRoutes, threat: Callable) -> String:
	if crossing_now:
		return ""
	if not is_instance_valid(leader) or not leader.spawned or leader.zone != pet.zone:
		return "lost"
	if World.is_downed(leader) or World.is_downed(pet):
		return "downed"
	if _hp.x >= 0 and (leader.hp < _hp.x or pet.hp < _hp.y):
		return "struck"
	_hp = Vector2i(leader.hp, pet.hp)
	if leader.max_hp > 0 and float(leader.hp) / leader.max_hp < setting("hurt_below", 0.5):
		return "hurt"
	if not leader.queued_steps.is_empty() or leader.action_order != GridEntity.Order.NONE \
			or leader.has_move_order and leader.move_order != _ordered and not World.free_body(leader):
		return "moved"  # (A free body's own move is its client's word, the "guide" command's "stop", 695.)
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(pet.tile, entity.tile) <= Companion.SIGHT_RANGE \
				and threat.call(entity) and (pet.senses == null or pet.senses.sees(entity, -1, false)):
			return "danger"
	if pet.zone == goal["area"] and World.distance(pet.tile, goal["cell"]) <= int(setting("arrive", 3.0)):
		return "arrived"
	if _leg.is_empty():
		if pet.zone == goal["area"] and (routes == null or not routes.is_ready(WorldRoutes.OPEN)):
			# Here, before the world's routes are in: a walk here alone.
			_leg = {"area": pet.zone, "from": pet.tile, "to": goal["cell"], "way": {}}
		elif routes == null or not routes.is_ready(WorldRoutes.OPEN):
			return ""  # The routes are not in yet: she waits.
		else:
			var legs := routes.route(pet.zone, pet.tile, goal["area"], goal["cell"])
			if legs.is_empty() or legs[0]["area"] != pet.zone or legs[-1].has("meets"):
				return "no_way"
			_leg = legs[0]
		_cells = _walk_of(routes, _leg)
		if _cells.is_empty() and pet.tile != _leg["to"]:
			return "no_way"
	var near := World.distance(pet.tile, leader.tile)
	_heel()
	if not (_leg["way"] as Dictionary).is_empty() and World.distance(pet.tile, _leg["to"]) <= 1:
		if near > int(setting("wait", 3.0)):
			return ""  # At the way out: they come up first.
		crossing = _leg["way"]
		crossing_at = _leg["to"]
		return "cross"
	if near > int(setting("wait", 3.0)) or World.tick < pet.next_move_tick:
		return ""
	_walk()
	return ""


## The cells of [param leg] ahead of her: maps' WorldRoutes.leg_cells
## where it is, else a walk there.
func _walk_of(routes: WorldRoutes, leg: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if routes.has_method("leg_cells"):
		cells.assign(routes.call("leg_cells", leg))
	else:
		cells.assign(World.find_path(pet.tile, leg["to"], true))
	var here := cells.find(pet.tile)
	return cells.slice(here + 1) if here != -1 else cells


## One step along the leg; round a body in her way by a short walk to a
## cell a few ahead.
func _walk() -> void:
	while not _cells.is_empty() and _cells[0] == pet.tile:
		_cells.pop_front()
	if _cells.is_empty():
		if pet.tile != _leg["to"]:
			Heel.step(pet, _leg["to"], true)
		return
	var next := _cells[0]
	if World.distance(pet.tile, next) > 1:
		# Pushed off her walk: back to it.
		Heel.step(pet, next, true)
		return
	if World.is_free(next) and World.try_move(pet, next - pet.tile):
		_cells.pop_front()
		return
	var past := _cells[mini(4, _cells.size() - 1)]
	var path := World.find_path(pet.tile, past, true, null, 200)
	if not path.is_empty() and World.try_move(pet, path[0] - pet.tile):
		var at := _cells.find(pet.tile)
		if at != -1:
			_cells = _cells.slice(at + 1)


## Her player's body follows her: their move order her heel's cell once
## they are two or more cells off. A free body takes no move order (688):
## its client is sent the route to her heel each time the heel moves (695),
## and steers it as a click's route.
func _heel() -> void:
	if World.distance(leader.tile, pet.tile) < Heel.STOP:
		return
	var heel := Heel.cell(leader, pet)
	if heel == NONE or heel == leader.tile:
		return
	if World.free_body(leader):
		if heel != _ordered and send_route.is_valid():
			var path: Array = []
			for cell: Vector2i in World.walk_path(leader.tile, heel, leader):
				path.append([cell.x, cell.y])
			send_route.call(path, self)
		_ordered = heel
		return
	leader.move_order = heel
	leader.has_move_order = true
	leader.move_via.clear()
	_ordered = heel


## Why the walk stopped, in words for her voice ("%s" her player's name).
static func stop_words(why: String, who: String) -> String:
	var words: String = STOPS.get(why, "you stopped")
	return words % who if "%s" in words else words
