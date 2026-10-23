class_name Monster
extends GridEntity
## Picks the nearest player it can see (within sight range, in line of sight).
## Attacks if that player is in melee reach, otherwise walks toward them.
##
## A monster of a kind (its level marker's, spawn_spec "kind") fights as
## that kind does (its row in levels/monsters.json: kinds), in a manner of
## its own (_temper, from its name) and a temperament (Temper):
## it makes for a tile beside its target that no other monster is making
## for, so a pack surrounds rather than queues (_pick_slot).
##
## With nobody in sight it idles (Idle, level.json "idle", else by kind,
## IDLE_BY_KIND), at IDLE_PACE of its step time: GUARD stands at its home
## facing its set way and now and then glances aside; WANDER strolls about
## its home; PATROL walks a route of waypoints; GATHER stands or sits round
## a point, facing it. After a fight it walks back (home, its route, its
## place at the point) and goes on. Its facing is its level entry's, or one
## of its own from its name.
##
## It sees and hears by its Senses: a monster of a kind only what is lit
## (or carries a light) in a cone before it, a monster of no kind all
## round, as monsters did. Hearing something with nobody in sight it turns
## that way (LISTEN_TICKS) and may see who made it.
##
## A monster of a kind is more or less alert (Alert): a noise or a glimpse
## sends it to look (SUSPICIOUS), a target lost from sight or a fight heard
## after it (HUNTING), to where it last saw it and on the way it was going;
## there it looks round, and in time it gives up and goes back. Too far
## from where it took up the chase (LEASH) it gives up at once, and lets
## that one be a while (GIVE_UP_TICKS): escape is possible.
##
## Far from every player and companion it thinks less often, or not at all
## (World.Tier); the world tick moves it on then (_world_tick).

## Mass reads off the body: the sprite runs from SHADE_LIGHT at
## SHADE_LIGHT_MASS to SHADE_DARK at SHADE_DARK_MASS. Darker is heavier.
const SHADE_LIGHT_MASS := 20.0
const SHADE_DARK_MASS := 80.0
const SHADE_LIGHT := Color(1.0, 0.62, 0.55)
const SHADE_DARK := Color(0.33, 0.04, 0.08)

## PLAIN: straight at it, and hit it (a monster of no kind).
## DART: in, a blow, and (DART_AFTER_TICKS on, its blow played out) out of
##   reach again while it cools down.
## HEAVY: plods, charges the last CHARGE_RANGE tiles at CHARGE_PACE, and
##   winds up (WINDUP_TICKS) a blow that lands on its target only if it is
##   still in reach; a whiff otherwise, and a knock or a stun spoils it.
## FLANK: works round to its target's back or side before it strikes
##   (FLANK_PATIENCE_TICKS from the front at most); from behind, its blow
##   does BACKSTAB_DAMAGE more.
enum Tactic { PLAIN, DART, HEAVY, FLANK }
const TACTIC_NAMES := {"plain": Tactic.PLAIN, "dart": Tactic.DART, "heavy": Tactic.HEAVY, "flank": Tactic.FLANK}
## Each kind's body, tactic, idling, doors, leash and temperaments (kinds).
const KINDS_PATH := "res://levels/monsters.json"
const FLOAT_PROPS: Array[String] = ["mass", "move_ticks"]
## BOLD: never holds back, a longer leash (BOLD_LEASH), breaks only when
## nearly dead. CAUTIOUS: holds back till another is at its target, calls
## for help when it first sees someone. COWARDLY: calls for help, holds
## back till two others are at its target, breaks early, or alone against
## two or more (COWARD_ODDS_TILES). Each breaks below FLEE_BELOW of its hp;
## its boldness (holding back) is drawn within BOLDNESS. Its target holding
## a dread weapon (World.holder_dread, decision 365): a coward counts it as
## two, the cautious hold back till two others are at it and break below
## DREAD_FLEE_BELOW; the bold take no notice.
enum Temper { BOLD, CAUTIOUS, COWARDLY }
const TEMPER_NAMES := {"bold": Temper.BOLD, "cautious": Temper.CAUTIOUS, "cowardly": Temper.COWARDLY}
const BOLDNESS := {Temper.BOLD: Vector2(0.6, 1.0), Temper.CAUTIOUS: Vector2(0.1, 0.29), Temper.COWARDLY: Vector2(0.0, 0.09)}
const FLEE_BELOW := {Temper.BOLD: 0.15, Temper.CAUTIOUS: 0.35, Temper.COWARDLY: 0.6}
const DREAD_FLEE_BELOW := 0.5
## An archer's arrows (decision 375's bundle): WORN_BUNDLE_CHANCE of them
## come worn, their condition drawn within WORN_BUNDLE, so one a player
## takes is sometimes worth swapping and sometimes not.
const WORN_BUNDLE_CHANCE := 0.3
const WORN_BUNDLE := Vector2i(4, 9)
const BOLD_LEASH := 1.5
const COWARD_ODDS_TILES := 3
## Fleeing (Alert.FLEEING): it runs FLEE_TILES at most at a time, and
## recovers after FLEE_TICKS with nobody within FLEE_NEAR_TILES.
const FLEE_TICKS := 60
const FLEE_TILES := 6
const FLEE_NEAR_TILES := 4
## A call for help (Senses.NOISE_CALL) at most so often; a rout
## (Senses.NOISE_ROUT) breaks a cautious one under ROUT_HURT of its hp.
const CALL_EVERY_TICKS := 100
const ROUT_HURT := 0.7
const DART_AFTER_TICKS := 3
const CHARGE_RANGE := 4
const CHARGE_PACE := 0.5
const WINDUP_TICKS := 6
const FLANK_PATIENCE_TICKS := 20
const BACKSTAB_DAMAGE := 1
## Its manner, from its name: a step this much quicker or slower, a cooldown
## this many ticks either way, up to REACTION_TICKS_MAX to act on a new
## target, a chance a tick of PAUSE_CHANCE_MAX at most to stop a moment
## (PAUSE_TICKS) on the way in; bolder than HOLD_BACK_BELOW, or it waits
## HOLD_BACK_RANGE off until another monster is at its target or its target
## is under half its hp.
const PACE_SPREAD := 0.15
const COOLDOWN_SPREAD := 2
const REACTION_TICKS_MAX := 6
const PAUSE_CHANCE_MAX := 0.12
const PAUSE_TICKS := Vector2i(2, 6)
const HOLD_BACK_BELOW := 0.3
const HOLD_BACK_RANGE := 3
## Looking out is skipped while the nearest player or companion was, at the
## tier's last measure, this much beyond its sight: more than anyone walks,
## or is shoved, in World.TIER_EVERY_TICKS.
const LOOK_MARGIN_TILES := 8
## A nearer target is taken over the one it has only when this much nearer.
const RETARGET_TILES := 2
const NO_TILE := Vector2i(-9999, -9999)
## How far (tiles looked at) it searches for a way to a tile beside its
## target before going straight at it instead.
const SLOT_SEARCH_TILES := 120
## How far (tiles looked at) it searches for a way to its target itself
## (nowhere free beside it, or a monster of no kind): its target is in
## sight, so a way that needs more is round a crowd it cannot get through,
## not worth a search of the whole map every tick.
const CHASE_SEARCH_TILES := 400
## Hearing something with nobody in sight: it turns that way and holds
## still so long (ticks); a noise heard more than LISTEN_STALE_TICKS ago
## (it was not thinking then) is let go.
const LISTEN_TICKS := 20
const LISTEN_STALE_TICKS := 20
## How alert it is (shown over its head): IDLE, as it idles; SUSPICIOUS, a
## noise or a glimpse to look into, at its idle pace; HUNTING, a target
## lost from sight or a fight heard, at its chase pace; FIGHTING, a target
## in sight; FLEEING, broken and running (_flee). A monster of no kind only
## idles and fights.
enum Alert { IDLE, SUSPICIOUS, HUNTING, FIGHTING, FLEEING }
## So long (ticks) since the last thing that roused it before it gives up.
const SUSPICIOUS_TICKS := 100
const HUNT_TICKS := 150
## At its lead it looks round: these turns (eighths of a turn from the way
## it faces), LOOK_TICKS each.
const LOOK_ROUND: Array[int] = [2, -4, 2]
const LOOK_TICKS := 10
## Hunting, it goes on past where it last saw its quarry so far (tiles) the
## way it was going: round the corner it went round.
const HUNT_ON_TILES := 2
## Fighting or hunting more than LEASH tiles from where it took up the
## chase, it gives up, and lets that one be for GIVE_UP_TICKS unless it
## comes within LEASH / 2 of there or strikes it.
const LEASH := 20
const GIVE_UP_TICKS := 100
## Doors: the kinds that open them (kinds' "opens_doors"; the rest, the
## brute, break them, "door_force" times their blow on a door; a level
## entry's "opens_doors" says otherwise).
## Looking or hunting, it opens a closed door only with a reason beyond it,
## heard or seen there no longer than DOOR_FRESH_TICKS ago (opens_doors_now):
## a shut door and quiet behind it, you can hide.
const DOOR_FRESH_TICKS := 40
const NO_DOOR := Vector3i(-9999, -9999, 0)
## _door_on_way's answer is kept so long (ticks) for the same goal.
const DOOR_WAY_TICKS := 20
## With no way to its target at all (a crowd round it), it looks for one
## again only after this many ticks: a crowd does not open in a tick.
const CHASE_RETRY_TICKS := 5
## An archer (a bow in its hands, decision 341) shoots from KEEP_NEAR cells
## out to its bow's reach; nearer than KEEP_NEAR it steps back.
const KEEP_NEAR := 3
## A shield (decision 345) is up while its target is this near, and its
## stamina above GUARD_REST of its most; below that it lowers it to get
## its breath back, raising it again only above GUARD_RESTED.
const GUARD_TILES := 2
const GUARD_REST := 0.25
const GUARD_RESTED := 0.5
## Not fighting, one of a kind that "picks_up" looks for a weapon beside it
## (World.weapon_near) this often (ticks); fighting bare-handed, every
## step it would take.
const PICK_UP_EVERY := 10

## What it does with nobody in sight. NONE: stands where it is (a monster of
## no kind, as monsters were).
## MARCH (a raider, Raids): along its route once, to the last waypoint, and
## stands there.
## HOMEWARD (the barrow's dead, decision 547): up to its grave, a niche of
## a shallower band from its level's "graves", and there it lies down still
## (laid) till the curse renews (rise).
enum Idle { NONE, GUARD, WANDER, PATROL, GATHER, MARCH, HOMEWARD }
const IDLE_MODES := {"none": Idle.NONE, "guard": Idle.GUARD, "wander": Idle.WANDER, "patrol": Idle.PATROL,
	"gather": Idle.GATHER, "march": Idle.MARCH, "homeward": Idle.HOMEWARD}
## HOMEWARD: how far it searches for its way (a barrow's breadth), and how
## long it lies down at a time (renewed before it would get up).
const HOMEWARD_SEARCH_TILES := 2000
const LAID_HOLD_TICKS := 6000
const LAID_RENEW_TICKS := 600
## Idling it walks this much slower than it chases (its step time times this).
const IDLE_PACE := 1.6
## GUARD: a glance aside every so often (ticks), up to GLANCE_STEPS_MAX
## eighths of a turn (2: 90 degrees) either way, held a moment.
const GLANCE_EVERY_TICKS := Vector2i(30, 70)
const GLANCE_HOLD_TICKS := Vector2i(8, 20)
const GLANCE_STEPS_MAX := 2
## WANDER: to a free tile at most this far from home, then a pause.
const WANDER_RADIUS := 3
const WANDER_PAUSE_TICKS := Vector2i(15, 60)
## PATROL: a pause at each waypoint. With no route set, a loop of its own of
## PATROL_LOOP_POINTS about its home, PATROL_LOOP_RADIUS out.
const PATROL_PAUSE_TICKS := Vector2i(8, 25)
const PATROL_LOOP_POINTS := 4
const PATROL_LOOP_RADIUS := 3
## GATHER: its place is a free tile this near the point (not in fire); some
## sit there, by name, the rest stand.
const GATHER_RADIUS := 2
const SIT_CHANCE := 0.5
## MARCH: a waypoint this near counts as reached (raiders crowd each other),
## and a step it cannot take now is tried again after this long (ticks).
const MARCH_NEAR := 2
const MARCH_RETRY_TICKS := 15
## The dead walking home, blocked by the same one: they wait so long
## (ticks), stepping aside, before they fight it; a block older than
## BLOCKED_FORGET_TICKS is forgotten (decision 561).
const BLOCKED_WAIT_TICKS := 20
const BLOCKED_FORGET_TICKS := 60
## How far (tiles looked at) it searches for its way home or about.
const IDLE_SEARCH_TILES := 400
## Choosing a tile to stroll to or a patrol waypoint within so many tiles of
## home, it looks at no more than this many tiles for each tile of the
## square round home that reaches: a spot only a long way round from home
## is not about home (and looking for it was most of a monster's first
## turn near a player).
const ABOUT_SEARCH_PER_TILE := 2
## How it is standing, for the views: SIT at a gathering.
enum Pose { STAND, SIT }
## The eight ways round, clockwise from north (for glances).
const AROUND: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

