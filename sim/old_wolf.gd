class_name OldWolf
extends Animal
## The old grey (780 amended (15); enemy-ai's old wolf design, the
## coordinator's approval, 11-06; lore's old_wolf.pack, Jeff's: "In the
## hills and foothills a wolf pack follows an old grey"). An apex (his row's
## "apex", "lair" and "escort": Apex lays him and his pack): not a brute like
## the bear but the pack's mind. He fights through his pack and leaves
## openings a player can read.
##
## - He hangs back while his pack lives: HANG cells off his target (near to
##   far), at the fight's edge, and comes in only at one down or turned
##   away from him. His pack gone, he comes in himself (a wolf's dart).
## - The howl (told): his head up and a long cry ("howl", heard TELL_REACH,
##   far when he is out), "every" ticks while two or more of his pack live.
##   At its end his pack about his target dart in at once. Struck while he
##   howls, he breaks it off: a bonus for the one who goes for him.
## - The lunge (told): a line "cells" long at his target (World.telegraph),
##   then he rushes along it and bites the first foe met, dragging them a
##   cell toward his pack. Never into a downing (the coordinator): no lunge
##   at a foe under half their hp while any of his pack is within 2 of them.
## - The pant: after each lunge he stands "pant" ticks, sides heaving: the
##   opening: he strikes nobody and keeps his place (a stun or a knockdown
##   ends it early, as any move's).
## He never charges or knocks down: that is the bear's. Every move logs
## "[apex]" with his hp, never a player's name.

## His howl's cry, and his tells' (sound's).
const TELL_REACH := 8
const HOWL_REACH := 50
## No lunge at a foe under half their hp with his pack this near them.
const DOWNING_PACK_TILES := 2
## His moves' defaults, under monsters.json's row "moves" (combat tunes):
## ticks to land, its reach, damage, the drag's impulse, ticks between
## ("spring": his told lunge; a row's "lunge" is combat's, Monster.LUNGE).
const HOWL := {"windup": 12, "every": 120, "rush_tiles": 6}
const SPRING := {"windup": 8, "cells": 3, "damage": 4, "drag": 60.0, "every": 50}
const PANT := {"ticks": 20}
## Cells off his target he keeps while his pack lives: [near, far].
const HANG := [3, 4]
var howl := HOWL.duplicate()
var spring := SPRING.duplicate()
var pant := PANT.duplicate()

## The den (his home where laid), his lair's door to walk to, and whether
## he is out in his land (Apex's, as the bear's).
var den := NO_TILE
## The den rule (780 amended (26), the boar king's, shared: Apex.to_den):
## under DEN_BELOW of its hp in its lair it never flees but walks to its den,
## within DEN_RULE "near" of it fighting on; at bay where it stands once struck
## "at_bay_after" times on the way; one told bite back for each blow on it
## that lands on the way, never more owed ("bite_per_blow", _den_bite);
## past its own escort in its way, and at bay where it stands once a foe
## bars its way home ("barred"). Its walk's state (Apex.to_den's).
const DEN_BELOW := 0.15
const DEN_RULE := {"near": 3, "far": false, "log": "den", "at_bay_after": 0, "bite_per_blow": true, "barred": true}
var _wallow_from: GridEntity = null
var _wallow_far := false
var _wallow_hits := 0
var _wallow_seen := -1
var _wallow_owed := false
var _wallow_owed_seen := -1
var _wallow_tick := -1  # When it turned for home (its pack covers it from then).
var _wallow_barred := -1  # Since when a foe bars its way home ("barred"); at bay, its last look.
var _wallow_at_bay := false  # Barred from its den: cornered where it stands.
var apex_goal := NO_TILE
var apex_out := false
## The move under way: {move, telegraph, lands, shape, toward, from}; a
## lunge's rush {move: "rush"} till rush_ended; the pant {move: "pant"}.
var _move := {}
var _next_howl := 0
var _next_spring := 0
var _hooked := false


