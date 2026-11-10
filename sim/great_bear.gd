class_name GreatBear
extends Animal
## The great bear (decision 780, apex creatures; the pilot): far bigger than
## any other beast of the forest, it keeps a den and its ground. A lone
## traveller does well to go round it; two or three, or one well armed, can
## take it.
##
## Read before it is fought. It roars, heard far off (ROAR_REACH): waking,
## at dusk, a fight's start and at half its hp. Prey flee it as they flee
## any predator. It hunts deer on its ground by day.
##
## Its ground: within TERRITORY_TILES of its den (its home). It goes for a
## player there, or one who struck it, and nobody past that. With no blow
## given or taken for CALM_TICKS, or its foe past its ground, it gives that
## foe up for BREAK_OFF_TICKS and goes home. By night it walks home and
## sleeps (pose SIT, sight SLEEP_SIGHT), healing a little at a time
## (HEAL_EVERY): the only place it heals. A party that creeps in by night
## gets the first blow. At dawn it wakes with a roar; by day it roams (an
## Animal predator's wander about its den). The coordinator's flip, 780,
## enemy-ai's side (2): the roster's day beast.
##
## Its moves (World.telegraph tells, combat's shapes; it stands while one
## winds up):
## - swipe: a cone, 2 ahead. Each body in it takes SWIPE's damage, swept
##   back (World.sweep, impulse: 2 cells on a player).
## - slam: a ring round it. It rears, then slams: damage, pushed and knocked
##   down. Taken with two or more foes beside it.
## - charge: a line, 6 at most, at a foe 3 or more off. A roar, then a rush
##   (World.rush). The first body met takes the blow and the damage. A
##   charge that meets nobody leaves it winded (stamina 0, decision 597):
##   that is the opening.
## A stun or a knockdown mid-tell (a flank blow from behind: every tell is
## flank-marked, World.telegraph's flank, combat's 780 side) breaks the move off, its telegraph ended unlanded. Every move logs "[apex]"
## with its end and the bear's hp, never a player's name.
##
## Every blow is told (780 amended (8)): a foe it can touch (beside it, or
## a free body within its body's reach, 2 cells off) gets a swipe or a slam,
## never a plain blow; "[apex] ... blow" logs one if it ever lands.
##
## Its party (780 amended (8), combat's draft, the coordinator's ruling):
## the players who join its fight, once they strike it, are struck by it or
## are a tell's target, PARTY "most" at most. Its hp grows by
## "hp_per_player" of its base for each past the first, its hp
## kept in the same share; each newcomer raises it once, none leaving lowers
## it; asleep, it is its base again. Combat's flank guard reads party_size.
## Companions who join the same way count too (780 amended (10), the
## coordinator's ruling): "companion_share" of a player each, "most" at most;
## party_size stays the players alone (the flank guard is player-only).
##
## Read from afar (780 amended (2)): its roar is told to players
## out of sight within ROAR_REACH (World.far_cry: sound's "far_cry"), and it
## leaves prints as it walks, one each TRACK_STRIDE cells (World.mark_track:
## terrain's "tracks"), outdoors.

