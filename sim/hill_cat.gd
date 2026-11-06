class_name HillCat
extends Animal
## The hill cat (decision 814; the coordinator's approval of
## C:/dev/review/enemy-ai/hill_cat_design.md): a wild predator that lies up on
## a perch above grazing ground in the hills and drops on what passes below.
## One to a perch (maps' "perch" places, Level.PLACE_KINDS: "at" where it
## lies, "watch" the cells it may pounce onto, 6+ cells from every safe path).
##
## Lying up (lying()): still on its perch. A player who comes within
## SPOT_DAY cells of it by day (SPOT_NIGHT by night), looking its way, with
## a clear line, has spotted it (mark_spotted, once a cat a player: World.cat_spotted, which
## Main turns into "+1 Wayfaring, a hill cat"); it snarls. A spotted player
## is never pounced on: the careful player's bonus. Companions' Wren may
## point one out (mark_spotted, the same path).
##
## The pounce (its row's "moves" "pounce" over POUNCE): something standing on
## a watch cell within its reach (4 by night, 2 by day: by day it drops only
## on what walks right under it), a player or kept companion who has not
## spotted it, or an animal of its diet, it crouches for (a told line,
## World.telegraph, "windup" ticks) and leaps along the line. Who stands on
## the line's end cell when it lands (World.tell_struck, decision 810) takes
## "damage" (cause &"pounce"), never down to 0 (it never downs a player), and
## is knocked back a cell; it lands beside them. One who stepped off the line
## takes nothing, and it lands there, open, recovering "recover" ticks.
##
## Down off its perch it fights as a bold predator (Animal's), till under
## half its hp: then it breaks off, runs, and once out of everyone's sight
## is gone, its perch empty for BEATEN_DAYS (so a beaten cat is not back that
## night to be beaten again for its pelt). With no foe for CALM_TICKS it goes
## back up to its perch and lies up again. Killed, its perch is empty for
## KILLED_DAYS; it drops its kind's (a pelt and meat).
##
## Never saved (Snapshot skips it) nor retired; a restart lays every perch
## afresh. HillCat.step_perches (World.step, every PERCH_CHECK_STEPS) puts a
## cat on each perch of an awake zone that has none and is not closed, out
## of every player's sight. Server only.

## Its moves' numbers under monsters.json's row "moves" "pounce" (combat's
## to tune): reach by night and by day (cells), the crouch's ticks, damage,
## the knock's impulse (70 shoves a player about a cell), the ticks before
## another, and the ticks it stays where it lands after a miss.
const POUNCE := {"reach": 4, "day_reach": 3, "windup": 11, "damage": 6, "impulse": 70.0, "every": 40, "recover": 6, "width": 3}
## A lying cat is spotted within this many cells (with a clear line), by
## a player looking its way SPOT_LOOK_TICKS on end (combat's: a glance past
## is not a look).
const SPOT_DAY := 5
const SPOT_NIGHT := 3
const SPOT_LOOK_TICKS := 6
## How far off their facing a player looks (degrees either side).
const SPOT_HALF_ANGLE := 60.0
## Its snarl's reach, and its pounce cry's.
const SNARL_REACH := 8
## How often it looks about from its perch.
const PERCH_LOOK_TICKS := 3
## A spotted player this near brings it down to fight (cornered).
const CORNERED := 2
## No foe this long: back up to its perch.
const CALM_TICKS := 150
## Its perch empty this many game days once it is beaten off, or killed.
const BEATEN_DAYS := 1.0
const KILLED_DAYS := 2.0
## Broken off: its pace (ticks a cell; a player walks 2.5), and how far off
## (or out of their line) every player must be for it to be gone.
const BROKEN_PACE := 1.5
const LOST_REACH := 14
## Broken off, it runs this many cells (a blood trail behind it, 764's), then
## lies up hurt to heal: found there it fights where it lies, plain, at
## HURT_PACE, no flight; with nobody coming nearer for LIE_UP_GONE_TICKS it is gone (the
## coordinator's, and combat's: a melee chaser can finish it).
const LIE_UP_RUN := 12
const HURT_PACE := 3.0
const LIE_UP_GONE_TICKS := 100
const LIE_UP_ROUSED := 3
## Limping off, it is lost only this far off (or out of line): it lies up
## 12 or so from where it broke, so a late follower closing in keeps it
## (playtest's seventh tour: at 14 its first limp step had it gone).
const SLINK_LOST_REACH := 20
## And it limps at least this long first (playtest's eighth tour: lying up
## out of the follower's line, it was gone the tick it got up).
const SLINK_MIN_TICKS := 20
## World steps between perch checks.
const PERCH_CHECK_STEPS := 50