func _ready() -> void:
	super()
	_hook()
	den = home if home != NO_TILE else tile
	_no_flee()
	var moves: Variant = Monster.kinds().get(_kind(), {}).get("moves", {})
	if moves is Dictionary:
		for move: String in ["howl", "spring", "pant"]:
			var each: Dictionary = {"howl": howl, "spring": spring, "pant": pant}[move]
			var given: Variant = moves.get(move, {})
			if given is Dictionary:
				for key: String in given:
					if each.has(key):
						each[key] = given[key]
	_next_howl = World.tick + int(howl["every"]) / 2


func _hook() -> void:
	if not _hooked:
		_hooked = true
		World.rush_ended.connect(_on_rush_ended)
		World.entity_died.connect(_on_died)


func _sim_tick() -> void:
	_hook()
	if den == NO_TILE:
		den = tile
	if _tend_move():
		return
	if Apex.to_den(self, DEN_BELOW, den, struck_by, DEN_RULE):
		return
	if apex_goal != NO_TILE:
		target = null
		if World.tick >= next_move_tick and not World.is_stunned(self):
			move_ticks = _pace
			if not _idle_step(apex_goal, GreatBear.WALK_SEARCH_TILES):
				next_move_tick = World.tick + 5
		return
	if apex_out and target == null and World.distance(tile, home) > wander_radius * 2 + 2:
		if World.tick >= next_move_tick and not World.is_stunned(self):
			move_ticks = _pace * IDLE_PACE
			if not _idle_step(home, GreatBear.WALK_SEARCH_TILES):
				next_move_tick = World.tick + 5
		return
	super()


func _kind() -> String:
	return str(spawn_spec.get("kind", "old_wolf"))


## Always bold, never sleeps: his ground is his pack's.
func _settle_bold() -> void:
	_bold = true
	temper = Temper.BOLD
	wander_radius = maxi(_roam, 4)
	_no_flee()


## It never flees (780 amended (26)): under DEN_BELOW in its lair it goes to
## its den instead (Apex.to_den), as the boar king does.
func _no_flee() -> void:
	for t: int in flee_below:
		flee_below[t] = 0.0
	dread_flee_below = 0.0


## His bite back on the walk to his den (Apex.to_den's "bite_per_blow"):
## his fight's led bite at [param by], its lead_ticks told (780 amended (23),
## (26)). True if begun.
func _den_bite(by: GridEntity) -> bool:
	return World.try_wind_up(self, by, lead_ticks)


## His pack about him: living wolves of his herd within PACK_TILES (his
## escort and the den's keepers alike).
func pack() -> Array[Monster]:
	var out: Array[Monster] = []
	for entity in World.monsters():
		if entity != self and entity is Animal and not entity is OldWolf and (entity as Animal).herd == herd \
				and (entity as Animal).spawned and entity.hp > 0 and World.distance(tile, entity.tile) <= PACK_TILES:
			out.append(entity)
	return out


## His moves at a player or companion; deer he hunts as a wolf does.
func _special_tick() -> bool:
	if target == null or target is Animal:
		return false
	var mates := pack()
	var d := World.distance(tile, target.tile)
	if mates.size() >= 2 and World.tick >= _next_howl:
		_next_howl = World.tick + int(howl["every"])
		_begin_howl()
		return true
	if World.tick >= _next_spring and d >= 2 and d <= int(spring["cells"]) and _may_lunge(mates):
		var toward := Vector2(World.struck_cell(target) - tile).normalized()  # As its check (the boar king's hold run).
		var shape := Telegraph.line(tile, toward, float(spring["cells"]), 1)
		var cells := World.telegraph_cells(shape)
		if World.struck_cell(target) in cells and not mates.any(func(m: Monster) -> bool: return m.tile in cells):
			_next_spring = World.tick + int(spring["every"])
			_begin("lunge", shape, int(spring["windup"]))
			_move["toward"] = toward
			return true
	if mates.is_empty() or _opening():
		return false  # Alone, or his target open: in he comes (a wolf's dart).
	_hang_back(d)
	return true


## Never into a downing: not at a foe under half their hp with his pack
## within DOWNING_PACK_TILES of them.
func _may_lunge(mates: Array[Monster]) -> bool:
	if target.max_hp > 0 and target.hp * 2 < target.max_hp:
		for mate in mates:
			if World.distance(mate.tile, target.tile) <= DOWNING_PACK_TILES:
				return false
	return true


