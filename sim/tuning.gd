class_name Tuning
extends RefCounted
## Feel tuning in a local host (decision 673; Jeff: "i need way to tune
## combat and animation feel that has a quicker feedback loop"): the values
## that drive how a fight feels, changed while the game runs, saved for the
## trees to commit, with slow motion and a frame step to watch a blow land,
## and the practice hall's arena calls (a dummy, a kind spawned, a thing
## given, a reset).
##
## Only where this process is the whole world: Net's HOST (the sim and the
## view in one), never a joined client (whose numbers would be the server's)
## nor a server (the box: nothing here ever runs there, a save is never
## read). The repo's files stay the source: a change lives in this process,
## a save writes only what changed to user://tuning, and the trees put
## Jeff's numbers in their data files; nothing here writes levels/ or art/.
##
## A field is a path, its first part the source that reads and sets it:
##   combat.<key>, combat.moves.<move>.<key>   World's levels/combat.json
##   physics.<key>                             World's levels/physics.json
##   items.<id>.<key>                          an item's verb, levels/items.json
## and any a tree registers (register_source: pc-character's feel.json, the
## camera's). fields() lists them for the panel (ui's), each with its group,
## kind (int, float, bool, ints, floats), range, owner and when it takes.

## Where a save goes, and the copy for review (the coordinator routes it).
static var save_dir := "user://tuning"
static var review_dir := "C:/dev/review/tuning"
## The time scales F8 goes through, in turn.
const SCALES: Array[float] = [1.0, 0.5, 0.25]
## A dummy's hp back to full after this long without a blow (3 s).
const DUMMY_REFILL_TICKS := 30
## The items whose verbs the panel shows, in its order.
const VERB_ITEMS: Array[String] = ["bow", "sword", "shield", "battle_axe", "giant_axe", "dagger", "spear", "mace"]
## A verb's keys the panel leaves out: words, and a bow's worked out from
## its others (its longest step, its ticks to full draw).
const VERB_SKIP: Array[String] = ["kind", "says"]
const RANGED_SKIP: Array[String] = ["draw_full", "cells"]
## combat.json's and physics.json's own keys, each with its range.
const COMBAT_KEYS := {
	"swing_base": [0.0, 20.0], "swing_per_kg": [0.0, 10.0], "ref_mass": [10.0, 200.0], "whiff_scale": [1.0, 3.0],
	"recover_at": [0, 100], "winded_move_scale": [1.0, 3.0], "winded_blow_scale": [0.0, 1.0], "winded_regen_delay": [0, 100],
}
const PHYSICS_KEYS := {
	"shove_scale": [0.0, 3.0], "knockback_min_speed": [0.0, 10.0], "slide_per_speed": [0.0, 3.0], "max_travel": [0, 12],
	"momentum_scale": [0.0, 3.0], "momentum_ticks": [0, 30], "restitution": [0.0, 1.0], "impact_per_energy": [0.0, 1.0],
	"brace_restitution": [0.0, 1.0], "stun_ticks_base": [0, 30], "stun_ticks_per_speed": [0.0, 10.0],
	"knockback_stun_ticks": [0, 30], "lunge_ticks_per_cell": [0.0, 5.0], "lunge_min_speed": [0.0, 10.0],
	"rush_stop_speed": [0.0, 10.0], "swing_speed": [0.0, 20.0], "throw_speed": [0.0, 30.0],
	"load_k": [0.0, 3.0], "load_free": [0.0, 1.0], "load_heavy": [0.0, 2.0], "load_overloaded": [0.0, 3.0],
}
## physics.json's names where World's vars differ (as load_physics_rules).
const PHYSICS_FIELDS := {"knockback_min_speed": "knockback_min_force", "stun_ticks_per_speed": "stun_ticks_per_force"}

