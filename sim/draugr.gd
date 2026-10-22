class_name Draugr
extends Monster
## The barrow's draugr (decision 548; Jeff's docs/lore/crypt.md, the
## coordinator's rulings): he talks first, and for gold offers a pact, a
## fight in his lair at a difficulty the gold sets; beaten, he yields (at
## 1 hp, never dies) and the players in his lair are blessed (Main.bless,
## 544); then he rests, and the barrow's dead lie still, till he rises
## again (RISE_DAYS). Per challenger: he rises from his rest for each new
## pact, and his rest runs on. Server only; to a client he is a monster.
##
## Seated (awake, the curse on) he fights nobody unless struck: then he
## fights back, and yields as ever, but blesses nobody (a fight without the
## pact wins nothing; Jeff's to decide, on his list). Resting he lies still,
## struck or not, till a pact raises him. A pact is lost when the challenger
## falls, or leaves the lair: he heals and keeps the gold.
##
## His talk is npc's offer contract (talks, offers_for, accept_offer,
## offer_spoken, offer_withdrawn): Main's speaker lookup reads it.

enum State { SEATED, PACT, AT_REST }

## The difficulties by measures of the offering given (1, 2, 3 or more):
## Main.bless's names, 5, 10 or 15 uses (economy.json return.field.uses).
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
## His hp and blows at each, times his kind's; and the dead he raises in
## his lair to fight beside him (0, 1 or 2 since decision 561).
const SCALE := {"easy": 1.0, "normal": 1.5, "hard": 2.0}
const RETINUE := {"easy": 0, "normal": 1, "hard": 2}
## Game days he rests once laid to rest (a rules number, Jeff's to move).
const RISE_DAYS := 3
## How near a player comes before he speaks first (cells, in his lair).
const HEARING_TILES := 5
## A player this far off has left: he speaks to them again when they come back.
const GONE_TILES := 12
## The offering when economy.json gives none (return.offering).
const OFFERING := 8
## How often, resting, he stills any of the dead that stirred (a respawn).
const STILL_EVERY_TICKS := 20

const WORDS := "You bring the living's gold. Give it, and face me: win, and the dead will let you go. One measure for an easy fight, two for a harder, three for the hardest."
const TITLE := "Face the draugr"

var state := State.SEATED
## The pact's: whose it is (a player id), at what difficulty.
var challenger_id := ""
var difficulty := ""
## World.steps when he rises from his rest (-1: not resting); kept in his
## props, so a restart finds him resting.
var rests_until := -1
## Who would have been blessed at the last yield (bless unset, a test).
var blessed_last: Array = []
var _base_hp := 0
var _base_damage := 0
var _retinue: Array[GridEntity] = []
var _spoken_to: Dictionary[String, bool] = {}
var _stilled_tick := -100000

signal offer_spoken(player_id: String, offer: Dictionary)
signal offer_withdrawn(player_id: String)


func _ready() -> void:
	super()
	talks = true
	if not Net.is_authority():
		return
	_base_hp = max_hp
	_base_damage = attack_damage
	var kept: Variant = spawn_spec.get("props", {}).get("rests_until") if spawn_spec.get("props") is Dictionary else null
	if kept != null and int(kept) > World.steps:
		rests_until = int(kept)
		state = State.AT_REST


func _sim_tick() -> void:
	_speak()
	match state:
		State.PACT:
			if not _pact_holds():
				_end_pact()
		State.AT_REST:
			if World.steps >= rests_until:
				_rise_again()
			elif World.tick - _stilled_tick >= STILL_EVERY_TICKS:
				_still_the_dead()
	if state == State.AT_REST:
		_lie_still()  # Laid to rest: he lies still till a pact wakes him, struck or not.
		return
	super()


func _world_tick(seconds: float) -> void:
	super(seconds)
	if state == State.PACT:
		_end_pact()  # Nobody near: the pact is forfeit.
	if state == State.AT_REST and World.steps >= rests_until:
		_rise_again()


## Whether he would fight [param entity] (decision 551, enemy-ai's side):
## in his lair, his pact's party, or one that struck him; resting, nobody.
func threatens(entity: GridEntity) -> bool:
	if state == State.AT_REST or not _may_threaten(entity) or not _in_lair(entity):
		return false
	if entity == _provoked or entity == _struck_by():
		return true
	return state == State.PACT and entity in _party()


