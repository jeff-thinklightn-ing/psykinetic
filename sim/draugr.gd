class_name Draugr
extends Monster
## The barrow's draugr (decision 548; Jeff's docs/lore/crypt.md, the
## coordinator's rulings): he talks first, and for gold offers a pact, a
## fight in his lair at the deal the gold buys (573: 10, 50 or 100 gold for
## 5, 10 or 15 charges), his level that deal's and one more for each charge
## the players in his zone hold when it begins; the living coming in while
## it is on give him half his most again (living_came). Beaten, he yields (at
## 1 hp, never dies) and the players in his lair are blessed (World.bless,
## Main's barrow_won, 544 and 573); then he rests, and the barrow's dead lie still, till he rises
## again (rise_s). Per challenger: he rises from his rest for each new
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
const DEALS: Array[Dictionary] = [{"name": "easy", "gold": 10, "charges": 5},
	{"name": "normal", "gold": 50, "charges": 10}, {"name": "hard", "gold": 100, "charges": 15}]
## His hp and blows at each deal, times his kind's (the dead he raises
## beside him: his waves, DEFAULT_WAVES).
const SCALE := {"easy": 1.0, "normal": 1.5, "hard": 2.0}
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
## Real seconds he rests once laid to rest (714 amended (2); Jeff, no
## scarcity in the barrow: 300, were 3 game days; F7's draugr.rise_s).
static var rise_s := 300.0
const RISE_S_SPAN := [30.0, 3600.0]
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
## Said as he first takes up a fight, once a fight (the band, 714;
## Jeff's words): the robbers broke his barrow, and the living are all one to him.
const ANGER := "Thieves in my barrow, thieves in my hall. You are all the same to me."
## Ticks between his question and his asking (a pause).
const ASK_DELAY_TICKS := 30
## His Hall waits for the first one's companion (573 amended; Jeff: "door
## closes to quickly companion can't get in"): while she is coming along
## within DOOR_WAIT_CELLS of his lair, no farther off than COMING_TICKS
## ago, up to DOOR_WAIT_TICKS, then it shuts whether she is in or not.
const DOOR_WAIT_CELLS := 6
const DOOR_WAIT_TICKS := 50
const COMING_TICKS := 10
## His mind in the fight (603, enemy-ai's side; combat's moves, Jeff's
## words): drafts. At BACK_OFF_STAMINA or under (after the spin) he backs
## off till no longer winded; his dead rise in waves as his hp passes
## each wave's "at" (and the next wave early at a back-off); he spins at 2 or more foes the sweep
## would catch, or 1 that struck him twice within STRUCK_TWICE_TICKS; he
## throws at a foe THROW_NEAR to THROW_FAR off with no player beside him (a
## companion holding him does not stop it, 603 amended, enemy-ai's side: the challenger
## standing back while she tanks him), his target or any player so placed,
## never at one closing on him (nearer within CLOSING_TICKS, the
## coordinator's ruling: a thrown axe always leaves a real charge to make); he charges to
## his thrown axe; disarmed, his fists.
const BACK_OFF_STAMINA := 10
## His waves of the dead, the fight's difficulty (Jeff: "the waves are what
## determines the difficulty of the encounter"): his row's "waves", one
## entry a wave, each {"at": his hp share it comes at, "count": {deal: how
## many}, "kinds": the kinds that rise (in turn), "per_player": how many
## more for each player past the first in his lair at the pact's start}.
## Without the row's, DEFAULT_WAVES: today's numbers (normal's one dead at
## three quarters, hard's two at three quarters and a half). The charges'
## extra dead (CHARGES_PER_RISEN) go each to the wave with fewest, the
## earliest first.
const DEFAULT_WAVES: Array[Dictionary] = [
	{"at": 0.75, "count": {"easy": 0, "normal": 1, "hard": 1}, "kinds": ["skeleton"], "per_player": 0},
	{"at": 0.5, "count": {"easy": 0, "normal": 0, "hard": 1}, "kinds": ["skeleton"], "per_player": 0},
	{"at": 0.25, "count": {"easy": 0, "normal": 0, "hard": 0}, "kinds": ["skeleton"], "per_player": 0}]