## His target down, or turned away from him: his opening to come in.
func _opening() -> bool:
	if World.is_down(target) or World.is_downed(target):
		return true
	var to_me := Vector2(tile - target.tile)
	return to_me != Vector2.ZERO and Vector2(target.facing).dot(to_me.normalized()) < -0.25


## At the fight's edge: HANG[0]..HANG[1] cells off, facing his target.
func _hang_back(d: int) -> void:
	World.face(self, Senses.way_toward(tile, target.tile))
	if World.tick < next_move_tick or World.is_stunned(self):
		return
	move_ticks = _pace
	if d < int(HANG[0]):
		var best := NO_TILE
		var best_d := d
		for way in World.DIRECTIONS:
			var at: Vector2i = tile + way
			var off := World.distance(at, target.tile)
			if off > best_d and World.is_walkable(at) and World.is_free(at):
				best = at
				best_d = off
		if best != NO_TILE:
			World.try_move(self, best - tile)
			World.face(self, Senses.way_toward(tile, target.tile))
		return
	if d > int(HANG[1]):
		_idle_step(target.tile)


func _begin_howl() -> void:
	pose = Pose.STAND
	_move = {"move": "howl", "telegraph": 0, "lands": World.tick + int(howl["windup"]), "from": World.tick}
	_cry(&"howl", TELL_REACH)
	if apex_out:
		World.far_cry.emit(self, &"howl", HOWL_REACH)
	_log_move("howl", "begins, lands in %d ticks" % int(howl["windup"]))


func _begin(move: String, shape: Dictionary, ticks: int) -> void:
	var id := World.telegraph(self, move, shape, ticks, true)  # Flank-marked: a blow from behind staggers him.
	if id == 0:
		return
	_move = {"move": move, "telegraph": id, "lands": World.tick + ticks, "shape": shape, "toward": Vector2(facing), "from": World.tick}
	_cry(StringName(move), TELL_REACH)
	_log_move(move, "tell, lands in %d ticks" % ticks)


## The move under way: true while it holds him (a tell, a rush, the pant).
func _tend_move() -> bool:
	if _move.is_empty():
		return false
	var move := str(_move["move"])
	if move == "rush":
		return true
	var from := int(_move["from"])
	if stunned_until_tick > from or down_until > from or not spawned:
		if int(_move.get("telegraph", 0)) != 0:
			World.end_telegraph(int(_move["telegraph"]), false)
		_log_move(move, "broken")
		_move = {}
		return false
	if World.tick < int(_move["lands"]):
		return true
	match move:
		"howl":
			_move = {}
			_pack_rush()
		"lunge":
			# Its told line stays down until the rush stops (810 amended (2)): ended in _on_rush_ended.
			var told := int(_move["telegraph"])
			var toward: Vector2 = _move["toward"]
			_move = {}
			if World.rush(self, toward, int(spring["cells"]), {"blow": {"impulse": 0.0}, "within": World.told_cells(told)}):  # Never past its told end (780 amended (27)).
				_move = {"move": "rush", "telegraph": told, "toward": toward}
				return true
			World.end_telegraph(told, false)
			_log_move("lunge", "no room")
			_begin_pant()
		"pant":
			_move = {}
			_log_move("pant", "over")
			return false
	return true


## The howl's end: his pack about his target dart in at once.
func _pack_rush() -> void:
	if not is_instance_valid(target) or not target.spawned:
		_log_move("howl", "no one")
		return
	var sent := 0
	for mate in pack():
		if World.distance(mate.tile, target.tile) > int(howl["rush_tiles"]):
			continue
		mate.target = target
		mate._follow(target.tile, Alert.HUNTING, HUNT_TICKS)
		mate.next_attack_tick = mini(mate.next_attack_tick, World.tick)
		mate.next_move_tick = mini(mate.next_move_tick, World.tick)
		mate._dart_until = -1
		if mate is Animal:
			(mate as Animal)._burst_until = World.tick + BURST_TICKS
		sent += 1
	_log_move("howl", "the pack rushes, %d" % sent)


