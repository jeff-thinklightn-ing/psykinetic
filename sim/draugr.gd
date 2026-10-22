class_name Draugr
extends Monster
## The barrow's draugr (decision 548; Jeff's docs/lore/crypt.md, the
## coordinator's rulings): he talks first, and for gold offers a pact, a
## fight in his lair at the deal the gold buys (573: 20, 50 or 100 gold for
## 5, 10 or 15 charges), his level that deal's and one more for each charge
## the players in his zone hold when it begins; the living coming in while
## it is on give him half his most again (living_came). Beaten, he yields (at
## 1 hp, never dies) and the players in his lair are blessed (World.bless,
## Main's barrow_won, 544 and 573); then he rests, and the barrow's dead lie still, till he rises
## again (RISE_DAYS). Per challenger: he rises from his rest for each new
## pact, and his rest runs on. Server only; to a client he is a monster.
##
## Seated (awake, the curse on) he fights nobody unless struck. The first
## player into his lair shuts his Hall (hall_door) and is asked why they
## came and to return the stolen gold, nothing more (573 amended, Jeff's
## words). Under the least deal, or struck unasked, he fights at his own
## level; beaten so (his "death") he gives his respect, blesses nobody and
## is laid to rest. The Hall opens when it is settled. Resting he lies still,
## struck or not, till a pact raises him. A pact is lost when the challenger
## dies (not while they lie downed and may be raised), or leaves the lair:
## he heals and keeps the gold.
##
## His talk is npc's offer contract (talks, offers_for, accept_offer,
## offer_spoken, offer_withdrawn): Main's speaker lookup reads it.

enum State { SEATED, PACT, AT_REST }

## The deals when economy.json gives none (return.field.deals, 573): the
## gold a step costs and the charges it gives, the highest step the gold
## reaches taken; their names are Main's barrow_won's.
const DEALS: Array[Dictionary] = [{"name": "easy", "gold": 20, "charges": 5},
	{"name": "normal", "gold": 50, "charges": 10}, {"name": "hard", "gold": 100, "charges": 15}]
## His hp and blows at each deal, times his kind's; and the dead he raises
## in his lair to fight beside him (0, 1 or 2 since decision 561).
const SCALE := {"easy": 1.0, "normal": 1.5, "hard": 2.0}
const RETINUE := {"easy": 0, "normal": 1, "hard": 2}
## His level past the deal's (573, enemy-ai's side; drafts for Jeff): each
## charge held in his zone at a pact's start adds CHARGE_SCALE to his hp and
## blows, and each CHARGES_PER_RISEN one more of the dead, MOST_MORE_RISEN
## at most.
const CHARGE_SCALE := 0.05
const CHARGES_PER_RISEN := 10
const MOST_MORE_RISEN := 3
## How far round him the dead rise (cells), on free floor of his lair in
## his sight: round the dais, not behind a pillar (580; 2 before).
const RETINUE_REACH := 3
## The living come in while a pact is on: this much of his most back.
const LIVING_HEAL := 0.5
## Game days he rests once laid to rest (a rules number, Jeff's to move).
const RISE_DAYS := 3
## How near a player comes before he speaks first (cells, in his lair).
const HEARING_TILES := 5
## A player this far off has left: he speaks to them again when they come back.
const GONE_TILES := 12
## How often, resting, he stills any of the dead that stirred (a respawn).
const STILL_EVERY_TICKS := 20

## His words, Jeff's own (573 amended): he asks why one entered, then what
## he asks of them, and explains nothing more (the deals are a puzzle).
const ASKED := "Why have you entered my Hall, %s?"
const WORDS := "Return the gold your people stole from this place, when you do that you may leave."
const WON := "...you have honored the pact, I shall give you the power to cheat death"
const RESPECT := "...warrior, you have my respect."
## Ticks between his question and his asking (a pause).
const ASK_DELAY_TICKS := 30
## His mind in the fight (603, enemy-ai's side; combat's moves, Jeff's
## words): drafts. At BACK_OFF_STAMINA or under (after the spin) he backs
## off till no longer winded; his dead rise in waves as his hp passes
## WAVES (and one at each back-off); he spins at 2 or more foes the sweep
## would catch, or 1 that struck him twice within STRUCK_TWICE_TICKS; he
## throws at a foe THROW_NEAR to THROW_FAR off with none beside him; he
## charges to his thrown axe; disarmed, his fists.
const BACK_OFF_STAMINA := 10
const WAVES: Array[float] = [0.75, 0.5, 0.25]
const SPIN_EVERY_TICKS := 60
const THROW_EVERY_TICKS := 100
const THROW_NEAR := 4
const THROW_FAR := 8
const STRUCK_TWICE_TICKS := 30
const TITLE := "Face the draugr"