## It cried out: a noise of [param kind] (&"call", &"rout") its side hears,
## and views and sound play (a client never sees World.noise).
signal cried(kind: StringName)

## Off: no monster idles (they stand where they are, as before idling). For
## tests staged in a real level whose monsters must stay put.
static var idling := true
## Off: no monster notices anyone (none sees, hears, hunts or fights; each
## stays IDLE, idling as idling says). For tests staging a real level
## (--still-monsters), whose players must not be hunted.
static var noticing := true

@export var sight_range := 7:
	set(value):
		sight_range = value
		if senses != null:
			senses.sight_range = value
## What it sees, hears and remembers (the server's; null on a client).
var senses: Senses
## How alert it is (Alert); the views show it.
var alert := Alert.IDLE
## Who it went for this tick (null for nobody), for the companions' minds.
var target: GridEntity
var tactic := Tactic.PLAIN
var reaction_ticks := 0
var boldness := 1.0
var pause_chance := 0.0
## The tile beside its target it is making for (NO_TILE: none).
var slot := NO_TILE
var _pace := 0.0
var _rng := RandomNumberGenerator.new()
var _noticed_tick := 0
## {target, lands, direction, from}: a blow wound up (HEAVY).
var _windup := {}
## DART: out of reach from _dart_from till _dart_until, cooling down.
var _dart_from := -1
var _dart_until := -1
## FLANK: ticks spent beside its target's front, ready to strike.
var _front_ticks := 0
## Idling: how, where home is (its level tile) and which way it faces there,
## its route (PATROL; loop, or back and forth), the point it gathers at.
var idle := Idle.NONE
var home := NO_TILE
var home_facing := Vector2i(0, 1)
var route: Array[Vector2i] = []
var route_loop := true
var gather_point := NO_TILE
var wander_radius := WANDER_RADIUS
var pose := Pose.STAND
var _idle_rng := RandomNumberGenerator.new()
## Going back after a fight.
var _returning := false
## WANDER's tile, GATHER's place.
var _idle_goal := NO_TILE
## Pausing, or holding a glance, till then.
var _idle_until := 0
## The tick of the last noise it turned to, and till when it listens.
var _listened_tick := -1
var _listening_until := -1
## Alertness (a monster of a kind: _wary): SUSPICIOUS or HUNTING till
## _alert_until; where it is making for (_lead), the turns it has looked
## there and till when it holds the last; whom it hunts, where it last saw
## them and where before that; where it took up the chase (_post, for the
## leash); whom it has given up on, till when (instance id -> tick); a
## glimpse this tick.
var _wary := false
## The raid group it marches with (Raids; "" for none), and its share of
## the group's strength.
var raid := ""
var raid_strength := 0.0
## The factions its kind's fights on sight (Factions.on_sight, decision
## 545): their monsters, and "town" the residents' bodies. Most kinds none.
var foes: Array[String] = []
## How far (cells) its call for help carries: its kind's "call", else
## Senses.NOISE_CALL (decision 561: a grave robber's is 6).
var call_reach := Senses.NOISE_CALL
## HOMEWARD (decision 547): the grave it walks to (NO_TILE till chosen) and
## whether it lies there still, both kept in its saved props (and whether
## the draugr's rest laid it, stilled, decision 580); whom it fights
## on the way: one in its way, or one that struck it.
var grave := NO_TILE
var laid := false
var stilled := false
var _provoked: GridEntity
## Who blocks its way home, since when and when last (decision 561).
var _blocked_by: GridEntity
var _blocked_since := -1
var _blocked_last := -1
## Its kind's: it never flees (the dead); it keeps to the room it stands in
## (the anchor of its level round its home: the altar's guards), sees and
## fights nobody outside it, and goes after no noise.
var fearless := false
var keeps_room := false
## Its kind's own blow with a thing it wields (its row's "blows", item id
## to a verb, read through Items.verb_from): the draugr's battle axe a
## heavy strike in his hands, the knockdown his spin's alone (603 amended);
## the thing's own verb for anyone else.
var blows := {}
## An archer's hold before it looses (decision 620, enemy-ai's side): it
## waits till its cone (World.spread_of) has closed to aim_spread degrees,
## or it has held aim_hold_max ticks; its kind's row. 0 for both, it looses
## as soon as its draw reaches (a goblin snaps, the patient dead wait).
var aim_spread := 0.0
var aim_hold_max := 0
## Whether players can talk to it (npc's offer contract, decision 548: the
## draugr): Main's speaker lookup takes it in.
var talks := false
var _room := Rect2i()
var _alert_until := 0
var _lead := NO_TILE
var _looks := 0
var _look_until := -1
var _quarry: GridEntity
## Its arrows' wear rolled (_wear_bundle).
var _bundle_rolled := false
var _quarry_at := NO_TILE
var _quarry_from := NO_TILE
var _post := NO_TILE
var _given_up: Dictionary[int, int] = {}
var _glimpsed := NO_TILE
## Whether it opens doors (DOOR_OPENERS); whether its lead is a guess (a
## hunt's tiles on past where it saw them) and, if so, where it saw them;
## when it last heard or saw something real for its lead; the door it is
## breaking (NO_DOOR: none).
var opens_doors := true
var door_force := 1
## Its temperament, and how far from where it took up a chase it gives up
## (its kind's "leash", longer if bold).
var temper := Temper.CAUTIOUS
var leash := LEASH
## Fleeing from; when it last called for help; the newest noise it has
## looked at for a rout.
var _flee_from := NO_TILE
var _called_tick := -100000
var _rout_tick := -1
## kinds(), read once.
static var _kinds := {}
var _lead_guess := false
var _lead_seen := NO_TILE
var _evidence_tick := -1
var _bash_key := NO_DOOR
## _door_on_way's last answer: {to, from, tick, door}.
var _door_way := {}
var _glancing := false
var _route_index := 0
var _route_step := 1
var _sits := false
## Woken, it idles from this tick on (_woke_up).
var _idle_from := 0
## The way it is walking as it idles, and where to (_idle_step).
var _idle_path: Array[Vector2i] = []
## A HEAVY one closing its last CHARGE_RANGE at CHARGE_PACE (charging).
var _charging := false
## Its kind's "picks_up" (decision 349): it takes up a weapon lying beside it.
var picks_up := false
var _pick_look_tick := -100000
var _idle_path_to := NO_TILE
## How often it thinks (World.Tier), and the tick that was worked out (-1:
## not yet). World's.
var tier := 0
var tier_tick := -1
## Beyond World.VIEW_TILES of everyone when its tier was worked out: on
## nobody's screen. World's.
var beyond_view := false
## The tiles to the nearest player or companion when its tier was worked
## out (-1: not measured), and the zone's comings then. World's.
var nearest_sought := -1
var tier_comings := -1
## The World.steps of its last world tick (-1: none yet), and whether one
## is queued for it. World's.
var world_step := -1
var world_queued := false
## The tick its tier last became FAR (-1: not FAR): far long enough, it is
## kept as a record instead (Main._retire, decision 352). World's.
var far_since := -1


## Its two hands, [right, left] Items ids ("" empty), when it has them
## (Items.CARRIED slots, a kind's "wields", decision 338); else empty.
## Replicated (decision 483) where its slots are not, so a client draws
## what it holds and the bow it draws without being sent its pack: the
## server's follows its slots (_slots_set); a client's is written into
## them, the pack left empty, for the views to read as a player's.
var hands := PackedStringArray():
	set(value):
		hands = value
		if value.size() != 2:
			return
		if slots.size() >= Items.HANDED and slots[Items.RIGHT_HAND] == value[0] and slots[Items.LEFT_HAND] == value[1]:
			return
		var held := slots.duplicate() if slots.size() >= Items.HANDED else Items.tidy([], Items.CARRIED)
		held[Items.RIGHT_HAND] = value[0]
		held[Items.LEFT_HAND] = value[1]
		slots = held


func _slots_set() -> void:
	var now := PackedStringArray([slots[Items.RIGHT_HAND], slots[Items.LEFT_HAND]]) if slots.size() >= Items.HANDED else PackedStringArray()
	if now != hands:
		hands = now


func _init() -> void:
	super()
	mass = 40.0
	move_ticks = 4
	max_hp = 12
	attack_damage = 1
	strength = 6
	max_stamina = 60
	attack_ticks = 10
	tiered = true
	# Its pace changes as it charges and as it idles; a client slides its
	# steps by it.
	replicate("move_ticks")
	replicate("pose")
	replicate("alert")
	replicate("down_until")
	replicate("ailments")
	# Its bow drawn, its guard up: the tell a player steps out of the line by
	# (decision 455).
	replicate("raised")
	replicate("raised_tick")
	# What its hands hold (decision 483): drawn, and its bow when drawn.
	replicate("hands")


func _ready() -> void:
	super()
	# An explicit tint wins; otherwise colour by mass.
	if _sprite != null and tint.a <= 0.0:
		var heaviness := clampf(inverse_lerp(SHADE_LIGHT_MASS, SHADE_DARK_MASS, mass), 0.0, 1.0)
		_sprite.modulate = SHADE_LIGHT.lerp(SHADE_DARK, heaviness)
	if Net.is_authority():
		_temper()
		_settle_idle()
		var kind := str(spawn_spec.get("kind", ""))
		_wary = kinds().has(kind)
		var row: Dictionary = kinds().get(kind, {})
		var opens: Variant = spawn_spec.get("opens_doors")
		opens_doors = bool(opens) if opens != null else bool(row.get("opens_doors", true))
		door_force = int(row.get("door_force", 1))
		picks_up = bool(row.get("picks_up", false))
		fearless = bool(row.get("fearless", false))
		keeps_room = bool(row.get("keeps_room", false))
		pays_swings = bool(row.get("swing_stamina", false))  # Decision 597: off until enemy-ai's design.
		stamina_regen_every = maxi(1, int(row.get("stamina_regen_every", 1)))  # Decision 603.
		stamina_regen_amount = maxi(0, int(row.get("stamina_regen", 0)))  # 603 amended.
		blows = row.get("blows", {})
		aim_spread = float(row.get("aim_spread", 0.0))
		aim_hold_max = int(row.get("aim_hold_max", 0))
		call_reach = int(row.get("call", Senses.NOISE_CALL))
		if keeps_room:
			_room = room_of(home)
		var dead := _level_dead(kind)
		if TEMPER_NAMES.has(str(dead.get("temper", ""))):
			temper = TEMPER_NAMES[str(dead["temper"])]
		if not bool(dead.get("graves", true)) and idle == Idle.HOMEWARD:
			idle = Idle.WANDER
		leash = roundi(int(row.get("leash", LEASH)) * (BOLD_LEASH if temper == Temper.BOLD else 1.0))
		senses = Senses.new(self, sight_range, Senses.CONE_COS if _wary else -1.0)
		senses.dark_sight = bool(dead.get("sees_in_dark", false))


## Its level's word on the dead (decision 580: barrow_lair's "dead", the
## draugr's oldest, angry and animated by his magic): {temper, sees_in_dark,
## graves} for a kind of the dead's side; {} for any other, or none given.
func _level_dead(kind: String) -> Dictionary:
	var given: Variant = _zone_config().get("dead", {})
	if not given is Dictionary or (given as Dictionary).is_empty() or _factions().of_kind(kind) != "dead":
		return {}
	return given


## How it idles, where its home is and which way it faces, from its spawn
## spec ("home", "facing", "idle": as Level gives them), else by its kind and
## its name.
func _settle_idle() -> void:
	_idle_rng.seed = hash(String(name) + "/idle")
	var tile_given: Variant = spawn_spec.get("tile")
	home = spawn_spec.get("home", tile_given if tile_given is Vector2i else NO_TILE)
	var set_facing: Variant = spawn_spec.get("facing")
	home_facing = set_facing if set_facing is Vector2i and set_facing in AROUND else own_facing(String(name))
	facing = home_facing
	var given: Dictionary = spawn_spec.get("idle", {})
	var mode := str(given.get("mode", ""))
	idle = IDLE_MODES[mode] if IDLE_MODES.has(mode) else idle_of(str(spawn_spec.get("kind", "")))
	route.assign(given.get("route", []))
	route_loop = bool(given.get("loop", true))
	var point: Variant = given.get("point")
	gather_point = point if point is Vector2i else home
	wander_radius = int(given.get("radius", WANDER_RADIUS))
	_sits = _idle_rng.randf() < SIT_CHANCE
	_idle_until = World.tick + _idle_rng.randi_range(0, GLANCE_EVERY_TICKS.y)


## Its kind's tactic and its own manner, the same every time for the same
## name (a respawn, a restart). A monster of no kind is PLAIN, as it was.
func _temper() -> void:
	var kind := str(spawn_spec.get("kind", ""))
	_pace = move_ticks
	if not kinds().has(kind):
		return
	tactic = kinds()[kind]["tactic"]
	_rng.seed = hash(String(name))
	_pace = move_ticks * (1.0 + _rng.randf_range(-PACE_SPREAD, PACE_SPREAD))
	move_ticks = _pace
	attack_ticks = maxi(4, attack_ticks + _rng.randi_range(-COOLDOWN_SPREAD, COOLDOWN_SPREAD))
	reaction_ticks = _rng.randi_range(0, REACTION_TICKS_MAX)
	boldness = _rng.randf()
	pause_chance = _rng.randf_range(0.0, PAUSE_CHANCE_MAX)
	_settle_temper(kind)
	var factions := _factions()
	foes = factions.on_sight(factions.of_kind(kind))


