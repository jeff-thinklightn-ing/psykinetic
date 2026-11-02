class_name Balance
extends RefCounted
## Keep the balance (decision 761, phase 1; Jeff: "farms have needs, like
## wolves are stealing sheep, and wolves population is attracted to deer"):
## in an area whose level's "herds" says "balance": true (a test level; no
## real level until Jeff asks), the deer, the wolves, a herder's fold and the
## meat left lying drive each other on the world tick, and a fold that loses
## sheep raises a quest the whole area shares. Server only. World keeps one
## (World.balance), made by Main beside the herds; saved in the snapshot
## ("balance": to_dict). Rules: levels/economy.json "balance".
##
## The loop:
## - Wolves the area holds: its deer / wolf_per_deer, plus the meat lying
##   there / meat_per_wolf (Herds.capacity asks wolf_capacity). Past it they
##   leave, leave of the excess a day; under it they breed as ever, times
##   carrion_breed while meat lies there (Herds._breed asks breed_factor).
## - Meat lying: every meat thing on the ground of such an area (a kill's
##   remains, a drop), from when it lands (cell_changed) until it is picked
##   up, eaten by a wolf (eat) or rots after rot_days. Each one that rots or
##   is eaten was left lying: the quest's ledger counts it, and who left it
##   (World's put-down label: the killer for remains).
## - Hunger: 1 - (deer + meat lying / meat_per_deer) / (wolves x deer_each),
##   0..1. The fold loses (wolves - calm_wolves) x sheep_base + wolves x
##   sheep_hungry x hunger sheep a day (many wolves take some; hungry ones
##   take more, so thinning the deer too far costs the flock), whole ones taken at the day's turn (the night), from its
##   stockpile count. Not while any of the area's wolves are out as bodies:
##   then they are the ones taking (enemy-ai's side), never counted twice.
## - Brought home: meat that lay on such an area's ground or came off it,
##   banked at a store (World._bank_thing: banked) counts home.
##
## The quest, one per fold: once the fold has lost ask.lost sheep within
## ask.days, it is asked (asked: npc's farmer says so), shared by everyone in
## the area, judged deadline_days on (judged):
## - "balanced": wolves no more than at the start, deer within deer_low ..
##   deer_high of what the ground keeps, at most lost_most sheep lost and
##   left_most meat left lying: thrive.lambs lambs to the fold, thrive.wool
##   wool and thrive.meat meat to the fold's town's store.
## - "badly": wolves bad_wolves x the start or more, or bad_left meat left
##   lying or more: the flock is lost and town_wolves.count wolves come to
##   the town at night (threat_changed: npc's "threat in town").
## - "off": anything else: the flock is lost.
## A lost flock comes back (Jeff): back.sheep sheep back.days later. A fold
## rests rest_days after a judgement before it asks again.
##
## The town's nights of wolves: threat(town) "wolves" while any are left;
## enemy-ai's bodies call town_wolf_killed, and one at the store takes
## night_take(town). Each day's turn the far tier's wolves (nobody watching:
## watched) take one thing each from takes, as a raid takes food, never
## gold or people; after nights they go back, and the threat is cleared.

signal asked(fold_id: String)
signal judged(fold_id: String, outcome: String)
signal threat_changed(town: String, kind: String, on: bool)
## A fold's sheep changed (wolves, a judgement, the flock come back).
signal fold_changed(fold_id: String)

var rules := {}
var herds: Herds = null
var stockpile: Stockpile = null
## (uid) -> its Items id; unset, World.items'.
var id_of := Callable()
## () -> the folds: [{id, area, cell, town, farmer}] (Main: the herders').
var folds := Callable()
## (area, cell, uid, why) -> whether it was taken off the ground and ended.
var remove := Callable()
## (town) -> whether someone is there to meet the wolves (Main: a player in
## its zone); unset, nobody.
var watched := Callable()
## () -> int: the World's steps.
var clock := Callable()

## Meat lying: uid -> {area, cell, since, by}.
var _lying: Dictionary = {}
## Meat taken up off such ground: uid -> {area, by}.
var _carried: Dictionary = {}
## Fold id -> its quest: {area, town, from, until, wolves, deer, lost, left,
## home, left_by: {who: n}, home_by: {who: n}}.
var _quests: Dictionary = {}
## Fold id -> the days it lost sheep on (the last ask.days).
var _lost: Dictionary = {}
## Fold id -> sheep owed to the wolves, in parts.
var _pressure: Dictionary = {}
## Fold id -> the day its flock comes back.
var _back: Dictionary = {}
## Fold id -> the day it may ask again.
var _rest: Dictionary = {}
## Town -> {kind, left, nights}.
var _threats: Dictionary = {}
var _at := -1
var _day := -1