## Its perch: place id, the cell it lies on, its watch.
var perch := ""
var perch_cell := NO_TILE
var watch: Dictionary[Vector2i, bool] = {}
var pounce := POUNCE.duplicate()
var _lying := true
## Player ids who have spotted it.
var _spotted: Dictionary[String, bool] = {}
## The pounce under way: {telegraph, lands, shape, toward, from}.
var _move := {}
var _next_pounce := 0
var _recover_until := -1
var _perch_look_tick := -1
## Player id -> the tick they began looking its way (within reach).
var _looking: Dictionary[String, int] = {}
## Instance id -> its trail, as the cat saw it at its looks: [tick, cell]
## each time it was first seen on a new cell, the newest last (its pace).
var _trails: Dictionary[int, Array] = {}
var _calm_since := -1
var _broke_off := false
## Broken off: where it broke, when, the cell it last bled on; lying up hurt;
## roused there; since when no player has followed (-1: one has).
var _broke_at := NO_TILE
var _broke_tick := -1
var _bled_at := NO_TILE
var _lying_hurt := false
var _roused := false
var _unfollowed_since := -1
## Lying up hurt: the nearest player's distance at the last approach (or
## the farthest since): one coming a cell nearer than it is following.
var _near_mark := 1 << 20
## Unfollowed, it limps off away from them, gone once it has lost them all.
var _slinking := false
var _slink_since := -1
## Each player's cell at its last look, lying up: found is a player who came
## within LIE_UP_ROUSED by their own steps, not one it limped past.
var _seen_at: Dictionary[int, Vector2i] = {}
## The cell its next pounce aims at (_pounce_target's lead).
var _aim := NO_TILE

## Each perch: place id -> {cat (a HillCat or null), closed_until (World.steps)}.
static var _perches := {}


func _ready() -> void:
	super()
	var props: Variant = spawn_spec.get("props", {})
	if props is Dictionary:
		perch = str(props.get("perch", ""))
		for each: Variant in props.get("watch", []):
			var cell: Variant = each if each is Vector2i else (Vector2i(int(each[0]), int(each[1])) if each is Array and each.size() >= 2 else null)
			if cell is Vector2i:
				watch[cell] = true
	perch_cell = home if home != NO_TILE else tile
	if Net.is_authority():
		World.entity_died.connect(_on_died)
	var moves: Variant = Monster.kinds().get(_kind(), {}).get("moves", {})
	if moves is Dictionary and moves.get("pounce") is Dictionary:
		for key: String in moves["pounce"]:
			if pounce.has(key):
				pounce[key] = moves["pounce"][key]


# --- What others ask (companions' 814 side reads these behind has_method) -----------

## Whether it lies up on its perch unroused: no foe, no pounce under way.
func lying() -> bool:
	return spawned and hp > 0 and _lying and target == null and _move.is_empty()


## Whether the player [param player_id] has spotted it.
func spotted_by(player_id: String) -> bool:
	return _spotted.has(player_id)


## The player [param player_id] has spotted it (seen it, or been shown it):
## once a cat a player, it snarls and World.cat_spotted tells Main.
func mark_spotted(player_id: String) -> void:
	if player_id.is_empty() or _spotted.has(player_id) or not spawned:
		return
	_spotted[player_id] = true
	_cry(&"call", SNARL_REACH)
	print("[cat] %s spotted at %s" % [name, tile])
	World.cat_spotted.emit(self, player_id)


# --- Its turn ------------------------------------------------------------------------