## After a lunge: he stands, sides heaving, striking nobody (the opening).
func _begin_pant() -> void:
	_move = {"move": "pant", "telegraph": 0, "lands": World.tick + int(pant["ticks"]), "from": World.tick}
	_cry(&"pant", TELL_REACH)
	_log_move("pant", "for %d ticks" % int(pant["ticks"]))


## A lunge's rush over: the first foe met is bitten and dragged a cell
## toward his pack; then he pants.
func _on_rush_ended(entity: GridEntity, reason: String, _at: Vector2i, result: Dictionary) -> void:
	if entity != self or _move.get("move", "") != "rush":
		return
	var told := int(_move.get("telegraph", 0))
	var toward: Vector2 = _move.get("toward", Vector2(facing))
	_move = {}
	var bitten: GridEntity = null
	var stunned_until := -1
	for each: Variant in result.get("struck", []):
		var met: Variant = each.get("body") if each is Dictionary else null
		if met is GridEntity and is_instance_valid(met) and met != self and (met as GridEntity).spawned \
				and not (met is Monster and _same_pack(met as Monster)):
			bitten = met
			stunned_until = int(each.get("stunned_until", -1))
			break
	if bitten == null and is_instance_valid(target) and target.spawned and World.distance(tile, target.tile) <= 1 \
			and _on_told(target, told):
		bitten = target  # Run up to them on his line: the bite at its end. Stepped off it, they're clear (780 amended (23)).
	if bitten != null:
		# Told (340 amended (4)): a raised shield facing his line takes the bite; his drag unchanged.
		var harm := World.told_guard(bitten, self, int(spring["damage"]), toward, stunned_until)
		if harm > 0:
			World.damage(bitten, harm, self, &"attack")
		var drag := _drag_way(bitten)
		if drag != Vector2.ZERO and is_instance_valid(bitten) and bitten.spawned and bitten.hp > 0:
			World.launch(self, bitten, drag, float(spring["drag"]))
		_log_move("lunge", "bit (%s)%s" % [reason, ", dragged" if drag != Vector2.ZERO else ""])
	else:
		_log_move("lunge", "dodged (%s)" % reason)
	World.end_telegraph(told, true)  # Landed, as ever; its told line down till now (810 amended (2)).
	_begin_pant()


## Whether [param body] stands on telegraph [param told]'s cells (the cell a
## blow on it strikes, World.struck_cell): the run-up bite's reach.
func _on_told(body: GridEntity, told: int) -> bool:
	return World.struck_cell(body) in World.told_cells(told)


## Whether he is fighting [param entity] (companions read it,
## Companion._apex_with): his target, or the one he broke off from on his
## walk to his den (780 amended (26)), whom he still fights.
func engaged_with(entity: GridEntity) -> bool:
	return is_instance_valid(entity) and (target == entity or _wallow_from == entity)


## The way from [param bitten] toward his pack's middle; none with no pack.
func _drag_way(bitten: GridEntity) -> Vector2:
	var mates := pack()
	if mates.is_empty():
		return Vector2.ZERO
	var middle := Vector2.ZERO
	for mate in mates:
		middle += Vector2(mate.tile)
	middle /= float(mates.size())
	var way := middle - Vector2(bitten.tile)
	return way.normalized() if way.length() > 0.5 else Vector2.ZERO


func _same_pack(other: Monster) -> bool:
	return other is Animal and (other as Animal).herd == herd


func note_struck(by: GridEntity) -> void:
	super(by)
	Apex.struck(self, by)  # His wait to go out starts again (780 amended (13)); by, one of its fighters (780 amended (20)).
	if str(_move.get("move", "")) == "howl":
		_move = {}
		_log_move("howl", "broken (struck)")


func _on_died(entity: GridEntity, cause: StringName) -> void:
	if entity == self:
		print("[apex] %s falls (%s) at %s" % [_kind(), cause, tile])
		Apex.died(self)


func _log_move(move: String, how: String) -> void:
	print("[apex] %s %s at %s -> %s (%d/%d)" % [_kind(), move, tile, how, hp, max_hp])