func _init(saved := {}, with_herds: Herds = null, with_stockpile: Stockpile = null, with_rules := {}, with_clock := Callable()) -> void:
	rules = with_rules if not with_rules.is_empty() else Production.read_rules().get("balance", {})
	herds = with_herds
	stockpile = with_stockpile
	clock = with_clock
	from_dict(saved)


func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


func _prey() -> String:
	return str(rules.get("prey", "deer"))


func _predator() -> String:
	return str(rules.get("predator", "wolf"))


# --- Reading ----------------------------------------------------------------------

## Whether [param area] keeps the balance: its level's "herds" says so.
func governs(area: String) -> bool:
	return herds != null and bool(herds.areas.get(area, {}).get("herds", {}).get("balance", false))


## The meat lying in [param area], in units.
func lying(area: String) -> int:
	var sum := 0
	for uid: int in _lying:
		if str(_lying[uid]["area"]) == area:
			sum += 1
	return sum


## The meat lying in [param area] within [param reach] of [param cell]
## (enemy-ai: a wolf's smell), nearest first: [{uid, cell}].
func meat_near(area: String, cell: Vector2i, reach: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for uid: int in _lying:
		var row: Dictionary = _lying[uid]
		var at: Vector2i = row["cell"]
		if str(row["area"]) == area and maxi(absi(at.x - cell.x), absi(at.y - cell.y)) <= reach:
			out.append({"uid": uid, "cell": at})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Vector2(a["cell"] - cell).length()
		var db := Vector2(b["cell"] - cell).length()
		return da < db or da == db and int(a["uid"]) < int(b["uid"]))
	return out


## How many wolves [param area] holds: its deer, and the meat lying there.
func wolf_capacity(area: String) -> float:
	if herds == null:
		return 0.0
	return herds.total(area, _prey()) / maxf(float(rules.get("wolf_per_deer", 8.0)), 0.001) 		+ float(lying(area)) / maxf(float(rules.get("meat_per_wolf", 4.0)), 0.001)


## Whether Herds asks this of [param area]'s [param species].
func steers(area: String, species: String) -> bool:
	return species == _predator() and governs(area)


## [param area]'s wolves' breeding, times carrion_breed while meat lies there.
func breed_factor(area: String) -> float:
	return float(rules.get("carrion_breed", 2.0)) if lying(area) > 0 else 1.0


## How hungry [param area]'s wolves are, 0..1 (0 with none).
func hunger(area: String) -> float:
	if herds == null:
		return 0.0
	var wolves := herds.total(area, _predator())
	if wolves <= 0.0:
		return 0.0
	var food := herds.total(area, _prey()) + float(lying(area)) / maxf(float(rules.get("meat_per_deer", 4.0)), 0.001)
	return clampf(1.0 - food / (wolves * maxf(float(rules.get("deer_each", 3.0)), 0.001)), 0.0, 1.0)