func _sim_tick() -> void:
	if _tend_pounce():
		return
	if World.tick < _recover_until:
		pose = Pose.STAND
		return
	if _broke_off:
		_broken_tick()
		return
	if hp * 2 < max_hp and not _lying:
		_break_off()
		return
	if _lying:
		pose = Pose.SIT
		if World.tick - _perch_look_tick >= PERCH_LOOK_TICKS:
			_perch_look_tick = World.tick
			_spot_check()
			var quarry := _pounce_target()
			if quarry != null:
				_begin_pounce(quarry)
				return
		var struck := _struck_by()
		if struck == null and not _cornered_by_spotter():
			return
		_lying = false
		pose = Pose.STAND
	super()
	if target != null:
		_calm_since = -1
		return
	if _calm_since < 0:
		_calm_since = World.tick
	if World.tick - _calm_since >= CALM_TICKS:
		_go_back_up()


## Bold off its perch (its fight), at its perch by day and night alike.
func _settle_bold() -> void:
	_bold = not _lying
	temper = Temper.BOLD if _bold else Temper.CAUTIOUS
	wander_radius = DEN_RADIUS


func _kind() -> String:
	return str(spawn_spec.get("kind", "hill_cat"))


func _is_night() -> bool:
	return DayNight.daylight(DayNight.now()) < NIGHT_LIGHT


## Each player within its spotting reach, looking its way (within
## SPOT_HALF_ANGLE of their facing) with a clear line, spots it: one who
## looks up at the rocks, not one walking on with their eyes ahead.
func _spot_check() -> void:
	var reach := SPOT_NIGHT if _is_night() else SPOT_DAY
	var seen: Dictionary[String, bool] = {}
	for each in World.sought():
		if not each is Player or not each.spawned or World.distance(each.tile, tile) > reach:
			continue
		var way := Vector2(tile - each.tile)
		var looking := Vector2(each.facing)
		if looking != Vector2.ZERO and absf(rad_to_deg(looking.angle_to(way))) > SPOT_HALF_ANGLE:
			continue
		if World.has_line_of_sight(each.tile, tile):
			var id := (each as Player).player_id
			if not _looking.has(id):
				_looking[id] = World.tick
			if World.tick - _looking[id] >= SPOT_LOOK_TICKS:
				mark_spotted(id)
			seen[id] = true
	for id: String in _looking.keys():
		if not seen.has(id):
			_looking.erase(id)  # Looked away, or out of reach: the look starts again.


## Whether a player who spotted it stands within CORNERED of it.
func _cornered_by_spotter() -> bool:
	for each in World.sought():
		if each is Player and spotted_by((each as Player).player_id) and World.distance(each.tile, tile) <= CORNERED:
			return true
	return false


## Who spotted [param body] for a pounce's sake: a player themselves, a
## companion by her keeper.
func _spotted_for(body: GridEntity) -> bool:
	if body is Player:
		return spotted_by((body as Player).player_id)
	if body is Companion:
		return spotted_by((body as Companion).keeper_id)  # Her keeper's id ("" unkept: never spotted).
	return false


## Whether [param body] (or a companion's keeper) is looking its way now,
## mid-look: it would be seen crouching, so it waits.
func _looked_at_by(body: GridEntity) -> bool:
	if body is Player:
		return _looking.has((body as Player).player_id)
	if body is Companion:
		return _looking.has((body as Companion).keeper_id)
	return false


## The nearest thing on its watch within its reach that it would drop on:
## a player or kept companion who has not spotted it, or an animal of its
## diet; null for none, or before its next pounce may come.
func _pounce_target() -> GridEntity:
	if World.tick < _next_pounce or watch.is_empty():
		return null
	var reach := int(pounce["reach"]) if _is_night() else int(pounce["day_reach"])
	var best: GridEntity = null
	var best_d := reach + 1
	var candidates: Array[GridEntity] = []
	candidates.append_array(World.sought())
	for each in World.monsters():
		if each is Animal and str(each.spawn_spec.get("kind", "")) in diet:
			candidates.append(each)
	_note_trails(candidates)
	var best_aim := NO_TILE
	for each in candidates:
		if each == self or not each.spawned or each.hp <= 0 or each.protected or World.is_downed(each) or World.distance(tile, each.tile) > World.VIEW_TILES:
			continue
		if each is Companion and (each as Companion).keeper == null:
			continue
		if _spotted_for(each) or _looked_at_by(each):
			continue
		var aim := _footing(_lead_cell(each))
		if aim == NO_TILE or not watch.has(aim):
			continue  # Its way not read yet, or it will be off the watch: the next look.
		var d := World.distance(tile, aim)
		if d < best_d and d >= 1:
			best = each
			best_d = d
			best_aim = aim
	_aim = best_aim
	return best