## Its ground about its den.
const TERRITORY_TILES := 25
## No blow given or taken this long (20 s) in a fight: it gives its foe up.
const CALM_TICKS := 200
const BREAK_OFF_TICKS := 300
## Its roar's reach.
const ROAR_REACH := 50
## A tell's cry (sound's growl).
const TELL_REACH := 8
## Asleep, it sees this far; it heals 1 hp each HEAL_EVERY ticks.
const SLEEP_SIGHT := 2
const HEAL_EVERY := 50
## A print each this many cells walked.
const TRACK_STRIDE := 2
## How far its walk to its door or its ground may plan (a hill's 40 cells).
const WALK_SEARCH_TILES := 6000
## Its moves' numbers, the defaults under monsters.json's row "moves"
## {swipe, slam, charge} (780 amended (2): tuning is data, combat's and
## mine; drafts, tuned from playtest's runs): ticks to land, its
## shape, damage, impulse (physics' kg x speed: 140 pushes a player 2
## cells), and the ticks before it may use the move again.
const SWIPE := {"windup": 6, "length": 2.0, "half_angle": 60.0, "damage": 6, "impulse": 140.0, "every": 15}
const SLAM := {"windup": 12, "length": 1.5, "damage": 9, "impulse": 100.0, "down": 15, "every": 50}
const CHARGE := {"roar": 8, "cells": 6, "from": 3, "damage": 8, "impulse": 140.0, "every": 80}
## The moves as this bear has them: the defaults with its row's "moves" over them.
## Its party's numbers, the defaults under the row's "party" block.
const PARTY := {"hp_per_player": 0.0, "companion_share": 0.0, "most": 3}
var swipe := SWIPE.duplicate()
var slam := SLAM.duplicate()
var charge := CHARGE.duplicate()

## The den: where it spawned (its home).
var den := NO_TILE
## Its lair's door it walks to, going in or out with a player watching
## (Apex, 780 amended (13)); NO_TILE when not.
var apex_goal := NO_TILE
## Out in its land (Apex): it roams by its ground there and never sleeps
## out (dusk takes it home).
var apex_out := false
var asleep := false
## The move under way: {move, telegraph, lands, shape, toward}; a charge's
## rush {move: "rush"} till rush_ended.
var _move := {}
var _next_swipe := 0
var _next_slam := 0
var _next_charge := 0
## The last blow it gave or took in a fight.
var _blow_tick := -1
## Foes given up: instance id -> the tick it may take them up again.
var _left_be: Dictionary[int, int] = {}
## Who struck it: instance id -> the tick of their last blow (engaged_with).
var _struck_at: Dictionary[int, int] = {}
var _roared_fight := false
var _roared_half := false
var _hooked := false
## The cell it last stood on, and the cells walked since its last print.
var _last_tile := NO_TILE
var _strides := 0
## The tick it was winded at, -1 while it is not (its "recovers" line).
var _winded_at := -1
## The players it is fighting on its ground (780 amended (8)); 1 out of a fight.
var party_size := 1
## The companions in its fight (780 amended (10)); 0 out of a fight.
var companions := 0
var party := PARTY.duplicate()
## Its max_hp for one player (its row's).
var _base_hp := 0
## The players who joined its fight: player_id (else the body's instance id)
## -> the body's instance id.
var _joined: Dictionary[String, int] = {}
## The companions who joined its fight: instance id -> instance id.
var _joined_companions: Dictionary[String, int] = {}


func _ready() -> void:
	super()
	_hook()  # Before its first tick: one laid and killed at once still falls (Apex).
	den = home if home != NO_TILE else tile
	_base_hp = max_hp
	var given_party: Variant = Monster.kinds().get(_kind(), {}).get("party", {})
	if given_party is Dictionary:
		for key: String in given_party:
			party[key] = float(given_party[key])  # The whole block (combat's flank_guard_per_player reads it too).
	var moves: Variant = Monster.kinds().get(_kind(), {}).get("moves", {})
	if moves is Dictionary:
		for move: String in ["swipe", "slam", "charge"]:
			var each: Dictionary = {"swipe": swipe, "slam": slam, "charge": charge}[move]
			var given: Variant = moves.get(move, {})
			if given is Dictionary:
				for key: String in given:
					if each.has(key):
						each[key] = given[key]