func _sim_tick() -> void:
	if not _bundle_rolled:
		_wear_bundle()
	_mind_the_rest()
	if laid:
		var woke_by := _waking_foe()
		if woke_by == null:
			_lie_still()  # Struck or not, it stays down (decision 547).
			return
		rise()  # A foe in sight: it sits up, turned to them, and keeps its grave (GUARD).
		World.face(self, Senses.way_toward(tile, woke_by.tile))
	if not noticing:
		_unnoticing()
		return
	if alert == Alert.FLEEING:
		_flee_tick()
		return
	if _wary and senses.last_tick > _rout_tick and _heard_rout():
		return
	var seen := _nearest_visible_target()
	if seen != null and _wary and _beyond_leash():
		_give_up(seen)
		seen = null
	if seen != target:
		_noticed_tick = World.tick
		slot = NO_TILE
		_front_ticks = 0
		if seen == null:
			if not _hunt(target):
				# The fight is over: back to where it idles, then on as before.
				_returning = idle != Idle.NONE
				if alert == Alert.FIGHTING:
					alert = Alert.IDLE
			_idle_goal = NO_TILE
			_glancing = false
		else:
			_quarry_at = seen.tile
			_quarry_from = NO_TILE
			if target == null:
				move_ticks = _pace
				pose = Pose.STAND
	target = seen
	if target == null:
		_drop_windup()
		if not raised.is_empty():
			World.try_stance(self, "")  # Nobody to shoot or guard against.
		if _pick_up(false):
			return
		_alert_tick()
		return
	var took_up := alert != Alert.FIGHTING
	if alert == Alert.IDLE:
		_post = tile
	alert = Alert.FIGHTING
	_quarry = target
	if target.tile != _quarry_at:
		_quarry_from = _quarry_at
		_quarry_at = target.tile
	if _wary:
		if took_up and temper != Temper.BOLD:
			_call_for_help()
		if _should_flee():
			_flee(target.tile)
			return
	if not World.winding(self).is_empty():
		return  # Its heavy blow wound up: it stands till World strikes it.
	if _meet_wind_up():
		return
	if _special_tick():
		return  # A kind's own moves (the draugr's spin, throw and charge: 603).
	match World.off_hand(self):
		"draw":
			if _shoot_tick():
				return
		"block":
			_guard_tick()
	if tactic == Tactic.PLAIN:
		if World.can_melee(tile, target.tile):
			if not _bash_guard():
				_blow()
		elif World.tick >= next_move_tick:
			var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now())
			if not path.is_empty():
				World.try_move(self, path[0] - tile)
			else:
				next_move_tick = World.tick + CHASE_RETRY_TICKS  # No way in: look again in a moment.
		return
	if not _windup.is_empty():
		_wind_on()
		return
	if World.tick - _noticed_tick < reaction_ticks:
		return  # Sizing it up.
	var can_strike := World.tick >= next_attack_tick and World.tick >= next_move_tick
	if World.can_melee(tile, target.tile):
		if tactic == Tactic.DART and World.tick < _dart_until:
			if World.tick >= _dart_from:
				_step_out()
			return
		if _bash_guard():
			return  # Its guard opened: the blows next.
		if not can_strike:
			return
		if tactic == Tactic.FLANK and (_in_front() or not World.guarding(target, self).is_empty()) \
				and _front_ticks < FLANK_PATIENCE_TICKS:
			_front_ticks += 1
			var round_to := _pick_slot()
			if round_to != NO_TILE and round_to != tile and _go_to(round_to):
				return
			if _front_ticks < FLANK_PATIENCE_TICKS:
				return
		_strike()
		return
	if tactic == Tactic.DART and World.tick < _dart_until:
		return  # Out of reach, cooling down.
	if World.tick < next_move_tick:
		return
	if World.wielded(self).is_empty() and _pick_up(true):
		return  # Bare-handed: the weapon at its feet first.
	if (boldness < HOLD_BACK_BELOW or _dreads_target()) \
			and World.distance(tile, target.tile) <= HOLD_BACK_RANGE and not _target_beset(_others_needed()):
		return  # Waits for the others.
	if _rng.randf() < pause_chance:
		next_move_tick = World.tick + _rng.randi_range(PAUSE_TICKS.x, PAUSE_TICKS.y)
		return
	if tactic == Tactic.HEAVY:
		_charging = World.distance(tile, target.tile) <= CHARGE_RANGE \
				and World.has_clear_line(tile, target.tile)
		move_ticks = _pace * (CHARGE_PACE if _charging else 1.0)
	slot = _pick_slot()
	if slot == NO_TILE or not _go_to(slot):
		# Nowhere free beside it: as near as it can get.
		var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now())
		if not path.is_empty():
			World.try_move(self, path[0] - tile)
		else:
			next_move_tick = World.tick + CHASE_RETRY_TICKS  # No way in: look again in a moment.


## noticing off: nobody seen or heard; it idles, IDLE.
func _unnoticing() -> void:
	target = null
	_drop_windup()
	alert = Alert.IDLE
	_idle_tick()


## A kind's own moves in a fight, before its hands' (a subclass's: the
## draugr's, 603); true when it took this tick. None here.
func _special_tick() -> bool:
	return false


## An archer's fight (decision 341): in its band (KEEP_NEAR to its bow's
## cells) with a clear shot it stands, draws (World.try_stance "draw") and
## looses at the angle to it once its draw's step reaches it, or at its
## longest step (try_loose; decision 583); struck, its draw is spoilt. Too near,
## it steps back; true for all of that. False when its fight is its kind's
## as ever: no clear shot from here, or out of reach (it closes as any
## monster does, till it has one), or too near and nowhere to step back
## (it fights with its blow).
func _shoot_tick() -> bool:
	if raised == "draw" and hurt_tick >= raised_tick:
		World.try_stance(self, "")  # Struck while drawing: it starts again.
	var d := World.distance(tile, target.tile)
	if d < KEEP_NEAR:
		World.try_stance(self, "")
		return World.tick >= next_move_tick and _step_back()
	if not _clear_shot():
		World.try_stance(self, "")
		return false
	if World.tick - _noticed_tick < reaction_ticks:
		return true  # Sizing it up.
	World.face(self, Senses.way_toward(tile, target.tile))
	if raised != "draw":
		World.try_stance(self, "draw")
	elif World.range_of(self) >= mini(d, World.longest_range(self)) and _aimed() 			and _cone_clear(World.spread_of(self)):
		World.try_loose(self, Vector2(target.tile - tile).angle())
	return true


## Whether its draw has been held long enough to loose (decision 620,
## enemy-ai's side): its cone at or under aim_spread, or held aim_hold_max
## ticks; always, for a kind with neither.
func _aimed() -> bool:
	if aim_spread <= 0.0 and aim_hold_max <= 0:
		return true
	var spread := World.spread_of(self)
	if spread < 0.0:
		return false  # Not drawing yet.
	if aim_spread > 0.0 and spread <= deg_to_rad(aim_spread) + 1e-6:
		return true
	return aim_hold_max > 0 and World.tick - raised_tick >= aim_hold_max


## Whether a cone of half-angle [param spread] (radians) toward its target
## has nobody else on either edge as far as the target (decision 620,
## enemy-ai's side): its arrow can fly anywhere in it.
func _cone_clear(spread: float) -> bool:
	if spread <= 0.0:
		return true
	var aim := Vector2(target.tile - tile).angle()
	var d := World.distance(tile, target.tile)
	for edge in [aim - spread, aim + spread]:
		var hit: Variant = World.shot_aim(self, edge, d).get("hit")
		if hit != null and hit != target:
			return false
	return true


## A shield's fight (decision 345): up, and turned to its target, while it
## is within GUARD_TILES (it fights on behind it: a raised shield never
## stops a blow of its own), down farther off, or to get its breath back
## under GUARD_REST of its stamina. A broken guard World lowers itself.
func _guard_tick() -> void:
	var near := World.distance(tile, target.tile) <= GUARD_TILES
	var breath := GUARD_REST if raised == "block" else GUARD_RESTED
	if near and (max_stamina <= 0 or stamina_fraction() > breath):
		var way := Senses.way_toward(tile, target.tile)
		if way != Vector2i.ZERO and facing != way:
			World.face(self, way)
		if raised != "block":
			World.try_stance(self, "block")
	elif raised == "block":
		World.try_stance(self, "")


## A shield-bearer's bash (World.try_bash, 379; decision 411) at its target
## beside it whose guard is up against it (World.guarding): the guard
## opened and the target staggered, so its next blows land. Never at an
## open foe. Whether it bashed.
func _bash_guard() -> bool:
	return World.bash_ready(self) and not World.guarding(target, self).is_empty() and World.try_bash(self, target)


## A plain blow at its target: its heavy weapon's wind-up, else at once.
func _blow() -> void:
	if World.windup_ticks(self) > 0:
		World.try_wind_up(self, target)
	else:
		World.try_attack(self, target)


## Its target winding a heavy blow up at it (World.winding, 392; decision
## 412): in its reach, a shield-bearer with its bash ready bashes (the
## stagger gives the blow up); else one not bold steps out of reach
## (_step_back), and keeps out till the blow has fallen; a bold one, or one
## with nowhere to step, fights on. Whether that was its turn.
func _meet_wind_up() -> bool:
	var theirs := World.winding(target)
	if theirs.is_empty() or theirs.get("target") != self:
		return false
	var reached := World.in_reach(target, self)
	if reached and World.bash_ready(self) and World.try_bash(self, target):
		return true
	if temper == Temper.BOLD:
		return false
	if not reached:
		return true  # Out of its reach: it keeps out till the blow falls.
	return _step_back() if World.tick >= next_move_tick else true


## Cornered while it flees, with a shield that bashes: a bash at a foe
## beside it (World.try_bash), to shove it off and stagger it, then away.
## Whether it bashed.
func _bash_free() -> bool:
	if not World.bash_ready(self):
		return false
	for entity in World.sought():
		if World.can_melee(tile, entity.tile) and World.try_bash(self, entity):
			return true
	return false


## One of a kind that "picks_up" (decision 349), with a weapon beside it it
## has a free hand for (World.weapon_near), takes it up
## (World.try_pick_up_weapon), and that is its turn. Not fighting it looks
## every PICK_UP_EVERY ticks; [param fighting] (bare-handed), every step.
func _pick_up(fighting: bool) -> bool:
	if not picks_up or World.tick < next_move_tick or World.is_stunned(self):
		return false
	if not fighting:
		if World.tick - _pick_look_tick < PICK_UP_EVERY:
			return false
		_pick_look_tick = World.tick
	if World.weapon_near(self) == World.NO_CELL or not World.try_pick_up_weapon(self):
		return false
	next_move_tick = World.tick + ceili(move_ticks)
	return true


## Whether its arrow would fly to its target: the first body on the shot's
## ray at the angle to it (World.shot_aim, as far as its bow's longest
## step) is the target, so no wall, door or friend is in the way.
func _clear_shot() -> bool:
	var cells := 0
	for hand in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		var verb := Items.verb_of(slots[hand]) if hand < slots.size() and not slots[hand].is_empty() else {}
		if verb.get("kind") == "ranged":
			cells = int(verb["cells"])
	if World.distance(tile, target.tile) > cells or target.tile == tile:
		return false
	if World.shot_aim(self, Vector2(target.tile - tile).angle(), cells).get("hit") != target:
		return false
	# A friend inside even its narrowest cone (decision 620): no shot from here.
	return _cone_clear(deg_to_rad(float(Items.verb_of(World.drawn_with(self)).get("spread_floor", 0.0))))


## A step away from its target, to the free neighbouring cell farthest from
## it (no search); false if none is farther.
func _step_back() -> bool:
	var best := Vector2i.ZERO
	var best_d := World.distance(tile, target.tile)
	for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var d := World.distance(tile + way, target.tile)
		if d > best_d and World.is_free(tile + way):
			best = way
			best_d = d
	return best != Vector2i.ZERO and World.try_move(self, best)


## A blow at its target, as its kind strikes; with a heavy weapon its
## wind-up (World.try_wind_up, decision 392) in place of any of its kind's.
func _strike() -> void:
	if World.windup_ticks(self) > 0:
		World.try_wind_up(self, target)
		return
	match tactic:
		Tactic.HEAVY:
			move_ticks = _pace
			var direction := target.tile - tile
			_windup = {"target": target, "lands": World.tick + WINDUP_TICKS, "direction": direction, "from": tile}
			World.face(self, direction)
			_world_winding(direction, WINDUP_TICKS)
		Tactic.FLANK:
			var behind := Vector2(tile - target.tile).dot(Vector2(target.facing)) < 0.0
			World.try_attack(self, target, attack_damage + (BACKSTAB_DAMAGE if behind else 0))
		_:
			if World.try_attack(self, target) and tactic == Tactic.DART:
				_dart_from = World.tick + DART_AFTER_TICKS
				_dart_until = next_attack_tick - ceili(_pace)