const SPIN_EVERY_TICKS := 60
const THROW_EVERY_TICKS := 100
const THROW_NEAR := 6
const THROW_FAR := 8
const STRUCK_TWICE_TICKS := 30
const CLOSING_TICKS := 10
## Disarmed (combat's stopped charge; his axe bound to him, Jeff), he walks
## back for it, at once with nobody beside him, else after this many blows
## of his fists (a draft: a foe staying on him buys a few blows, not the
## fight).
const FISTS_BEFORE_AXE := 3
const TITLE := "Face the draugr"
## A payer's again (548 amended, npc's record; Jeff: "as long as you paid
## once you get unlimited attempts"): the offer's title and his words.
const AGAIN_TITLE := "Face the draugr again"
const AGAIN_WORDS := "Your gold is paid. Come, then."
## The refusal, always offered (Jeff on v0.1.192: "got stuck in draugr
## room because i dont have gold and can't attack him", then "instead of
## no just put the word "refuse""): a free deal whose one button provokes
## him, as striking him (Shift and a click) does: he says REFUSED and
## laughs, fights at his own level, and beaten gives his respect and the
## Hall opens (573 amended). First of his offers when the purse is under
## his least deal (today's panel shows the first deal), else last.
const REFUSE_TITLE := "Refuse"
const REFUSE_WORDS := "Refuse him, and he fights you for it."
## His words on being refused (Jeff's own).
const REFUSED := "Then I'll take it from you by force!"

var state := State.SEATED
## At rest he is gone (573 amended (4); Jeff: "he is otherworldly, he
## probably leaves a pile of his clothes, his crown, his axe on the ground"):
## no body, holding no cell (World.vacate), touched by nothing; his remains
## (art-kit's prop.draugr_remains) lie at pile_at, turned pile_facing (a
## prop's facing, Client3D's), and a click or E there hears his rest words.
## He comes back at his seat when his rest is over. Replicated, all three.
var gone := false:
	set(value):
		gone = value
		holds_cell = not value
var pile_at := NO_TILE
var pile_facing := Vector2i(0, 1)
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
## The dead still to rise in this pact: each wave's {"at", "count", "kinds"}.
var _waves: Array[Dictionary] = []
var _risen_left := 0
var _waves_passed := 0
var _next_spin := 0
var _next_throw := 0
## Each foe he might throw at: {entity: [its last cell, till when it counts
## as closing on him]} (603 amended, enemy-ai's side: his target's alone before).
var _foes_were := {}
var backing_off := false
## His fist blows since he was disarmed, and the attack he last counted.
var _fists := 0
var _fist_seen := -1
var _struck_at: Array[int] = []
var _asking := ""
var _ask_at := -1
## Whether he has said ANGER this fight (_restore clears it).
var _angered := false
## The tick the first one came into his lair while the Hall waits for
## their companion (-1: not waiting), and each companion's cells from his
## lair over the last COMING_TICKS (instance id -> {tick: cells}).
var _door_wait_from := -1
var _coming := {}

signal offer_spoken(player_id: String, offer: Dictionary)
signal offer_withdrawn(player_id: String)
## His Hall's door (573 amended; dungeon shuts or opens its edges): shut
## (false) when the first player comes into his lair while he sits, open
## (true) when it is settled: his pact won or lost, or the unpaid fight
## ended, or nobody living left in his lair.
signal hall_door(open: bool)
## A line he says unasked (Main's plain speech).
signal said(text: String)
## The barrow's seal (666, enemy-ai's side; dungeon's Hall below the
## Ossuary): true while any OSSUARY_KINDS one spawned in his zone stands
## (hp left, not laid at rest, not his risen), false once every one is down;
## said at his first tick and on each change. Main holds the Hall's door.
signal ossuary_sealed(sealed: bool)

const OSSUARY_KINDS: Array[String] = ["skeleton", "skeleton_guard"]
## What ossuary_sealed last said: -1 nothing yet, else 0 or 1.
var _ossuary := -1


