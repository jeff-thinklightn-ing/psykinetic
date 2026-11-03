class_name GreatBear
extends Animal
## The great bear (decision 780, apex creatures; the pilot): far bigger than
## any other beast of the forest, it keeps a den and its ground. A lone
## traveller does well to go round it; two or three, or one well armed, can
## take it.
##
## Read before it is fought. It roars, heard far off (ROAR_REACH): waking,
## at dusk, a fight's start and at half its hp. Prey flee it as they flee
## any predator. It hunts deer on its ground by night.
##
## Its ground: within TERRITORY_TILES of its den (its home). It goes for a
## player there, or one who struck it, and nobody past that. With no blow
## given or taken for CALM_TICKS, or its foe past its ground, it gives that
## foe up for BREAK_OFF_TICKS and goes home. By day it walks home and sleeps
## (pose SIT, sight SLEEP_SIGHT), healing a little at a time (HEAL_EVERY):
## the only place it heals. A party that creeps in gets the first blow. By
## night it roams (an Animal predator's wander about its den).
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
## A stun or a knockdown mid-tell (a flank blow, combat's 780 side) breaks
## the move off, its telegraph ended unlanded. Every move logs "[apex]"
## with its end and the bear's hp, never a player's name.

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
## Its moves' numbers (drafts, tuned by playtest): ticks to land, its
## shape, damage, impulse (physics' kg x speed: 140 pushes a player 2
## cells), and the ticks before it may use the move again.
const SWIPE := {"windup": 6, "length": 2.0, "half_angle": 60.0, "damage": 7, "impulse": 140.0, "every": 15}
const SLAM := {"windup": 12, "length": 1.5, "damage": 9, "impulse": 100.0, "down": 15, "every": 50}
const CHARGE := {"roar": 8, "cells": 6, "from": 3, "damage": 8, "impulse": 140.0, "every": 80}

## The den: where it spawned (its home).
var den := NO_TILE
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
var _roared_fight := false
var _roared_half := false
var _was_night := false
var _hooked := false


func _ready() -> void:
	super()
	den = home if home != NO_TILE else tile


func _sim_tick() -> void:
	if not _hooked:
		_hooked = true
		World.rush_ended.connect(_on_rush_ended)
	if den == NO_TILE:
		den = tile
	_dusk()
	if _tend_move():
		return
	if asleep:
		var foe := _struck_by()
		if foe == null:
			foe = _nearest_visible_target()
		if foe == null:
			pose = Pose.SIT
			if World.tick % HEAL_EVERY == 0 and hp < max_hp:
				hp += 1
			return
		_wake()
	elif not _is_night() and target == null and alert != Alert.FIGHTING and (_blow_tick < 0 or World.tick - _blow_tick > CALM_TICKS):
		if World.distance(tile, den) <= 1:
			_sleep()
			return
		if World.tick >= next_move_tick:
			_idle_step(den)  # Home for the day.
		return
	super()
	if target == null:
		_roared_fight = false


## Whether it is night where it stands (Animal's NIGHT_LIGHT), always day
## indoors.
func _is_night() -> bool:
	return World.fields.outdoor and DayNight.daylight(DayNight.now()) < NIGHT_LIGHT


## It roars at nightfall, awake.
func _dusk() -> void:
	var night := _is_night()
	if night and not _was_night and not asleep:
		_roar("dusk")
	_was_night = night


func _sleep() -> void:
	asleep = true
	pose = Pose.SIT
	sight_range = SLEEP_SIGHT
	print("[apex] %s sleeps at its den %s (%d/%d)" % [_kind(), den, hp, max_hp])


func _wake() -> void:
	asleep = false
	pose = Pose.STAND
	sight_range = int(Monster.kinds().get(_kind(), {}).get("sight_range", 8))
	_roar("waking")


func _roar(why: String) -> void:
	_cry(&"roar", ROAR_REACH)
	print("[apex] %s roars (%s) at %s (%d/%d)" % [_kind(), why, tile, hp, max_hp])


func _kind() -> String:
	return str(spawn_spec.get("kind", "great_bear"))


## Always bold: its own ground is its fight (Animal's boldness by night or
## pack is a wolf's).
func _settle_bold() -> void:
	_bold = true
	temper = Temper.BOLD
	wander_radius = maxi(_roam, 6) if _is_night() else DEN_RADIUS


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
	_blow_tick = -1
	print("[apex] %s breaks off (%s) at %s (%d/%d)" % [_kind(), why, tile, hp, max_hp])