## A wound-up blow (HEAVY): lands when due if its target is still in reach,
## else a whiff; a knock off its tile or a stun spoils it.
func _wind_on() -> void:
	if tile != _windup["from"] or World.is_stunned(self):
		_drop_windup()
		return
	if World.tick < int(_windup["lands"]):
		return
	# Untyped till checked: a target freed since (a player who died or left)
	# cannot be put in a GridEntity.
	var aimed: Variant = _windup["target"]
	var direction: Vector2i = _windup["direction"]
	_windup = {}
	if is_instance_valid(aimed) and (aimed as GridEntity).spawned and World.can_melee(tile, (aimed as GridEntity).tile):
		World.try_attack(self, aimed as GridEntity)
	else:
		World.try_swing(self, direction)


## DART: a step out of its target's reach, as far from it as it can.
func _step_out() -> void:
	if World.tick < next_move_tick:
		return
	var best := Vector2i.ZERO
	var best_score := -INF
	var away := Vector2(tile - target.tile).normalized()
	for direction in World.DIRECTIONS:
		var to := tile + direction
		if World.distance(to, target.tile) < 2 or not World.is_free(to) or not World.is_walkable(to) \
				or not World.can_melee(tile, to):
			continue
		var score := Vector2(direction).normalized().dot(away)
		if score > best_score:
			best = direction
			best_score = score
	if best != Vector2i.ZERO:
		World.try_move(self, best)


## A step toward [param to]; false if there is no way there.
func _go_to(to: Vector2i) -> bool:
	var path := World.find_path(tile, to, false, null, SLOT_SEARCH_TILES, false, {}, opens_doors_now())
	if path.is_empty():
		return false
	World.try_move(self, path[0] - tile)
	return true


## The free tile beside its target that it can strike from and that no
## other monster is making for, nearest first; FLANK sooner behind or
## beside it. Its own (where it stands, or the one it was making for) a
## little sooner, so it does not dither. NO_TILE when there is none.
func _pick_slot() -> Vector2i:
	var claimed := {}
	for entity in World.monsters():
		if entity != self and entity is Monster and (entity as Monster).target == target:
			claimed[(entity as Monster).slot] = true
	var best := NO_TILE
	var best_score := INF
	var facing := Vector2(target.facing).normalized()
	for direction in World.DIRECTIONS:
		var at := target.tile + direction
		if claimed.has(at) or not World.is_walkable(at) or not World.can_melee(at, target.tile):
			continue
		var occupant := World.get_entity_at(at)
		if occupant != null and occupant != self:
			continue
		var score := float(World.distance(tile, at))
		if tactic == Tactic.FLANK:
			score += 3.0 * Vector2(direction).normalized().dot(facing)
		if at == tile or at == slot:
			score -= 0.5
		if score < best_score:
			best = at
			best_score = score
	return best


## FLANK: beside its target's front (where it faces, or either side of it).
func _in_front() -> bool:
	return Vector2(tile - target.tile).normalized().dot(Vector2(target.facing).normalized()) > 0.5


## [param need] others already at its target, or its target under half its hp.
func _target_beset(need := 1) -> bool:
	if target.max_hp > 0 and target.hp * 2 < target.max_hp:
		return true
	var at := 0
	for direction in World.DIRECTIONS:
		# The cells round it, not every monster (perf: most hold back now).
		var other := World.get_entity_at(target.tile + direction)
		if other != null and other != self and other is Monster and World.are_adjacent(other.tile, target.tile):
			at += 1
			if at >= need:
				return true
	return false


## The nearest player, or companion whose owner is online, it sees
## (Senses.sees); the one it has kept unless another is RETARGET_TILES
## nearer. One bearing its kind's bane it sees bane_notice times farther;
## one bearing a grudge against its kind it goes for first (417; decision
## 420). A kind whose faction fights others on sight (foes, decision 545)
## looks for their monsters and the residents too. Entities still in their
## spawn grace are passed over.
func _nearest_visible_target() -> GridEntity:
	if idle == Idle.HOMEWARD:
		return _in_the_way()
	var marks := _marks(World.kind_of(self))
	var bane: Array[GridEntity] = marks["bane"]
	# Nobody near enough to be seen: its tier's measure (a few ticks old,
	# nobody come or gone since) is beyond its sight by more than anyone
	# could close meanwhile. Most looks end here.
	if target == null and raid == "" and nearest_sought > sight_range + LOOK_MARGIN_TILES \
			and tier_comings == World.zone.comings and World.tick - tier_tick < World.TIER_EVERY_TICKS \
			and bane.is_empty() and foes.is_empty():
		return null
	var grudge: Array[GridEntity] = marks["grudge"]
	var farther := float(Items.growth()["bane_notice"]) if not bane.is_empty() else 1.0
	var nearest: GridEntity = null
	var nearest_distance := ceili(sight_range * maxf(farther, 1.0)) + 1
	var grudged: GridEntity = null
	var grudged_distance := nearest_distance
	var kept := -1
	_glimpsed = NO_TILE
	for entity in World.sought():
		# Out of sight range first: a few sums, where most looks end.
		var at := entity.tile
		var d := maxi(absi(at.x - tile.x), absi(at.y - tile.y))
		var times := farther if entity in bane else 1.0
		if d > sight_range * times or entity.protected or World.is_downed(entity):
			continue  # Too far, in its spawn grace, or downed (no finishing blows: decision 544).
		if keeps_room and not _room.has_point(at):
			continue  # Outside the room it keeps.
		if entity is Player or (entity is Companion and entity.keeper != null):
			if not _given_up.is_empty() and _letting_be(entity):
				continue
			# Its target it follows, cone or not (it turns as it goes).
			if senses.sees(entity, d, entity != target, times):
				if entity == target:
					kept = d
				if d < nearest_distance:
					nearest = entity
					nearest_distance = d
				if entity in grudge and d < grudged_distance:
					grudged = entity
					grudged_distance = d
			elif _wary and alert == Alert.IDLE and _glimpsed == NO_TILE and senses.glimpses(entity, d):
				_glimpsed = at
	if raid != "":
		# A raider goes for the town's folk too (decision 333): they run, and
		# beaten down they are taken (Raids._spared).
		for entity in World.townsfolk():
			var d := World.distance(tile, entity.tile)
			if d <= sight_range and d < nearest_distance and senses.sees(entity, d, entity != target):
				if entity == target:
					kept = d
				nearest = entity
				nearest_distance = d
	if not foes.is_empty():
		# Its side's enemies on sight (decision 545): the barrow's dead and
		# robbers at each other, and both at the residents (Pip).
		var factions := _factions()
		var others: Array[GridEntity] = []
		if raid == "" and "town" in foes:
			others.append_array(World.townsfolk())  # A raider has already looked (above).
		for entity in World.monsters():
			if entity != self and not entity is Animal and factions.of_kind(World.kind_of(entity)) in foes:
				others.append(entity)
		for entity in others:
			var d := World.distance(tile, entity.tile)
			if d <= sight_range and d < nearest_distance and not entity.protected \
					and (not keeps_room or _room.has_point(entity.tile)) and senses.sees(entity, d, entity != target):
				if entity == target:
					kept = d
				nearest = entity
				nearest_distance = d
	if grudged != null:
		return grudged  # Its kind's grudge-bearer first, near or far.
	if tactic != Tactic.PLAIN and kept >= 0 and kept - nearest_distance < RETARGET_TILES:
		return target
	return nearest


## Nobody in sight: the newest noise it has not turned to yet, if fresh,
## turns it that way, and it holds still a moment (LISTEN_TICKS) to look.
## That noise ({} for none).
func _listen() -> Dictionary:
	if senses.heard.is_empty() or World.tick < next_move_tick or World.is_stunned(self):
		return {}
	var noise: Dictionary = senses.heard.back()
	var heard_at := int(noise["tick"])
	if heard_at <= _listened_tick:
		return {}
	_listened_tick = heard_at
	if World.tick - heard_at > LISTEN_STALE_TICKS:
		return {}
	var way := Senses.way_toward(tile, noise["at"])
	if way != Vector2i.ZERO:
		World.face(self, way)
	pose = Pose.STAND
	_glancing = true  # A guard turns back to its way after (_guard).
	_listening_until = World.tick + LISTEN_TICKS
	return noise


# --- Alertness ------------------------------------------------------------------

## Nobody in sight: a monster of no kind listens and idles; one of a kind is
## roused by what it hears or glimpses, and goes to look (_search) till it
## gives up.
func _alert_tick() -> void:
	var noise := _listen()
	if not _wary or idle == Idle.HOMEWARD or keeps_room:
		_idle_tick()  # The dead on their way home, a room's guard: no going to look.
		return
	if not noise.is_empty():
		_heard(noise)
	elif _glimpsed != NO_TILE and alert == Alert.IDLE:
		_follow(_glimpsed, Alert.SUSPICIOUS, SUSPICIOUS_TICKS)
	if alert == Alert.IDLE:
		_idle_tick()
		return
	if _beyond_leash():
		# The quarry may be gone (a player who died): a freed one can't be
		# passed as a GridEntity.
		_give_up(_quarry if is_instance_valid(_quarry) else null)
		return
	if World.tick >= _alert_until:
		if alert == Alert.HUNTING:
			alert = Alert.SUSPICIOUS  # A last look about, then back.
			_follow(tile, Alert.SUSPICIOUS, SUSPICIOUS_TICKS / 2)
		else:
			_give_up(null)
			return
	_search()


## What a noise rouses it to: a fight (not through a wall), a door struck
## or broken, something smashed, a shout, to hunt; the rest to look. A
## blow on itself from someone it does not see, to hunt the one who struck
## it.
func _heard(noise: Dictionary) -> void:
	var at: Vector2i = noise["at"]
	var kind: StringName = noise["kind"]
	var urgent: bool = (kind == &"fight" and not noise.get("muffled", false)) or kind in [&"door_struck", &"door_broken", &"break"] \
			or int(noise["radius"]) >= Senses.NOISE_SHOUT
	var source: Variant = noise["source"]
	if kind == &"rout":
		return  # Its side breaking: _heard_rout.
	if kind == &"call" and source is Monster and _same_side(source):
		# Its side calling for help: after whom they fight.
		var caller := source as Monster
		_listening_until = -1
		_follow(caller.target.tile if is_instance_valid(caller.target) else caller.tile, Alert.HUNTING, HUNT_TICKS)
		return
	if at == tile and kind == &"fight" and is_instance_valid(source) and source != self:
		var striker := source as GridEntity
		_given_up.erase(striker.get_instance_id())
		_quarry = striker
		at = striker.tile
	if urgent:
		_listening_until = -1
	_follow(at, Alert.HUNTING if urgent else Alert.SUSPICIOUS, HUNT_TICKS if urgent else SUSPICIOUS_TICKS)


## [param lost] went out of its sight: after it, to where it last saw it and
## on HUNT_ON_TILES the way it was going. False (no hunt) for a monster of
## no kind, one gone, or one it has given up on; nor one downed, not lost but
## fallen (Mortally Wounded: it goes back to its idle, and does not stand
## over the body while it could be raised).
func _hunt(lost: GridEntity) -> bool:
	if not _wary or idle == Idle.HOMEWARD or keeps_room or lost == null or not is_instance_valid(lost) or not lost.spawned \
			or _given_up.has(lost.get_instance_id()) or World.is_downed(lost):
		return false
	_quarry = lost
	var lead := _quarry_at if _quarry_at != NO_TILE else tile
	if _quarry_from != NO_TILE and _quarry_at != NO_TILE:
		var way := Vector2i(signi(_quarry_at.x - _quarry_from.x), signi(_quarry_at.y - _quarry_from.y))
		for n in range(HUNT_ON_TILES, 0, -1):
			var on := _quarry_at + way * n
			if World.is_walkable(on) and World.has_clear_line(_quarry_at, on):
				lead = on
				break
	_follow(lead, Alert.HUNTING, HUNT_TICKS, lead != _quarry_at)
	_lead_seen = _quarry_at
	_evidence_tick = World.tick
	return true


## Off to [param lead] at [param level] (a hunt stays a hunt for a lesser
## lead), for [param ticks] from now; it looks round when there. A
## [param guess] is no reason to open a door to it.
func _follow(lead: Vector2i, level: Alert, ticks: int, guess := false) -> void:
	if alert == Alert.IDLE:
		_post = tile
	if not (alert == Alert.HUNTING and level == Alert.SUSPICIOUS):
		alert = level
	_alert_until = World.tick + ticks
	_lead = lead
	_lead_guess = guess
	_lead_seen = NO_TILE
	if not guess:
		_evidence_tick = World.tick
	_looks = 0
	_look_until = -1
	_returning = false
	pose = Pose.STAND


