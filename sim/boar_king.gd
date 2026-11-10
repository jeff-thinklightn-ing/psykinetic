class_name BoarKing
extends Animal
## The boar king (780 amended (16); enemy-ai's boar king design, the
## coordinator's approval, 11-08; Jeff, 11-03: "Move the boar king to the
## boar's lair in the forest ... Higher level players can push him back into
## the lair by clearing"). An apex (his row's "apex", "lair" and "escort":
## Apex lays him and his sounder of boars): not the bear's wall of claws nor
## the old grey's pack mind, but the forest's battering ram.
##
## - The charge (told): at a foe "from" to "cells" off, his head down, a
##   snort ("snort", heard TELL_REACH) and a told line through them, "past"
##   cells beyond (World.telegraph "charge", flank-marked). Then he runs it
##   (World.rush; cried "charge"). The first foe met takes "damage" and is
##   knocked aside off the line ("impulse", across it).
## - The overrun: a charge that meets nobody runs to its end and he skids
##   "skid" ticks, standing, turning nobody (cried "skid", heard by players
##   only): his flank open. One that ends against a tree, a rock or a wall
##   stuns him "stun" ticks instead (World._stun_for, cause &"crash"): the
##   bigger opening, made by the one who dodged with a tree at their back.
## - Up close, his charge ready (playtest's second run: a foe kept close
##   never saw one): he stands "paw" ticks on a snort, pawing, then backs off
##   facing them a cell each "back_step" ticks, and charges once "from"
##   clear (no second snort). Followed or cornered, "back" ticks out or no
##   step away, the short charge ("short" cells) from where he stands.
## - The hook: close, his kind's HEAVY blow (Monster's wound-up strike),
##   slow and light (his row's attack_ticks 30, 3 hp): the charge is his
##   threat.
## - His sounder, one at a time (the coordinator's ruling after playtest's
##   run): one boar of it engages his target (engager); the rest keep a ring
##   2 to 3 off (Animal._sounder_tick). A charge that hits sends the engager
##   in behind it ("join_tiles"); a dodged one sends nobody, and while he
##   charges, skids or lies stunned by a crash no boar strikes: the dodge's
##   opening is the player's, whole.
## - Never into a downing (the coordinator): no charge at a foe under
##   "not_below" of their hp, and at such a foe one of them strikes, not
##   three: none of his sounder while he can strike them himself; his
##   charge's hit never takes a player or companion below 1 hp. His hook can
##   down, as any blow.
## - His charge's hit is "damage" in all, its knock-aside's impact part of
##   it; after it no boar strikes for "quiet" ticks, then the one joins.
## - His wallow (the coordinator, after playtest's third run): he never
##   flees; under "wallow_below" of his hp in his lair he walks to his den
##   (Apex's lair heal), biting back at one who struck him beside him, never
##   chasing nor charging; at his wallow, cornered, he fights.
## - The bellow: at a fight's start and at half his hp ("bellow", heard
##   TELL_REACH; told far, BELLOW_REACH, while he is out: World.far_cry).
## Every move logs "[apex]" with his hp, never a player's name.

const TELL_REACH := 8
const BELLOW_REACH := 50
## His charge's defaults, under monsters.json's row "moves" (combat tunes):
## ticks of its tell, its longest line and how far past his foe it runs,
## the nearest foe it is for, damage, the impulse across the line, ticks
## between, the skid's and the crash's ticks, the share of a foe's hp under
## which none is charged, and how near his target a boar of his sounder
## joins.
## His back-off, a foe too close to charge: the paw's ticks stood still on
## the snort, the most ticks he backs off, ticks a cell backing (slower than
## his walk), and the short charge's cells when he can't get "from" clear.
const CHARGE := {"windup": 12, "cells": 7, "past": 2, "from": 3, "damage": 6, "impulse": 140.0, "every": 60,
	"skid": 15, "stun": 25, "not_below": 0.33, "join_tiles": 8, "paw": 6, "back": 14, "back_step": 5.0, "short": 2,
	"quiet": 20, "wallow_below": 0.15}