func note_struck(by: GridEntity) -> void:
	super(by)
	_blow_tick = World.tick
	if asleep:
		_wake()
	if not _roared_half and hp * 2 < max_hp:
		_roared_half = true
		_roar("half")


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
	if d <= 1:
		if World.tick >= _next_slam and _foes_beside() >= 2:
			var ring := {"kind": "ring", "origin": [tile.x, tile.y], "facing": [facing.x, facing.y],
				"length": float(SLAM["length"]), "inner": 0.0}  # Every cell beside it (combat's).
			_begin("slam", ring, int(SLAM["windup"]))
			_next_slam = World.tick + int(SLAM["every"])
			return true
		if World.tick >= _next_swipe:
			_begin("swipe", Telegraph.cone(tile, Vector2(facing), float(SWIPE["length"]), float(SWIPE["half_angle"])), int(SWIPE["windup"]))
			_next_swipe = World.tick + int(SWIPE["every"])
		return true  # Between blows it stands its ground: no blow without a tell.
	if d >= int(CHARGE["from"]) and d <= int(CHARGE["cells"]) and World.tick >= _next_charge:
		var toward := Vector2(target.tile - tile).normalized()
		var shape := Telegraph.line(tile, toward, float(CHARGE["cells"]), 1)
		if target.tile in World.telegraph_cells(shape):
			_begin("charge", shape, int(CHARGE["roar"]))
			_move["toward"] = toward
			_next_charge = World.tick + int(CHARGE["every"])
			return true
	return false


func _foes_beside() -> int:
	var count := 0
	for each in World.sought():
		if each != self and World.distance(tile, each.tile) <= 1 and each.hp > 0:
			count += 1
	return count


func _begin(move: String, shape: Dictionary, ticks: int) -> void:
	var id := World.telegraph(self, move, shape, ticks)
	if id == 0:
		return
	_move = {"move": move, "telegraph": id, "lands": World.tick + ticks, "shape": shape, "toward": Vector2(facing), "from": World.tick}
	_cry(StringName(move), TELL_REACH)


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
			var struck := _hit_cells(cells, int(SWIPE["damage"]))
			World.sweep(self, _move["toward"], float(SWIPE["half_angle"]) * 2.0, int(ceil(float(SWIPE["length"]))), {"impulse": float(SWIPE["impulse"])})
			World.end_telegraph(id, true)
			_log_move(move, "landed on %d" % struck if struck > 0 else "dodged")
		"slam":
			var hit := _bodies(cells)
			_hit_cells(cells, int(SLAM["damage"]))
			World.sweep(self, _move["toward"], 360.0, 1, {"impulse": float(SLAM["impulse"])})
			for each in hit:
				if is_instance_valid(each) and each.spawned:
					World.knock_down(each, self, int(SLAM["down"]))
			World.end_telegraph(id, true)
			_log_move(move, "landed on %d" % hit.size() if not hit.is_empty() else "dodged")
		"charge":
			World.end_telegraph(id, true)
			if World.rush(self, _move["toward"], int(CHARGE["cells"]), {"blow": {"impulse": float(CHARGE["impulse"])}}):
				_move = {"move": "rush"}
				return true
			_log_move(move, "no room")
	_move = {}
	return true


## A charge's rush over: the body it met takes the blow; none met, it is
## winded.
func _on_rush_ended(entity: GridEntity, reason: String, _at: Vector2i, result: Dictionary) -> void:
	if entity != self or _move.get("move", "") != "rush":
		return
	_move = {}
	var hit := 0
	for each: Variant in result.get("struck", []):
		var met: Variant = each.get("body") if each is Dictionary else null
		if met is GridEntity and is_instance_valid(met) and met != self and (met as GridEntity).spawned:
			World.damage(met, int(CHARGE["damage"]), self, &"attack")
			hit += 1
	if hit > 0:
		_blow_tick = World.tick
		_log_move("charge", "landed on %d (%s)" % [hit, reason])
	else:
		stamina = 0  # Winded (597): the opening.
		winded = true
		_log_move("charge", "dodged (%s)" % reason)


## The bodies on [param cells] but its own.
func _bodies(cells: Array[Vector2i]) -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	for each in World.entities():
		if each != self and each.spawned and each.hp > 0 and each.max_hp > 0 and each.tile in cells:
			out.append(each)
	return out


## [param damage] to each body on [param cells]; how many.
func _hit_cells(cells: Array[Vector2i], damage: int) -> int:
	var hit := _bodies(cells)
	for each in hit:
		World.damage(each, damage, self, &"attack")
	if not hit.is_empty():
		_blow_tick = World.tick
	return hit.size()


func _log_move(move: String, how: String) -> void:
	print("[apex] %s %s at %s -> %s (%d/%d)" % [_kind(), move, tile, how, hp, max_hp])