## SUSPICIOUS or HUNTING: a step toward its lead (at its idle pace or its
## chase pace), else, there or with no way there, a look round.
func _search() -> void:
	if World.is_stunned(self) or World.tick < next_move_tick or World.tick < _listening_until \
			or World.tick < _look_until:
		return
	move_ticks = _pace if alert == Alert.HUNTING else _pace * IDLE_PACE
	if _bash_key != NO_DOOR and _bash():
		return
	if _lead != NO_TILE and tile != _lead:
		if _idle_step(_lead):
			return
		if _lead_guess and _lead_seen != NO_TILE and _lead_seen != _lead:
			_lead = _lead_seen  # No way on: where it saw them, then.
			_lead_guess = false
			return
		# A way that failed with doors open has no door to blame; but one
		# that failed only for someone standing there may be a way to beside
		# them (the door search ignores who stands at the goal, and keeps
		# that way as its idle path).
		var opens := opens_doors_now()
		var occupied := World.get_entity_at(_lead) != null
		var door := {} if opens and not occupied else _door_on_way(_lead)
		if opens:
			door = {}
		if door.is_empty() and _idle_path_to == _lead and not _idle_path.is_empty():
			return  # On along it to beside them.
		if not door.is_empty():
			# A closed door it will not open now: it breaks it (one that
			# cannot open doors, with a reason), else it goes to the door
			# and listens there.
			if not opens_doors and _has_reason():
				_bash_key = door["key"]
				return
			if tile != door["near"]:
				_lead = door["near"]
				_lead_guess = true  # Nothing beyond the door says go on.
				return
		# No way there (a crowd, a wall): it looks from here.
		_lead = NO_TILE
		next_move_tick = World.tick + CHASE_RETRY_TICKS
		return
	if _looks < LOOK_ROUND.size():
		World.face(self, turned(facing, LOOK_ROUND[_looks]))
		_looks += 1
		_look_until = World.tick + LOOK_TICKS


## Whether it is charging as it steps: a HEAVY one closing its last
## CHARGE_RANGE on its target at CHARGE_PACE (a braced spear stops it, items'
## weapons-as-verbs).
func charging() -> bool:
	return _charging and alert == Alert.FIGHTING and is_instance_valid(target)


## Whether it walks through closed doors now: one that opens doors does
## as it idles, goes back and fights; looking or hunting, only with a
## reason beyond (_has_reason).
func opens_doors_now() -> bool:
	if not opens_doors:
		return false
	if alert == Alert.SUSPICIOUS or alert == Alert.HUNTING:
		return _has_reason()
	return true


## Something real behind its lead, heard or seen no longer than
## DOOR_FRESH_TICKS ago.
func _has_reason() -> bool:
	return not _lead_guess and World.tick - _evidence_tick <= DOOR_FRESH_TICKS


## The first closed door on its way to [param to] were doors open, and the
## tile before it ({key, near}); {} for none (the same capped search). With
## no door on it, the way up to [param to] (whoever stands there) is kept as
## its idle path, for _search to go on along: the way failed only for them.
func _door_on_way(to: Vector2i) -> Dictionary:
	# The answer kept a while for the same goal from the same tile (perf: a
	# search of IDLE_SEARCH_TILES each time it was asked).
	if _door_way.get("to") == to and _door_way.get("from") == tile \
			and World.tick - int(_door_way.get("tick", -100000)) < DOOR_WAY_TICKS:
		return _door_way["door"]
	var found := _first_door_on_way(to)
	_door_way = {"to": to, "from": tile, "tick": World.tick, "door": found}
	return found


func _first_door_on_way(to: Vector2i) -> Dictionary:
	var path := World.find_path(tile, to, true, null, IDLE_SEARCH_TILES)  # Someone may stand there.
	var at := tile
	for next in path:
		var step := next - at
		# A diagonal step goes by one of its two straight ways: either's doors.
		var legs: Array = [[at, step]] if step.x == 0 or step.y == 0 else [
			[at, Vector2i(step.x, 0)], [at + Vector2i(step.x, 0), Vector2i(0, step.y)],
			[at, Vector2i(0, step.y)], [at + Vector2i(0, step.y), Vector2i(step.x, 0)]]
		for leg: Array in legs:
			var door := World.door_across(leg[0], leg[1])
			if door != null and not door.is_open():
				return {"key": door.key, "near": leg[0]}
		at = next
	if path.size() > 1 and path.back() == to:
		_idle_path = path.slice(0, path.size() - 1)
		_idle_path_to = to
	return {}


## Breaking the door _bash_key: to it, then a blow whenever it can. False
## (and done with it) once it is open or broken.
func _bash() -> bool:
	var door := World.door_on(_bash_key)
	if door == null or door.is_open():
		_bash_key = NO_DOOR
		return false
	var sides := Terrain.edge_cells(_bash_key)
	if tile in sides:
		World.try_bash_door(self, _bash_key, attack_damage * door_force)
		return true
	var near: Vector2i = sides[0] if World.distance(tile, sides[0]) <= World.distance(tile, sides[1]) else sides[1]
	if not _idle_step(near):
		_bash_key = NO_DOOR
		return false
	return true


## More than LEASH from where it took up the chase; a room keeper's leash
## is its room (out of it, not how far it came: the draugr, taking up his
## fight at his throne, gave up 12 cells into his 32-cell hall).
func _beyond_leash() -> bool:
	if keeps_room and _room.has_area():
		return not _room.has_point(tile)
	return _post != NO_TILE and World.distance(tile, _post) > leash


## Lets [param who] be for GIVE_UP_TICKS (null: nobody in particular), and
## goes back to where it idles.
func _give_up(who: GridEntity) -> void:
	if who != null and is_instance_valid(who):
		_given_up[who.get_instance_id()] = World.tick + GIVE_UP_TICKS
	_calm()
	_returning = idle != Idle.NONE


## Whether it lets [param entity] be (given up on it, a while yet, and it is
## not back near where it took up the chase).
func _letting_be(entity: GridEntity) -> bool:
	var id := entity.get_instance_id()
	var until: int = _given_up.get(id, -1)
	if until < World.tick:
		_given_up.erase(id)
		return false
	return _post == NO_TILE or World.distance(entity.tile, _post) > leash / 2


## Back to IDLE: a monster that was looking or hunting goes back to where it
## idles (the world tick's walk, when far).
func _calm() -> void:
	if alert == Alert.SUSPICIOUS or alert == Alert.HUNTING or alert == Alert.FLEEING:
		_returning = idle != Idle.NONE
		_idle_goal = NO_TILE
	alert = Alert.IDLE
	_lead = NO_TILE
	_lead_guess = false
	_quarry = null
	_bash_key = NO_DOOR


# --- Kinds (levels/monsters.json) ---------------------------------------------------

## Every kind's row in KINDS_PATH, read once: kind -> {body, tactic (Tactic),
## idle (Idle), opens_doors, door_force, leash, temperament (Temper ->
## weight)}. A row that will not read is left out, with a warning; a field
## missing or wrong falls back to a monster of no kind's.
## What it leaves where it falls (decision 318): its kind's "drops" (each
## {item, count: [least, most], chance}, levels/monsters.json), made now
## (ItemBook.mint, "remains" of it), as many of each as dropped rolls,
## seeded by its name and the tick. World.damage lays them on the ground,
## and its purse_gold beside them. Server only.
func remains() -> Array[int]:
	var uids: Array[int] = []
	var row: Dictionary = kinds().get(str(spawn_spec.get("kind", "")), {})
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%s/remains/%d" % [name, World.tick])
	for drop: Variant in row.get("drops", []):
		for i in dropped(drop, roll):
			# Its make (decision 474): the row's own, else this monster's.
			var style := str(drop.get("style", World.style_from(self)))
			var uid := World.items.mint(str(drop["item"]), "remains", World._label_of(self), zone, tile, style)
			World.items.mark_grave(uid, World.grave_from(self), zone, tile)  # Decision 555.
			uids.append(uid)
	return uids


## The gold it leaves where it falls (decision 601; Jeff: "gold drop from
## humanoid enemies"; 601 amended, Jeff: "consolidate gold coins to being
## stackable in the inventory but not taking up a pack slot"): a roll of
## its kind's "purse" [least, most], seeded by its name and the tick; 0
## for a row without one (animals, the undead). Never a thing: World.damage
## drops it on the ground as a count (World.drop_gold), minted, a small
## leak into the economy. Server only.
func purse_gold() -> int:
	var row: Dictionary = kinds().get(str(spawn_spec.get("kind", "")), {})
	var purse: Array = row.get("purse", [0, 0])
	if purse.size() != 2 or int(purse[1]) <= 0:
		return 0
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%s/purse/%d" % [name, World.tick])
	return roll.randi_range(int(purse[0]), int(purse[1]))


## What it leaves at its feet when it yields rather than dies (decision
## 603, items' side; Jeff: "the draugr will have a large battle axe that he drops as
## loot"): its kind's "yields" rows (drops' shape), minted now ("remains"
## of it, its make) and laid on the ground where it stands. The caller says
## when (the draugr: once per pact won, in Draugr's yield path); a lost pact or an
## unpaid fight never asks. The uids laid. Server only.
func yielded() -> Array[int]:
	var uids: Array[int] = []
	if not Net.is_authority():
		return uids
	var row: Dictionary = kinds().get(str(spawn_spec.get("kind", "")), {})
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%s/yielded/%d" % [name, World.tick])
	for drop: Variant in row.get("yields", []):
		for i in dropped(drop, roll):
			var uid := World.items.mint(str(drop["item"]), "remains", World._label_of(self), zone, tile, str(drop.get("style", World.style_from(self))))
			if World.put_on_ground(uid, tile) == World.NO_CELL:
				World.items.end(uid, "lost", "no ground at %s" % tile, zone, tile)
				continue
			uids.append(uid)
	return uids


## How many of drop row [param drop] fall, by [param roll]: none if its
## "chance" (decision 481: a kobold's pick 1 in 5; 1 when absent, and then
## no roll is spent on it) fails, else a roll between its count's least and
## most. 0 for a row with no item.
static func dropped(drop: Variant, roll: RandomNumberGenerator) -> int:
	if not drop is Dictionary or str(drop.get("item", "")).is_empty():
		return 0
	if drop.has("chance") and roll.randf() >= float(drop["chance"]):
		return 0
	var count: Variant = drop.get("count", [1, 1])
	var least := int(count[0]) if count is Array and count.size() > 0 else 1
	var most := int(count[1]) if count is Array and count.size() > 1 else least
	return roll.randi_range(least, maxi(least, most))


static func kinds() -> Dictionary:
	if _kinds.is_empty():
		_kinds = read_kinds(KINDS_PATH)
	return _kinds


## The kinds in [param path] (see kinds).
static func read_kinds(path: String) -> Dictionary:
	var out := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		push_warning("[monsters] %s is missing or not a JSON object: no kinds" % path)
		return out
	for kind: String in parsed:
		var row: Variant = parsed[kind]
		if not row is Dictionary:
			push_warning("[monsters] %s: %s is not a kind" % [path, kind])
			continue
		var body: Variant = row.get("body", {})
		var tactic_name := str(row.get("tactic", "plain"))
		var idle_name := str(row.get("idle", "none"))
		if not TACTIC_NAMES.has(tactic_name):
			push_warning("[monsters] %s: %s's tactic %s is none of %s" % [path, kind, tactic_name, TACTIC_NAMES.keys()])
		if not IDLE_MODES.has(idle_name):
			push_warning("[monsters] %s: %s's idle %s is none of %s" % [path, kind, idle_name, IDLE_MODES.keys()])
		var weights := {}
		var given: Variant = row.get("temperament", {})
		for temper_name: String in TEMPER_NAMES:
			weights[TEMPER_NAMES[temper_name]] = maxf(0.0, float(given.get(temper_name, 0)) if given is Dictionary else 0.0)
		var props := {}
		if body is Dictionary:
			for key: String in body:
				# JSON's numbers are floats: a whole one is an int, as the
				# props were, but for those that are floats (FLOAT_PROPS).
				var value: Variant = body[key]
				props[key] = int(value) if value is float and value == floorf(value) and key not in FLOAT_PROPS else value
		out[kind] = {"body": props, "tactic": TACTIC_NAMES.get(tactic_name, Tactic.PLAIN),
			"idle": IDLE_MODES.get(idle_name, Idle.NONE), "opens_doors": bool(row.get("opens_doors", true)),
			"door_force": int(row.get("door_force", 1)), "leash": int(row.get("leash", LEASH)), "temperament": weights,
			"strength": maxf(0.0, float(row.get("strength", 0.0))), "side": str(row.get("side", "")),
			"role": str(row.get("role", "")), "herd": str(row.get("herd", kind)),
			"diet": (row.get("diet", []) as Array).duplicate() if row.get("diet") is Array else [],
			"drops": (row.get("drops", []) as Array).duplicate(true) if row.get("drops") is Array else [],
			"purse": _purse(row.get("purse")),
			"yields": (row.get("yields", []) as Array).duplicate(true) if row.get("yields") is Array else [],
			"wields": (row["wields"] as Dictionary).duplicate() if row.get("wields") is Dictionary else {},
			"picks_up": bool(row.get("picks_up", false)), "art": str(row.get("art", "")),
			"label": str(row.get("label", "")), "fearless": bool(row.get("fearless", false)),
			"keeps_room": bool(row.get("keeps_room", false)), "script": str(row.get("script", "")),
			"call": int(row.get("call", Senses.NOISE_CALL)),
			# Kept, or a peer reading the row never sees them: the client's
			# person_words (the robbers drawn as people), the boss's breath.
			"person": str(row.get("person", "")), "swing_stamina": bool(row.get("swing_stamina", false)),
			"stamina_regen_every": maxi(1, int(row.get("stamina_regen_every", 1))),
			"waves": (row["waves"] as Array).duplicate(true) if row.get("waves") is Array else [],
			"stamina_regen": maxi(0, int(row.get("stamina_regen", 0))),
			"blows": _blows(kind, row.get("blows")),
			"aim_spread": _aim_spread(path, kind, row.get("aim_spread", 0.0)),
			"aim_hold_max": maxi(0, int(row.get("aim_hold_max", 0)))}
	return out