## [param cell], or if no one can stand there (a rock) the nearest walkable
## cell back along the line from it toward the cat (combat's); NO_TILE for none.
func _footing(cell: Vector2i) -> Vector2i:
	if cell == NO_TILE or World.is_walkable(cell):
		return cell
	var back := Vector2(tile - cell)
	for k in range(1, int(ceil(back.length()))):
		var at := Vector2i((Vector2(cell) + back.normalized() * float(k)).round())
		if at != tile and World.is_walkable(at):
			return at
	return NO_TILE


## Each candidate's trail: a new cell seen is added; trails of those no
## longer about are dropped.
func _note_trails(candidates: Array[GridEntity]) -> void:
	var kept: Dictionary[int, Array] = {}
	for each in candidates:
		if not each.spawned:
			continue
		var id := each.get_instance_id()
		var trail: Array = _trails.get(id, [])
		if trail.is_empty() or trail[-1][1] != each.tile:
			trail.append([World.tick, each.tile])
			if trail.size() > 8:
				trail.pop_front()
		kept[id] = trail
	_trails = kept


## Where [param body] will stand when a pounce begun now lands (combat's:
## its pace times the crouch; playtest's tour had a walker who kept moving
## missed at the cell it stood on): on along its step's way at its step's
## pace; its own cell if it stands; NO_TILE until the cat has seen it at one
## look before. Never capped: a lead off the watch or out of reach is no
## pounce (_pounce_target waits for the next look).
func _lead_cell(body: GridEntity) -> Vector2i:
	var trail: Array = _trails.get(body.get_instance_id(), [])
	if trail.is_empty() or int(trail[0][0]) >= World.tick:
		return NO_TILE  # First seen at this look: one more, to read its way.
	if World.free_body(body):
		# A free walker (699): from its centre, at its velocity, from now
		# (combat's, from playtest's fourth tour: its held tile lags its
		# centre, and its step is part-way through).
		var v := World.body_velocity(body)
		if v == Vector2.ZERO:
			return World.struck_cell(body)
		return Vector2i((World.body_centre(body) + v * float(int(pounce["windup"]))).round())
	var speed := body.step_velocity.length()
	if speed <= 0.0 or body.step_until < float(World.tick) - 1.0 / speed:
		return body.tile  # It stands (no step under way or just ended).
	# Its steps from the one under way on to the landing, at its step's pace
	# and way (World.try_move's step_velocity and step_until).
	var landing := float(World.tick + int(pounce["windup"]))
	var more := 0 if landing < body.step_until else floori((landing - body.step_until) * speed) + 1
	var way := Vector2i(signi(roundi(body.step_velocity.x * 1000.0)), signi(roundi(body.step_velocity.y * 1000.0)))
	return body.tile + way * more


func _begin_pounce(quarry: GridEntity) -> void:
	var aim := _aim if _aim != NO_TILE else quarry.tile
	var toward := Vector2(aim - tile).normalized()
	var shape := Telegraph.line(tile, toward, Vector2(aim - tile).length(), int(pounce["width"]))  # Its true length: a slant's longer than its cells.
	if aim not in World.telegraph_cells(shape):
		print("[cat] %s holds: its line from %s misses %s" % [name, tile, aim])
		return  # The told line must end on the cell it strikes (810).
	World.face(self, Senses.way_toward(tile, aim))
	var ticks := int(pounce["windup"])
	var id := World.telegraph(self, "pounce", shape, ticks, true)
	if id == 0:
		return
	pose = Pose.STAND
	_next_pounce = World.tick + int(pounce["every"])
	_move = {"telegraph": id, "lands": World.tick + ticks, "shape": shape, "toward": toward, "from": World.tick, "aim": aim}
	print("[cat] %s crouches at %s for %s at %s, aims at %s, lands in %d ticks (%s, reach %d)" % [name, tile, World.kind_of(quarry),
		quarry.tile, aim, ticks, "night" if _is_night() else "day", int(pounce["reach"]) if _is_night() else int(pounce["day_reach"])])