## (And: ticks after a charge's hit no boar of his sounder strikes, then the
## one joins; the share of his hp under which he breaks off to his wallow.)
var charge := CHARGE.duplicate()

## His den (his home where laid), his lair's door to walk to, and whether he
## is out in his land (Apex's, as the bear's and the old grey's).
var den := NO_TILE
var apex_goal := NO_TILE
var apex_out := false
## The move under way: {move, telegraph, lands, toward, cells, from}; the
## run {move: "rush"} till rush_ended; the skid {move: "skid"}.
var _move := {}
var _next_charge := 0
var _hooked := false
var _bellowed_fight := false
var _bellowed_half := false
## The boar of his sounder at his target (engager), kept while it lives.
var _engager: Animal = null
## After a charge's hit: no boar strikes till _quiet_until; the engager
## joins at _join_at (-1: none due).
var _quiet_until := 0
var _join_at := -1
## Who struck him last (his bite back on his way to his wallow).
var _bit_by: GridEntity = null
## His charge's told cells while it is told or run ([] else): his sounder
## stands off them (Animal._ring).
var told_line: Array[Vector2i] = []
## Why his last charge check missed (_try_charge; the log's reason).
var _miss := ""
## His wallow: the foe he broke off from, and whether they stood by his den
## ("far": away and alone instead, the far side of his roam).
var _wallow_from: GridEntity = null
var _wallow_far := false
## Cells off a foe he goes to, the far way, before standing (left alone).
const WALLOW_CLEAR := 6


func _ready() -> void:
	super()
	_hook()
	den = home if home != NO_TILE else tile
	var moves: Variant = Monster.kinds().get(_kind(), {}).get("moves", {})
	if moves is Dictionary and moves.get("charge") is Dictionary:
		for key: String in moves["charge"]:
			if charge.has(key):
				charge[key] = moves["charge"][key]
	_no_flee()


## He never flees (Monster's flee_below): below "wallow_below" he goes to his
## wallow instead (playtest's run: at 7/60 he hovered off a foe for 30 s).
func _no_flee() -> void:
	for t: int in flee_below:
		flee_below[t] = 0.0
	dread_flee_below = 0.0


func _hook() -> void:
	if not _hooked:
		_hooked = true
		World.rush_ended.connect(_on_rush_ended)
		World.entity_died.connect(_on_died)


func _sim_tick() -> void:
	_hook()
	if den == NO_TILE:
		den = tile
	if _join_at >= 0 and World.tick >= _join_at:
		_join_at = -1
		_sounder_charge()
	if _tend_move():
		return
	if _to_wallow():
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
	if target == null:
		_bellowed_fight = false


func _kind() -> String:
	return str(spawn_spec.get("kind", "boar_king"))


## Always bold, never sleeps: boars are about by day and by night.
func _settle_bold() -> void:
	_bold = true
	temper = Temper.BOLD
	wander_radius = maxi(_roam, 4)
	_no_flee()