## A row's "aim_spread" (decision 620, enemy-ai's side): degrees, raised to
## the bow's spread_floor with a warning (under it, it would loose only on
## its hold cap); 0 for none. Every archer kind arms "bow" today.
static func _aim_spread(path: String, kind: String, value: Variant) -> float:
	var spread := maxf(0.0, float(value)) if value is float or value is int else 0.0
	var floor_at := float(Items.verb_of("bow").get("spread_floor", 0.0))
	if spread > 0.0 and spread < floor_at:
		push_warning("[monsters] %s: %s's aim_spread %s is under the bow's floor %s: raised" % [path, kind, spread, floor_at])
		spread = floor_at
	return spread


## A row's "blows" (603 amended): item id to the kind's own verb with it,
## each filled in as a catalog verb is (Items.verb_from); an unknown item
## or a verb of no known kind is left out.
static func _blows(kind: String, given: Variant) -> Dictionary:
	var out := {}
	if not given is Dictionary:
		return out
	for id: String in given:
		var verb := Items.verb_from("%s's blow with %s" % [kind, id], given[id]) if given[id] is Dictionary and Items.exists(id) else {}
		if verb.is_empty():
			push_warning("Monster: %s's blow with %s left out" % [kind, id])
			continue
		out[id] = verb
	return out


## A row's "purse" (decision 601): [least, most] whole gold, least at
## least 0 and most at least least; [0, 0] (none) for anything else.
static func _purse(value: Variant) -> Array:
	if value is not Array or (value as Array).size() != 2 or not ((value[0] is float or value[0] is int) and (value[1] is float or value[1] is int)):
		return [0, 0]
	var least := maxi(int(value[0]), 0)
	return [least, maxi(int(value[1]), least)]


## Each kind's body (mass, hp, pace, blows): what Level.MONSTER_TYPES gives a
## marker of that kind.
static func bodies() -> Dictionary:
	var out := {}
	for kind: String in kinds():
		out[kind] = (kinds()[kind]["body"] as Dictionary).duplicate()
	return out


## The art slot a view draws a monster of [param kind] from (its row's
## "art", an ArtKit slot such as "creature.boar"); "" for none, a stand-in.
## Any peer: the kind comes with the spawn (spawn_spec "kind").
static func art_of(kind: String) -> String:
	return str(kinds().get(kind, {}).get("art", ""))


## How a monster of [param kind] idles when its level entry does not say.
static func idle_of(kind: String) -> Idle:
	return kinds()[kind]["idle"] if kinds().has(kind) else Idle.NONE


## Its temperament: its level entry's ("temperament"), else one of its
## kind's by their weights, drawn by its name (the same every time).
func _settle_temper(kind: String) -> void:
	var given := str(spawn_spec.get("temperament", ""))
	if TEMPER_NAMES.has(given):
		temper = TEMPER_NAMES[given]
	else:
		var weights: Dictionary = kinds()[kind]["temperament"]
		var total := 0.0
		for w: float in weights.values():
			total += w
		var draw := RandomNumberGenerator.new()
		draw.seed = hash(String(name) + "/temper")
		var pick := draw.randf() * total
		temper = Temper.CAUTIOUS
		for t: Temper in [Temper.BOLD, Temper.CAUTIOUS, Temper.COWARDLY]:
			pick -= float(weights.get(t, 0.0))
			if pick < 0.0 and float(weights.get(t, 0.0)) > 0.0:
				temper = t
				break
	# Its boldness (holding back, _target_beset) within its temperament's span.
	var span: Vector2 = BOLDNESS[temper]
	boldness = lerpf(span.x, span.y, boldness)


# --- Fleeing, calls and routs -------------------------------------------------------

## How many others it waits for at its target before it closes in: a
## coward two, the cautious one (two at a dread holder), the bold one.
func _others_needed() -> int:
	if temper == Temper.COWARDLY or temper == Temper.CAUTIOUS and _dreads_target():
		return 2
	return 1


## Once, its first tick: the arrows in its hands worn or not
## (WORN_BUNDLE_CHANCE), drawn by its name. Only a bundle with no instance
## yet, as its level arms it: one from a save keeps its condition.
func _wear_bundle() -> void:
	_bundle_rolled = true
	var hand := World.bundle_slot(self)
	if hand < 0 or hand < slot_items.size() and slot_items[hand] != 0:
		return
	var draw := RandomNumberGenerator.new()
	draw.seed = hash(String(name) + "/bundle")
	if draw.randf() >= WORN_BUNDLE_CHANCE:
		return
	World.items.set_condition(World.slot_uid(self, hand), draw.randi_range(WORN_BUNDLE.x, WORN_BUNDLE.y))


## Whether its target holds a dread thing and it minds (not bold; an
## animal never: a wolf is cautious by its row, but knows no names).
func _dreads_target() -> bool:
	if not is_instance_valid(target):
		return false
	var kind := World.kind_of(self)
	if not kind.is_empty() and World.holder_bane(target, kind):
		return true  # Its kind's bane (417; decision 420): whatever its temper, a beast too.
	return temper != Temper.BOLD and not self is Animal and World.holder_dread(target)


## The bearers among World.sought() of its kind's bane and of a grudge
## against its kind (World.holder_bane, holder_grudge; 417, decision 420):
## {bane: [], grudge: []}, looked up once a tick a kind.
static var _marked := {}
static func _marks(kind: String) -> Dictionary:
	var had: Dictionary = _marked.get(kind, {})
	if had.get("tick", -1) == World.tick and had.get("zone") == World.zone:
		return had
	var bane: Array[GridEntity] = []
	var grudge: Array[GridEntity] = []
	for entity in World.sought() if not kind.is_empty() else []:  # A kindless one has no bane.
		if World.holder_bane(entity, kind):
			bane.append(entity)
		if World.holder_grudge(entity, kind):
			grudge.append(entity)
	had = {"tick": World.tick, "zone": World.zone, "bane": bane, "grudge": grudge}
	_marked[kind] = had
	return had


## Fighting: whether it breaks and runs (FLEE_BELOW of its hp, DREAD_FLEE_BELOW
## for the cautious at a dread holder, or a coward alone against two or more
## near, a dread holder counted as two).
func _should_flee() -> bool:
	if fearless:
		return false
	var dreaded := _dreads_target()
	var below := float(FLEE_BELOW[temper])
	if dreaded and temper == Temper.CAUTIOUS:
		below = maxf(below, DREAD_FLEE_BELOW)
	if max_hp > 0 and hp < max_hp * below:
		return true
	if temper != Temper.COWARDLY:
		return false
	var foes := 0
	for entity in World.sought():
		if World.distance(tile, entity.tile) <= COWARD_ODDS_TILES:
			foes += 2 if dreaded and entity == target else 1
	if foes < 2:
		return false
	for dy in range(-COWARD_ODDS_TILES, COWARD_ODDS_TILES + 1):
		for dx in range(-COWARD_ODDS_TILES, COWARD_ODDS_TILES + 1):
			var other := World.get_entity_at(tile + Vector2i(dx, dy))
			if other != null and other != self and other is Monster:
				return false  # Not alone.
	return true


## It breaks: away from [param threat] for FLEE_TICKS (more while the threat
## is near); one that breaks of itself ([param routs]: hurt, outnumbered,
## not routed) is a rout to those of its side who hear it, who may break
## too. A routed one does not rout others again, or a rout would echo.
func _flee(threat: Vector2i, routs := true) -> void:
	if alert == Alert.IDLE:
		_post = tile
	alert = Alert.FLEEING
	_flee_from = threat
	_alert_until = World.tick + FLEE_TICKS
	target = null
	slot = NO_TILE
	_drop_windup()
	_bash_key = NO_DOOR
	_lead = NO_TILE
	move_ticks = _pace
	if routs:
		_cry(&"rout", Senses.NOISE_ROUT)


## FLEEING: a step away from what it runs from, toward its post if that is
## away from it; recovering (SUSPICIOUS, then back) once nobody has been
## near for FLEE_TICKS.
func _flee_tick() -> void:
	for entity in World.sought():
		if World.distance(tile, entity.tile) <= FLEE_NEAR_TILES:
			_alert_until = World.tick + FLEE_TICKS
			_flee_from = entity.tile
			break
	if World.tick >= _alert_until:
		alert = Alert.SUSPICIOUS
		_follow(tile, Alert.SUSPICIOUS, SUSPICIOUS_TICKS / 2)  # A look about, then back.
		return
	if World.is_stunned(self) or World.tick < next_move_tick:
		return
	var goal := _flee_goal()
	if goal == NO_TILE or goal == tile or not _idle_step(goal):
		if _bash_free():
			return  # Shoved off: away next.
		next_move_tick = World.tick + CHASE_RETRY_TICKS  # Cornered: a moment, then again.


## Where it runs to: its post if that is farther from the threat than it
## is, else the farthest walkable tile of a few straight away from it.
func _flee_goal() -> Vector2i:
	if _post != NO_TILE and _post != tile \
			and World.distance(_post, _flee_from) > World.distance(tile, _flee_from) + 1:
		return _post
	var away := Vector2i(signi(tile.x - _flee_from.x), signi(tile.y - _flee_from.y))
	if away == Vector2i.ZERO:
		away = -facing
	for n in range(FLEE_TILES, 0, -1):
		for way: Vector2i in [away, Vector2i(away.x, 0), Vector2i(0, away.y)]:
			var at := tile + way * n
			if way != Vector2i.ZERO and World.is_walkable(at) and World.is_free(at):
				return at
	return NO_TILE


## A call for help, at most every CALL_EVERY_TICKS: those of its side who
## hear it come after its target.
func _call_for_help() -> void:
	if World.tick - _called_tick < CALL_EVERY_TICKS:
		return
	_called_tick = World.tick
	_cry(&"call", call_reach)


## Whether [param other] is of its side (Factions.of_kind, allies one side,
## decision 416; with no factions, every monster of a kind is).
## The world's factions (Holdings'), or levels/factions.json read once where
## there are no holdings (a test, a tool).
static func _factions() -> Factions:
	if World.holdings != null:
		return World.holdings.factions
	if _read_factions == null:
		_read_factions = Factions.read()
	return _read_factions


static var _read_factions: Factions


func _same_side(other: GridEntity) -> bool:
	if not other is Monster or not (other as Monster)._wary or other is Animal:
		return false  # An animal is of no side but its herd's (Animal).
	var mine := str(spawn_spec.get("kind", ""))
	var theirs := str(other.spawn_spec.get("kind", ""))
	var factions: Factions = World.holdings.factions if World.holdings != null else null
	if factions == null:
		return true
	return factions.same_side(factions.of_kind(mine), factions.of_kind(theirs))


## A rout heard since it last looked, from its side: a coward breaks, and
## a cautious one under ROUT_HURT of its hp.
func _heard_rout() -> bool:
	if senses.last_tick <= _rout_tick:
		return false
	var since := _rout_tick
	_rout_tick = int(senses.heard.back()["tick"])
	if temper == Temper.BOLD:
		return false
	for noise: Dictionary in senses.heard:
		if int(noise["tick"]) <= since or noise["kind"] != &"rout":
			continue
		var source: Variant = noise["source"]
		if source == self or not is_instance_valid(source) or not _same_side(source):
			continue
		if temper == Temper.COWARDLY or (max_hp > 0 and hp < max_hp * ROUT_HURT):
			_flee(noise["at"], false)
			return true
	return false


# --- Idling ---------------------------------------------------------------------

## Nobody in sight: back from a fight first, then as it idles; slower than
## it chases.
func _idle_tick() -> void:
	if not idling or idle == Idle.NONE or World.is_stunned(self) or World.tick < next_move_tick \
			or World.tick < _listening_until:
		return
	if World.tick < _idle_from and not _returning:
		return  # Just woken: in a moment of its own.
	move_ticks = _pace * IDLE_PACE
	if _returning:
		var back := _back_to()
		if back == NO_TILE or tile == back or not _idle_step(back):
			_returning = false
			_idle_until = World.tick + _idle_rng.randi_range(PATROL_PAUSE_TICKS.x, PATROL_PAUSE_TICKS.y)
		return
	match idle:
		Idle.GUARD:
			_guard()
		Idle.WANDER:
			_wander()
		Idle.PATROL:
			_patrol()
		Idle.GATHER:
			_gather()
		Idle.MARCH:
			_march()
		Idle.HOMEWARD:
			_homeward()