## The repo's value of each path changed (to reset to and to save beside).
static var _repo := {}
## What each source registered: prefix -> {"get": Callable(path) -> Variant,
## "set": Callable(path, value) -> bool, "fields": Callable() -> Array}.
static var _sources := {}
## The time scale now (one of SCALES) and whether paused.
static var _scale := 1.0
static var paused := false
## What the arena made, so clear() takes only those away.
static var _made: Array[GridEntity] = []


## Whether tuning may run here: a local host, never a client or a server.
static func allowed() -> bool:
	return Net.mode == Net.Mode.HOST


## A tree's own fields (decision 673's step 2): [param prefix] ("feel")
## read by [param getter] (path -> value, null when unknown), set by
## [param setter] (path, value -> applied), listed by [param lister] (rows
## as fields() gives them).
static func register_source(prefix: String, getter: Callable, setter: Callable, lister: Callable) -> void:
	_sources[prefix] = {"get": getter, "set": setter, "fields": lister}


## Every field the panel shows: {path, group, kind, min, max, owner, takes}
## (takes: "now", or "spawn" for one read when a body is made).
static func fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in COMBAT_KEYS:
		out.append(_row("combat." + key, "Stamina and swings", COMBAT_KEYS[key], "combat"))
	for move: String in World.moves:
		var values: Dictionary = World.moves[move]
		for key: String in values:
			if _number(values[key]):
				out.append(_row("combat.moves.%s.%s" % [move, key], "Telegraphs and boss moves", _span(values[key]), "combat"))
	for key: String in PHYSICS_KEYS:
		out.append(_row("physics." + key, "Load" if key.begins_with("load_") else "Knockback and mass", PHYSICS_KEYS[key], "physics"))  # The load: 676.
	for id in VERB_ITEMS:
		var verb := Items.verb_of(id)
		for key: String in verb:
			if key not in VERB_SKIP and not (verb["kind"] == "ranged" and key in RANGED_SKIP) and (_number(verb[key]) or verb[key] is bool or verb[key] is Array):
				out.append(_row("items.%s.%s" % [id, key], "Verbs: " + id, _span(verb[key]), "items"))
	for prefix: String in _sources:
		var given: Variant = (_sources[prefix]["fields"] as Callable).call()
		if given is Array:
			for row: Variant in given:
				if row is Dictionary:
					out.append(row)
	for row in out:
		row["kind"] = _kind_of(value(row["path"]))
		if not row.has("takes"):
			row["takes"] = "now"
	return out


## [param path]'s value now; null for none.
static func value(path: String) -> Variant:
	var parts := path.split(".")
	match parts[0]:
		"combat":
			if parts.size() == 4 and parts[1] == "moves":
				return World.moves.get(parts[2], {}).get(parts[3])
			return World.get(parts[1]) if parts.size() == 2 and COMBAT_KEYS.has(parts[1]) else null
		"physics":
			return World.get(PHYSICS_FIELDS.get(parts[1], parts[1])) if parts.size() == 2 and PHYSICS_KEYS.has(parts[1]) else null
		"items":
			return Items.verb_of(parts[1]).get(parts[2]) if parts.size() == 3 else null
	if _sources.has(parts[0]):
		return (_sources[parts[0]]["get"] as Callable).call(path)
	return null


## [param path] set to [param given] at once (its kind's: a float for a
## float, a list of as many numbers or any length for a list); false, and
## nothing changed, when not allowed here, an unknown path or a value of
## another kind. The repo's value is kept the first time, for reset and save.
static func apply(path: String, given: Variant) -> bool:
	if not allowed():
		return false
	var now: Variant = value(path)
	if now == null:
		return false
	var fitted: Variant = _fit(now, given)
	if fitted == null:
		return false
	if not _repo.has(path):
		_repo[path] = now.duplicate() if now is Array else now
	if not _put(path, fitted):
		return false
	if _same(fitted, _repo[path]):
		_repo.erase(path)
	return true