func _ready() -> void:
	super()
	talks = true
	replicate("gone")
	replicate("pile_at")
	replicate("pile_facing")
	if not Net.is_authority():
		return
	_base_hp = max_hp
	_base_damage = attack_damage
	var kept: Variant = spawn_spec.get("props", {}).get("rests_until") if spawn_spec.get("props") is Dictionary else null
	if kept == null or int(kept) <= World.steps:
		# His rest as World.dead_rest holds it over his zone (saved; 573 amended (3)): a room reset, a
		# restart or a regeneration puts him back from the level's table, whose props never had it.
		var rest: Dictionary = World.dead_rest.get(zone if zone != "" else World.zone.name, {})
		if not rest.is_empty() and str(rest.get("side", "")) == _factions().of_kind(str(spawn_spec.get("kind", "draugr"))):
			kept = int(rest.get("until", 0))
			if rest.has("pile"):
				_keep_prop("pile", rest["pile"])  # His remains where he fell (573 amended (4)).
				_keep_prop("pile_facing", rest.get("pile_facing", [0, 1]))
	if kept != null and int(kept) > World.steps:
		rests_until = int(kept)
		_keep_prop("rests_until", rests_until)
		state = State.AT_REST
		# Gone, his remains where he fell (573 amended (4)); an old rest
		# without them leaves them at his seat. He holds no cell from his
		# first tick (_stay_gone: World.spawn gives him his seat's).
		var props: Dictionary = spawn_spec.get("props", {})
		pile_at = _cell(props.get("pile"), home if home != NO_TILE else tile)
		pile_facing = _cell(props.get("pile_facing"), Vector2i(0, 1))
		gone = true
	# What a client may read of him (648, npc's side): seated at his spawn, or at rest, a click talks.
	peaceable = state == State.SEATED or state == State.AT_REST


func _sim_tick() -> void:
	# What a client may read of him (648, npc's side): seated and unprovoked, or at rest (573 amended (3):
	# his rest words), a click or E talks; in a pact, struck or provoked, it strikes.
	peaceable = state == State.SEATED and _provoked == null and _struck_by() == null or state == State.AT_REST
	_tell_ossuary()
	if gone and state != State.AT_REST and not _come_back():
		return  # His rest over, someone on his seat and every cell beside it: he waits, gone.
	if state != State.AT_REST:
		_speak()  # At rest he is silent (573 amended (3)): no offer, no hall ask.
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
		_stay_gone()  # At rest he is gone till his rest runs out (573 amended (4)).
		return
	super()
	if target != null and not _angered and state != State.AT_REST:
		_angered = true
		said.emit(ANGER)


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


## Beaten to 1 hp or less: he yields, never dies. Laid to rest, he has
## yielded already: struck on, he lies at 1, silent (combat's clip had him
## giving his respect over and over).
func _world_damaged(amount: int, cause: StringName) -> void:
	if Net.is_authority() and hp <= 1:
		hp = 1
		super(amount, cause)
		if state != State.AT_REST:
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
	var toward: Vector2i = World.call("melee_way", self, target) if World.free_body(target) else Senses.way_toward(tile, target.tile)  # A free body by its centre (699).
	World.face(self, toward)  # Toward his target (his spin strikes the whole disc: 603 amended (7)).
	var foes := 0
	for each: Variant in World.call("spin_targets", self):
		if each is GridEntity and each != self and (each is Player or each is Companion) and not _is_dead(each):
			foes += 1  # The living in his sweep, his challenger's party or not; never his own dead.
	var struck_twice := _struck_at.size() >= 2
	if not winded and World.tick >= _next_spin and (foes >= 2 or foes == 1 and struck_twice):
		if bool(World.call("try_spin", self)):
			_next_spin = World.tick + SPIN_EVERY_TICKS
			_struck_at.clear()
			return true
	var axe: Dictionary = World.call("axe_state", self)
	if bool(World.call("is_disarmed", self)) and World.has_method("recall_axe"):
		if _walk_for_axe(axe):
			return true
	else:
		_fists = 0
		_fist_seen = -1
	if str(axe.get("where", "")) == "ground" and not bool(World.call("is_disarmed", self)):
		if bool(World.call("try_axe_charge", self)):
			return true
	var at := _throw_mark()
	if str(axe.get("where", "")) == "hand" and not winded and World.tick >= _next_throw and not _foe_beside(true) and at != null:
		if bool(World.call("try_axe_throw", self, at.tile)):
			_next_throw = World.tick + THROW_EVERY_TICKS
			return true
	return false