var state := State.SEATED
## The pact's: whose it is (a player id), at what deal (its name), and the
## charges held in his zone when it began.
var challenger_id := ""
var difficulty := ""
var charges_met := 0
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
## His Hall shut on a visit; whom he asked, and when he asks them (tick).
var hall_shut := false
## The fight (603): the dead still to rise, the waves passed, when he may
## spin or throw next, whether he is backing off, when he was struck.
var _risen_left := 0
var _waves_passed := 0
var _next_spin := 0
var _next_throw := 0
var backing_off := false
var _struck_at: Array[int] = []
var _asking := ""
var _ask_at := -1

signal offer_spoken(player_id: String, offer: Dictionary)
signal offer_withdrawn(player_id: String)
## His Hall's door (573 amended; dungeon shuts or opens its edges): shut
## (false) when the first player comes into his lair while he sits, open
## (true) when it is settled: his pact won or lost, or the unpaid fight
## ended, or nobody living left in his lair.
signal hall_door(open: bool)
## A line he says unasked (Main's plain speech).
signal said(text: String)


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
	_open_hall()  # His zone asleep: nobody in his Hall.
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
	if Net.is_authority() and amount > 0:
		_struck_at.append(World.tick)
		while not _struck_at.is_empty() and World.tick - _struck_at[0] > STRUCK_TWICE_TICKS:
			_struck_at.pop_front()
		_wave_due()


# --- The fight (603, enemy-ai's side) --------------------------------------------------

## His choice each fighting tick (Monster._special_tick), the first that
## applies: back off when spent, spin, charge to his axe or throw it; else
## (false) he closes and strikes as any monster, with his fists if disarmed
## (combat's). Nothing while one of his moves runs (World.boss_busy), and
## nothing at all before combat's moves exist.
func _special_tick() -> bool:
	if not World.has_method("try_spin") or target == null:
		return false
	if bool(World.call("boss_busy", self)):
		return true
	if stamina <= BACK_OFF_STAMINA or backing_off and bool(World.call("is_winded", self)):
		if not backing_off:
			backing_off = true
			_raise_wave()  # The dead cover him while he gets his breath.
		if World.tick >= next_move_tick:
			_step_back()
		return true
	backing_off = false
	var winded := bool(World.call("is_winded", self))
	var foes := 0
	for each: Variant in World.call("spin_targets", self):
		if each is GridEntity and threatens(each):
			foes += 1
	var struck_twice := _struck_at.size() >= 2
	if not winded and World.tick >= _next_spin and (foes >= 2 or foes == 1 and struck_twice):
		if bool(World.call("try_spin", self)):
			_next_spin = World.tick + SPIN_EVERY_TICKS
			_struck_at.clear()
			return true
	var axe: Dictionary = World.call("axe_state", self)
	if str(axe.get("where", "")) == "ground" and not bool(World.call("is_disarmed", self)):
		if bool(World.call("try_axe_charge", self)):
			return true
	if str(axe.get("where", "")) == "hand" and not winded and World.tick >= _next_throw and not _foe_beside():
		var d := World.distance(tile, target.tile)
		if d >= THROW_NEAR and d <= THROW_FAR and World.call("axe_line_hit", self, target.tile) == target:
			if bool(World.call("try_axe_throw", self, target.tile)):
				_next_throw = World.tick + THROW_EVERY_TICKS
				return true
	return false


## Whether a foe stands beside him (a throw then waits for the blow).
func _foe_beside() -> bool:
	for entity in World.sought():
		if World.distance(tile, entity.tile) <= 1 and threatens(entity):
			return true
	return false


## A wave due: his hp past the next of WAVES raises its share of the dead
## still to rise.
func _wave_due() -> void:
	if state != State.PACT:
		return
	while _waves_passed < WAVES.size() and float(hp) <= float(max_hp) * WAVES[_waves_passed]:
		_waves_passed += 1
		_raise_wave()


## The next of his dead: their share of those left over the waves to come
## (all left at the last), at least one while any are left.
func _raise_wave() -> void:
	if _risen_left <= 0:
		return
	var waves_left := maxi(WAVES.size() - _waves_passed + 1, 1)
	var count := mini(ceili(float(_risen_left) / waves_left), _risen_left)
	_risen_left -= count
	_raise_retinue(count)


# --- Talk (npc's offer contract) ------------------------------------------------------