## [param path] back to the repo's value.
static func reset(path: String) -> bool:
	if not _repo.has(path):
		return false
	var was: Variant = _repo[path]
	_repo.erase(path)
	return _put(path, was)


static func reset_all() -> void:
	for path: String in _repo.keys():
		reset(path)


## What has changed: path -> {"value", "repo"}.
static func changes() -> Dictionary:
	var out := {}
	for path: String in _repo:
		out[path] = {"value": value(path), "repo": _repo[path]}
	return out


## The changes written to save_dir/<date_time>.json with the build's
## version; the file's path, "" when not allowed or nothing changed.
static func save() -> String:
	if not allowed() or _repo.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(save_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var path := save_dir.path_join("%s.json" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify({"version": Net.version, "saved": stamp, "changes": changes()}, "\t"))
	file.close()
	return path


## The save at [param path] copied into review_dir (made if missing), for
## the coordinator to route; the copy's path, "" when it could not be.
static func copy_to_review(path: String) -> String:
	if not allowed() or not FileAccess.file_exists(path):
		return ""
	DirAccess.make_dir_recursive_absolute(review_dir)
	var to := review_dir.path_join(path.get_file())
	return to if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), to) == OK else ""


## A save read back in, each change applied; how many took (-1 when not
## allowed or not a save).
static func load_file(path: String) -> int:
	if not allowed():
		return -1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if data is not Dictionary or data.get("changes") is not Dictionary:
		return -1
	var took := 0
	for field: String in data["changes"]:
		var change: Variant = data["changes"][field]
		if change is Dictionary and apply(field, change.get("value")):
			took += 1
	return took


## F8: the next of SCALES; the scale now.
static func cycle_scale() -> float:
	if not allowed():
		return Engine.time_scale
	_scale = SCALES[(SCALES.find(_scale) + 1) % SCALES.size()]
	if not paused:
		Engine.time_scale = _scale
	return _scale


static func time_scale() -> float:
	return _scale


## F9: everything held (the sim's tick, the clips, the eases), or let go
## at the scale it had.
static func toggle_pause() -> bool:
	if not allowed():
		return paused
	paused = not paused
	World.pause_at_tick = -1
	Engine.time_scale = 0.0 if paused else _scale
	return paused


## ".": paused, one sim tick played at the scale, the view with it, then
## held again (World stops at the tick).
static func step_once() -> void:
	if not allowed() or not paused:
		return
	World.pause_at_tick = World.tick + 1
	Engine.time_scale = _scale


## Back to plain time, as when the game starts (and for tests).
static func plain_time() -> void:
	paused = false
	_scale = 1.0
	World.pause_at_tick = -1
	Engine.time_scale = 1.0


## The arena (the practice hall): a dummy at [param at], one that never
## moves or strikes and never dies (its hp held at 1, full again after
## DUMMY_REFILL_TICKS without a blow); a body of the build's plain monster.
static func spawn_dummy(at: Vector2i) -> GridEntity:
	var dummy := spawn_kind("brute", at, false)
	if dummy is Monster:
		(dummy as Monster).never_dies = true
		dummy.name = "Dummy%d" % _made.size()
	return dummy


## One of [param kind] (monsters.json's) at [param at]: [param fights], or
## standing guard where it is.
static func spawn_kind(kind: String, at: Vector2i, fights := true) -> GridEntity:
	if not allowed() or not World.spawn_spec.is_valid():
		return null
	var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
	if spec.is_empty():
		return null
	spec["name"] = "Practice%s%d" % [kind.capitalize().replace(" ", ""), _made.size()]
	spec["tile"] = at
	if not fights:
		spec["idle"] = {"mode": "guard"}
	var made: Variant = World.spawn_spec.call(spec)
	if made is not GridEntity:
		return null
	if not fights and made is Monster:
		(made as Monster).practice_still = true  # Passive: it stands and takes it; it can die.
	_made.append(made)
	return made