## Below "wallow_below" of his hp, in his lair (out, Apex's beaten back takes
## him home first): no new fight; he walks to his den, where Apex's lair heal
## makes him whole left alone. On the way he bites back at whoever struck him
## if they are beside him, never chasing nor charging. At his wallow,
## cornered, he fights as ever. True while it holds him.
func _to_wallow() -> bool:
	if apex_out or hp <= 0 or float(hp) >= float(charge["wallow_below"]) * float(max_hp):
		_wallow_from = null
		_wallow_far = false
		return false
	if target != null and _wallow_from == null:
		# Where to: his den, unless the foe stands by it (within 3), when
		# going home is no retreat: away and alone instead, the far way.
		_wallow_from = target
		_wallow_far = World.distance(target.tile, den) <= 3
		_log_move("wallow", "breaks off" + (", the far way (a foe by his den)" if _wallow_far else ""))
	var foe := _wallow_from if _wallow_from != null and is_instance_valid(_wallow_from) and _wallow_from.spawned \
			and _wallow_from.hp > 0 else null
	if not _wallow_far and World.distance(tile, den) <= 1:
		return false  # At his wallow: cornered, he fights.
	if _wallow_far and foe != null and World.distance(tile, foe.tile) <= 1 and _away_from(foe, true) == Vector2i.ZERO:
		return false  # The far way, and no step away: cornered, he fights.
	target = null
	_foe = null
	_drop_windup()
	if World.is_stunned(self):
		return true
	var by := _bit_by
	if by != null and is_instance_valid(by) and by.spawned and by.hp > 0 and World.distance(tile, by.tile) <= 1 \
			and World.tick >= next_attack_tick:
		_world_set_facing(Senses.way_toward(tile, by.tile))
		if World.try_attack(self, by):
			next_attack_tick = World.tick + World.attack_ticks_of(self)
			_log_move("wallow", "bites back")
			return true
	if World.tick >= next_move_tick:
		move_ticks = _pace
		if _wallow_far:
			# Each step away from them, within his roam of his den, never nearer
			# (never through their reach); WALLOW_CLEAR off, he stands, alone.
			if foe != null and World.distance(tile, foe.tile) < WALLOW_CLEAR:
				var way := _away_from(foe, true)
				if way != Vector2i.ZERO:
					World.try_move(self, way)
		elif not _idle_step(den, GreatBear.WALK_SEARCH_TILES):
			next_move_tick = World.tick + 5
	return true


## His sounder: the living boars following him (Apex's escort).
func sounder() -> Array[Animal]:
	var out: Array[Animal] = []
	for entity in World.monsters():
		if entity is Animal and (entity as Animal).escort_lead == self and entity.spawned and entity.hp > 0:
			out.append(entity)
	return out


## Whether [param foe] may be charged: not under "not_below" of their hp.
func may_charge(foe: GridEntity) -> bool:
	return foe != null and (foe.max_hp <= 0 or float(foe.hp) >= float(charge["not_below"]) * float(foe.max_hp))


## Whether he is charging (its tell or its run).
func charging_now() -> bool:
	return str(_move.get("move", "")) in ["charge", "rush"]


## His move windows, when the fight is his and no boar of his sounder
## strikes (the coordinator, after playtest's hold run: his boars did 30 of
## 45 hp while he pawed): pawing, backing off, telling, running, skidding or
## stunned.
func in_move_window() -> bool:
	return str(_move.get("move", "")) in ["paw", "back", "charge", "rush", "skid"] or World.is_stunned(self)


## His opening after a dodge: skidding, or stunned by a crash.
func open_now() -> bool:
	return str(_move.get("move", "")) == "skid" or World.is_stunned(self) and stun_cause == &"crash"


## The one boar of his sounder that may be at [param foe] now, or null: none
## while he charges or lies open (a dodge's opening is the player's), none at
## a foe under "not_below" while he can strike them himself; else the
## nearest of his sounder to them, kept while it lives and follows him.
func engager(foe: GridEntity) -> Animal:
	if foe == null or World.tick < _quiet_until or in_move_window():
		return null
	if not may_charge(foe) and (World.distance(tile, foe.tile) <= 1 or _in_strike_reach(foe)):
		return null
	if _engager == null or not is_instance_valid(_engager) or not _engager.spawned or _engager.hp <= 0 			or _engager.escort_lead != self:
		_engager = null
		var best := 1 << 30
		for boar in sounder():
			var d := World.distance(boar.tile, foe.tile)
			if d < best:
				best = d
				_engager = boar
	return _engager


## Whether [param boar] of his sounder may go at [param foe] now.
func may_engage(boar: Animal, foe: GridEntity) -> bool:
	return engager(foe) == boar