## Whom he would throw at (603 amended, enemy-ai's side): his target, else the nearest
## player, THROW_NEAR to THROW_FAR off, not closing on him, his throw's line
## meeting them first; null for none. Each foe's step is watched here (its
## own step nearer him is its closing; his toward it is not).
func _throw_mark() -> GridEntity:
	var marks: Array[GridEntity] = [target]
	for entity in World.sought():
		if entity is Player and entity != target and World.distance(tile, entity.tile) <= THROW_FAR + 2:
			marks.append(entity)
	var seen := {}
	var best: GridEntity = null
	for foe in marks:
		var was: Array = _foes_were.get(foe, [foe.tile, 0])
		var until: int = was[1]
		var d := World.distance(tile, foe.tile)
		if foe.tile != was[0] and d < World.distance(tile, was[0]):
			until = World.tick + CLOSING_TICKS
		seen[foe] = [foe.tile, until]
		if best == null and World.tick >= until and d >= THROW_NEAR and d <= THROW_FAR 				and World.call("axe_line_hit", self, foe.tile) == foe:
			best = foe
	_foes_were = seen
	return best


## Disarmed: a step for his axe where it lies (combat's World takes it up
## for him once he is on or beside it), at once with no foe beside him,
## else once he has struck FISTS_BEFORE_AXE blows with his fists; true while
## he goes (no blow), false to fight on with his fists.
func _walk_for_axe(axe: Dictionary) -> bool:
	if next_attack_tick != _fist_seen:
		if _fist_seen != -1:
			_fists += 1
		_fist_seen = next_attack_tick
	var cell: Variant = axe.get("cell")
	if not cell is Vector2i or World.distance(tile, cell) <= 1:
		return false
	if _foe_beside() and _fists < FISTS_BEFORE_AXE:
		return false
	if World.tick >= next_move_tick and not _go_to(cell):
		return false
	return true


## Whether a foe stands beside him (a throw then waits for the blow);
## [param players_only]: a player (a companion holding him does not stop
## his throw, 603 amended, enemy-ai's side).
func _foe_beside(players_only := false) -> bool:
	for entity in World.sought():
		if World.distance(tile, entity.tile) <= 1 and entity != self and (entity is Player or entity is Companion and not players_only):
			return true
	return false


## A wave due: his hp past the next wave's "at" raises it.
func _wave_due() -> void:
	if state != State.PACT:
		return
	while _waves_passed < _waves.size() and float(hp) <= float(max_hp) * float(_waves[_waves_passed]["at"]):
		_raise_wave()


## The next of his waves risen (at its hp, or early when he backs off, when
## it then does not come again); nothing once all have.
func _raise_wave() -> void:
	if _waves_passed >= _waves.size():
		return
	var wave := _waves[_waves_passed]
	_waves_passed += 1
	_risen_left -= int(wave["count"])
	_raise_retinue(int(wave["count"]), wave["kinds"])


## This pact's waves from [param table] (his row's "waves") at [param level]
## with [param extra] more dead (the charges') and [param players] in his lair.
static func plan_waves(table: Array, level: String, extra: int, players: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in table:
		if not entry is Dictionary:
			continue
		var counts: Variant = entry.get("count", {})
		var count := int(counts.get(level, 0)) if counts is Dictionary else 0
		count += roundi(float(entry.get("per_player", 0)) * maxi(players - 1, 0))
		var kinds: Array = []
		for kind: Variant in (entry.get("kinds", []) as Array if entry.get("kinds") is Array else []):
			kinds.append(str(kind))
		if kinds.is_empty():
			kinds = ["skeleton"]
		out.append({"at": clampf(float(entry.get("at", 0.0)), 0.0, 1.0), "count": maxi(count, 0), "kinds": kinds})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] > b["at"])
	for i in (extra if not out.is_empty() else 0):
		var fewest := 0
		for w in out.size():
			if out[w]["count"] < out[fewest]["count"]:
				fewest = w
		out[fewest]["count"] += 1
	return out


# --- Talk (npc's offer contract) ------------------------------------------------------