## Where it goes back to after a fight: home, or (PATROL) the nearest
## waypoint of its route, or (GATHER) its place at the point.
func _back_to() -> Vector2i:
	match idle:
		Idle.HOMEWARD:
			return grave if grave != NO_TILE else home
		Idle.PATROL:
			_ensure_route()
			if route.is_empty():
				return home
			var nearest := 0
			for i in route.size():
				if World.distance(tile, route[i]) < World.distance(tile, route[nearest]):
					nearest = i
			_route_index = nearest
			return route[nearest]
		Idle.GATHER:
			return _gather_place()
		Idle.MARCH:
			return route[mini(_route_index, route.size() - 1)] if not route.is_empty() else home
	return home


## MARCH: on to its route's next waypoint (near enough is there), to the
## last; there it stands. A step it cannot take now (a crowd, no way found)
## is tried again in a moment.
func _march() -> void:
	if route.is_empty() or World.tick < _idle_until:
		return
	var last := route.size() - 1
	_route_index = mini(_route_index, last)
	var to := route[_route_index]
	var near := 0 if _route_index == last else MARCH_NEAR
	if World.distance(tile, to) <= near:
		_route_index = mini(_route_index + 1, last)
		return
	if not _idle_step(to):
		if _route_index < last and World.distance(tile, to) <= MARCH_NEAR * 2:
			_route_index += 1  # Crowded round it: on to the next.
		_idle_until = World.tick + MARCH_RETRY_TICKS


## HOMEWARD: on toward its grave (chosen the first time), down when there.
## A step it cannot take: whoever stands in its way on a cell nearer home
## it fights (_blocker); one of its own side it waits behind.
func _homeward() -> void:
	if World.tick < _idle_until or not _settle_grave():
		return
	if tile == grave:
		lay_down()
		return
	if _idle_step(grave, HOMEWARD_SEARCH_TILES):
		return
	# Blocked (decision 561, 547's "in the way" amended): it waits
	# BLOCKED_WAIT_TICKS for the same one, stepping aside, before it fights.
	var blocker := _blocker()
	if blocker != null:
		if blocker != _blocked_by or World.tick - _blocked_last > BLOCKED_FORGET_TICKS:
			_blocked_by = blocker
			_blocked_since = World.tick
		_blocked_last = World.tick
		if World.tick - _blocked_since >= BLOCKED_WAIT_TICKS:
			_provoked = blocker
		else:
			_step_aside(blocker)
	_idle_until = World.tick + MARCH_RETRY_TICKS


## Out of [param blocker]'s way: a step straight back from it, else to a
## side, onto a free cell; none, and it stands.
func _step_aside(blocker: GridEntity) -> void:
	var back := Vector2i(signi(tile.x - blocker.tile.x), signi(tile.y - blocker.tile.y))
	var ways: Array[Vector2i] = [back, Vector2i(back.y, back.x), Vector2i(-back.y, -back.x)]
	for way in ways:
		if way != Vector2i.ZERO and World.is_walkable(tile + way) and World.is_free(tile + way) and World.try_move(self, way):
			return


## Whether it has a grave, choosing one the first time (choose_grave, kept
## in its props); with none in its level it wanders where it stands.
func _settle_grave() -> bool:
	if grave != NO_TILE:
		return true
	# Every other one of the zone's dead takes the free grave nearest it, a
	# few steps off, and lies there; the rest walk home (decision 561: of the barrow's four,
	# two lie and two walk).
	var settled := 0
	for other in World.monsters():
		if other != self and other is Monster and (other as Monster).grave != NO_TILE:
			settled += 1
	grave = choose_grave(settled % 2 == 1)
	if grave == NO_TILE:
		idle = Idle.WANDER
		return false
	_keep_prop("grave", grave)
	return true


## A grave for it (decision 547): one of its level's "graves" ([x, y, band]
## each, band 0 shallowest) in a band shallower than the grave nearest where
## it stands (the old dead walk up, home), else one no deeper, else any;
## none another of the zone's monsters has; of those, one by its name.
## With [param nearest], the free one nearest it (decision 561). NO_TILE
## when there are none.
func choose_grave(nearest_one := false) -> Vector2i:
	var graves := zone_graves()
	if graves.is_empty():
		return NO_TILE
	var taken: Dictionary[Vector2i, bool] = {}
	for other in World.monsters():
		if other != self and other is Monster and (other as Monster).grave != NO_TILE:
			taken[(other as Monster).grave] = true
	var mine := 0
	var nearest := -1
	for each: Vector3i in graves:
		var d := World.distance(tile, Vector2i(each.x, each.y))
		if nearest < 0 or d < nearest:
			nearest = d
			mine = each.z
	var shallower: Array[Vector2i] = []
	var no_deeper: Array[Vector2i] = []
	var free: Array[Vector2i] = []
	for each: Vector3i in graves:
		var at := Vector2i(each.x, each.y)
		if taken.has(at):
			continue
		free.append(at)
		if each.z <= mine:
			no_deeper.append(at)
		if each.z < mine:
			shallower.append(at)
	if nearest_one and not free.is_empty():
		var best := free[0]
		for at in free:
			if World.distance(tile, at) < World.distance(tile, best):
				best = at
		return best
	var pick := shallower if not shallower.is_empty() else (no_deeper if not no_deeper.is_empty() else free)
	if pick.is_empty():
		return NO_TILE
	return pick[absi(hash(String(name) + "/grave")) % pick.size()]


## Whoever stands in its way home: beside it, on a cell nearer its grave, one
## it may fight (_may_fight); null for none.
func _blocker() -> GridEntity:
	var here := World.distance(tile, grave)
	for direction in AROUND:
		var other := World.get_entity_at(tile + direction)
		if other != null and other != self and World.distance(tile + direction, grave) < here and _may_fight(other):
			return other
	return null


## Whether it fights [param other] when it is in its way or strikes it: a
## player, a kept companion, a resident when its side fights the town, a
## monster of its foes. Never one of its own side.
func _may_fight(other: GridEntity) -> bool:
	if other is Player or (other is Companion and (other as Companion).keeper != null):
		return true
	if other is Resident:
		return "town" in foes
	return other is Monster and not other is Animal and _factions().of_kind(World.kind_of(other)) in foes


## Whether it would fight [param entity] as things stand (decision 551,
## enemy-ai's side, for companions' guide): a player or kept companion; a
## resident when its side fights the town, or it raids; a monster of its
## foes. A room keeper only one in its room; one walking home counts (it
## fights who is in its way). Never while it lies in its grave, nor one
## gone, downed or in its spawn grace. Distance and sight are the asker's.
func threatens(entity: GridEntity) -> bool:
	if not _may_threaten(entity):
		return false
	if keeps_room and not _room.has_point(entity.tile):
		return false
	if entity is Player or (entity is Companion and (entity as Companion).keeper != null):
		return _given_up.is_empty() or not _letting_be(entity)
	if raid != "" or "town" in foes:
		if entity in World.townsfolk():
			return true
	return _may_fight(entity)


## Whether either of it and [param entity] is out of any fight: gone, dead,
## lying in its grave, downed or in its spawn grace (threatens).
func _may_threaten(entity: GridEntity) -> bool:
	return spawned and hp > 0 and not laid and entity != null and is_instance_valid(entity) and entity != self \
			and entity.spawned and entity.hp > 0 and not entity.protected and not World.is_downed(entity)


## HOMEWARD's target: the one in its way (_blocker) or that struck it, while
## it is in sight; else nobody, and it walks on.
func _in_the_way() -> GridEntity:
	var struck := _struck_by()
	if struck != null and _may_fight(struck):
		_provoked = struck
	if _provoked != null:
		if not is_instance_valid(_provoked) or not _provoked.spawned or _provoked.hp <= 0:
			_provoked = null
		else:
			var d := World.distance(tile, _provoked.tile)
			if d > sight_range or not senses.sees(_provoked, d, false):
				_provoked = null
	return _provoked


## Whoever struck it just now (a fight noise on its own tile from someone),
## else null.
func _struck_by() -> GridEntity:
	if World.tick - hurt_tick > 1:
		return null
	for i in range(senses.heard.size() - 1, -1, -1):
		var noise: Dictionary = senses.heard[i]
		if int(noise["tick"]) < hurt_tick:
			break
		var source: Variant = noise["source"]
		if noise["kind"] == &"fight" and noise["at"] == tile and is_instance_valid(source) and source != self:
			return source
	return null


## Down at its grave, or stilled (the draugr laid to rest, step 3): it lies
## still (down_until, which the views draw) till rise, kept in its props so
## a restart finds it lying.
func lay_down() -> void:
	laid = true
	target = null
	_provoked = null
	alert = Alert.IDLE
	_drop_windup()
	_keep_prop("laid", true)
	_lie_still()


## The foe of its side one lying at its grave sees and gets up for, or null
## (580 amended; Jeff, the Ossuary: "the ones that are are lying down"):
## within its sight_range, any way it lies (no cone), by its own sight (a
## barrow layer's dead see in the dark). Never one stilled by the draugr's
## rest (stilled, or lying at its grave while it lasts), which holds
## whatever comes.
func _waking_foe() -> GridEntity:
	if stilled or sight_range <= 0 or not World.dead_rest.is_empty() and _under_rest():
		return null
	for entity in World.sought():
		if entity == self or not entity.spawned or entity.hp <= 0 or entity.protected or World.is_downed(entity):
			continue
		var d := World.distance(tile, entity.tile)
		if d <= sight_range and _may_fight(entity) and senses.sees(entity, d, false):
			return entity
	return null


## Up again when the curse renews: one that lay at its grave keeps it
## (GUARD there); one stilled on its way walks on.
func rise() -> void:
	if not laid:
		return
	laid = false
	if stilled:
		stilled = false
		_keep_prop("stilled", false)
	down_until = World.tick
	_keep_prop("laid", false)
	if idle == Idle.HOMEWARD and grave != NO_TILE and tile == grave:
		idle = Idle.GUARD
		home = grave


## The draugr's rest over its zone (World.dead_rest, decision 580): one of
## the resting side lies still while it lasts, wherever he is and whether
## or not his zone is awake (a respawn too), and one it laid gets up when it
## is over. Not the draugr himself, who keeps his own rest.
func _mind_the_rest() -> void:
	if World.dead_rest.is_empty() and not stilled:
		return
	var resting := _under_rest()
	if resting and not laid:
		stilled = true
		_keep_prop("stilled", true)
		lay_down()
	elif not resting and stilled:
		rise()


## Whether the draugr's rest holds it now: its zone's, over its side, not
## run out; never the draugr himself.
func _under_rest() -> bool:
	var rest: Dictionary = World.dead_rest.get(World.zone.name, {})
	return not rest.is_empty() and World.steps < int(rest.get("until", 0)) and not self is Draugr \
			and _factions().same_side(_factions().of_kind(World.kind_of(self)), str(rest.get("side", "")))


func _lie_still() -> void:
	if down_until - World.tick < LAID_RENEW_TICKS:
		down_until = World.tick + LAID_HOLD_TICKS


## [param key] set to [param value] in its spawn spec's props, which a save
## keeps (Snapshot): the spec copied first, never the level's own.
func _keep_prop(key: String, value: Variant) -> void:
	spawn_spec = spawn_spec.duplicate()
	var props: Variant = spawn_spec.get("props", {})
	var kept: Dictionary = (props as Dictionary).duplicate() if props is Dictionary else {}
	kept[key] = value
	spawn_spec["props"] = kept


## How long (ticks) a dead [param kind] of the zone's level waits to come
## back: its level.json "respawn_s" (seconds; one number for every kind, or
## by kind), else [param otherwise] (decision 561: the barrow's dead 600,
## its robbers 300).
static func respawn_ticks(kind: String, otherwise: int) -> int:
	var given: Variant = _zone_config().get("respawn_s")
	if given is Dictionary:
		given = given.get(kind)
	if given is float or given is int:
		return maxi(0, roundi(float(given) * World.TICK_RATE))
	return otherwise


## The graves of the zone's level (its level.json "graves", [x, y, band]
## each, as Regen writes them for the barrow), read once a zone.
static func zone_graves() -> Array[Vector3i]:
	var config := _zone_config()
	var out: Array[Vector3i] = []
	var listed: Variant = config.get("graves", [])
	if listed is Array:
		for each: Variant in listed:
			if each is Array and each.size() >= 2:
				out.append(Vector3i(int(each[0]), int(each[1]), int(each[2]) if each.size() > 2 else 0))
	return out


## The room round [param cell]: the anchor of the zone's level it lies in,
## its "regenerate" block's or, on a level drawn by hand, its own top-level
## "anchors" (decision 580: the draugr's lair); an empty Rect2i in none.
static func room_of(cell: Vector2i) -> Rect2i:
	var config := _zone_config()
	var block: Variant = config.get("regenerate", {})
	var anchors: Variant = (block.get("anchors", []) if block is Dictionary else []).duplicate()
	var own: Variant = config.get("anchors", [])
	if anchors is Array and own is Array:
		anchors.append_array(own)
	if anchors is Array:
		for anchor: Variant in anchors:
			var rect: Variant = anchor.get("rect") if anchor is Dictionary else null
			if rect is Array and rect.size() == 4:
				var room := Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
				if room.has_point(cell):
					return room
	return Rect2i()