## His offer to [param player_id]: the pact, unless he is in another's.
func offers_for(player_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == State.PACT:
		return out  # A pact is on (theirs or another's): no more words.
	var steps: Array = deals().map(func(each: Dictionary) -> int: return int(each["gold"]))
	out.append({"id": "deal:%d" % id, "kind": "deal", "title": TITLE, "words": WORDS,
		"what": {"offering": steps[0], "least": steps[0], "most": steps[-1], "steps": steps},
		"accept": "give", "cost": steps[0]})
	return out


## [param player] says yes to his offer with [param gold]: under the least
## deal he refuses; else the gold is his, and the pact begins at the deal
## it buys (the highest step it reaches).
func accept_offer(player: Player, offer: Dictionary, gold: int) -> Dictionary:
	var deal := deal_for(gold)
	if state == State.PACT:
		return {"ok": false, "say": "I am bound in another's pact. Wait.", "line": ""}
	if not str(offer.get("id", "")).begins_with("deal:"):
		return {"ok": false, "say": "", "line": ""}
	if gold <= 0:
		return {"ok": false, "say": "", "line": ""}
	if gold > World.gold_of(player.player_id):
		return {"ok": false, "say": "You have not so much.", "line": ""}
	World.add_gold(player.player_id, -gold, "the draugr's pact")
	if deal.is_empty():
		# Under the least deal (573 amended): he keeps it and attacks, at his
		# kind's own level; beaten, he gives his respect and nothing more.
		_provoked = player
		target = player
		return {"ok": true, "say": "", "line": "%s gives the draugr %d gold, too little: he attacks." % [player.name, gold]}
	start_pact(player, str(deal["name"]))
	return {"ok": true, "say": "", "line": "%s gives the draugr %d gold and takes up his pact for %d risings." % [player.name, gold, int(deal["charges"])]}


## His deals, least first (economy.json return.field.deals, 573; DEALS when
## it gives none).
static func deals() -> Array:
	var rules: Variant = Production.read_rules().get("return", {})
	var field: Variant = rules.get("field", {}) if rules is Dictionary else {}
	var given := Economy.deals(field) if field is Dictionary else []
	return given if not given.is_empty() else DEALS.duplicate()


## The deal [param gold] buys: the highest step it reaches; {} under the
## least.
static func deal_for(gold: int) -> Dictionary:
	var best := {}
	for each: Dictionary in deals():
		if gold >= int(each.get("gold", 0)):
			best = each
	return best


## Speaks first to a player come near him in his lair (once a visit), when
## he has an offer for them.
func _speak() -> void:
	_tend_hall()
	for entity in World.sought():
		if not entity is Player:
			continue
		var player_id := (entity as Player).player_id
		var d := World.distance(tile, entity.tile)
		if d > GONE_TILES:
			_spoken_to.erase(player_id)
		elif d <= HEARING_TILES and _in_lair(entity) and not _spoken_to.has(player_id) and player_id != _asking:
			var offers := offers_for(player_id)
			if not offers.is_empty():
				_spoken_to[player_id] = true
				offer_spoken.emit(player_id, offers[0])


## His Hall on a visit (573 amended): the first player into his lair while
## he sits shuts it, is asked why they came, and after ASK_DELAY_TICKS is
## told what he asks of them (his offer's words); it opens again when nobody
## living (downed counts as living) is left in his lair.
func _tend_hall() -> void:
	if not hall_shut:
		if state != State.SEATED:
			return
		for entity in World.sought():
			if entity is Player and entity.hp > 0 and _in_lair(entity):
				hall_shut = true
				_asking = (entity as Player).player_id
				_ask_at = World.tick + ASK_DELAY_TICKS
				hall_door.emit(false)
				said.emit(ASKED % entity.name)
				return
		return
	if _asking != "" and World.tick >= _ask_at:
		var offers := offers_for(_asking)
		if not offers.is_empty():
			_spoken_to[_asking] = true
			offer_spoken.emit(_asking, offers[0])
		_asking = ""
	for entity in World.sought():
		if entity is Player and entity.hp > 0 and entity.spawned and _in_lair(entity):
			return
	_open_hall()


func _open_hall() -> void:
	if hall_shut:
		hall_shut = false
		_asking = ""
		hall_door.emit(true)


# --- The pact -------------------------------------------------------------------------

## The pact begins with [param player] at [param level]: he rises (from his
## rest too), grows to it, and raises its dead beside him.
func start_pact(player: Player, level: String) -> void:
	state = State.PACT
	challenger_id = player.player_id
	difficulty = level
	_provoked = null
	charges_met = maxi(int(World.charges_in.call(zone if zone != "" else World.zone.name)), 0) if World.charges_in.is_valid() else 0
	var scale := float(SCALE.get(level, 1.0)) + CHARGE_SCALE * charges_met
	max_hp = roundi(_base_hp * scale)
	hp = max_hp
	attack_damage = roundi(_base_damage * scale)
	down_until = World.tick
	for each in World.sought():
		if each is Player:
			offer_withdrawn.emit((each as Player).player_id)  # Nothing stands while he fights.
	# His dead rise in waves through the fight (603), not all at once.
	_risen_left = int(RETINUE.get(level, 0)) + mini(charges_met / CHARGES_PER_RISEN, MOST_MORE_RISEN)
	_waves_passed = 0
	_next_spin = World.tick
	_next_throw = World.tick
	backing_off = false
	_struck_at.clear()


## [param player] come into his zone (Main's _living_came, 573): in a pact
## he draws breath from them, half his most back at once; his level stays.
func living_came(player: Player) -> void:
	if state != State.PACT or player == null:
		return
	hp = mini(hp + roundi(max_hp * LIVING_HEAL), max_hp)


## Whether the pact is still on: its challenger in his lair, standing or
## lying downed (Mortally Wounded: while they may yet be raised he turns to
## the others, or waits, and does not heal); lost when they die or leave.
func _pact_holds() -> bool:
	var player := _challenger()
	return player != null and player.spawned and player.hp > 0 and _in_lair(player)


## The pact lost (the challenger fallen, or gone): he heals, keeps the gold,
## and sits again (or rests on, if he was resting).
func _end_pact() -> void:
	challenger_id = ""
	difficulty = ""
	charges_met = 0
	_restore()
	_open_hall()
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
		said.emit(WON)
		# His battle axe for the winners, at his feet (603: his row's
		# "yields", items' Monster.yielded); never on a lost or unpaid fight.
		if has_method("yielded"):
			call("yielded")
		if World.bless.is_valid():
			World.bless.call(ids, difficulty)  # Main's (544).
		challenger_id = ""
		difficulty = ""
		charges_met = 0
	else:
		# Unpaid (573 amended): his "death". He yields as ever, blesses
		# nobody, gives his respect and is laid to rest.
		said.emit(RESPECT)
	if rests_until <= World.steps:
		rests_until = World.steps + RISE_DAYS * DayNight.day_steps
		_keep_prop("rests_until", rests_until)
	_rest_over(rests_until)
	_open_hall()
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
	for zone_name in _rest_zones():
		World.dead_rest.erase(zone_name)
	if state == State.AT_REST:
		state = State.SEATED
		down_until = World.tick
	for entity in World.monsters():
		if entity != self and entity is Monster and _is_dead(entity):
			(entity as Monster).rise()


## Laid to rest: every one of the barrow's dead in his zone lies still
## (those in the zones his level "stills" as each next thinks, 580).
func _still_the_dead() -> void:
	_stilled_tick = World.tick
	for entity in World.monsters():
		if entity != self and entity is Monster and _is_dead(entity) and not (entity as Monster).laid \
				and not entity in _retinue:
			(entity as Monster)._mind_the_rest()


## His rest, till World.steps [param until], laid over his side's dead in
## his own zone and each his level "stills" (World.dead_rest, decision 580;
## saved, so it holds in a zone asleep, unloaded or after a restart).
func _rest_over(until: int) -> void:
	var side := _factions().of_kind(World.kind_of(self))
	for zone_name in _rest_zones():
		World.dead_rest[zone_name] = {"until": until, "side": side}


## His own zone and those his level's "stills" names.
func _rest_zones() -> Array[String]:
	var out: Array[String] = [World.zone.name]
	var named: Variant = _zone_config().get("stills", [])
	if named is Array:
		for each: Variant in named:
			if str(each) not in out:
				out.append(str(each))
	return out


## [param count] of the dead raised round him in his lair (World.spawn_spec).
func _raise_retinue(count: int) -> void:
	if count <= 0 or not World.spawn_spec.is_valid():
		return
	var spots: Array[Vector2i] = []
	for dy in range(-RETINUE_REACH, RETINUE_REACH + 1):
		for dx in range(-RETINUE_REACH, RETINUE_REACH + 1):
			var at := tile + Vector2i(dx, dy)
			if at != tile and _in_lair_cell(at) and World.is_free(at) and World.has_line_of_sight(tile, at):
				spots.append(at)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return World.distance(tile, a) < World.distance(tile, b))
	for i in mini(count, spots.size()):
		var spec := Level._spec_for("monster_skeleton", Level.MONSTER_TYPES)
		if spec.is_empty():
			return
		spec["name"] = "%sRisen%d" % [name, _retinue.size() + 1]
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