func _sim_tick() -> void:
	_hook()
	if den == NO_TILE:
		den = tile
	_track()
	if winded and _winded_at < 0:
		_winded_at = World.tick
	elif not winded and _winded_at >= 0:
		print("[apex] %s recovers (winded %d ticks) at %s (%d/%d)" % [_kind(), World.tick - _winded_at, tile, hp, max_hp])
		_winded_at = -1
	if _tend_move():
		return
	if apex_goal != NO_TILE or apex_out and target == null 			and (_blow_tick < 0 or World.tick - _blow_tick > CALM_TICKS) and World.distance(tile, home) > wander_radius * 2 + 2:
		_walk_to(apex_goal if apex_goal != NO_TILE else home)
		return
	if asleep:
		var foe := _struck_by()
		if foe == null:
			foe = _nearest_visible_target()
		if foe == null and not _is_night():
			_wake()  # Dawn.
			return
		if foe == null:
			pose = Pose.SIT
			if World.tick % HEAL_EVERY == 0 and hp < max_hp:
				hp += 1
			return
		_wake()
	elif not apex_out and _is_night() and target == null and alert != Alert.FIGHTING and (_blow_tick < 0 or World.tick - _blow_tick > CALM_TICKS):
		if World.distance(tile, den) <= 1:
			_sleep()
			return
		if World.tick >= next_move_tick:
			_idle_step(den)  # Home for the night.
		return
	super()
	if target == null:
		_roared_fight = false


## To its door, or out to its roaming ground (Apex): awake, after no one,
## at its pace to the door, slower to its ground.
func _walk_to(to: Vector2i) -> void:
	if asleep:
		_wake()
	if apex_goal != NO_TILE:
		target = null
	if World.tick < next_move_tick or World.is_stunned(self):
		return
	move_ticks = _pace if apex_goal != NO_TILE else _pace * IDLE_PACE
	if not _idle_step(to, WALK_SEARCH_TILES):
		next_move_tick = World.tick + 5  # A crowd, or no way just now: a moment.


func _hook() -> void:
	if not _hooked:
		_hooked = true
		World.rush_ended.connect(_on_rush_ended)
		World.entity_died.connect(_on_died)


## [param entity] joins its fight (a player striking it, struck by it, or a
## tell's target): its party grows by one, PARTY "most" at most; a
## companion the same, in its own count (780 amended (10)).
func _join(entity: GridEntity) -> void:
	if not is_instance_valid(entity) or entity.hp <= 0:
		return
	var into: Dictionary[String, int]
	var key := str(entity.get_instance_id())
	if entity is Player:
		into = _joined
		if (entity as Player).player_id != "":
			key = (entity as Player).player_id  # One who comes back (a new body) is the same one.
	elif entity is Companion:
		into = _joined_companions
	else:
		return
	for each: String in into.keys():
		var body := instance_from_id(into[each]) as GridEntity
		if body == null or not body.spawned:
			into.erase(each)  # Gone from the land: a newcomer takes its place, not one beside it.
	if into.has(key):
		into[key] = entity.get_instance_id()
		return
	if into.size() >= maxi(1, int(party["most"])):
		return
	into[key] = entity.get_instance_id()
	_set_party(maxi(party_size, _joined.size()), maxi(companions, _joined_companions.size()))  # Never lowered in a fight.


## Its party to [param n] players and [param with] companions: max_hp from
## its base, hp kept in the same share.
func _set_party(n: int, with := 0) -> void:
	if (n == party_size and with == companions) or _base_hp <= 0:
		return
	var share := float(hp) / float(maxi(1, max_hp))
	party_size = n
	companions = with
	var counted := n + float(party["companion_share"]) * with
	max_hp = roundi(_base_hp * (1.0 + float(party["hp_per_player"]) * (counted - 1.0)))
	hp = clampi(roundi(share * max_hp), 1 if hp > 0 else 0, max_hp)
	print("[apex] %s party %d, companions %d at %s (%d/%d)" % [_kind(), n, with, tile, hp, max_hp])