## The folds of [param area] (every area: ""): [{id, area, cell, town,
## farmer, sheep}] (enemy-ai: where a wolf takes one).
func folds_in(area := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fold: Dictionary in (folds.call() if folds.is_valid() else []):
		if (area.is_empty() or str(fold["area"]) == area) and governs(str(fold["area"])):
			var row := fold.duplicate()
			row["sheep"] = stockpile.count(str(fold["id"]), "sheep") if stockpile != null else 0
			row["reach"] = int(rules.get("fold_reach", 4))
			out.append(row)
	return out


## Fold [param fold_id]'s quest ({} for none): a copy.
func quest(fold_id: String) -> Dictionary:
	return _quests.get(fold_id, {}).duplicate(true)


## The quests going on: fold id -> quest.
func quests() -> Dictionary:
	return _quests.duplicate(true)


## What threatens [param town] now ("wolves"), "" for nothing.
func threat(town: String) -> String:
	return str(_threats.get(town, {}).get("kind", ""))


## The wolves still to come at [param town]'s nights.
func wolves_at(town: String) -> int:
	return int(_threats.get(town, {}).get("left", 0))


# --- Meat on the ground ---------------------------------------------------------------

## [param cell] of [param area] holds [param uids] now (World.ground_changed):
## its meat newly there lies from now, put down by [param by] (uid -> who;
## the killer for remains); meat that lay there and is gone was taken up.
func cell_changed(area: String, cell: Vector2i, uids: PackedInt32Array, by := {}) -> void:
	if not governs(area):
		return
	var meat: Array = rules.get("meat", ["meat"])
	for uid in uids:
		if not _lying.has(uid) and _id(uid) in meat:
			_lying[uid] = {"area": area, "cell": cell, "since": now(), "by": str(by.get(uid, _carried.get(uid, {}).get("by", "")))}
			_carried.erase(uid)
	var gone: Array[int] = []
	for uid: int in _lying:
		var row: Dictionary = _lying[uid]
		if str(row["area"]) == area and row["cell"] == cell and uid not in uids:
			gone.append(uid)
	for uid in gone:
		_carried[uid] = {"area": area, "by": str(_lying[uid]["by"])}
		_lying.erase(uid)


## Meat [param uid] went into a store (World._bank_thing) by [param who]: if
## it lay on such ground, it was brought home.
func banked(uid: int, who := "") -> void:
	var row: Dictionary = _carried.get(uid, _lying.get(uid, {}))
	_carried.erase(uid)
	_lying.erase(uid)
	if row.is_empty():
		return
	for fold: String in _quests:
		var each: Dictionary = _quests[fold]
		if str(each["area"]) == str(row["area"]):
			each["home"] = int(each["home"]) + 1
			var name := who if not who.is_empty() else str(row["by"])
			if not name.is_empty():
				each["home_by"][name] = int(each["home_by"].get(name, 0)) + 1


## A wolf ate meat [param uid] where it lies (enemy-ai): taken off the
## ground, left lying. Whether it was meat lying.
func eat(uid: int) -> bool:
	if not _lying.has(uid):
		return false
	_gone(uid, "eaten by wolves")
	return true


## [param uid] goes off the ground ([param why]), left lying: the ledger.
func _gone(uid: int, why: String) -> void:
	var row: Dictionary = _lying[uid]
	_lying.erase(uid)
	if remove.is_valid():
		remove.call(str(row["area"]), row["cell"], uid, why)
	for fold: String in _quests:
		var each: Dictionary = _quests[fold]
		if str(each["area"]) == str(row["area"]):
			each["left"] = int(each["left"]) + 1
			var who := str(row["by"])
			if not who.is_empty():
				each["left_by"][who] = int(each["left_by"].get(who, 0)) + 1


func _id(uid: int) -> String:
	return str(id_of.call(uid)) if id_of.is_valid() else (World.items.id_of(uid) if World.items != null else "")


# --- The fold and the town ---------------------------------------------------------------

## A wolf body took a sheep of fold [param fold_id] (enemy-ai): whether
## there was one.
func take_sheep(fold_id: String) -> bool:
	if stockpile == null or not stockpile.take(fold_id, "sheep", 1, "taken by wolves"):
		return false
	_lose(fold_id, 1)
	return true


func _lose(fold_id: String, count: int) -> void:
	var days: Array = _lost.get(fold_id, [])
	for i in count:
		days.append(_day)
	_lost[fold_id] = days
	if _quests.has(fold_id):
		_quests[fold_id]["lost"] = int(_quests[fold_id]["lost"]) + count
	fold_changed.emit(fold_id)


## A wolf at [param town] in the night takes one thing of its store (the
## first of town_wolves.takes it has): what, "" for nothing.
func night_take(town: String) -> String:
	if threat(town).is_empty() or stockpile == null:
		return ""
	for what: Variant in rules.get("town_wolves", {}).get("takes", ["meat", "sheep", "food"]):
		if stockpile.take(town, str(what), 1, "taken by wolves in the night"):
			return str(what)
	return ""


## A wolf of [param town]'s nights was killed (enemy-ai): one fewer to come;
## the last cleared.
func town_wolf_killed(town: String) -> void:
	if not _threats.has(town):
		return
	_threats[town]["left"] = int(_threats[town]["left"]) - 1
	if int(_threats[town]["left"]) <= 0:
		_clear(town)


func _clear(town: String) -> void:
	var kind := threat(town)
	_threats.erase(town)
	print("[balance] a town's threat is cleared")
	threat_changed.emit(town, kind, false)


# --- The world tick -----------------------------------------------------------------------

## Moves the balance on by the time since the last call (World's world
## tick, after the herds'): the folds' losses in parts, and on a new day the
## rot, the sheep taken, the asks, the judgements and the town's nights.
func tick() -> void:
	var steps := now()
	var since := 0 if _at < 0 else steps - _at
	_at = steps
	var day_steps := maxi(DayNight.day_steps, 1)
	var days := minf(float(since) / day_steps, 1.0)
	if days > 0.0:
		for fold in folds_in():
			var area := str(fold["area"])
			if _bodies_out(area):
				continue  # The bodies take what they take (enemy-ai's side).
			var wolves := herds.total(area, _predator())
			var a_day := maxf(wolves - float(rules.get("calm_wolves", 3.0)), 0.0) * float(rules.get("sheep_base", 0.17)) 				+ wolves * float(rules.get("sheep_hungry", 0.6)) * hunger(area)
			_pressure[fold["id"]] = float(_pressure.get(fold["id"], 0.0)) + a_day * days
	var day := steps / day_steps
	if day != _day:
		var first := _day < 0
		_day = day
		if not first:
			_daily()


func _bodies_out(area: String) -> bool:
	for each in herds.groups_in(area, _predator()):
		if int(each["out"]) > 0:
			return true
	return false


func _daily() -> void:
	var day_steps := maxi(DayNight.day_steps, 1)
	# The rot.
	var old: Array[int] = []
	for uid: int in _lying:
		if now() - int(_lying[uid]["since"]) >= int(float(rules.get("rot_days", 1.0)) * day_steps):
			old.append(uid)
	for uid in old:
		_gone(uid, "rotted")
	var ask: Dictionary = rules.get("ask", {})
	for fold in folds_in():
		var id := str(fold["id"])
		# The sheep the night took.
		var owed := floori(float(_pressure.get(id, 0.0)))
		var taken := mini(owed, stockpile.count(id, "sheep"))
		_pressure[id] = float(_pressure.get(id, 0.0)) - owed
		if taken > 0:
			stockpile.take(id, "sheep", taken, "taken by wolves in the night")
			_lose(id, taken)
			print("[balance] wolves took %d sheep from a fold" % taken)
		var recent: Array = (_lost.get(id, []) as Array).filter(func(at: Variant) -> bool:
			return int(at) > _day - int(ask.get("days", 3)))
		_lost[id] = recent
		# The flock come back.
		if _back.has(id) and _day >= int(_back[id]):
			_back.erase(id)
			var rule: Dictionary = rules.get("back", {})
			stockpile.deposit(id, "sheep", int(rule.get("sheep", 3)), str(fold.get("farmer", "")), "a flock again")
			fold_changed.emit(id)
		# The ask.
		if not _quests.has(id) and recent.size() >= int(ask.get("lost", 2)) and _day >= int(_rest.get(id, -1)):
			_ask(fold)
		elif _quests.has(id) and _day >= int(_quests[id]["until"]):
			_judge(fold)
	_town_nights()


func _ask(fold: Dictionary) -> void:
	var id := str(fold["id"])
	var area := str(fold["area"])
	_quests[id] = {"area": area, "town": str(fold.get("town", "")), "from": _day,
		"until": _day + int(rules.get("deadline_days", 4)), "wolves": herds.total(area, _predator()),
		"deer": herds.total(area, _prey()), "lost": 0, "left": 0, "home": 0, "left_by": {}, "home_by": {}}
	print("[balance] a fold asks: %d wolves, %d deer" % [roundi(herds.total(area, _predator())), roundi(herds.total(area, _prey()))])
	asked.emit(id)


## The outcome of fold [param fold_id]'s quest were it judged now.
func outcome(fold_id: String) -> String:
	var each: Dictionary = _quests.get(fold_id, {})
	if each.is_empty():
		return ""
	var judge: Dictionary = rules.get("judge", {})
	var area := str(each["area"])
	var wolves := herds.total(area, _predator())
	var deer := herds.total(area, _prey())
	var room := herds.capacity(area, _prey())
	var start := float(each["wolves"])
	if wolves >= start * float(judge.get("bad_wolves", 1.5)) and wolves > start or int(each["left"]) >= int(judge.get("bad_left", 12)):
		return "badly"
	if wolves <= start and deer >= room * float(judge.get("deer_low", 0.5)) and deer <= room * float(judge.get("deer_high", 0.9)) 			and int(each["lost"]) <= int(judge.get("lost_most", 1)) and int(each["left"]) <= int(judge.get("left_most", 3)):
		return "balanced"
	return "off"


func _judge(fold: Dictionary) -> void:
	var id := str(fold["id"])
	var each: Dictionary = _quests[id]
	var result := outcome(id)
	var town := str(each["town"])
	var farmer := str(fold.get("farmer", ""))
	if result == "balanced":
		var thrive: Dictionary = rules.get("thrive", {})
		stockpile.deposit(id, "sheep", int(thrive.get("lambs", 2)), farmer, "lambs, the wolves kept off")
		if not town.is_empty():
			for what in ["wool", "meat"]:
				if int(thrive.get(what, 0)) > 0:
					stockpile.deposit(town, what, int(thrive[what]), farmer, "from the farm, the wolves kept off")
	else:
		var left := stockpile.count(id, "sheep")
		if left > 0:
			stockpile.take(id, "sheep", left, "the flock lost to the wolves")
		_back[id] = _day + int(rules.get("back", {}).get("days", 5))
	if result == "badly" and not town.is_empty():
		var rule: Dictionary = rules.get("town_wolves", {})
		_threats[town] = {"kind": "wolves", "left": int(rule.get("count", 3)), "nights": int(rule.get("nights", 3))}
		threat_changed.emit(town, "wolves", true)
	print("[balance] a fold's quest is judged %s: lost %d, left %d, home %d" % [result, int(each["lost"]), int(each["left"]), int(each["home"])])
	_quests.erase(id)
	_rest[id] = _day + int(rules.get("rest_days", 4))
	fold_changed.emit(id)
	judged.emit(id, result)


func _town_nights() -> void:
	var towns: Array = _threats.keys()
	towns.sort()
	for town: String in towns:
		var each: Dictionary = _threats[town]
		if not (watched.is_valid() and bool(watched.call(town))):
			var took := 0
			for i in int(each["left"]):
				if not night_take(town).is_empty():
					took += 1
			print("[balance] wolves in a town's night took %d things" % took)
		each["nights"] = int(each["nights"]) - 1
		if int(each["nights"]) <= 0:
			_clear(town)


# --- Saving -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var lying := {}
	for uid: int in _lying:
		var row: Dictionary = _lying[uid].duplicate()
		row["cell"] = [row["cell"].x, row["cell"].y]
		lying[str(uid)] = row
	var carried := {}
	for uid: int in _carried:
		carried[str(uid)] = _carried[uid].duplicate()
	return {"lying": lying, "carried": carried, "quests": _quests.duplicate(true), "lost": _lost.duplicate(true),
		"pressure": _pressure.duplicate(), "back": _back.duplicate(), "rest": _rest.duplicate(),
		"threats": _threats.duplicate(true), "at": _at, "day": _day}


func from_dict(saved: Dictionary) -> void:
	_at = int(saved.get("at", -1))
	_day = int(saved.get("day", -1))
	var lying: Variant = saved.get("lying", {})
	if lying is Dictionary:
		for key: Variant in lying:
			var row: Variant = lying[key]
			var cell: Variant = Snapshot.vector(row.get("cell")) if row is Dictionary else null
			if cell is Vector2i:
				_lying[int(key)] = {"area": str(row.get("area", "")), "cell": cell, "since": int(row.get("since", 0)), "by": str(row.get("by", ""))}
	var carried: Variant = saved.get("carried", {})
	if carried is Dictionary:
		for key: Variant in carried:
			if carried[key] is Dictionary:
				_carried[int(key)] = {"area": str(carried[key].get("area", "")), "by": str(carried[key].get("by", ""))}
	for name in ["quests", "lost", "threats"]:
		var value: Variant = saved.get(name, {})
		if value is Dictionary:
			var into: Dictionary = {"quests": _quests, "lost": _lost, "threats": _threats}[name]
			for key: Variant in value:
				into[str(key)] = value[key]
	for key: Variant in saved.get("pressure", {}):
		_pressure[str(key)] = float(saved["pressure"][key])
	for key: Variant in saved.get("back", {}):
		_back[str(key)] = int(saved["back"][key])
	for key: Variant in saved.get("rest", {}):
		_rest[str(key)] = int(saved["rest"][key])
	# Saved JSON gives numbers back as floats; the quests' counts are whole.
	for id: String in _quests:
		var each: Dictionary = _quests[id]
		for key in ["from", "until", "lost", "left", "home"]:
			each[key] = int(each.get(key, 0))
		for key in ["left_by", "home_by"]:
			if not each.get(key) is Dictionary:
				each[key] = {}
	for id: String in _lost:
		_lost[id] = (_lost[id] as Array).map(func(at: Variant) -> int: return int(at)) if _lost[id] is Array else []