## His charge at a player or companion in its reach; else Monster's fight
## (his hook close, closing in). Deer he leaves be.
func _special_tick() -> bool:
	if target == null or target is Animal:
		return false
	if not _bellowed_fight:
		_bellowed_fight = true
		_bellow("fight")
	var d := World.distance(tile, target.tile)
	if World.tick < _next_charge or not may_charge(target):
		return false
	if d >= int(charge["from"]) and d <= int(charge["cells"]):
		return _try_charge(d + int(charge["past"]), true)
	if d < int(charge["from"]):
		_begin_back_off()
		return true
	return false


## His charge at [param run] cells, if its line takes in his target where
## they stand (decision 810); [param snort]: its tell cried (not after a
## back-off's, cried already).
func _try_charge(run: int, snort: bool) -> bool:
	# Drawn to the cell a blow on them strikes (a free body's centre), not
	# their tile: the two part when a body stands off its cell's middle
	# (playtest's hold run: twice clear, no line, a paw again).
	var at := World.struck_cell(target)
	if at == tile:
		_miss = "struck at his own cell"
		return false
	var toward := Vector2(at - tile).normalized()
	var cells := World.telegraph_cells(Telegraph.line(tile, toward, float(run), 1))
	if not at in cells:
		var longer := Telegraph.line(tile, toward, float(run + 1), 1)
		if not at in World.telegraph_cells(longer):
			_miss = _why_missed(at, longer)
			return false
		run += 1
	var shape := Telegraph.line(tile, toward, float(run), 1)
	_next_charge = World.tick + int(charge["every"])
	_begin_charge(shape, toward, run, snort)
	return _move.get("move", "") == "charge"


## Why a told line missed [param at] (logged at a back-off's end, playtest's
## to read): out of its length, or blocked at a cell, by the terrain or a
## body; no names.
func _why_missed(at: Vector2i, shape: Dictionary) -> String:
	var raw := Telegraph.cells(shape)
	if not at in raw:
		return "struck at %s, its tile %s: off the line's %d cells (%d off)" % [at, target.tile, raw.size(), World.distance(tile, at)]
	for cell in raw:
		if cell == at:
			break
		if not (World.is_walkable(cell) or World.is_water(cell)):
			return "struck at %s, its tile %s: blocked at %s by the ground" % [at, target.tile, cell]
	return "struck at %s, its tile %s: no clear sight to it" % [at, target.tile]


## A foe too close to charge: he stands "paw" ticks, snorting and pawing,
## then backs off facing them (playtest's run: a foe kept close never saw a
## charge, only his bite).
func _begin_back_off() -> void:
	_next_charge = World.tick + int(charge["every"])
	World.face(self, Senses.way_toward(tile, target.tile))
	_move = {"move": "paw", "telegraph": 0, "lands": World.tick + int(charge["paw"]), "from": World.tick}
	_cry(&"snort", TELL_REACH)
	_log_move("paw", "backs off to charge")


## Backing off: a step a "back_step" ticks away from his target, facing
## them, till "from" clear, then his charge; "back" ticks out, or no step
## away (cornered, or followed step for step), the short charge from where
## he stands.
func _tend_back_off() -> bool:
	if not is_instance_valid(target) or not target.spawned or target.hp <= 0 or target is Animal \
			or not may_charge(target):
		_end_back_off("its foe gone or low")
		return false
	var d := World.distance(tile, World.struck_cell(target))
	var out: bool = World.tick >= int(_move["lands"]) or bool(_move.get("stuck", false))
	if d >= int(charge["from"]) or out:
		var run := d + int(charge["past"]) if d >= int(charge["from"]) else maxi(int(charge["short"]), d + 1)
		var how := "clear, %d off" % d if d >= int(charge["from"]) else "short, %d off" % d
		if _try_charge(run, false):
			move_ticks = _pace
			_log_move("back", how)
			return true
		if out:
			# No line in his time: no second paw till his charge comes round again.
			_end_back_off("%s, no line: %s" % [how, _miss])
			_next_charge = World.tick + int(charge["every"])
			return false
		# Clear but no line (a tree or a rock between): a step more for one.
		if not _move.get("lined", false):
			_move["lined"] = true
			_log_move("back", "%s, no line yet: %s" % [how, _miss])
	if World.tick >= next_move_tick and not World.is_stunned(self):
		move_ticks = float(charge["back_step"])
		var way := _away_from(target)
		if way == Vector2i.ZERO or not World.try_move(self, way):
			_move["stuck"] = true
		else:
			# A step faces its way (World.try_move) and World.face waits out the
			# step: backing, he keeps his face on them (the view's back_off).
			_world_set_facing(Senses.way_toward(tile, target.tile))
	return true