## A plain blow (Monster's): never meant to land (every blow is told), so
## logged if it does: a tripwire for the tours. At once, never led (338
## amended (4)), so the tripwire sees it land.
func _blow() -> bool:
	lead_ticks = 0
	var was := target.hp if is_instance_valid(target) else 0
	var began := super()
	if is_instance_valid(target) and target.hp < was:
		print("[apex] %s blow %s %d at %s (%d/%d)" % [_kind(), World.kind_of(target), was - target.hp, tile, hp, max_hp])
	return began


## Whether it is night by its body's clock (DayNight's light under Animal's
## NIGHT_LIGHT), indoors too: a den in a cave keeps the hours.
func _is_night() -> bool:
	return DayNight.daylight(DayNight.now()) < NIGHT_LIGHT


func _sleep() -> void:
	asleep = true
	pose = Pose.SIT
	sight_range = SLEEP_SIGHT
	print("[apex] %s sleeps at %s (its den %s) (%d/%d)" % [_kind(), tile, den, hp, max_hp])
	_joined.clear()
	_joined_companions.clear()
	_set_party(1)  # Asleep: its base again (780 amended (8)).


func _wake() -> void:
	asleep = false
	pose = Pose.STAND
	sight_range = int(Monster.kinds().get(_kind(), {}).get("sight_range", 8))
	_roar("waking")


func _roar(why: String) -> void:
	_cry(&"roar", ROAR_REACH)
	World.far_cry.emit(self, &"roar", ROAR_REACH)
	print("[apex] %s roars (%s) at %s (%d/%d)" % [_kind(), why, tile, hp, max_hp])


## A print on the cell it left, each TRACK_STRIDE cells, facing the way it
## went (a step, not a push or a rush's slide more than a cell).
func _track() -> void:
	if _last_tile != NO_TILE and tile != _last_tile:
		var delta := tile - _last_tile
		if World.distance(tile, _last_tile) == 1:
			_strides += 1
			if _strides >= TRACK_STRIDE:
				_strides = 0
				World.mark_track(_last_tile, World.track_facing(delta))
	_last_tile = tile


func _kind() -> String:
	return str(spawn_spec.get("kind", "great_bear"))


## Always bold: its own ground is its fight (Animal's boldness by night or
## pack is a wolf's).
func _settle_bold() -> void:
	_bold = true
	temper = Temper.BOLD
	wander_radius = DEN_RADIUS if _is_night() else maxi(_roam, 6)


## A player or companion on its ground, or one that struck it, unless given
## up; else deer on its ground (Animal's prey).
func _nearest_visible_target() -> GridEntity:
	var struck := _struck_by()
	var seen: GridEntity = struck if struck != null and not struck is Animal else super()
	if seen == null:
		return null
	var id := seen.get_instance_id()
	if _left_be.has(id):
		if World.tick < _left_be[id] and seen != struck:
			return null
		_left_be.erase(id)
	if seen is Animal:
		return seen if World.distance(seen.tile, den) <= TERRITORY_TILES else null
	if seen != struck and World.distance(seen.tile, den) > TERRITORY_TILES:
		_give_up_on(seen, "off its ground")
		return null
	if seen == target and _blow_tick >= 0 and World.tick - _blow_tick > CALM_TICKS and seen != struck:
		_give_up_on(seen, "no blows")
		return null
	if seen != target:
		_blow_tick = World.tick
	return seen


func _give_up_on(foe: GridEntity, why: String) -> void:
	_left_be[foe.get_instance_id()] = World.tick + BREAK_OFF_TICKS
	_struck_at.erase(foe.get_instance_id())
	_blow_tick = -1
	print("[apex] %s breaks off (%s) at %s (%d/%d)" % [_kind(), why, tile, hp, max_hp])


func note_struck(by: GridEntity) -> void:
	super(by)
	_blow_tick = World.tick
	if is_instance_valid(by) and by != self:
		_struck_at[by.get_instance_id()] = World.tick
		_join(by)
	Apex.struck(self)  # Its wait to go out starts again (780 amended (13)).
	if asleep:
		_wake()
	if not _roared_half and hp * 2 < max_hp:
		_roared_half = true
		_roar("half")