## The pounce under way: true while it holds the cat; landed or broken here.
func _tend_pounce() -> bool:
	if _move.is_empty():
		return false
	var from := int(_move["from"])
	if stunned_until_tick > from or down_until > from or not spawned:
		World.end_telegraph(int(_move["telegraph"]), false)
		print("[cat] %s pounce broken" % name)
		_move = {}
		return false
	if World.tick < int(_move["lands"]):
		return true
	var cells := World.telegraph_cells(_move["shape"])
	World.end_telegraph(int(_move["telegraph"]), true)
	var toward: Vector2 = _move["toward"]
	var end: Vector2i = _move["aim"]
	_move = {}
	_lying = false
	if cells.is_empty():
		return true
	# Where it comes down: a T, the aimed cell and its two neighbours across
	# the leap (combat's; playtest's third tour: a walker's way bends a cell
	# round the rocks under a perch), never one the tell did not show (810).
	var across := Vector2i(Vector2(-toward.y, toward.x).round())
	var pad: Array[Vector2i] = []
	for each: Vector2i in [end, end + across, end - across]:
		if each in cells:
			pad.append(each)
	var hit: Array[GridEntity] = []
	for each in World.tell_struck(self, pad):
		if each != self and each.spawned and each.hp > 0 and each.max_hp > 0:
			hit.append(each)
	_land(cells, end, hit)
	_cry(&"pounce", SNARL_REACH)
	for each in hit:
		var damage := int(pounce["damage"])
		if each is Player or each is Companion:
			damage = mini(damage, each.hp - 1)  # It knocks back, never downs (the coordinator).
		if damage > 0:
			World.damage(each, damage, self, &"pounce")
	if not hit.is_empty():
		World.sweep(self, toward, 60.0, 1, {"impulse": float(pounce["impulse"]), "only": hit})
		target = hit[0]
		_recover_until = World.tick + attack_ticks  # A beat for the one knocked back to stand (combat's).
	else:
		_recover_until = World.tick + int(pounce["recover"])  # Landed in the open: the opening.
	print("[cat] %s pounce at %s -> %s" % [name, end, "landed on %d" % hit.size() if not hit.is_empty() else "missed"])
	return true


## Lands on the line: its end cell if free, else the nearest free cell back
## along it toward where it leapt from.
func _land(cells: Array[Vector2i], end: Vector2i, hit: Array[GridEntity]) -> void:
	var order := cells.duplicate()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return World.distance(a, end) < World.distance(b, end))
	for cell in order:
		if cell == tile:
			return
		if World.is_walkable(cell) and World.is_free(cell) and not World.is_burning(cell):
			var leapt_from := tile
			World._relocate(self, cell)
			_world_slide_from(leapt_from, World.tick, float(int(pounce["windup"])) * 0.4)
			return


## Under half its hp: it runs, and is gone once out of everyone's sight.
## Broken off: the run (fast, no bites, bleeding), then lying up hurt.
func _broken_tick() -> void:
	if _lying_hurt:
		_lie_up_tick()
		return
	if tile != _bled_at:
		_bled_at = tile
		World.mark_blood(tile)  # Its trail, for one who follows (764's blood).
	var run_ticks := float(LIE_UP_RUN) * BROKEN_PACE * 3.0
	if World.distance(tile, _broke_at) >= LIE_UP_RUN or World.tick - _broke_tick >= int(run_ticks):
		_lying_hurt = true
		alert = Alert.IDLE
		target = null
		pose = Pose.SIT
		move_ticks = HURT_PACE
		_unfollowed_since = World.tick
		_near_mark = _nearest_distance()
		print("[cat] %s lies up hurt at %s (%d/%d)" % [name, tile, hp, max_hp])
		return
	if alert != Alert.FLEEING:
		var near := _nearest_player()
		_flee(near.tile if near != null else tile - facing, false)  # Still running: it bites no more (combat's).
	move_ticks = BROKEN_PACE
	super._sim_tick()
	move_ticks = BROKEN_PACE