## Everything the arena made, gone.
static func clear() -> void:
	for made in _made:
		if is_instance_valid(made):
			World.despawn(made)
	_made.clear()


## [param id] given to [param who]: worn if armour, in the left hand if a
## shield or arrows, else the right (two hands: the left emptied), a bow's
## arrows with it; what was there gone. False when it is no thing.
static func give(who: GridEntity, id: String) -> bool:
	if not allowed() or who == null or Items.def(id).is_empty():
		return false
	var definition := Items.def(id)
	var slot := Items.RIGHT_HAND
	if not definition.get("armour", {}).is_empty():
		slot = Items.ARMOUR
	elif "shield" in definition.get("tags", []) or "ammo" in definition.get("tags", []):
		slot = Items.LEFT_HAND
	var empty: Array[int] = [slot]
	if slot == Items.RIGHT_HAND and (int(definition.get("hands", 1)) == 2 or str(definition.get("verb", {}).get("kind", "")) == "ranged"):
		empty.append(Items.LEFT_HAND)
	for each in empty:
		if who.slots.size() > each and not str(who.slots[each]).is_empty():
			World.items.end(World.take_item(who, who, each), "gone")
	if not World.put_item(who, who, slot, World.items.mint(id, "practice")):
		return false
	if str(definition.get("verb", {}).get("kind", "")) == "ranged":
		World.put_item(who, who, Items.LEFT_HAND, World.items.mint("arrows", "practice"))
	return true


## [param who] at full hp and stamina.
static func full(who: GridEntity) -> void:
	if not allowed() or who == null:
		return
	who.hp = who.max_hp
	who.stamina = who.max_stamina


static func _row(path: String, group: String, span: Array, owner: String) -> Dictionary:
	return {"path": path, "group": group, "min": span[0], "max": span[1], "owner": owner}


## A range for a value with none of its own: from 0 to four times it.
static func _span(now: Variant) -> Array:
	if now is Array:
		var most := 1.0
		for each: Variant in now:
			most = maxf(most, float(each))
		return [0, most * 4.0]
	if now is bool:
		return [false, true]
	return [0, maxf(4.0 * float(now), 1.0 if now is float else 10.0)]


static func _number(v: Variant) -> bool:
	return v is int or v is float


static func _kind_of(v: Variant) -> String:
	if v is bool:
		return "bool"
	if v is int:
		return "int"
	if v is float:
		return "float"
	if v is Array:
		return "ints" if not v.is_empty() and v.all(func(e: Variant) -> bool: return e is int) else "floats"
	return ""


## [param given] as [param now]'s kind; null when it cannot be.
static func _fit(now: Variant, given: Variant) -> Variant:
	if now is bool:
		return given if given is bool else null
	if now is int or now is float:
		if not _number(given) or float(given) < 0.0:
			return null
		return roundi(float(given)) if now is int else float(given)
	if now is Array:
		if given is not Array or (given as Array).is_empty():
			return null
		var whole := _kind_of(now) == "ints"
		var out := []
		for each: Variant in given:
			if not _number(each) or float(each) < 0.0:
				return null
			out.append(roundi(float(each)) if whole else float(each))
		return out
	return null


static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		return a == b
	if _number(a) and _number(b):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _put(path: String, v: Variant) -> bool:
	var parts := path.split(".")
	match parts[0]:
		"combat":
			if parts.size() == 4:
				World.moves[parts[2]][parts[3]] = v  # As load_combat_rules' merge, its kind kept.
			else:
				World.load_combat_rules(JSON.stringify({parts[1]: v}))
			return true
		"physics":
			World.load_physics_rules(JSON.stringify({parts[1]: v}))
			return true
		"items":
			return Items.set_verb(parts[1], parts[2], v)
	if _sources.has(parts[0]):
		return bool((_sources[parts[0]]["set"] as Callable).call(path, v))
	return false