## Whether it is fighting [param entity] (decision 780 amended (4), for
## companions: she fights it only when it is engaged with her or her player):
## its target is [param entity], or [param entity] struck it within CALM_TICKS.
## A foe it broke off from is no longer engaged till they strike again.
func engaged_with(entity: GridEntity) -> bool:
	if not is_instance_valid(entity):
		return false
	if target == entity:
		return true
	var at: int = _struck_at.get(entity.get_instance_id(), -1)
	return at >= 0 and World.tick - at <= CALM_TICKS


## Its moves at a player or companion; deer it hunts as Monster does.
func _special_tick() -> bool:
	if target == null or target is Animal:
		return false
	if not _roared_fight:
		_roared_fight = true
		_roar("fight")
	if World.is_winded(self):
		return true  # Winded after a charge that met nobody: it stands, heaving (the opening).
	var d := World.distance(tile, target.tile)
	World.face(self, Senses.way_toward(tile, target.tile))
	if d <= 1 or _in_strike_reach(target):  # A free body touched from 2 off is beside it too (780 amended (8)).
		if World.tick >= _next_slam and _foes_beside() >= 2:
			var ring := {"kind": "ring", "origin": [tile.x, tile.y], "facing": [facing.x, facing.y],
				"length": float(slam["length"]), "inner": 0.0}  # Every cell beside it (combat's).
			_begin("slam", ring, int(slam["windup"]))
			_next_slam = World.tick + int(slam["every"])
			return true
		if World.tick >= _next_swipe:
			_begin("swipe", Telegraph.cone(tile, Vector2(facing), float(swipe["length"]), float(swipe["half_angle"])), int(swipe["windup"]))
			_next_swipe = World.tick + int(swipe["every"])
		return true  # Between blows it stands its ground: no blow without a tell.
	if d >= int(charge["from"]) and d <= int(charge["cells"]) and World.tick >= _next_charge:
		# Drawn to the cell a blow on it strikes (a free body's centre), as the
		# check (the boar king's hold run: the tile and that cell part).
		var toward := Vector2(World.struck_cell(target) - tile).normalized()
		var shape := Telegraph.line(tile, toward, float(charge["cells"]), 1)
		if toward != Vector2.ZERO and World.struck_cell(target) in World.telegraph_cells(shape):  # Aimed at where it is (decision 810).
			_begin("charge", shape, int(charge["roar"]))
			_move["toward"] = toward
			_next_charge = World.tick + int(charge["every"])
			return true
	return false


func _foes_beside() -> int:
	var count := 0
	for each in World.sought():
		if each != self and each.hp > 0 and (World.distance(tile, each.tile) <= 1 or _in_strike_reach(each)):
			count += 1
	return count


func _begin(move: String, shape: Dictionary, ticks: int) -> void:
	var id := World.telegraph(self, move, shape, ticks, true)  # Flank-marked (combat's 780 side): a blow from behind staggers it.
	if id == 0:
		return
	_join(target)
	_move = {"move": move, "telegraph": id, "lands": World.tick + ticks, "shape": shape, "toward": Vector2(facing), "from": World.tick}
	_cry(StringName(move), TELL_REACH)
	print("[apex] %s %s tell at %s, lands in %d ticks (%d/%d)" % [_kind(), move, tile, ticks, hp, max_hp])