## Lying up hurt: still, till a player comes within LIE_UP_ROUSED or strikes
## it, then a cornered fight where it lies (plain, no dart, no flight, at
## HURT_PACE); gone, its perch closed BEATEN_DAYS, once nobody has followed
## for LIE_UP_GONE_TICKS.
func _lie_up_tick() -> void:
	if not _roused:
		# Followed is coming nearer (playtest's sixth tour: on the open hills
		# one standing 12 cells off still sees it, and it lay there for ever).
		var d := _nearest_distance()
		if d < _near_mark:
			_unfollowed_since = World.tick
			_near_mark = d
		elif d > _near_mark:
			_near_mark = d  # Gone farther: only coming back in counts again.
		if not _slinking and World.tick - _unfollowed_since >= LIE_UP_GONE_TICKS:
			_slinking = true  # Nobody came: it gets up and limps off (combat's: not gone in plain sight).
			_slink_since = World.tick
			print("[cat] %s unfollowed, slinks off from %s" % [name, tile])
		if _slinking:
			if World.tick - _slink_since >= SLINK_MIN_TICKS and _lost_to_all(SLINK_LOST_REACH):
				HillCat.close(perch, BEATEN_DAYS)
				print("[cat] %s beaten off, gone from %s" % [name, perch])
				World.despawn(self)
				return
			pose = Pose.STAND
			move_ticks = HURT_PACE
		else:
			pose = Pose.SIT
		var near := _nearest_player()
		var struck := _struck_by()
		var came := false
		if near != null and World.distance(near.tile, tile) <= LIE_UP_ROUSED:
			var was: Vector2i = _seen_at.get(near.get_instance_id(), NO_TILE)
			came = not _slinking or (was != NO_TILE and was != near.tile)
		_seen_at.clear()
		for each in World.sought():
			if each is Player:
				_seen_at[each.get_instance_id()] = each.tile
		if struck == null and not came:
			if _slinking:
				_limp_from(near)
			return
		_roused = true
		target = struck if struck != null else near
		alert = Alert.FIGHTING
		print("[cat] %s found lying up: cornered" % name)
	pose = Pose.STAND
	tactic = Tactic.PLAIN  # Done running: it stays in reach (combat's).
	temper = Temper.BOLD
	_bold = true
	move_ticks = HURT_PACE
	if alert == Alert.FLEEING:
		alert = Alert.FIGHTING
	super._sim_tick()
	move_ticks = HURT_PACE


func _break_off() -> void:
	_broke_off = true
	_broke_at = tile
	_broke_tick = World.tick
	var from := _struck_by()
	_flee(from.tile if from != null else (target.tile if target != null else tile - facing))
	move_ticks = BROKEN_PACE
	print("[cat] %s breaks off at %s (%d/%d)" % [name, tile, hp, max_hp])


## Back up to its perch, and lies up there.
func _go_back_up() -> void:
	if tile == perch_cell:
		_lying = true
		_calm_since = -1
		pose = Pose.SIT
		return
	if World.tick < next_move_tick:
		return
	if not _idle_step(perch_cell) and World.distance(tile, perch_cell) <= int(pounce["reach"]) \
			and World.is_free(perch_cell) and _out_of_sight():
		World._relocate(self, perch_cell)  # No way up on foot: a leap back, unseen.


## Broken off, whether it has lost them: every player LOST_REACH off, or
## with no line to it (over a rise, behind rock).
func _lost_to_all(reach := LOST_REACH) -> bool:
	for each in World.sought():
		if each is Player and World.distance(each.tile, tile) <= mini(reach, World.VIEW_TILES) 				and World.has_line_of_sight(each.tile, tile):
			return false
	return true


## Unfollowed, a limp step on away from [param near] (a flee runs only
## while one is close; this goes on till it has lost them).
func _limp_from(near: GridEntity) -> void:
	if World.tick < next_move_tick or World.is_stunned(self):
		return
	var away := Vector2(tile - near.tile).normalized() if near != null else Vector2(-facing)
	if away == Vector2.ZERO:
		away = Vector2(1, 0)
	# The open cell farthest from them among a fan of ways (along a wall too;
	# into a corner only if nothing is farther).
	var from := near.tile if near != null else tile - facing
	var goals: Array[Vector2i] = []
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.6, -1.6, 2.2, -2.2]:
		var way := away.rotated(turn)
		for far in range(10, 1, -2):
			var goal := Vector2i((Vector2(tile) + way * float(far)).round())
			if World.is_walkable(goal) and World.distance(goal, from) > World.distance(tile, from):
				goals.append(goal)
				break
	goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return World.distance(a, from) > World.distance(b, from))
	for goal in goals:
		if _idle_step(goal):
			return
	next_move_tick = World.tick + 5  # Nowhere away: a moment, then again.