func _end_back_off(why: String) -> void:
	_move = {}
	move_ticks = _pace
	_log_move("back", why)


## The step farthest from [param foe], straight back or aside, never nearer;
## ZERO if none. [param in_roam]: only within his roam of his den.
func _away_from(foe: GridEntity, in_roam := false) -> Vector2i:
	var d := World.distance(tile, foe.tile)
	var best := Vector2i.ZERO
	var best_d := d
	var best_len := Vector2(tile - foe.tile).length()
	for way: Vector2i in World.DIRECTIONS:
		var cell := tile + way
		if not (World.is_walkable(cell) and World.is_free(cell)) or World.is_link_cell(cell):
			continue
		if in_roam and World.distance(cell, den) > wander_radius * 2 + 2:
			continue
		var cd := World.distance(cell, foe.tile)
		var clen := Vector2(cell - foe.tile).length()
		if cd > best_d or cd == best_d and clen > best_len + 0.01:
			best = way
			best_d = cd
			best_len = clen
	return best


func _begin_charge(shape: Dictionary, toward: Vector2, run: int, snort := true) -> void:
	var ticks := int(charge["windup"])
	var id := World.telegraph(self, "charge", shape, ticks, true)  # Flank-marked: a blow from behind staggers him.
	if id == 0:
		return
	World.face(self, Senses.way_toward(tile, target.tile))
	_move = {"move": "charge", "telegraph": id, "lands": World.tick + ticks, "toward": toward, "cells": run, "from": World.tick}
	told_line = World.telegraph_cells(shape)
	if snort:
		_cry(&"snort", TELL_REACH)
	_log_move("charge", "tell, lands in %d ticks" % ticks)


## The move under way: true while it holds him (the tell, the run, the skid).
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
		move_ticks = _pace
		return false
	if move == "back":
		return _tend_back_off()
	if World.tick < int(_move["lands"]):
		return true
	match move:
		"charge":
			# His told line stays down until the run stops (810 amended (2)): ended in _on_rush_ended.
			var told := int(_move["telegraph"])
			var toward: Vector2 = _move["toward"]
			var cells := int(_move["cells"])
			_move = {}
			if World.rush(self, toward, cells, {"blow": {"impulse": 0.0}, "within": World.told_cells(told)}):  # Never past its told end (780 amended (27)).
				_move = {"move": "rush", "toward": toward, "telegraph": told}
				_cry(&"charge", NOISE_CHARGE)
				return true
			World.end_telegraph(told, false)
			_log_move("charge", "no room")
		"skid":
			_move = {}
			_log_move("skid", "over")
			return false
		"paw":
			_move = {"move": "back", "telegraph": 0, "lands": World.tick + int(charge["back"]), "from": World.tick}
			return _tend_back_off()
	return true