## Whom he fights: in a pact, the challenger and theirs in his lair; else
## one that struck him, while in his lair.
func _nearest_visible_target() -> GridEntity:
	var struck := _struck_by()
	if struck != null and _may_fight(struck):
		_provoked = struck
	if _provoked != null and (not is_instance_valid(_provoked) or not _provoked.spawned or _provoked.hp <= 0
			or World.is_downed(_provoked) or not _in_lair(_provoked)):
		_provoked = null
	if state == State.PACT:
		var nearest: GridEntity = null
		for entity in _party():
			if _in_lair(entity) and (nearest == null or World.distance(tile, entity.tile) < World.distance(tile, nearest.tile)):
				nearest = entity
		if nearest != null:
			return nearest
	return _provoked


## Beaten to 1 hp or less: he yields, never dies.
func _world_damaged(amount: int, cause: StringName) -> void:
	if Net.is_authority() and hp <= 1:
		hp = 1
		super(amount, cause)
		_yield()
		return
	super(amount, cause)


# --- Talk (npc's offer contract) ------------------------------------------------------

## His offer to [param player_id]: the pact, unless he is in another's.
func offers_for(player_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == State.PACT:
		return out  # A pact is on (theirs or another's): no more words.
	var offering := offering()
	out.append({"id": "deal:%d" % id, "kind": "deal", "title": TITLE, "words": WORDS,
		"what": {"offering": offering, "least": offering, "most": offering * DIFFICULTIES.size()},
		"accept": "give", "cost": offering})
	return out


## [param player] says yes to his offer with [param gold]: under the
## offering he refuses; else the gold is his, and the pact begins at the
## difficulty its measures set.
func accept_offer(player: Player, offer: Dictionary, gold: int) -> Dictionary:
	var offering := offering()
	if state == State.PACT:
		return {"ok": false, "say": "I am bound in another's pact. Wait.", "line": ""}
	if not str(offer.get("id", "")).begins_with("deal:"):
		return {"ok": false, "say": "", "line": ""}
	if gold < offering:
		return {"ok": false, "say": "Not for so little. The living's measure: %d gold at the least." % offering, "line": ""}
	if gold > World.gold_of(player.player_id):
		return {"ok": false, "say": "You have not so much.", "line": ""}
	World.add_gold(player.player_id, -gold, "the draugr's pact")
	start_pact(player, difficulty_for(gold))
	var says := {"easy": "So be it. Stand and face me.", "normal": "Good. The dead rise beside me.",
		"hard": "The hardest, then. Few have stood it."}
	return {"ok": true, "say": says[difficulty], "line": "%s gives the draugr %d gold and takes up his pact (%s)." % [player.name, gold, difficulty]}


## The offering a measure of gold is (economy.json return.offering).
static func offering() -> int:
	var rules: Variant = Production.read_rules().get("return", {})
	return maxi(int(rules.get("offering", OFFERING)) if rules is Dictionary else OFFERING, 1)


## The difficulty [param gold] buys: a measure easy, two normal, three or
## more hard.
static func difficulty_for(gold: int) -> String:
	var measures := clampi(gold / offering(), 1, DIFFICULTIES.size())
	return DIFFICULTIES[measures - 1]


## Speaks first to a player come near him in his lair (once a visit), when
## he has an offer for them.
func _speak() -> void:
	for entity in World.sought():
		if not entity is Player:
			continue
		var player_id := (entity as Player).player_id
		var d := World.distance(tile, entity.tile)
		if d > GONE_TILES:
			_spoken_to.erase(player_id)
		elif d <= HEARING_TILES and _in_lair(entity) and not _spoken_to.has(player_id):
			var offers := offers_for(player_id)
			if not offers.is_empty():
				_spoken_to[player_id] = true
				offer_spoken.emit(player_id, offers[0])


# --- The pact -------------------------------------------------------------------------

## The pact begins with [param player] at [param level]: he rises (from his
## rest too), grows to it, and raises its dead beside him.
func start_pact(player: Player, level: String) -> void:
	state = State.PACT
	challenger_id = player.player_id
	difficulty = level
	_provoked = null
	var scale := float(SCALE[level])
	max_hp = roundi(_base_hp * scale)
	hp = max_hp
	attack_damage = roundi(_base_damage * scale)
	down_until = World.tick
	for each in World.sought():
		if each is Player:
			offer_withdrawn.emit((each as Player).player_id)  # Nothing stands while he fights.
	_raise_retinue(int(RETINUE[level]))


## Whether the pact is still on: its challenger standing in his lair.
func _pact_holds() -> bool:
	var player := _challenger()
	return player != null and player.hp > 0 and not World.is_downed(player) and _in_lair(player)


## The pact lost (the challenger fallen, or gone): he heals, keeps the gold,
## and sits again (or rests on, if he was resting).
func _end_pact() -> void:
	challenger_id = ""
	difficulty = ""
	_restore()
	state = State.AT_REST if rests_until > World.steps else State.SEATED


## Beaten: in a pact, the players in his lair are blessed and he is laid
## to rest (his rest runs on if he was resting already); unpaid, nobody is.
func _yield() -> void:
	target = null
	_provoked = null
	_drop_windup()
	if state == State.PACT:
		var ids: Array = []
		for entity in World.sought():
			if entity is Player and _in_lair(entity) and entity.hp > 0:
				ids.append((entity as Player).player_id)
		blessed_last = ids
		if World.bless.is_valid():
			World.bless.call(ids, difficulty)  # Main's (544).
		challenger_id = ""
		difficulty = ""
		if rests_until <= World.steps:
			rests_until = World.steps + RISE_DAYS * DayNight.day_steps
			_keep_prop("rests_until", rests_until)
	_restore()
	if rests_until > World.steps:
		state = State.AT_REST
		_lie_still()
		_still_the_dead()
	else:
		state = State.SEATED


## His kind's hp and blows again, healed, his raised dead gone.
func _restore() -> void:
	max_hp = _base_hp
	hp = max_hp
	attack_damage = _base_damage
	target = null
	alert = Alert.IDLE
	_returning = true
	for raised_one in _retinue:
		if is_instance_valid(raised_one) and raised_one.spawned:
			World.despawn(raised_one)
	_retinue.clear()


## His rest over: the curse renews, and the dead rise.
func _rise_again() -> void:
	rests_until = -1
	_keep_prop("rests_until", -1)
	if state == State.AT_REST:
		state = State.SEATED
		down_until = World.tick
	for entity in World.monsters():
		if entity != self and entity is Monster and _is_dead(entity):
			(entity as Monster).rise()


## Laid to rest: every one of the barrow's dead in his zone lies still.
func _still_the_dead() -> void:
	_stilled_tick = World.tick
	for entity in World.monsters():
		if entity != self and entity is Monster and _is_dead(entity) and not (entity as Monster).laid \
				and not entity in _retinue:
			(entity as Monster).lay_down()


## [param count] of the dead raised round him in his lair (World.spawn_spec).
func _raise_retinue(count: int) -> void:
	if count <= 0 or not World.spawn_spec.is_valid():
		return
	var spots: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var at := tile + Vector2i(dx, dy)
			if at != tile and _in_lair_cell(at) and World.is_free(at):
				spots.append(at)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return World.distance(tile, a) < World.distance(tile, b))
	for i in mini(count, spots.size()):
		var spec := Level._spec_for("monster_skeleton", Level.MONSTER_TYPES)
		if spec.is_empty():
			return
		spec["name"] = "%sRisen%d" % [name, i + 1]
		spec["tile"] = spots[i]
		spec["idle"] = {"mode": "guard"}
		var risen: Variant = World.spawn_spec.call(spec)
		if risen is GridEntity:
			_retinue.append(risen)


func _challenger() -> Player:
	for entity in World.sought():
		if entity is Player and (entity as Player).player_id == challenger_id:
			return entity
	return null


## The challenger and their companion.
func _party() -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	var player := _challenger()
	if player == null:
		return out
	out.append(player)
	for entity in World.sought():
		if entity is Companion and (entity as Companion).keeper == player and not World.is_downed(entity):
			out.append(entity)
	return out


func _in_lair(entity: GridEntity) -> bool:
	return _in_lair_cell(entity.tile)


## His lair: the room he keeps (his level's anchor round him); anywhere
## within his leash when his level gives none.
func _in_lair_cell(cell: Vector2i) -> bool:
	if _room.has_area():
		return _room.has_point(cell)
	return World.distance(home, cell) <= leash


func _is_dead(entity: GridEntity) -> bool:
	return _factions().same_side(_factions().of_kind(World.kind_of(entity)), _factions().of_kind(World.kind_of(self)))