## The move under way, if any: true while it holds the bear (its tell, its
## rush); landed or broken off here.
func _tend_move() -> bool:
	if _move.is_empty():
		return false
	var move := str(_move["move"])
	if move == "rush":
		return true
	# Stunned or knocked down since its tell began (its tick does not run
	# meanwhile, so read when that came, not whether it lasts).
	var from := int(_move["from"])
	if stunned_until_tick > from or down_until > from or not spawned:
		World.end_telegraph(int(_move["telegraph"]), false)
		_log_move(move, "broken")
		_move = {}
		return false
	if World.tick < int(_move["lands"]):
		return true
	var cells := World.telegraph_cells(_move["shape"])
	var id := int(_move["telegraph"])
	match move:
		"swipe":
			var swept := _bodies(cells)
			var struck := _hit_cells(cells, int(swipe["damage"]))
			World.sweep(self, _move["toward"], float(swipe["half_angle"]) * 2.0, int(ceil(float(swipe["length"]))), {"impulse": float(swipe["impulse"]), "only": swept})  # A body spared is not pushed (810).
			World.end_telegraph(id, true)
			_log_move(move, "landed on %d" % struck if struck > 0 else "dodged")
		"slam":
			var hit := _bodies(cells)
			_hit_cells(cells, int(slam["damage"]))
			World.sweep(self, _move["toward"], 360.0, 1, {"impulse": float(slam["impulse"]), "only": hit})  # A body spared is not pushed (810).
			for each in hit:
				if is_instance_valid(each) and each.spawned:
					World.knock_down(each, self, int(slam["down"]))
			World.end_telegraph(id, true)
			_log_move(move, "landed on %d" % hit.size() if not hit.is_empty() else "dodged")
		"charge":
			# Its told line stays down until the rush stops (810 amended (2)): ended in _on_rush_ended.
			if World.rush(self, _move["toward"], int(charge["cells"]), {"blow": {"impulse": float(charge["impulse"])}}):
				_move = {"move": "rush", "telegraph": id}
				return true
			World.end_telegraph(id, false)
			_log_move(move, "no room")
	_move = {}
	return true


## Its fall, logged for playtest's tours (which inferred it from its hp).
func _on_died(entity: GridEntity, cause: StringName) -> void:
	if entity == self:
		print("[apex] %s falls (%s) at %s, party %d" % [_kind(), cause, tile, party_size])
		Apex.died(self)  # Dead its rise, then in its lair (780 amended (13)).


## A charge's rush over: the body it met takes the blow; none met, it is
## winded.
func _on_rush_ended(entity: GridEntity, reason: String, _at: Vector2i, result: Dictionary) -> void:
	if entity != self or _move.get("move", "") != "rush":
		return
	var told := int(_move.get("telegraph", 0))
	_move = {}
	var hit := 0
	for each: Variant in result.get("struck", []):
		var met: Variant = each.get("body") if each is Dictionary else null
		if met is GridEntity and is_instance_valid(met) and met != self and (met as GridEntity).spawned:
			World.damage(met, int(charge["damage"]), self, &"attack")
			hit += 1
	World.end_telegraph(told, true)  # Landed, as ever; its told line down till now (810 amended (2)).
	if hit > 0:
		_blow_tick = World.tick
		_log_move("charge", "landed on %d (%s)" % [hit, reason])
	else:
		stamina = 0  # Winded (597): the opening.
		winded = true
		_log_move("charge", "dodged (%s)" % reason)


## The bodies its tell on [param cells] strikes but its own (decision 810:
## World.tell_struck, by the centre's cell, lag judged in the player's
## favour; it read the held tile, which keeps a body till 0.1 past the edge).
func _bodies(cells: Array[Vector2i]) -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	for each in World.tell_struck(self, cells):
		if each.spawned and each.hp > 0 and each.max_hp > 0:
			out.append(each)
	return out


## [param damage] to each body on [param cells]; how many.
func _hit_cells(cells: Array[Vector2i], damage: int) -> int:
	var hit := _bodies(cells)
	for each in hit:
		_join(each)
		World.damage(each, damage, self, &"attack")
	if not hit.is_empty():
		_blow_tick = World.tick
	return hit.size()


func _log_move(move: String, how: String) -> void:
	print("[apex] %s %s at %s -> %s (%d/%d)" % [_kind(), move, tile, how, hp, max_hp])