## How far the nearest player is (a large number for none).
func _nearest_distance() -> int:
	var near := _nearest_player()
	return World.distance(near.tile, tile) if near != null else 1 << 20


func _nearest_player() -> GridEntity:
	var best: GridEntity = null
	for each in World.sought():
		if each is Player and (best == null or World.distance(each.tile, tile) < World.distance(best.tile, tile)):
			best = each
	return best


## Whether no player is within sight of it.
func _out_of_sight() -> bool:
	for each in World.sought():
		if each is Player and World.distance(each.tile, tile) <= World.VIEW_TILES:
			return false
	return true


func _on_died(entity: GridEntity, _cause: StringName) -> void:
	if entity == self:
		HillCat.close(perch, KILLED_DAYS)
		print("[cat] %s killed at %s; %s empty %.0f days" % [name, tile, perch, KILLED_DAYS])


# --- The perches ---------------------------------------------------------------------

## Perch [param id] empty for [param days] game days.
static func close(id: String, days: float) -> void:
	if id.is_empty():
		return
	_perches[id] = {"cat": null, "closed_until": World.steps + int(days * DayNight.day_steps)}


## The cat on perch [param id], or null.
static func on_perch(id: String) -> HillCat:
	var cat: Variant = _perches.get(id, {}).get("cat")
	return cat if cat is HillCat and is_instance_valid(cat) and (cat as HillCat).spawned else null


## Every perch forgotten (a test's fresh start); no despawns.
static func clear_perches() -> void:
	_perches.clear()


## A cat on each perch of each awake zone that has none and is not closed,
## out of every player's sight (World.step, each PERCH_CHECK_STEPS).
static func step_perches() -> void:
	if not Net.is_authority() or World.holdings == null or not World.spawn_spec.is_valid():
		return
	var was := World.zone
	var zones: Array[Zone] = []
	zones.assign(World.zones.values())
	if World.zone != null and World.zone not in zones:
		zones.append(World.zone)
	for zone in zones:
		var area := zone.name
		if not World.zone_awake(zone):
			continue
		for id in World.holdings.places_in(area):
			var place := World.holdings.place(id)
			if place.get("kind") != "perch" or on_perch(id) != null:
				continue
			if World.steps < int(_perches.get(id, {}).get("closed_until", 0)):
				continue
			World.enter(zone)
			_lay(id, place)
	World.enter(was)


## A cat on perch [param id] ([param place], World in its zone), if its cell
## is free and out of every player's sight ([param in_view]: a test's, in
## sight too).
static func _lay(id: String, place: Dictionary, in_view := false) -> HillCat:
	var cell: Vector2i = place["cell"]
	if not World.is_walkable(cell) or not World.is_free(cell):
		return null
	for each in World.sought():
		if each is Player and World.distance(each.tile, cell) <= World.VIEW_TILES and not in_view:
			return null
	var spec := Level._spec_for("monster_hill_cat", Level.MONSTER_TYPES)
	if spec.is_empty():
		return null
	spec["name"] = "HillCat_%s" % str(place.get("key", id)).validate_node_name()
	spec["tile"] = cell
	spec["home"] = cell
	var watch_cells: Array = []
	for each: Variant in place.get("watch", []):
		if each is Vector2i:
			watch_cells.append([each.x, each.y])
	(spec["props"] as Dictionary)["perch"] = id
	(spec["props"] as Dictionary)["watch"] = watch_cells
	var made: Variant = World.spawn_spec.call(spec)
	if not made is HillCat:
		return null
	_perches[id] = {"cat": made, "closed_until": 0}
	print("[cat] %s lies up on %s at %s" % [(made as HillCat).name, id, cell])
	return made