## The zone's level.json, read once each time its terrain is loaded (a
## reload or a generation reads it again).
static func _zone_config() -> Dictionary:
	var zone := World.zone
	if zone == null or zone.name.is_empty() or not Level.exists(zone.name):
		return {}
	var key := "%d/%s/%d" % [zone.get_instance_id(), zone.name, zone.terrain_loads]
	if not _zone_configs.has(key):
		if _zone_configs.size() >= 32:
			_zone_configs.clear()  # Zones and their reloads come and go: never many kept.
		_zone_configs[key] = Level.source(zone.name)["config"]
	return _zone_configs[key]


static var _zone_configs: Dictionary[String, Dictionary] = {}


## Whether it has marched to its route's end (or as near as its fellows let
## it, [param near] tiles).
func marched(near := 0) -> bool:
	return idle == Idle.MARCH and not route.is_empty() and World.distance(tile, route.back()) <= near


## GUARD: at home, facing its way, and every so often a glance aside, held
## a moment, then back.
func _guard() -> void:
	if tile != home:
		if not _idle_step(home, IDLE_SEARCH_TILES, beyond_view):
			_idle_until = World.tick + PATROL_PAUSE_TICKS.y  # Someone is on it: wait.
		return
	if World.tick < _idle_until:
		return
	if _glancing or facing != home_facing:
		World.face(self, home_facing)
		_glancing = false
		_idle_until = World.tick + _idle_rng.randi_range(GLANCE_EVERY_TICKS.x, GLANCE_EVERY_TICKS.y)
		return
	var steps := _idle_rng.randi_range(1, GLANCE_STEPS_MAX) * (1 if _idle_rng.randf() < 0.5 else -1)
	World.face(self, turned(home_facing, steps))
	_glancing = true
	_idle_until = World.tick + _idle_rng.randi_range(GLANCE_HOLD_TICKS.x, GLANCE_HOLD_TICKS.y)


## WANDER: to a free tile near home, a pause, another.
func _wander() -> void:
	if World.tick < _idle_until:
		return
	if _idle_goal == tile:
		_idle_goal = NO_TILE
		_idle_until = World.tick + _idle_rng.randi_range(WANDER_PAUSE_TICKS.x, WANDER_PAUSE_TICKS.y)
		return
	if _idle_goal == NO_TILE:
		_idle_goal = _wander_goal()
		if _idle_goal == NO_TILE:
			_idle_until = World.tick + WANDER_PAUSE_TICKS.x
			return
	if not _idle_step(_idle_goal, _about_search(wander_radius), beyond_view):
		_idle_goal = NO_TILE
		_idle_until = World.tick + WANDER_PAUSE_TICKS.x


## A free tile it can walk to, at most wander_radius from home, not where it
## stands; NO_TILE if a few tries find none.
func _wander_goal() -> Vector2i:
	for i in 12:
		var at := home + Vector2i(_idle_rng.randi_range(-wander_radius, wander_radius),
				_idle_rng.randi_range(-wander_radius, wander_radius))
		if at == tile or not World.is_walkable(at) or not World.is_free(at) or World.is_fire(at):
			continue
		if _straight(tile, at, wander_radius * 2 + 2):
			_idle_path.clear()  # It walks there straight (_idle_step).
			return at
		if beyond_view:
			continue  # On nobody's screen: a spot it can walk to straight, or none.
		var path := World.find_path(tile, at, false, null, _about_search(wander_radius), false, {}, opens_doors)
		if not path.is_empty():
			# The way there is the walk's first plan (_idle_step).
			_idle_path = path
			_idle_path_to = at
			return at
	return NO_TILE


## The step from [param from] toward [param to] that goes straight at it, or
## if that is shut one of its two halves (each nearer, never farther): ZERO
## if none. With [param now], only onto a free tile (the step it takes);
## without, by the terrain alone (whether it could walk there).
static func _direct_step(from: Vector2i, to: Vector2i, now: bool) -> Vector2i:
	var toward := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	for direction: Vector2i in [toward, Vector2i(toward.x, 0), Vector2i(0, toward.y)]:
		if direction != Vector2i.ZERO and World.terrain_step_open(from, direction) \
				and (not now or World.is_free(from + direction)):
			return direction
	return Vector2i.ZERO


## Whether one could walk from [param from] to [param to] by straight steps
## (_direct_step, the terrain alone) in [param steps] at most.
static func _straight(from: Vector2i, to: Vector2i, steps: int) -> bool:
	var at := from
	for i in steps:
		if at == to:
			return true
		var direction := _direct_step(at, to, false)
		if direction == Vector2i.ZERO:
			return false
		at += direction
	return at == to


## How many tiles a search for a spot within [param radius] of home looks
## at (ABOUT_SEARCH_PER_TILE).
static func _about_search(radius: int) -> int:
	return (radius * 2 + 1) * (radius * 2 + 1) * ABOUT_SEARCH_PER_TILE


## PATROL: waypoint to waypoint, a pause at each; round again (a loop) or
## back the way it came.
func _patrol() -> void:
	_ensure_route()
	if route.size() < 2 or World.tick < _idle_until:
		return
	var to := route[_route_index]
	if tile == to or not _idle_step(to, IDLE_SEARCH_TILES, beyond_view):
		# There (or no way there now: on to the next).
		if route_loop:
			_route_index = (_route_index + 1) % route.size()
		else:
			if _route_index + _route_step < 0 or _route_index + _route_step >= route.size():
				_route_step = -_route_step
			_route_index += _route_step
		_idle_until = World.tick + _idle_rng.randi_range(PATROL_PAUSE_TICKS.x, PATROL_PAUSE_TICKS.y)


## A route of its own when none is set (if World.take_plan allows it this
## step; till then it has none): home, then PATROL_LOOP_POINTS - 1
## tiles round it it can walk to, in turn round the compass from a way of
## its own, as a loop.
func _ensure_route() -> void:
	if not route.is_empty() or home == NO_TILE:
		return
	if not World.take_plan():
		return  # Enough worked out this step: it waits a step or two.
	route.append(home)
	var start := _idle_rng.randi_range(0, AROUND.size() - 1)
	var per := AROUND.size() / (PATROL_LOOP_POINTS - 1)
	for i in PATROL_LOOP_POINTS - 1:
		var way := AROUND[(start + i * per) % AROUND.size()]
		for reach in range(PATROL_LOOP_RADIUS, 0, -1):
			var at := home + way * reach
			# Straight from home if it can be walked so; a search only if not.
			if World.is_walkable(at) and not World.is_fire(at) and at not in route \
					and (_straight(home, at, PATROL_LOOP_RADIUS * 2) \
						or not World.find_path(home, at, true, null, _about_search(PATROL_LOOP_RADIUS), false, {}, opens_doors).is_empty()):
				route.append(at)
				break
	route_loop = true


## GATHER: to its place by the point, then facing the point, sitting or
## standing.
func _gather() -> void:
	var place := _gather_place()
	if place == NO_TILE:
		return
	if tile != place:
		pose = Pose.STAND
		if not _idle_step(place, IDLE_SEARCH_TILES, beyond_view):
			_idle_goal = NO_TILE  # Taken or cut off: another place.
			_idle_until = World.tick + PATROL_PAUSE_TICKS.y
		return
	var toward := gather_point - tile
	toward = Vector2i(signi(toward.x), signi(toward.y))
	if toward != Vector2i.ZERO and facing != toward:
		World.face(self, toward)
	pose = Pose.SIT if _sits else Pose.STAND


## Its place round the gather point: a free tile within GATHER_RADIUS (not
## the point, not fire, nearest the point first), one of its own by name
## among those; kept while it is free.
func _gather_place() -> Vector2i:
	if _idle_goal != NO_TILE and (_idle_goal == tile or World.is_free(_idle_goal)):
		return _idle_goal
	var places: Array[Vector2i] = []
	for reach in range(1, GATHER_RADIUS + 1):
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var at := gather_point + Vector2i(dx, dy)
				if World.distance(at, gather_point) != reach or not World.is_walkable(at) or World.is_fire(at):
					continue
				if at != tile and not World.is_free(at):
					continue
				places.append(at)
		if not places.is_empty():
			break
	if places.is_empty():
		return NO_TILE
	_idle_goal = places[absi(hash(String(name))) % places.size()]
	return _idle_goal


## A step toward [param to] as it idles, looking at [param max_tiles] at
## most for the way (a stroll's spot, near, less); false if there is no way.
## With [param straight_only] (idling on nobody's screen) only a straight
## step, never a search: false if that is shut, and it waits or goes
## elsewhere, as idling does when there is no way.
## Straight toward it when it can (_direct_step); else by a planned way,
## kept from step to step (_idle_path) and planned again only when the next
## step on it is taken, it is somewhere else (pushed, moved on by the world
## tick) or the goal has changed: planning at every step was most of what
## idling cost.
func _idle_step(to: Vector2i, max_tiles := IDLE_SEARCH_TILES, straight_only := false) -> bool:
	if _idle_path.is_empty() or _idle_path_to != to or World.distance(tile, _idle_path[0]) != 1 \
			or not World.is_free(_idle_path[0]):
		# Straight there if it can (most idle walks are a few tiles over open
		# floor): a few looks, where planning the way is a search.
		var direct := _direct_step(tile, to, true)
		if direct != Vector2i.ZERO:
			_idle_path.clear()
			return World.try_move(self, direct)
		if straight_only:
			return false  # Out of everyone's view: it waits, or goes elsewhere.
		_idle_path = World.find_path(tile, to, false, null, max_tiles, false, {}, opens_doors_now())
		_idle_path_to = to
		if _idle_path.is_empty():
			return false
	if World.try_move(self, _idle_path[0] - tile):
		_idle_path.pop_front()
		return true
	_idle_path.clear()
	return false


## It thinks again after not thinking at all (World._tier: out of FAR, or
## its zone woken): its idling (a stroll, a glance, its loop) starts after
## a moment of its own, up to World.WAKE_SPREAD_TICKS, so a crowd woken
## together does not all choose and plan on one tick. Its looking out and
## fighting start at once.
func _woke_up() -> void:
	_idle_from = World.tick + id % World.WAKE_SPREAD_TICKS


## The world tick (far from everyone, or its zone asleep): [param seconds]
## gone by at once. A fight is over; one on its way back after a fight
## walks back (home, its route, its place at the point) as far as it would
## have in that time at its idle pace, by a real way (World.walk), and is
## back if it gets there. No hits.
func _world_tick(seconds: float) -> void:
	target = null
	slot = NO_TILE
	_drop_windup()
	_glancing = false
	_calm()
	_mind_the_rest()
	if laid:
		return
	if idle == Idle.HOMEWARD:
		# Far from everyone: on home by a real way, as far as it would have
		# gone, and down if it got there.
		move_ticks = _pace * IDLE_PACE
		_returning = false
		if _settle_grave() and World.walk(self, grave, seconds * World.TICK_RATE) and tile == grave:
			lay_down()
		return
	if idle == Idle.MARCH and not route.is_empty():
		# Marching far from everyone: on by a real way toward its route's end,
		# as far as it would have gone.
		move_ticks = _pace * IDLE_PACE
		_returning = false
		if World.walk(self, route.back(), seconds * World.TICK_RATE):
			_route_index = route.size() - 1
		return
	if not _returning:
		return
	move_ticks = _pace * IDLE_PACE
	# A patrol with no route yet goes home, its first waypoint, rather than
	# work its route out now: it does that when it is near and thinking.
	var back := home if idle == Idle.PATROL and route.is_empty() else _back_to()
	if back != NO_TILE and World.walk(self, back, seconds * World.TICK_RATE):
		_returning = false
		_idle_goal = NO_TILE


## The way a monster called [param monster_name] faces when its level entry
## sets none: one of AROUND, the same every time (the editor draws it).
static func own_facing(monster_name: String) -> Vector2i:
	return AROUND[absi(hash(monster_name + "/facing")) % AROUND.size()]


## [param direction] turned [param steps] eighths of a turn (clockwise for
## positive), one of AROUND.
static func turned(direction: Vector2i, steps: int) -> Vector2i:
	var at := AROUND.find(direction)
	if at < 0:
		return direction
	return AROUND[posmod(at + steps, AROUND.size())]


## A wound-up blow given up before it was struck: the views told to stop
## (GridEntity.winding with 0 ticks; decision 392).
func _drop_windup() -> void:
	if not _windup.is_empty():
		_world_winding(_windup["direction"], 0)
	_windup = {}


## A cry of [param kind], heard [param radius] cells off (World.noise), and
## told to whoever sees it (cried).
func _cry(kind: StringName, radius: int) -> void:
	World.noise(tile, radius, kind, self)
	cried.emit(kind)
	for peer in viewers():
		_net_cried.rpc_id(peer, kind)


@rpc("authority", "call_remote", "reliable")
func _net_cried(kind: StringName) -> void:
	cried.emit(kind)