## His run over: the foe met is struck and knocked aside; none met, he
## skids, or against the terrain he is stunned; then his sounder joins.
func _on_rush_ended(entity: GridEntity, reason: String, _at: Vector2i, result: Dictionary) -> void:
	if entity != self or _move.get("move", "") != "rush":
		return
	var toward: Vector2 = _move.get("toward", Vector2(facing))
	World.end_telegraph(int(_move.get("telegraph", 0)), true)  # Landed, as ever; his told line down till now (810 amended (2)).
	_move = {}
	var hit := 0
	for each: Variant in result.get("struck", []):
		var met: Variant = each.get("body") if each is Dictionary else null
		if not (met is GridEntity and is_instance_valid(met) and met != self and (met as GridEntity).spawned):
			continue
		if met is Animal and (met as Animal).escort_lead == self:
			continue  # His own sounder: shouldered past.
		_gore(met as GridEntity, toward)
		hit += 1
	if hit > 0:
		_log_move("charge", "landed on %d (%s)" % [hit, reason])
	elif reason == "wall":
		World._stun_for(self, int(charge["stun"]), &"crash")
		_log_move("charge", "crashed, stunned %d ticks" % int(charge["stun"]))
	else:
		_move = {"move": "skid", "telegraph": 0, "lands": World.tick + int(charge["skid"]), "from": World.tick}
		_cry(&"skid", 0)
		_log_move("charge", "dodged (%s), skids %d ticks" % [reason, int(charge["skid"])])
	if hit > 0:
		# The charge is the hit, not a pile-on's start: no boar strikes for
		# "quiet" ticks, then the one joins. A dodged one sends nobody.
		_quiet_until = World.tick + int(charge["quiet"])
		_join_at = _quiet_until


## [param body] met by his run: its damage, never below 1 hp for a player or
## companion, and knocked aside off the line.
func _gore(body: GridEntity, toward: Vector2) -> void:
	var damage := int(charge["damage"])
	if not body is Monster:
		damage = mini(damage, body.hp - 1)
	# Left low, not thrown into anything (a knock's impact could down them);
	# else knocked aside first, its impact part of the charge's "damage", not
	# on top (playtest's run: 6 and 2 of impact, 8).
	var knock := body is Monster or body.max_hp <= 0 \
			or float(body.hp - damage) >= float(charge["not_below"]) * float(body.max_hp)
	if knock:
		var aside := Vector2(-toward.y, toward.x)
		var cell := body.tile + Vector2i(roundi(aside.x), roundi(aside.y))
		if not (World.is_walkable(cell) and World.is_free(cell)):
			aside = -aside
		var slid := World.launch(self, body, aside, float(charge["impulse"]))
		damage = maxi(0, damage - int(slid.get("impact_damage", 0)))
	if damage > 0 and is_instance_valid(body) and body.spawned and body.hp > 0:
		World.damage(body, damage, self, &"attack")


## His charge's hit: the engager of his sounder, near his target, charges in
## behind it, unless they are under "not_below" of their hp.
func _sounder_charge() -> void:
	if not is_instance_valid(target) or not target.spawned or target.hp <= 0:
		return
	if not may_charge(target):
		_log_move("charge", "his sounder held (a foe low)")
		return
	var sent := 0
	var boar := engager(target)
	if boar != null and World.distance(boar.tile, target.tile) <= int(charge["join_tiles"]):
		boar.target = target
		boar._foe = target
		boar._charge_until = World.tick + CHARGE_TICKS
		boar._burst_until = World.tick + BURST_TICKS
		boar.next_attack_tick = mini(boar.next_attack_tick, World.tick)
		boar.next_move_tick = mini(boar.next_move_tick, World.tick)
		boar._cry(&"charge", NOISE_CHARGE)
		sent += 1
	if sent > 0:
		_log_move("charge", "one of his sounder joins")


func _bellow(why: String) -> void:
	_cry(&"bellow", TELL_REACH)
	if apex_out:
		World.far_cry.emit(self, &"bellow", BELLOW_REACH)
	_log_move("bellow", why)


func note_struck(by: GridEntity) -> void:
	super(by)
	_bit_by = by
	Apex.struck(self, by)  # His wait to go out starts again (780 amended (13)); by, one of its fighters (780 amended (20)).
	if not _bellowed_half and hp * 2 < max_hp:
		_bellowed_half = true
		_bellow("half")


func _on_died(entity: GridEntity, cause: StringName) -> void:
	if entity == self:
		print("[apex] %s falls (%s) at %s" % [_kind(), cause, tile])
		Apex.died(self)


func _log_move(move: String, how: String) -> void:
	print("[apex] %s %s at %s -> %s (%d/%d)" % [_kind(), move, tile, how, hp, max_hp])