## His offer to [param player_id]: the pact, unless he is in another's.
func offers_for(player_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == State.PACT:
		return out  # A pact is on (theirs or another's): no more words.
	if state == State.AT_REST:
		return out  # At rest no pact is bought (573 amended (3)); a click hears rest_words.
	var refuse := {"id": "deal:%d:refuse" % id, "kind": "deal", "title": REFUSE_TITLE, "words": REFUSE_WORDS,
		"what": {"level": "refuse", "steps": []}, "accept": "take", "cost": 0}
	var paid := _paid(player_id)
	if not paid.is_empty():
		# Paid once (548 amended): the fight again at the level paid for, no gold; no gold
		# deal while it stands, so none pays twice.
		out.append({"id": "deal:%d:again" % id, "kind": "deal", "title": AGAIN_TITLE, "words": AGAIN_WORDS,
			"what": {"level": str(paid["level"]), "steps": []}, "accept": "take", "cost": 0})
		out.append(refuse)
		return out
	var steps: Array = deals().map(func(each: Dictionary) -> int: return int(each["gold"]))
	var poor := World.gold_of(player_id) < int(steps[0])
	if poor:
		out.append(refuse)  # Too little for the least deal: the refusal first, the deal the panel shows.
	out.append({"id": "deal:%d" % id, "kind": "deal", "title": TITLE, "words": WORDS,
		"what": {"offering": steps[0], "least": steps[0], "most": steps[-1], "steps": steps},
		"accept": "give", "cost": steps[0]})
	if not poor:
		out.append(refuse)
	return out


## [param player] says yes to his offer with [param gold]: under the least
## deal he refuses; else the gold is his, and the pact begins at the deal
## it buys (the highest step it reaches).
func accept_offer(player: Player, offer: Dictionary, gold: int) -> Dictionary:
	var deal := deal_for(gold)
	if state == State.PACT:
		return {"ok": false, "say": "I am bound in another's pact. Wait.", "line": ""}
	if state == State.AT_REST:
		return {"ok": false, "say": "", "line": rest_words()}
	if not str(offer.get("id", "")).begins_with("deal:"):
		return {"ok": false, "say": "", "line": ""}
	if str(offer.get("id", "")).ends_with(":refuse"):
		# Refused: provoked, as a strike would; beaten, his respect, the Hall opened. His line, not ANGER.
		_provoked = player
		target = player
		peaceable = false  # The same tick, for the client (648).
		_angered = true
		said.emit(REFUSED)
		return {"ok": true, "say": "", "line": "%s refuses the draugr. He laughs, and rises to strike." % player.name}
	var paid := _paid(player.player_id)
	if str(offer.get("id", "")).ends_with(":again"):
		if paid.is_empty() or not SCALE.has(str(paid.get("level", ""))):
			return {"ok": false, "say": "", "line": ""}
		start_pact(player, str(paid["level"]))  # Paid once (548 amended): no gold.
		return {"ok": true, "say": "", "line": "%s takes up the draugr's pact again." % player.name}
	if not paid.is_empty():
		return {"ok": false, "say": AGAIN_WORDS, "line": ""}  # A gold deal while one is paid: never twice.
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
	_deal_paid(player.player_id, str(deal["name"]))  # Paid once: every fight after at this level (548 amended).
	return {"ok": true, "say": "", "line": "%s gives the draugr %d gold and takes up his pact for %d risings." % [player.name, gold, int(deal["charges"])]}


## [param player_id]'s paid deal for his zone (548 amended, npc's
## PlayerRecord.paid_deals through Main's World.paid_deal): {"level",
## "paid_step"}, {} for none or without the hook.
func _paid(player_id: String) -> Dictionary:
	var hook: Variant = World.get("paid_deal")
	if not hook is Callable or not (hook as Callable).is_valid() or player_id.is_empty():
		return {}
	var paid: Variant = (hook as Callable).call(player_id, zone if zone != "" else World.zone.name)
	return paid if paid is Dictionary else {}


## Records [param player_id]'s paid deal at [param level] for his zone, or
## erases it ("") (548 amended, Main's World.deal_paid; nothing without it).
func _deal_paid(player_id: String, level: String) -> void:
	var hook: Variant = World.get("deal_paid")
	if hook is Callable and (hook as Callable).is_valid():
		(hook as Callable).call(player_id, zone if zone != "" else World.zone.name, level)


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
## he sits shuts it (once their companion is in, or not coming, or after
## DOOR_WAIT_TICKS: _companion_coming), is asked why they came, and after ASK_DELAY_TICKS is
## told what he asks of them (his offer's words); it opens again when nobody
## living (downed counts as living) is left in his lair.
func _tend_hall() -> void:
	if not hall_shut:
		if state != State.SEATED:
			return
		var first: Player = null
		for entity in World.sought():
			if entity is Player and entity.hp > 0 and _in_lair(entity):
				first = entity
				break
		if first == null:
			_door_wait_from = -1
			_coming.clear()
			return
		if _door_wait_from < 0:
			_door_wait_from = World.tick
		if World.tick - _door_wait_from < DOOR_WAIT_TICKS and _companion_coming(first):
			return
		_door_wait_from = -1
		_coming.clear()
		hall_shut = true
		_asking = first.player_id
		_ask_at = World.tick + ASK_DELAY_TICKS
		hall_door.emit(false)
		said.emit(ASKED % first.name)
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


## Whether [param player]'s companion is on her way into his lair: hers,
## up, outside it and within DOOR_WAIT_CELLS of it, no farther off than
## COMING_TICKS ago; not one told to wait or rest, on an errand, pulling
## back or fleeing (companions' fields, read as they stand).
func _companion_coming(player: Player) -> bool:
	var coming := false
	for entity in World.sought():
		if not entity is Companion:
			continue
		var pet := entity as Companion
		if pet.keeper != player or pet.hp <= 0 or World.is_downed(pet) or _in_lair(pet) or pet.stays_put() 				or not pet.order.is_empty() or not pet.errand.is_empty() or pet.stance == Companion.Stance.PULL_BACK 				or pet.current_intent == Companion.Intent.RETREAT:
			continue
		var cells := _cells_from_lair(pet.tile)
		var seen: Dictionary = _coming.get(pet.get_instance_id(), {})
		for at: int in seen.keys():
			if World.tick - at > COMING_TICKS:
				seen.erase(at)
		var was: int = seen[seen.keys().min()] if not seen.is_empty() else cells  # Her cells COMING_TICKS ago, or since first seen.
		seen[World.tick] = cells
		_coming[pet.get_instance_id()] = seen
		if cells <= DOOR_WAIT_CELLS and cells <= was:
			coming = true
	return coming


## How many cells [param cell] lies outside his lair (0 inside it).
func _cells_from_lair(cell: Vector2i) -> int:
	if not _room.has_area():
		return maxi(0, World.distance(home, cell) - leash)
	var dx := maxi(maxi(_room.position.x - cell.x, cell.x - (_room.end.x - 1)), 0)
	var dy := maxi(maxi(_room.position.y - cell.y, cell.y - (_room.end.y - 1)), 0)
	return maxi(dx, dy)


func _open_hall() -> void:
	if hall_shut:
		hall_shut = false
		_asking = ""
		hall_door.emit(true)


# --- The pact -------------------------------------------------------------------------

## The pact begins with [param player] at [param level]: he rises (from his
## rest too), grows to it, and raises its dead beside him.
func start_pact(player: Player, level: String) -> void:
	print("[draugr] %s: pact taken, %s" % [zone if zone != "" else World.zone.name, level])
	state = State.PACT
	peaceable = false  # The same tick, for the client (648, npc's side).
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
	# His dead rise in waves through the fight (603), not all at once; all
	# at once till combat's moves are in (the waves, a draft for Jeff, ride
	# with the fight).
	var row: Dictionary = Monster.kinds().get(str(spawn_spec.get("kind", "draugr")), {})
	var table: Variant = row.get("waves")
	var players := 0
	for each in World.sought():
		if each is Player and each.hp > 0 and _in_lair(each):
			players += 1
	_waves = plan_waves(table if table is Array and not (table as Array).is_empty() else DEFAULT_WAVES, level,
		mini(charges_met / CHARGES_PER_RISEN, MOST_MORE_RISEN), players)
	_risen_left = 0
	for wave in _waves:
		_risen_left += int(wave["count"])
	_waves_passed = 0
	if not World.has_method("try_spin"):
		while _waves_passed < _waves.size():
			_raise_wave()
	_next_spin = World.tick
	_next_throw = World.tick
	_foes_were.clear()
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


## The admin's "quests reset all <player>" (ui's): what he holds of
## [param player_id] forgotten: his asking them (he asks again) and a pact
## of theirs, ended as lost. The words of what it cleared.
func forget_player(player_id: String) -> PackedStringArray:
	var cleared := PackedStringArray()
	if _spoken_to.erase(player_id):
		cleared.append("asked")
	if _asking == player_id:
		_asking = ""
		_ask_at = -1
	if challenger_id == player_id and not player_id.is_empty():
		_end_pact()
		cleared.append("pact")
	return cleared


## The pact lost (the challenger fallen, or gone): he heals, keeps the gold,
## and sits again (or rests on, if he was resting).
func _end_pact() -> void:
	print("[draugr] %s: pact lost" % (zone if zone != "" else World.zone.name))
	_drop_moves()
	_recall_axe()
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
	_drop_moves()
	_recall_axe()
	if state == State.PACT:
		var ids: Array = []
		for entity in World.sought():
			if entity is Player and _in_lair(entity) and entity.hp > 0:
				ids.append((entity as Player).player_id)
		blessed_last = ids
		for each_id: String in ids:
			if not _paid(each_id).is_empty():
				_deal_paid(each_id, "")  # Won: the paid deal is spent (548 amended).
		print("[draugr] %s: won, %d blessed" % [zone if zone != "" else World.zone.name, ids.size()])
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
		print("[draugr] %s: respect (unpaid, beaten)" % (zone if zone != "" else World.zone.name))
		said.emit(RESPECT)
	if rests_until <= World.steps:
		rests_until = World.steps + rest_steps()
		_keep_prop("rests_until", rests_until)
	if rests_until > World.steps:
		_vanish()
	_rest_over(rests_until)
	_open_hall()
	_restore()
	if rests_until > World.steps:
		state = State.AT_REST
		peaceable = true
		print("[draugr] %s: at rest till step %d" % [zone if zone != "" else World.zone.name, rests_until])
		_still_the_dead()
	else:
		state = State.SEATED


## His fight over (yielded, or the pact lost): a spin, throw or charge under
## way called off, its telegraph ended unlanded, no blow after it (combat's
## World.drop_boss_move, 603 amended (3); before it, nothing). Before
## _recall_axe, which clears a dropped charge's disarmed mark.
func _drop_moves() -> void:
	if World.has_method("drop_boss_move"):
		World.call("drop_boss_move", self)


## His fight over (yielded, or the pact lost): a thrown axe, bound to him,
## back in his hands (combat's World.recall_axe; before it, nothing).
func _recall_axe() -> void:
	if World.has_method("recall_axe"):
		World.call("recall_axe", self)


## His kind's hp and blows again, healed, his raised dead gone.
func _restore() -> void:
	max_hp = _base_hp
	hp = max_hp
	attack_damage = _base_damage
	target = null
	_angered = false
	alert = Alert.IDLE
	_returning = true
	for raised_one in _retinue:
		if is_instance_valid(raised_one) and raised_one.spawned:
			World.despawn(raised_one)
	_retinue.clear()


## Beaten (573 amended (4); Jeff: "when draugr falls i think he should not
## lie down"): he is gone, his remains on the cell he fell on, turned the
## first way (his own first, then on round) whose two side cells, where the
## axe's ends lie (art-kit's measure), are floor with no wall edge between;
## his own way if none is. He is kept at his seat, holding no cell.
func _vanish() -> void:
	pile_at = tile
	pile_facing = _pile_way(tile)
	_keep_prop("pile", [pile_at.x, pile_at.y])
	_keep_prop("pile_facing", [pile_facing.x, pile_facing.y])
	gone = true
	World.vacate(self, home if home != NO_TILE else tile)
	print("[draugr] %s: gone, his remains left" % (zone if zone != "" else World.zone.name))


## The way his remains lie at [param cell] (_vanish): a prop's facing, its
## local +x (the axe head's side) (facing.y, -facing.x).
func _pile_way(cell: Vector2i) -> Vector2i:
	var own := Vector2i(signi(facing.x), 0) if absi(facing.x) >= absi(facing.y) else Vector2i(0, signi(facing.y))
	if own == Vector2i.ZERO:
		own = Vector2i(0, 1)
	var way := own
	for i in 4:
		var side := Vector2i(way.y, -way.x)
		if World.is_walkable(cell + side) and World.is_walkable(cell - side) \
				and World.can_melee(cell, cell + side) and World.can_melee(cell, cell - side):
			return way
		way = Vector2i(-way.y, way.x)
	return own


## At rest: gone, kept at his seat holding no cell (a respawn from the
## level's table put him on it).
func _stay_gone() -> void:
	target = null
	if not gone:
		gone = true
	var seat := home if home != NO_TILE else tile
	if holds_cell or tile != seat:
		World.vacate(self, seat)


## His rest over: back at his seat, or the first free cell beside it (the
## coordinator's), his remains gone; false while every one is taken.
func _come_back() -> bool:
	if not World.hold_cell(self, home if home != NO_TILE else tile):
		return false
	gone = false
	pile_at = NO_TILE
	_keep_prop("pile", null)
	_keep_prop("pile_facing", null)
	if home_facing != Vector2i.ZERO:
		World.face(self, home_facing)
	print("[draugr] %s: he stands again" % (zone if zone != "" else World.zone.name))
	return true


## A saved cell ([x, y], or a Vector2i) read back; [param otherwise] if it is neither.
static func _cell(value: Variant, otherwise: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return otherwise


## Whether he rests (573 amended (3)): laid to rest, silent, no pact.
func resting() -> bool:
	return state == State.AT_REST


## What a click or E on him hears while he rests (573 amended (3)): his
## rest's days left, at least one.
func rest_words() -> String:
	var left := float(rests_until - World.steps)
	if left >= DayNight.day_steps:
		var days := ceili(left / maxf(DayNight.day_steps, 1.0))
		return "He rests. Come back in %d day%s." % [days, "" if days == 1 else "s"]
	var minutes := maxi(1, ceili(left / (60.0 * World.TICK_RATE)))
	return "He rests. Come back in %d minute%s." % [minutes, "" if minutes == 1 else "s"]


## His rest once laid to rest, in world steps (rise_s).
static func rest_steps() -> int:
	return roundi(rise_s * World.TICK_RATE)


## The tuning panel's source "draugr" (714 amended (2)): draugr.rise_s.
static func tuning_value(path: String) -> Variant:
	return rise_s if path == "draugr.rise_s" else null


static func set_tuning_value(path: String, value: Variant) -> bool:
	if path != "draugr.rise_s" or not (value is int or value is float):
		return false
	rise_s = clampf(float(value), RISE_S_SPAN[0], RISE_S_SPAN[1])
	return true


static func tuning_fields() -> Array:
	return [{"path": "draugr.rise_s", "group": "Draugr", "min": RISE_S_SPAN[0], "max": RISE_S_SPAN[1], "owner": "enemy-ai", "takes": "rest"}]


## His rest over: the curse renews, and the dead rise.
func _rise_again() -> void:
	rests_until = -1
	_keep_prop("rests_until", -1)
	for zone_name in _rest_zones():
		World.dead_rest.erase(zone_name)
	if state == State.AT_REST:
		state = State.SEATED
		print("[draugr] %s: his rest is over" % (zone if zone != "" else World.zone.name))
	if gone:
		_come_back()  # Else each tick tries again (_sim_tick).
	for entity in World.monsters():
		if entity != self and entity is Monster and _is_dead(entity):
			(entity as Monster).rise()


## ossuary_sealed when what it says changes (or first): whether any of his
## zone's OSSUARY_KINDS stands.
func _tell_ossuary() -> void:
	var stands := false
	for entity in World.monsters():
		if entity != self and entity is Monster and entity.hp > 0 and not (entity as Monster).laid \
				and World.kind_of(entity) in OSSUARY_KINDS and not entity in _retinue:
			stands = true
			break
	if int(stands) != _ossuary:
		_ossuary = int(stands)
		ossuary_sealed.emit(stands)


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
## kept through a zone asleep or unloaded and a room reset, not a restart).
func _rest_over(until: int) -> void:
	var side := _factions().of_kind(World.kind_of(self))
	var own := zone if zone != "" else World.zone.name
	for zone_name in _rest_zones():
		World.dead_rest[zone_name] = {"until": until, "side": side}
		if zone_name == own and pile_at != NO_TILE:
			# His remains, so a reset or restart lays them again (573 amended (4)).
			World.dead_rest[zone_name]["pile"] = [pile_at.x, pile_at.y]
			World.dead_rest[zone_name]["pile_facing"] = [pile_facing.x, pile_facing.y]


## His own zone and those his level's "stills" names.
func _rest_zones() -> Array[String]:
	var out: Array[String] = [World.zone.name]
	var named: Variant = _zone_config().get("stills", [])
	if named is Array:
		for each: Variant in named:
			if str(each) not in out:
				out.append(str(each))
	return out


## [param count] of the dead raised round him in his lair (World.spawn_spec),
## of [param kinds] in turn.
func _raise_retinue(count: int, kinds: Array = ["skeleton"]) -> void:
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
		var spec := Level._spec_for("monster_" + str(kinds[i % kinds.size()]), Level.MONSTER_TYPES)
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
