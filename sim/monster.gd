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
## nearly dead. CAUTIOUS: holds back till another is at its target or its
## band (band_min strong, BAND_TILES, decision 698) outnumbers the foes,
## calls for help when it first sees someone. COWARDLY: calls for help,
## holds back till two others are at its target or its band outnumbers
## them, breaks early, or against two or more its band no longer
## outnumbers (fewer than a band: alone, COWARD_ODDS_TILES). Each breaks
## below FLEE_BELOW of its hp;
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
## A coward with fewer than a band (band_min) breaks alone within so many
## cells of any monster.
const COWARD_ODDS_TILES := 3
## A band (decision 698): those of its side within so many cells, and the
## foes as near, counted against each other.
const BAND_TILES := 6
## A band stands as one (_band_holds) only this many strong, itself counted
## (the coordinator: "so a pair stays as cautious as before"); "band_min" in
## the fight block.
const BAND_MIN := 3
## Fleeing (Alert.FLEEING): it runs FLEE_TILES at most at a time, and
## recovers after FLEE_TICKS with nobody within FLEE_NEAR_TILES.
const FLEE_TICKS := 60
const FLEE_TILES := 6
const FLEE_NEAR_TILES := 4
## A routed one indoors (decision 702; Jeff: "they should run to the
## entrance") runs for a way out its path search finds looking at no more
## than this many cells (a whole barrow), one whose path never brings it
## within ESCAPE_CLEAR_TILES of its foe nearer than it was (not past the
## player).
const ESCAPE_SEARCH_TILES := 1000
const ESCAPE_CLEAR_TILES := 2
## A call for help (Senses.NOISE_CALL) at most so often; a rout
## (Senses.NOISE_ROUT) breaks a cautious one under ROUT_HURT of its hp.
const CALL_EVERY_TICKS := 100
const ROUT_HURT := 0.7
const DART_AFTER_TICKS := 3
const CHARGE_RANGE := 4
const CHARGE_PACE := 0.5
const WINDUP_TICKS := 6
## Its plain blow's lead (338 amended (4), "blows you can see"): the ticks it
## draws back, told as a winding, before the blow lands; out of its own
## cycle, so it strikes no less often. 0: at once, as before.
const LEAD_TICKS := 3
## Stop to strike (338 amended (4), enemy-ai's side; combat's numbers): no
## step for STRIKE_RECOVER_TICKS after any blow of its own lands or misses,
## and a blow begun only once it has stood SETTLE_TICKS where its last step
## (or push) brought it, so it is seen to stop, strike and stand, never to
## slide into its target swinging. Its told lunge and ambush stand already.
const STRIKE_RECOVER_TICKS := 4
const SETTLE_TICKS := 1
const FLANK_PATIENCE_TICKS := 20
const BACKSTAB_DAMAGE := 1
## A lurking chief's told strike from behind (790 amended (4), combat's
## numbers; its named row's "moves" "ambush" over these): the windup's ticks,
## its damage, the ticks it stands open after a miss, and its cue's reach.
const AMBUSH := {"windup": 8, "damage": 5, "recover": 8, "cue_reach": 8}
## A kind's told lunge (790 amended (4), combat's; its kind row's "moves"
## "lunge" over these): its blow from in front or side-on told as a line
## "reach" cells long before it lands, "damage" on whoever is still on it,
## standing open "recover" ticks after it, landed or missed (790 amended
## (6)), crying &"overreach". The crypt robbers' (their row: windup 10, recover 9).
const LUNGE := {"windup": 6, "damage": 3, "reach": 2, "recover": 8}
## Its manner, from its name: a step this much quicker or slower, a cooldown
## this many ticks either way, up to REACTION_TICKS_MAX to act on a new
## target, a chance a tick of PAUSE_CHANCE_MAX at most to stop a moment
## (PAUSE_TICKS) on the way in; bolder than HOLD_BACK_BELOW, or it waits
## HOLD_BACK_RANGE off until another monster is at its target or its target
## is under half its hp.
const PACE_SPREAD := 0.15
const COOLDOWN_SPREAD := 2
## The fight's feel as data (673 step 2, enemy-ai's side; combat's tuning
## panel, Jeff: "i need way to tune combat and animation feel that has a
## quicker feedback loop"): KINDS_PATH's "fight" block over these (the
## constants above, its defaults), and a kind's row's own "fight" over that.
## Each sets the var of its name (_apply_fight) at spawn: a change reaches
## new spawns. flee_below by temper name.
const FIGHT_DEFAULTS := {"windup_ticks": WINDUP_TICKS, "charge_range": CHARGE_RANGE, "charge_pace": CHARGE_PACE,
	"dart_after_ticks": DART_AFTER_TICKS, "backstab_damage": BACKSTAB_DAMAGE, "pace_spread": PACE_SPREAD,
	"cooldown_spread": COOLDOWN_SPREAD, "flank_patience_ticks": FLANK_PATIENCE_TICKS, "flee_ticks": FLEE_TICKS,
	"flee_tiles": FLEE_TILES, "flee_near_tiles": FLEE_NEAR_TILES, "rout_hurt": ROUT_HURT,
	"dread_flee_below": DREAD_FLEE_BELOW, "flee_below": {"bold": 0.15, "cautious": 0.35, "cowardly": 0.6},
	"band_min": BAND_MIN, "lead_ticks": LEAD_TICKS, "strike_recover_ticks": STRIKE_RECOVER_TICKS,
	"settle_ticks": SETTLE_TICKS}
## Each fight value's range on the tuning panel (673 step 2), by name
## (flee_below's three share one).
const FIGHT_SPANS := {"windup_ticks": [1, 30], "charge_range": [1, 10], "charge_pace": [0.1, 1.5],
	"dart_after_ticks": [0, 20], "backstab_damage": [0, 10], "pace_spread": [0.0, 0.5], "cooldown_spread": [0, 10],
	"flank_patience_ticks": [0, 100], "flee_ticks": [0, 300], "flee_tiles": [1, 20], "flee_near_tiles": [1, 20],
	"rout_hurt": [0.0, 1.0], "dread_flee_below": [0.0, 1.0], "flee_below": [0.0, 1.0], "band_min": [2, 10],
	"lead_ticks": [0, 10], "strike_recover_ticks": [0, 10], "settle_ticks": [0, 5]}
const FIGHT_INTS: Array[String] = ["windup_ticks", "charge_range", "dart_after_ticks", "backstab_damage",
	"cooldown_spread", "flank_patience_ticks", "flee_ticks", "flee_tiles", "flee_near_tiles", "band_min", "lead_ticks",
	"strike_recover_ticks", "settle_ticks"]
const REACTION_TICKS_MAX := 6
const PAUSE_CHANCE_MAX := 0.12
const PAUSE_TICKS := Vector2i(2, 6)
const HOLD_BACK_BELOW := 0.3
const HOLD_BACK_RANGE := 3
## How far a free target's centre moves before it works out its strike cells
## again (decision 699, enemy-ai's side).
const STRIKE_REPLAN := 0.3
## Its strike cell on a free body (699 amended, enemy-ai's side; combat's
## spec): one at least 0.5 + World.FOE_GAP from the body's centre (a free
## body stands that far off a monster's), and each cell short of this share
## of its weapon's span (World.span_of; the player's chase stops at the same,
## main.gd CHASE_SPAN_SHARE) costing what it is short as a cell walked; one
## at it or past it costs nothing more (a two-sided cost re-picked cells
## after a zig-zagging body, free_walk_test). None that far: any strike cell,
## as before.
const STRIKE_SPAN_SHARE := 0.85
## How far under that gap the cell it is making for may fall before it is
## given up (the body moving on).
const STRIKE_GAP_SLACK := 0.3
## A free body it has swung at from the cell it stands on, now at most this
## far past its reach (World.reach_limit) of it: till STRIKE_HOLD_TICKS after
## its next swing is ready, it holds that cell, waiting for a dodge to swing
## back, rather than step after each zig and back after each zag. One that was
## in its reach from there within the last STRIKE_HOLD_TICKS is held for the
## same, swung at or not (699 amended (2): a robber come to a body zig-zagging
## along a wall stepped after her before his told blow could start, and back).
## A body never in its reach from there is closed on, as before. A held cell is
## stood on (_strike_holding), not left for the way to her own cell.
const STRIKE_HOLD_SLACK := 0.3
const STRIKE_HOLD_TICKS := 8
## How far ahead, in ticks, it leads a moving free body (lead-the-target):
## past this it makes for where it will be then.
const LEAD_MAX_TICKS := 24
## The most a free body's way may be read to turn in a tick (radians) when
## it leads a circling one.
const LEAD_TURN_MAX := 0.3
## It leads a free body this many ticks ahead for each tick the body has
## held its course.
const LEAD_STEADY_FACTOR := 2
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
## A standoff (806 amended (8)): FIGHTING STANDOFF_TICKS without acting (no
## step, blow, windup, shot or guard), it chooses. A guard (Idle.GUARD at its
## home) with the one it fights within GUARD_REACH of its post and a way there
## presses in (no holding back or pausing that fight); otherwise it watches:
## lets that one be WATCH_TICKS, back to its post (a guard, facing them while
## in sight) or where it idles, roused by a blow or by them within
## WATCH_ROUSE of its post (its own cell, not a guard).
const STANDOFF_TICKS := 50
## An idle walk whose way was not found waits this long before searching for
## the same goal again (perf's heat run: failed plans, 0.74 ms a tick on castle
## 256, most of them the same goal tick after tick).
const IDLE_PLAN_RETRY_TICKS := 10
## A band fighter (a row's "band_fights", 806 amended (9); the robbers, Jeff:
## "fighting the robbers is not great right now"): hurt to its flee_below, it
## runs only to call its band, CALL_RUN_TICKS, toward its nearest mate, then
## comes back and fights to the end; with no mate left it never runs. Alone
## it never holds back, and it circles to a flank only while a mate is beside
## its target.
const CALL_RUN_TICKS := 20
## The band's rally (806 amended (14), the coordinator's ruling on enemy-ai's
## crypt band probe: robbers stood idle 5 to 12 cells from a mate being cut
## down). A band fighter idle or wary, looked at every RALLY_EVERY ticks,
## whose mate is fighting within RALLY_WALK walking cells (a path's length,
## a wall the way round it, never through), asks to come; the fighting mate
## sends those who asked one at a time, nearest first, RALLY_GAP apart (the
## first RALLY_GAP after the first ask), never while RALLY_MOST of its band
## already fight its foe or are on their way to it (sent and still coming:
## the enemy-ai probe's crypt rows had five to seven on a pair when the
## ones coming were not counted). One posted farther keeps its post.
const RALLY_EVERY := 10
const RALLY_WALK := 10
## And it must know of the fight (806 amended (17)): in its sight line within
## RALLY_SEE, or within RALLY_HEAR through walls (World.distance), as one hears
## a fight through a wall. dungeon's first_alone reads these two and
## RALLY_WALK (870): the first post nobody sees or hears is alone where the
## player meets him, not wherever the fight is dragged.
const RALLY_SEE := 9
const RALLY_HEAR := 6
const RALLY_GAP := 20
const RALLY_MOST := 4
## Off, no band rallies (a test's or a probe's measure of the rule).
static var rallies := true
## Sneak packs (824): a pack's members (props "pack", laid by dungeon, on a
## kind whose row has a "pack" block) share a target within PACK_WAKE_REACH
## of each other; the row's "pack" block over PACK_DEFAULTS: how much a cell
## near a mate's side of the target costs ("spread"), how many of the pack may
## be in reach of it at once ("in_reach"), and the ring the rest wait in
## ("hover", cells).
const PACK_WAKE_REACH := 8
const PACK_DEFAULTS := {"spread": 1.0, "in_reach": 2, "hover": [2, 3]}
## FLANK's lean (806 amended (9)): a cell round the back whose walk is more
## than this many steps longer than straight (round a sarcophagus) is not
## worth it; the nearest free cell instead.
const FLANK_DETOUR := 3
const GUARD_REACH := 4
const WATCH_TICKS := 600
const WATCH_ROUSE := 2
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
## HOMEWARD (the barrow's dead, decision 547; 631 amended): back to its
## grave, the cell it was laid on (its home), and there it rests standing
## still (laid) till a foe is seen or the curse renews (rise).
enum Idle { NONE, GUARD, WANDER, PATROL, GATHER, MARCH, HOMEWARD }
const IDLE_MODES := {"none": Idle.NONE, "guard": Idle.GUARD, "wander": Idle.WANDER, "patrol": Idle.PATROL,
	"gather": Idle.GATHER, "march": Idle.MARCH, "homeward": Idle.HOMEWARD}
## HOMEWARD: how far it searches for its way (a barrow's breadth).
const HOMEWARD_SEARCH_TILES := 2000
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
## How it is standing, for the views: SIT at a gathering (an animal's
## graze); DOWN an animal lying hurt (decision 764: a wounded deer down, to
## be finished; a view lays it on its side). Replicated as `pose`.
enum Pose { STAND, SIT, DOWN }
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
## Its kind's "senses" (decision 784): how far each noise carries for it
## (times its radius: World._hear), the cells of sight it adds while it looks
## about, and how fast it notices someone it sees (notice_rate; 0 for a kind
## with no "senses": it knows whom it sees at once, as before).
var hearing := 1.0
var alert_sight := 0
var notice_rate := 0.0
## Who it is noticing (784): instance id -> 0..1, NOTICE_FULL it knows
## them; filled each think it sees them, by how near (NOTICE_FILL_TICKS
## near at hand), faded over NOTICE_FADE_TICKS when it does not.
var _notice: Dictionary[int, float] = {}
var _notice_tick := -1
const NOTICE_FULL := 1.0
const NOTICE_SUSPECT := 0.4
const NOTICE_FILL_TICKS := 10.0
const NOTICE_FADE_TICKS := 100.0
## The most a think counts for (a MID tier thinks one tick in 4).
const NOTICE_STEP_MOST := 4
## A look about widens its cone by so many degrees.
const ALERT_CONE_DEGREES := 60.0
## The keenest ear of any kind (Monster.hearing_most), for World.noise.
static var _hearing_most := -1.0
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
## The cell it stands on as it last picked a strike cell, and the tick it
## first did there: a swing since (next_attack_tick past it) was from there
## (STRIKE_HOLD_TICKS).
var _strike_held := NO_TILE
var _strike_held_tick := -1
## The cell it last had its free target in reach from, and the tick
## (STRIKE_HOLD_TICKS, 699 amended (2)).
var _reached_from := NO_TILE
var _reached_tick := -1
## Its last _pick_slot held the cell it stands on (STRIKE_HOLD_SLACK): it
## stands there this tick rather than close on her own cell.
var _strike_holding := false
## Its last World.strike_cells against a free target, and where from (699).
var _strike_plan := {}
## Its free target's way when it last led it, and the tick (lead-the-target).
var _lead_way := Vector2.ZERO
var _lead_tick := -1
var _lead_turn := 0.0
## How many ticks its free target has held its course (lead-the-target).
var _lead_steady := 0
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
## The practice hall's (decision 673, Tuning): practice_still, it stands
## where it is and never strikes or moves; never_dies, its hp held at 1 and
## full again after Tuning.DUMMY_REFILL_TICKS without a blow (the dummy).
## Server only, never saved: the arena makes them each time.
var practice_still := false
var never_dies := false
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
## A named one's ways (790 amended (2): Hollowfell's chiefs; its
## row in levels/named_enemies.json). holds_post: it holds its post (home),
## going no further than this many cells from it after anyone and back to it
## when they go beyond (-1: none, its leash as ever). lurks: it stands where
## it was put and takes up no one it sees until its side engages near it (a
## call, or a blow struck by one of its side within its hearing) or it is
## struck; then it fights by its tactic till it has no one, and lurks again.
var holds_post := -1
var lurks := false
## Till when a lurker is roused (World ticks).
var _roused_until := -1
## Its told strike from behind is ready (790 amended (4), enemy-ai's side):
## armed while it lurks, spent on its first blow from behind or side-on
## after (begin_ambush, else the plain blow).
var _ambush_armed := true
## 806 amended (9): its row's "band_fights"; whether it has run to call its
## band this fight (once: then it fights on), and whom it comes back to.
var band_fights := false
## The band's hold-off (its row's "holds_off"; 806 amended (14), the coordinator's ruling on
## enemy-ai's crypt rows, 2026-11-11): one who would join a fight by himself
## while the party already has its share of his band on it (_hold_share)
## holds HOLD_NEAR to HOLD_FAR cells off, in sight and facing them, shifting
## his cell every HOLD_SHIFT_TICKS, and takes a place the moment one opens.
## A boss who stands never holds; if one comes in over the share, the newest
## fighter steps back. One the party strikes, or closes on and swings at,
## fights (her choice). A holder strikes nobody from his hold.
var holds_off := false
## Holding off now (_holds_now), and when it last took up its place at its
## party's fight (the newest steps back), and which party that was.
var _holding := false
var _joined_tick := -1
var _joined_party := 0
var _hold_shift_at := 0
## Ticks running a place has stood open at its party (HOLD_OPEN_TICKS).
var _hold_open := 0
## Its pack (824): props "pack" where its kind's row has a "pack" block, else
## "" (fights as ever: barrow_deep's grave guards are laid with the prop and
## no block); the block's rules (PACK_DEFAULTS); the most of its pack it has
## seen alive in this fight (the last left flees).
var pack_id := ""
var pack_rules := {}
var _pack_seen := 0
var _ran_to_call := false
var _rally: GridEntity = null
var _call_to := NO_TILE
## FLANK's lean checked by its path (806 amended (9)): [from, to, ok].
var _detour_mark: Array = []
## Decision 799, enemy-ai's side: the truce camp whose band it is ("" none;
## "?" not yet looked up). A camp place with "truce" (maps' level.json; the
## Toll Camp) keeps a truce with players: its band, of the holder's side and
## spawned in its radius, takes no player or kept companion as a foe till
## one of them strikes one of the band; then the whole band fights, till
## the camp falls and is retaken (Holdings.since moves on).
var _truce_camp := "?"
## Camp place id -> Holdings.now() its truce was broken at (never saved: a
## restart forms the bands afresh).
static var truce_broken: Dictionary[String, int] = {}
## Who struck it last, and when (World.damage; Jeff: "barrow guards aren't
## aggro enough sometimes just stand and take hits"). For ANSWER_TICKS after
## each blow it answers them: seen whatever its cone, and fought by a room
## keeper from up to ANSWER_REACH outside its room, a step or two out after
## them. Unanswered that long, it lets them be as before.
var struck_by: GridEntity = null:
	get:
		# A striker freed since (a companion felled and taken home, a player
		# gone; 806 amended (20), playtest's joined crypt run, 11-12): nobody,
		# and forgotten, so no typed reader (Apex.to_den, _den_able, _covers)
		# is handed a freed object and stops this body's tick.
		if struck_by != null and not is_instance_valid(struck_by):
			struck_by = null
		return struck_by
var struck_tick := -100000
## The players who have struck it (instance ids), for a named one's hold-back
## (806 amended (12)): a named foe a player has struck fights that player,
## alone or not; its temper shapes how, never whether.
var _struck_by_players: Dictionary[int, bool] = {}
const ANSWER_TICKS := 40
const ANSWER_REACH := 2
## Its kind's "never_lies" (573 amended (4); Jeff: the draugr "should not lie
## down, he is otherworldly"): World.knock_down only staggers it.
var never_lies := false
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
## What a client may read of a talking monster (decision 648, npc's side; Jeff
## struck the draugr by clicking): true while it sits unprovoked, or rests
## (573 amended (3): the draugr's rest words), and a click or E talks
## (combat's click, ui's window), false once it fights, is struck or
## provoked. Replicated; the talking kind sets it on the server
## (the draugr: Draugr._sim_tick, start_pact). A kind that never sets it is
## false, and a click strikes as ever.
var peaceable := false
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
## An idle walk's last failed plan (_idle_step): to where, and the tick it
## may search again (IDLE_PLAN_RETRY_TICKS).
var _idle_failed_to := NO_TILE
var _idle_retry_tick := -1
## The standoff (STANDOFF_TICKS): what it last did, since when, whether it
## presses in this fight, and the one it watches (an instance id; -1 none)
## and from where (WATCH_ROUSE).
var _standoff_mark := []
var _standoff_from := -1
var _pressing := false
## 806 amended (21): the ticks it began and last held back from its target
## (the hold-back of 806 amended (16)); -1 never.
var _held_back_since := -1
var _held_back_last := -1
var _watched := -1
var _watched_from := NO_TILE
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
## The way out it runs for, routed indoors (decision 702), or NO_TILE.
var _way_out := NO_TILE
var _called_tick := -100000
var _rout_tick := -1
## kinds(), read once.
static var _kinds := {}
static var _fight_block: Variant = null
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
## Its fight's feel (673 step 2: FIGHT_DEFAULTS, its kind's, fight_for).
var windup_ticks := WINDUP_TICKS
var charge_range := CHARGE_RANGE
var charge_pace := CHARGE_PACE
var dart_after_ticks := DART_AFTER_TICKS
var backstab_damage := BACKSTAB_DAMAGE
## 790 amended (10) (the coordinator's ruling on playtest's open-air crouch run,
## 11-13): a FLANK foe chooses its told backstab only when clearly behind its
## target, more than about 110 degrees round from her facing (the unit
## offset's dot on her facing under this); side-on, or anything short of
## that, it is its told lunge (clearly_behind).
const CLEARLY_BEHIND_DOT := -0.34
## The choice it made for the strike it is about to make (true: the
## backstab), kept for that strike, till a blow begins or this many ticks
## pass, so the bodies' drift at the edge never flips it (_chooses_backstab).
const STRIKE_CHOICE_TICKS := 20
var _strike_behind := false
var _strike_chosen_until := -1
var _strike_chosen_on: GridEntity = null
var pace_spread := PACE_SPREAD
var cooldown_spread := COOLDOWN_SPREAD
var flank_patience_ticks := FLANK_PATIENCE_TICKS
var flee_ticks := FLEE_TICKS
var flee_tiles := FLEE_TILES
var flee_near_tiles := FLEE_NEAR_TILES
var rout_hurt := ROUT_HURT
var band_min := BAND_MIN
var lead_ticks := LEAD_TICKS
var strike_recover_ticks := STRIKE_RECOVER_TICKS
var settle_ticks := SETTLE_TICKS
## The tick its wound-up blow is due, its recover still to come (_tend_recover).
var _recover_due := -1
var dread_flee_below := DREAD_FLEE_BELOW
var flee_below := {Temper.BOLD: 0.15, Temper.CAUTIOUS: 0.35, Temper.COWARDLY: 0.6}
## Its kind's "picks_up" (decision 349): it takes up a weapon lying beside it.
var picks_up := false
## Its kind's "lifts": the heaviest thing (kg, Items.weight_of) it takes up
## (the band, 714: a plain robber leaves the Tomb Sledge lie); no
## limit when its row names none.
var lifts := INF
## Its kind's "bound" (decision 702): of its level, never leaving it (the
## undead of a barrow); one not bound, routed indoors, runs for a way out.
var bound := false
## Its named one's id (decision 716; its spawn spec's "named"), "" for a
## monster known by its kind; and whom it has met and fought this life, by
## "kind/player id" (World.named_note says each once a life).
var named_id := ""
var named_noted := {}
## What a client shows over it (ui's ask, Jeff's barrow notes: the robbers'
## names unseen, the boss unmarked; decision 752): its named one's name, ""
## for one known by its kind, and whether it is a boss (its named row's or
## its kind's "boss": Brand, the draugr). Both replicated.
var given_name := ""
var boss := false
## A boss's stand (806 amended (14), the coordinator's ruling on enemy-ai's crypt
## band probe: Brand left his fight at an eighth and stood alive in a
## corner a minute later): a named row's "stand", it never flees; under
## STAND_BELOW of its hp it falls back to its own ground (_stand_at, its
## home) if it has left it and fights there to the end, by the den rule the
## great bear and the old grey keep (Apex.to_den, STAND_RULE).
var stands := false
var _stand_at := NO_TILE
const STAND_BELOW := 0.15
const STAND_RULE := {"near": 2, "barred": true, "log": "stand"}
## The den rule's state (Apex.to_den; 780 amended (16), (26)): the foe it
## broke off from and whether it went the far way; struck on its walk
## (at_bay_after); a bite owed (bite_per_blow); when it turned for home (its
## pack covers it from then); since when a foe bars its way home, and
## whether it is at bay, barred.
var _wallow_from: GridEntity = null
var _wallow_far := false
var _wallow_hits := 0
var _wallow_seen := -1
var _wallow_owed := false
var _wallow_owed_seen := -1
var _wallow_tick := -1
var _wallow_barred := -1
var _wallow_at_bay := false
## The rally (RALLY_WALK): those of its band who asked to come to its fight
## (instance id -> [the mate, its walk]), when it may send the next, and
## when it next looks for a mate's fight itself.
var _rally_asked: Dictionary[int, Array] = {}
var _rally_look_at := 0
## The rally's pace by fight (a foe's party, _rally_party: him and his
## companion one fight): when the next of the band may be sent to it.
static var _rally_fight_next: Dictionary[int, int] = {}
## The fight (_rally_party) it was sent to, while it is on its way (HUNTING):
## counted toward RALLY_MOST there. 0 when it was sent to none.
var _rally_for := 0
var _wallow_bay_hard := false  # At bay for a refused step its way read open for (780 amended (30)).
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
	replicate("teeter")  # Decision 783: a rim's wobble.
	replicate("ailments")
	replicate("peaceable")
	replicate("max_hp")  # 823: a named foe's strength scales it on the server; its bar reads it.
	# Its bow drawn, its guard up: the tell a player steps out of the line by
	# (decision 455).
	replicate("raised")
	replicate("raised_tick")
	# What its hands hold (decision 483): drawn, and its bow when drawn.
	replicate("hands")
	# Its name and boss marker over it (a named one's).
	replicate("given_name")
	replicate("boss")


func _ready() -> void:
	super()
	# An explicit tint wins; otherwise colour by mass.
	if _sprite != null and tint.a <= 0.0:
		var heaviness := clampf(inverse_lerp(SHADE_LIGHT_MASS, SHADE_DARK_MASS, mass), 0.0, 1.0)
		_sprite.modulate = SHADE_LIGHT.lerp(SHADE_DARK, heaviness)
	if Net.is_authority():
		_temper()
		_be_named()
		_settle_idle()
		var kind := str(spawn_spec.get("kind", ""))
		_wary = kinds().has(kind)
		var row: Dictionary = kinds().get(kind, {})
		var opens: Variant = spawn_spec.get("opens_doors")
		opens_doors = bool(opens) if opens != null else bool(row.get("opens_doors", true))
		door_force = int(row.get("door_force", 1))
		picks_up = bool(row.get("picks_up", false))
		lifts = float(row["lifts"]) if row.get("lifts") != null else INF
		bound = bool(row.get("bound", false))
		fearless = bool(row.get("fearless", false))
		never_lies = bool(row.get("never_lies", false))
		band_fights = bool(row.get("band_fights", false))
		holds_off = bool(row.get("holds_off", false))
		# A sought's guard keeps its room too (613, enemy-ai's side; Main._stand_band's props).
		var props: Variant = spawn_spec.get("props", {})
		keeps_room = bool(row.get("keeps_room", false)) or props is Dictionary and bool(props.get("keeps_room", false))
		pack_id = ""
		if row.get("pack") is Dictionary and props is Dictionary and str(props.get("pack", "")) != "":
			pack_id = str(props["pack"])
			pack_rules = PACK_DEFAULTS.duplicate(true)
			pack_rules.merge(row["pack"], true)
			band_fights = true  # Its pack is its band (806 amended (9)): mates its pack only (_mate_of).
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
		_take_senses(row.get("senses", {}))
		_take_named_ways()


## Its named row's ways (holds_post, lurks; 790 amended (2)):
## once, as it spawns. A lurker stands (Idle.GUARD) where it was put.
func _take_named_ways() -> void:
	if named_id.is_empty():
		return
	var row := NamedEnemy.def(named_id)
	holds_post = int(row.get("holds", -1)) if row.get("holds") is float or row.get("holds") is int else -1
	if holds_post >= 0:
		leash = holds_post
	lurks = bool(row.get("lurks", false))
	if lurks:
		idle = Idle.GUARD
	stands = bool(row.get("stand", false))
	if stands:
		_stand_fast()
	var moves: Variant = row.get("moves")
	if moves is Dictionary and (moves as Dictionary).get("ambush") is Dictionary:
		ambush = AMBUSH.duplicate()
		for key: String in moves["ambush"]:
			if ambush.has(key):
				ambush[key] = moves["ambush"][key]


## Whether it lurks now: a lurker with nobody to fight, not roused.
func lurking() -> bool:
	return lurks and target == null and World.tick >= _roused_until


## A lurker roused for HUNT_TICKS (its side engaged near it, or it was struck).
func _rouse() -> void:
	if lurks:
		_roused_until = World.tick + HUNT_TICKS


## Its told strike from behind (790 amended (4)): its numbers (AMBUSH's, by
## its named row), empty for one that has none.
var ambush := {}
## Its told lunge's numbers (LUNGE's, by its kind row; 790 amended (4)),
## empty for a kind with none.
var lunge := {}
## The told strike under way (an ambush or a lunge, one at a time):
## {move, telegraph, lands, shape, aim, cells, from, at}; empty for none.
var _ambush := {}
## Missed: it stands open till this tick.
var _ambush_open_until := -1
## Decision 899 (combat's dagger row): the open window follows a lunge (or an
## ambush) that struck nobody, one she stepped out of (open_after_miss).
var _open_missed := false


## Begins its told strike on [param on] (enemy-ai's to choose when: 790
## amended (4)): it faces them, the strike's cell told (World.telegraph
## "ambush", flank-marked: a blow from behind staggers it and breaks it),
## its cue cried, and it holds still for "windup" ticks. False, nothing
## begun, when it has no ambush, one is under way, or the told line from
## where it stands does not end on their cell (810: the tell shows what
## is struck).
func begin_ambush(on: GridEntity) -> bool:
	if ambush.is_empty() or not _ambush.is_empty() or not is_instance_valid(on) or not on.spawned:
		return false
	var aim := World.struck_cell(on)  # Who a told blow strikes is struck_cell's (combat's ruling, 810 amended).
	if aim == tile:
		return false
	var toward := Vector2(aim - tile).normalized()
	var shape := Telegraph.line(tile, toward, Vector2(aim - tile).length(), 1)
	if aim not in World.telegraph_cells(shape):
		return false
	World.face(self, Senses.way_toward(tile, aim))
	var ticks := int(ambush["windup"])
	var id := World.telegraph(self, "ambush", shape, ticks, true)
	if id == 0:
		return false
	_ambush = {"move": &"ambush", "telegraph": id, "lands": World.tick + ticks, "shape": shape, "aim": aim,
		"cells": [aim] as Array[Vector2i], "from": World.tick, "at": tile}
	_cry(&"ambush", int(ambush["cue_reach"]))
	print("[ambush] %s winds up at %s on %s at %s, lands in %d ticks" % [name, tile, alert_who(on), aim, ticks])  # Never a player's name (alert_who).
	return true


## Begins its told lunge at [param on] (790 amended (4)): it faces them,
## the line "reach" cells from it told (World.telegraph "lunge"; a step
## aside from it spares, a step back along it does not), and it holds still
## for "windup" ticks. False, nothing begun, when its kind has no lunge, a
## told strike is under way, or the line does not reach their cell.
func begin_lunge(on: GridEntity) -> bool:
	if lunge.is_empty() or not _ambush.is_empty() or not is_instance_valid(on) or not on.spawned:
		return false
	var at := World.struck_cell(on)  # Who a told blow strikes is struck_cell's (combat's ruling, 810 amended).
	if at == tile:
		return false
	var toward := Vector2(at - tile).normalized()
	var shape := Telegraph.line(tile, toward, float(lunge["reach"]), 1)
	var cells: Array[Vector2i] = []
	for cell in World.telegraph_cells(shape):
		if cell != tile:
			cells.append(cell)
	if at not in cells:
		return false
	World.face(self, Senses.way_toward(tile, at))
	var ticks := int(lunge["windup"])
	var id := World.telegraph(self, "lunge", shape, ticks)
	if id == 0:
		return false
	_ambush = {"move": &"lunge", "telegraph": id, "lands": World.tick + ticks, "shape": shape, "aim": at,
		"cells": cells, "from": World.tick, "at": tile}
	print("[lunge] %s winds up at %s on %s, lands in %d ticks" % [name, tile, alert_who(on), ticks])  # Never a player's name (alert_who).
	return true


## Whether its ambush holds it: wound up, or standing open after a miss
## (after any lunge, 790 amended (6)).
func ambushing() -> bool:
	return not _ambush.is_empty() or World.tick < _ambush_open_until


## The ambush under way, each fighting tick: true while it holds it. It
## lands when due on whoever is still on the told cell (World.tell_struck,
## 810): "damage", cause &"ambush". On nobody it stands open "recover"
## ticks; a lunge stands open after it lands too, overreached, and cries
## &"overreach" (790 amended (6)). A stun, a down or a knock off its cell
## since it began breaks it.
func _tend_ambush() -> bool:
	if _ambush.is_empty():
		return World.tick < _ambush_open_until
	var from := int(_ambush["from"])
	if stunned_until_tick > from or down_until > from or tile != _ambush["at"] or not spawned:
		_end_ambush(false)
		print("[ambush] %s broken" % name)
		return false
	if World.tick < int(_ambush["lands"]):
		return true
	var move: StringName = _ambush["move"]
	var numbers: Dictionary = lunge if move == &"lunge" else ambush
	var aim: Vector2i = _ambush["aim"]
	var struck: Array[Vector2i] = _ambush["cells"]
	_end_ambush(true)
	var hit: Array[GridEntity] = []
	for each in World.tell_struck(self, struck):
		if each != self and each.spawned and each.hp > 0 and each.max_hp > 0:
			hit.append(each)
	for each in hit:
		var amount := int(numbers["damage"])
		if move == &"lunge":
			# A raised guard facing it takes a lunge (World._meet_guard, 340)
			# and, as a shot, is never broken by it (only too little stamina
			# breaks it): a dagger's thrust, its tell all it has.
			var met: Variant = World._meet_guard(each, self, amount, 0.0, true, false, true)  # Told (340 amended (4)).
			if met != null:
				amount = int((met as Array)[0])
				if each.raised == "block":
					# 340 amended: taken on a raised shield, the robber thrown back as off a plain blow.
					World._stun_for(self, World.SHIELD_RECOIL_STUN, &"guarded")
		if amount > 0:
			World.damage(each, amount, self, move)
	next_attack_tick = maxi(next_attack_tick, World.tick + attack_ticks)
	if hit.is_empty() or move == &"lunge":
		# Stepped out of it, or any lunge, landed or missed (790 amended (6)): the opening.
		_ambush_open_until = World.tick + int(numbers["recover"])
		_open_missed = hit.is_empty()
	if move == &"lunge":
		_cry(&"overreach", 0)  # To whoever sees it (its drawn pose); no noise, so it wakes nobody.
	print("[%s] %s at %s -> %s" % [move, name, aim, "struck %d" % hit.size() if not hit.is_empty() else "missed"])
	return true


## Decision 899 (combat's dagger row): whether it stands open after a lunge
## that struck nobody (790 amended (6)'s overreach window, she stepped out of
## it): a dagger's double counts against it as from behind (World._try_hit),
## so reading him pays the dagger where his going round her used to.
func open_after_miss() -> bool:
	return _ambush.is_empty() and World.tick < _ambush_open_until and _open_missed


func _end_ambush(landed: bool) -> void:
	if not _ambush.is_empty():
		World.end_telegraph(int(_ambush["telegraph"]), landed)
	_ambush = {}


## Its kind's "senses" (decision 784; read_kinds' "senses"): {sight: cells
## in full light, cone: degrees it sees without turning (360 all round),
## night: 0..1 its sight left in the dark, hearing: times a noise's reach,
## alert_sight: cells more while it looks about (its cone 60 degrees
## wider), notice: how fast it notices}. A kind with none is as before.
func _take_senses(given: Variant) -> void:
	if not given is Dictionary or (given as Dictionary).is_empty():
		return
	var block := given as Dictionary
	if block.has("sight"):
		sight_range = maxi(1, int(block["sight"]))
	var eyes := block.duplicate()
	eyes["night"] = block.get("night", 0.0)
	eyes["alert_sight"] = block.get("alert_sight", 1)
	senses.take(eyes, 120.0 if _wary else 360.0)  # Its eyes, as any agent's (784 amended).
	hearing = maxf(0.0, float(block.get("hearing", 1.0)))
	alert_sight = senses.extra_sight
	notice_rate = maxf(0.01, float(block.get("notice", 1.0)))


## The cosine of half of a cone of [param degrees] (Senses.cone_cos); -1
## (all round) at 360 or more.
static func cone_cos_of(degrees: float) -> float:
	return -1.0 if degrees >= 360.0 else cos(deg_to_rad(clampf(degrees, 0.0, 360.0) / 2.0))


## The keenest "hearing" of any kind, at least 1 (World.noise looks so much
## farther for listeners, and each listener's own ear decides).
static func hearing_most() -> float:
	if _hearing_most < 0.0:
		_hearing_most = 1.0
		for kind: String in kinds():
			var block: Variant = kinds()[kind].get("senses", {})
			if block is Dictionary:
				_hearing_most = maxf(_hearing_most, float((block as Dictionary).get("hearing", 1.0)))
	return _hearing_most


## Whether it knows [param entity], seen [param d] cells off this think, by
## its notice (decision 784): at once for a kind with no "senses", within
## NOTICE_ALWAYS, its target, or one that struck it; else filled by how
## near (twice as fast while it looks about) till NOTICE_FULL. Past
## NOTICE_SUSPECT and not yet known, it turns to look ([member _glimpsed]).
func _noticed(entity: GridEntity, d: int, reach: float) -> bool:
	if notice_rate <= 0.0 or d <= Senses.NOTICE_ALWAYS or entity == target or _answering(entity):
		return true
	var id := entity.get_instance_id()
	var steps := _notice_steps
	var near := clampf(1.0 - float(d) / (reach + 1.0), 0.05, 1.0)
	var gain := notice_rate * near * steps / NOTICE_FILL_TICKS * (2.0 if senses.alerted else 1.0)
	# Seen this think: its fade (_fade_notice) is given back.
	var now: float = minf(float(_notice.get(id, 0.0)) + gain + steps / NOTICE_FADE_TICKS, NOTICE_FULL)
	_notice[id] = now
	if now >= NOTICE_FULL:
		return true
	if now >= NOTICE_SUSPECT and _glimpsed == NO_TILE:
		_glimpsed = entity.tile
	return false


## The ticks this think counts for (784's notice), set by _fade_notice.
var _notice_steps := 1


## Each think (784): its notice of those it no longer sees fades, and goes
## at 0 (so it never grows with the world); its look-about sight.
func _fade_notice() -> void:
	senses.alerted = alert == Alert.SUSPICIOUS or alert == Alert.HUNTING
	if notice_rate <= 0.0:
		return
	_notice_steps = clampi(World.tick - _notice_tick, 1, NOTICE_STEP_MOST) if _notice_tick >= 0 else 1
	_notice_tick = World.tick
	for id: int in _notice.keys():
		var left := float(_notice[id]) - _notice_steps / NOTICE_FADE_TICKS
		if left <= 0.0 or not is_instance_id_valid(id):
			_notice.erase(id)
		else:
			_notice[id] = left


## How far it notices [param entity] (784): 0..1, 1 it knows them.
func notice_of(entity: GridEntity) -> float:
	if notice_rate <= 0.0:
		return 1.0
	return float(_notice.get(entity.get_instance_id(), 0.0))


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


## A named one (decision 716): its record (made at its first spawn), its
## name over it, and its numbers times its fixed strength.
func _be_named() -> void:
	boss = bool(kinds().get(str(spawn_spec.get("kind", "")), {}).get("boss", false))
	named_id = str(spawn_spec.get("named", ""))
	if named_id.is_empty():
		return
	var record := World.named_enter(named_id, str(spawn_spec.get("kind", "")))
	spawn_spec["label"] = str(record["name"])
	given_name = str(record["name"])
	boss = boss or bool(NamedEnemy.def(named_id).get("boss", false))
	NamedEnemy.strengthen(self, record)
	_pace = move_ticks


## Its kind's tactic and its own manner, the same every time for the same
## name (a respawn, a restart). A monster of no kind is PLAIN, as it was.
func _temper() -> void:
	var kind := str(spawn_spec.get("kind", ""))
	_apply_fight(fight_for(kind))
	_pace = move_ticks
	if not kinds().has(kind):
		return
	tactic = kinds()[kind]["tactic"]
	var moves: Variant = kinds()[kind].get("moves")
	lunge = {}
	if moves is Dictionary and (moves as Dictionary).get("lunge") is Dictionary:
		lunge = LUNGE.duplicate()
		for key: String in moves["lunge"]:
			if lunge.has(key):
				lunge[key] = moves["lunge"][key]
	_rng.seed = hash(String(name))
	_pace = move_ticks * (1.0 + _rng.randf_range(-pace_spread, pace_spread))
	move_ticks = _pace
	attack_ticks = maxi(4, attack_ticks + _rng.randi_range(-cooldown_spread, cooldown_spread))
	reaction_ticks = _rng.randi_range(0, REACTION_TICKS_MAX)
	boldness = _rng.randf()
	pause_chance = _rng.randf_range(0.0, PAUSE_CHANCE_MAX)
	_settle_temper(kind)
	var factions := _factions()
	foes = factions.on_sight(factions.of_kind(kind))


func _sim_tick() -> void:
	if not _bundle_rolled:
		_wear_bundle()
	_tend_recover()
	_mind_the_rest()
	if not _ambush_armed and lurks and lurking():
		_ambush_armed = true  # Lurking again: its next first blow from behind is told.
	if laid:
		var woke_by := _waking_foe()
		if woke_by == null:
			if tile == grave and facing != home_facing:
				World.face(self, home_facing)  # Come home mid-step: turned once its step is done.
			return  # Struck or not, it stands still (decision 547; 631 amended: standing, not lying).
		rise()  # A foe in sight: it turns to them and keeps its grave (GUARD).
		World.face(self, Senses.way_toward(tile, woke_by.tile))
	if not noticing:
		_unnoticing()
		return
	if stands:
		if _stand_at == NO_TILE:
			_stand_at = home if home != NO_TILE else tile
		if Apex.to_den(self, STAND_BELOW, _stand_at, struck_by if is_instance_valid(struck_by) else null, STAND_RULE):  # Guarded here: the getter is not called on a read inside the class (806 amended (20)).
			return  # Low and off its ground: back to it (806 amended (14)'s stand).
	if alert == Alert.FLEEING:
		_flee_tick()
		return
	if _wary and senses.last_tick > _rout_tick and _heard_rout():
		return
	var looked := Time.get_ticks_usec()
	_fade_notice()
	var seen := _nearest_visible_target()
	var by_pack := false
	if seen == null and pack_id != "":
		seen = _pack_target()  # Its pack's fight is its own (824).
		by_pack = seen != null
	World.senses_usec += Time.get_ticks_usec() - looked  # Its own part, "senses" (784).
	if seen != null and _wary and _beyond_leash():
		_give_up(seen)
		seen = null
	if seen != target:
		_noticed_tick = World.tick
		slot = NO_TILE
		_front_ticks = 0
		if seen == null:
			if not _hunt(target if is_instance_valid(target) else null):  # A target freed (806 amended (20)): nobody to hunt.
				# The fight is over: back to where it idles, then on as before.
				_returning = idle != Idle.NONE
				_ran_to_call = false  # The fight over: next time it may run to call again.
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
	if seen != null and seen != target and not named_id.is_empty():
		World.named_note(self, "met", seen)  # Decision 716: npc's memory of it.
	target = seen
	if target == null:
		_holding = false
		_hold_open = 0
		_drop_windup()
		if not raised.is_empty():
			World.try_stance(self, "")  # Nobody to shoot or guard against.
		if _pick_up(false):
			return
		if band_fights or stands:
			_rally_look()
		_alert_tick()
		return
	var took_up := alert != Alert.FIGHTING
	if alert == Alert.IDLE:
		_post = tile
		_alert_note("%s %s (%d cells)" % ["takes up its pack's fight on" if by_pack else "sees",
				alert_who(target), World.distance(tile, target.tile)])
	alert = Alert.FIGHTING
	if (band_fights or stands) and not _rally_asked.is_empty():
		_rally_send()
	_quarry = target
	if target.tile != _quarry_at:
		_quarry_from = _quarry_at
		_quarry_at = target.tile
	if pack_id != "":
		if took_up and _pack_target() == null:
			_cry(&"whistle", 0)  # The first of its pack: heard by players, never by monsters (824).
		var alive := _pack_alive()
		_pack_seen = maxi(_pack_seen if not took_up else 0, alive)
		if _pack_seen > 0 and alive == 0:
			_flee(target.tile)  # The last of its pack (824): away, and out of the fight.
			return
	if _wary:
		if took_up and temper != Temper.BOLD and pack_id == "":
			_call_for_help()
		if _should_flee() and _breaks():
			return
	if took_up:
		_pressing = false
		_standoff_mark = []
	if holds_off and World.tick >= _ambush_open_until and _holds_now():
		# Never sent off mid-opening: he stands where he overreached (790 amended (6)).
		_hold_off()
		return  # The party has its share of the band on it: he holds off, his turn next.
	if _tend_ambush():
		return  # Its told strike from behind, or the opening after (790 amended (4)).
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
		if _in_strike_reach(target):
			_reached_from = tile
			_reached_tick = World.tick
			if not _bash_guard():
				_blow()
		elif World.tick >= next_move_tick:
			if World.free_body(target):
				slot = _pick_slot()
				if _strike_holding:
					return  # Holds the cell it reached her from (699 amended (2)).
				if slot != NO_TILE and _go_to(slot):
					return  # To a cell it can strike a free body from (699).
			var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now())
			if not path.is_empty():
				World.try_move(self, path[0] - tile)
			elif not _standing_off():
				next_move_tick = World.tick + CHASE_RETRY_TICKS  # No way in: look again in a moment.
		return
	if not _windup.is_empty():
		_wind_on()
		return
	if World.tick - _noticed_tick < reaction_ticks:
		return  # Sizing it up.
	var can_strike := World.tick >= next_attack_tick and World.tick >= next_move_tick
	if pack_id != "" and World.tick >= _dart_until and _pack_waits():
		_hover()
		return  # Faced, or enough of its pack at it: it waits its turn round it (824).
	if _in_strike_reach(target):
		_reached_from = tile
		_reached_tick = World.tick
	if _in_strike_reach(target) or can_strike and _meets_in_stride():
		if _darts() and World.tick < _dart_until:
			if World.tick >= _dart_from:
				_step_out()
			return
		if _bash_guard():
			return  # Its guard opened: the blows next.
		if not can_strike:
			return
		if tactic == Tactic.FLANK and _flanks_now() and (_in_front() or not World.guarding(target, self).is_empty()) \
				and _front_ticks < flank_patience_ticks:
			_front_ticks += 1
			var round_to := _pick_slot()
			if round_to != NO_TILE and round_to != tile and _go_to(round_to):
				return
			if _front_ticks < flank_patience_ticks:
				return
		if _ambush_armed and not ambush.is_empty() and not _in_front():
			_ambush_armed = false  # One a lurk-break, told or not (790 amended (4), enemy-ai's side).
			if begin_ambush(target):
				return
		_strike()
		return
	if _darts() and World.tick < _dart_until:
		return  # Out of reach, cooling down.
	if World.tick < next_move_tick:
		return
	if World.wielded(self).is_empty() and _pick_up(true):
		return  # Bare-handed: the weapon at its feet first.
	if pack_id == "" and not _pressing \
			and (boldness < HOLD_BACK_BELOW and temper != Temper.BOLD and not _struck_named(target) or _dreads_target()) \
			and World.distance(tile, target.tile) <= HOLD_BACK_RANGE and World.distance(tile, target.tile) > 1 \
			and not _target_beset(_others_needed()) and not _band_holds() and (not band_fights or _mate_near()):
		# Never beside its target (806 amended (16); the crypt camp, gen 3 seed 4): there it is out of
		# reach only across a wall's corner, and held so, its stand-off ran out, it
		# watched her, her nearness roused it, and it held again: ten minutes
		# FIGHTING and never a blow. Beside her it goes round to a cell it strikes from.
		if _first_holder():
			# 806 amended (21): two or more holding off one target, each waiting for
			# another at her, stared five seconds and walked home. The one who held
			# first presses; at her, it meets the others' _target_beset.
			if not _pressing:
				World._log("[press] %s presses in on %s" % [name, World.plain_name(target)])  # 392 amended (9).
			_pressing = true
		else:
			if _held_back_last < World.tick - 1:
				_held_back_since = World.tick
				World._log("[hold] %s holds off %s" % [name, World.plain_name(target)])  # 392 amended (9).
			_held_back_last = World.tick
			_standing_off()
			return  # Waits for the others; a band that outnumbers them goes in together.
	if not _pressing and _rng.randf() < pause_chance:
		next_move_tick = World.tick + _rng.randi_range(PAUSE_TICKS.x, PAUSE_TICKS.y)
		return
	if tactic == Tactic.HEAVY:
		_charging = World.distance(tile, target.tile) <= charge_range \
				and World.has_clear_line(tile, target.tile)
		move_ticks = _pace * (charge_pace if _charging else 1.0)
	slot = _pick_slot()
	if _strike_holding:
		return  # Holds the cell it reached her from (699 amended (2)).
	if slot == NO_TILE or not _go_to(slot):
		# Nowhere free beside it: as near as it can get.
		var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now())
		if not path.is_empty():
			World.try_move(self, path[0] - tile)
		elif not _standing_off():
			next_move_tick = World.tick + CHASE_RETRY_TICKS  # No way in: look again in a moment.


## Decision 897: [param gone] leaving the world; its own fields let go of it
## (GridEntity.forget). A gone target is nobody: the next tick looks again.
func forget(gone: GridEntity) -> void:
	super(gone)
	if target == gone:
		target = null
		slot = NO_TILE
	if _provoked == gone:
		_provoked = null
	if _blocked_by == gone:
		_blocked_by = null
	if _rally == gone:
		_rally = null
	if struck_by == gone:
		struck_by = null
	if _quarry == gone:
		_quarry = null
	if _wallow_from == gone:
		_wallow_from = null
	if _strike_chosen_on == gone:
		_strike_chosen_on = null  # 790 amended (10): its strike's choice was for gone.
		_strike_chosen_until = -1


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
		World.try_loose(self, _aim_angle())
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
	var aim := _aim_angle()
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


## A plain blow at its target: its heavy weapon's wind-up, else its lead
## (338 amended (4)), else at once. Whether it began or struck.
func _blow() -> bool:
	if not _stood_settle():
		return false
	var began: bool
	if World.windup_ticks(self) > 0 or lead_ticks > 0:
		began = World.try_wind_up(self, target, lead_ticks)
	else:
		began = World.try_attack(self, target)
	if began:
		_recover_after_blow()
	return began


## Stop to strike (338 amended (4), enemy-ai's side): whether it has stood
## settle_ticks since its last step or push ended (GridEntity._moved_tick,
## its step's move_ticks), so a blow begins only once it is seen to stand.
func _stood_settle() -> bool:
	return _moved_tick < 0 or World.tick >= _moved_tick + ceili(move_ticks) + settle_ticks  # Never moved: it stands.


## Stop to strike: no step till strike_recover_ticks after the blow it just
## began lands, landed or missed. Struck at once, from now; wound up, from
## its "lands", set once World has struck it (_tend_recover: a blow lands
## only once its striker's next_move_tick is past). A DART one steps out
## after its blow anyway (combat: "a wolf darts out anyway").
func _recover_after_blow() -> void:
	if _darts():
		return
	var w := World.winding(self)
	if w.is_empty():
		next_move_tick = maxf(next_move_tick, World.tick + strike_recover_ticks)
	else:
		_recover_due = int(w["lands"])


## Its wound-up blow fallen (or given up): its stop-to-strike recover from
## when it was due to land (_recover_after_blow).
func _tend_recover() -> void:
	if _recover_due >= 0 and World.winding(self).is_empty():
		next_move_tick = maxf(next_move_tick, _recover_due + strike_recover_ticks)
		_recover_due = -1


## Its target winding a heavy blow up at it (World.winding, 392; decision
## 412): in its reach, a shield-bearer with its bash ready bashes (the
## stagger gives the blow up); else one not bold steps out of reach
## (_step_back), and keeps out till the blow has fallen; a bold one, or one
## with nowhere to step, fights on. Whether that was its turn. A sword's
## lead (338 amended (2)) is its plain blow, not one to meet: it fights on.
func _meet_wind_up() -> bool:
	var theirs := World.winding(target)
	if theirs.is_empty() or theirs.get("target") != self or theirs.get("lead", false):
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
		if _in_strike_reach(entity) and World.try_bash(self, entity):
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
	if World.shot_aim(self, _aim_angle(), cells).get("hit") != target:
		return false
	# A friend inside even its narrowest cone (decision 620): no shot from here.
	return _cone_clear(deg_to_rad(float(Items.verb_of(World.drawn_with(self)).get("spread_floor", 0.0))))


## 806 amended (21): another of its side holds back from its target too (held
## it this tick or the last), and it held first of them all (the earlier
## since, then the lower id; one not holding yet holds from now), and the
## holders outnumber the foes about it (_band_odds: two on one player, not on
## two). A holder that dreads its target never goes first.
func _first_holder() -> bool:
	if _dreads_target():
		return false
	var mine := _held_back_since if _held_back_last >= World.tick - 1 else World.tick
	var others := 0
	for entity in World.monsters():
		var other := entity as Monster
		if other == null or other == self or not other.spawned or other.hp <= 0 or not _mate_of(other) \
				or other.target != target or other._held_back_last < World.tick - 1:
			continue
		others += 1
		if other._held_back_since < mine or other._held_back_since == mine and other.id < id:
			return false
	# Only holders that outnumber the foes about it (_band_odds' y: the players
	# and companions within BAND_TILES): a pair on two holds as before.
	return others > 0 and others + 1 > _band_odds().y


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
		# A heavy weapon's own, or a held lead at least lead_ticks.
		if _stood_settle() and World.try_wind_up(self, target, lead_ticks):
			_recover_after_blow()
		return
	match tactic:
		Tactic.HEAVY:
			# Its own windup_ticks it stands through already (_wind_on): no settle.
			move_ticks = _pace
			var direction := World.melee_way(self, target)
			if not _in_strike_reach(target):
				# Wound up on where it will be (lead-the-target): that way.
				var to := _run_on(windup_ticks)[-1] - World.body_centre(self)
				direction = Vector2i(roundi(cos(snappedf(to.angle(), PI / 4.0))), roundi(sin(snappedf(to.angle(), PI / 4.0))))
			_windup = {"target": target, "lands": World.tick + windup_ticks, "direction": direction, "from": tile, "began": World.tick}
			World.face(self, direction)
			_world_winding(direction, windup_ticks)
		Tactic.FLANK:
			# Clearly behind her, or not (790 amended (10): side-on is the lunge), chosen once a strike.
			var behind := _chooses_backstab()
			if not behind and begin_lunge(target):
				_strike_chosen_until = -1
				return  # From in front or side-on, told (790 amended (4)).
			if behind:
				# From behind, told too (the coordinator's approval of combat's
				# crypt design): the same wind-up as its front blow (lead_ticks),
				# its backstab's harm on top as it lands (World._tend_wind_ups'
				# "bonus"). Before, at once and untold.
				if _stood_settle() and World.try_wind_up(self, target, lead_ticks):
					wind_up["bonus"] = backstab_damage
					_strike_chosen_until = -1
					_recover_after_blow()
					if pack_id != "":
						_dart_out()  # A pack's: in, and out again (824).
			elif _blow():
				_strike_chosen_until = -1
				if pack_id != "":
					_dart_out()
		_:
			if _blow() and tactic == Tactic.DART:
				_dart_out()


## Out after the blow it just began lands (DART, and a pack's, 824): its
## lead, then dart_after_ticks; back before the next.
func _dart_out() -> void:
	if not World.winding(self).is_empty():
		_dart_from = int(World.winding(self)["lands"]) + dart_after_ticks
		_dart_until = World.tick + World.attack_ticks_of(self) - ceili(_pace)
	else:
		_dart_from = World.tick + dart_after_ticks
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
	var began := int(_windup["began"])
	_windup = {}
	if is_instance_valid(aimed) and (aimed as GridEntity).spawned and _in_strike_reach(aimed as GridEntity):
		World.try_attack(self, aimed as GridEntity)
	else:
		World.try_swing(self, direction)
	# Out of its cycle (338 amended (5), combat's numbers; as a lead is,
	# 338 amended (4)): its next blow attack_ticks_of after it began winding.
	next_attack_tick = mini(next_attack_tick, began + World.attack_ticks_of(self))
	_recover_after_blow()  # Landed or swung at the air: it stands (338 amended (4)).


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
## The slots claimed round each target (698 amended): target id -> {cell:
## [monsters]}, gathered from every monster once a tick, each pick added
## as it is made; read as before, by each one's own slot and target now,
## so it is the same as going through every monster on each pick.
static var _claims := {}
static var _claims_tick := -1


func _claimed_round(of: GridEntity) -> Dictionary:
	if _claims_tick != World.tick:
		_claims.clear()
		_claims_tick = World.tick
		for entity in World.monsters():
			var other := entity as Monster
			if other != null and other.target != null and is_instance_valid(other.target):
				var key := other.target.get_instance_id()
				if not _claims.has(key):
					_claims[key] = {}
				var round_it: Dictionary = _claims[key]
				if not round_it.has(other.slot):
					round_it[other.slot] = []
				(round_it[other.slot] as Array).append(other)
	var key := of.get_instance_id()
	if not _claims.has(key):
		_claims[key] = {}
	return _claims[key]


func _pick_slot() -> Vector2i:
	_strike_holding = false
	var held := false
	var claims := _claimed_round(target)
	var claimed := {}
	for at: Vector2i in claims:
		for by: Object in claims[at]:
			if by != self and is_instance_valid(by) and (by as Monster).target == target and (by as Monster).slot == at:
				claimed[at] = true
				break
	var best := NO_TILE
	var best_score := INF
	var facing := Vector2(target.facing).normalized()
	var centre := World.body_centre(target)
	var free := World.free_body(target)
	var lean := tactic == Tactic.FLANK and _flanks_now()
	var nearest := NO_TILE
	var nearest_score := INF
	var cells: Array[Vector2i] = []
	var meet := centre
	# Its pack's sides of the target (824): a cell on the side a mate takes costs more.
	var sides: Array[Vector2] = []
	if pack_id != "":
		for other in _pack_members():
			if other.target == target:
				var at_mate := other.slot if other.slot != NO_TILE else other.tile
				if at_mate != target.tile:
					sides.append((Vector2(at_mate) - centre).normalized())
	var spread := float(pack_rules.get("spread", 0.0))
	var aim := -1.0
	if free:
		var any := _strike_cells()  # Where it can strike a free body from (699).
		meet = _strike_plan.get("centre", centre)
		for at in any:
			# Not chest to chest (699 amended, enemy-ai's side); the cell it
			# stands on always stays (the body is held FOE_GAP off it), and its
			# slot with STRIKE_GAP_SLACK, so a zig-zagging body doesn't make
			# it re-pick back and forth.
			var gap := Vector2(at).distance_to(meet)
			if at == tile or gap >= 0.5 + World.FOE_GAP or at == slot and gap >= 0.5 + World.FOE_GAP - STRIKE_GAP_SLACK:
				cells.append(at)
		if _strike_held != tile:
			_strike_held = tile
			_strike_held_tick = World.tick
		var swung_here := next_attack_tick > _strike_held_tick and World.tick <= next_attack_tick + STRIKE_HOLD_TICKS
		var reached_here := _reached_from == tile and World.tick - _reached_tick <= STRIKE_HOLD_TICKS
		if not cells.has(tile) and (swung_here or reached_here) \
				and Vector2(tile).distance_to(meet) <= World.reach_limit(self) + STRIKE_HOLD_SLACK:
			cells.append(tile)  # Just dodged out of reach: it holds its ground.
			held = true
		if cells.is_empty():
			cells = any  # None that far: never without a cell to fight from.
		aim = STRIKE_SPAN_SHARE * World.span_of(World.blow_verb(self))
	else:
		for direction in World.DIRECTIONS:
			cells.append(target.tile + direction)
	for at in cells:
		# Never a level link's cell (571 amended (1); 571 refuses it to all but players): a slot there was
		# picked again and again, the step refused, beside a player at a doorway or stair.
		if claimed.has(at) or not World.is_walkable(at) or World.is_link_cell(at) or not free and not World.can_melee(at, target.tile):
			continue
		var occupant := World.get_entity_at(at)
		if occupant != null and occupant != self:
			continue
		var score := float(World.distance(tile, at))
		if at == tile or at == slot:
			score -= 0.5
		if aim > 0.0:
			score += maxf(0.0, aim - Vector2(at).distance_to(meet))  # Short of its reach costs; no farther cell is chased.
		if score < nearest_score:
			nearest = at
			nearest_score = score
		if lean:
			score += 3.0 * (Vector2(at) - centre).normalized().dot(facing)
		for side in sides:
			score += 2.0 * spread * maxf(0.0, (Vector2(at) - centre).normalized().dot(side))
		if score < best_score:
			best = at
			best_score = score
	if lean and best != nearest and not _short_way(best):
		best = nearest  # The way round is long (806 amended (9)): the nearest free cell.
	if best != NO_TILE:
		if not claims.has(best):
			claims[best] = []
		(claims[best] as Array).append(self)  # Seen by those picking after it this tick, once its slot is set.
	_strike_holding = held and best == tile
	return best


## Whether it steps out after its blows (DART, and a pack's, 824).
func _darts() -> bool:
	return tactic == Tactic.DART or pack_id != ""


## The others of its pack (824): spawned, alive, not running.
func _pack_members() -> Array[Monster]:
	var out: Array[Monster] = []
	for entity in World.monsters():
		var other := entity as Monster
		if other != null and other != self and other.pack_id == pack_id and other.spawned and other.hp > 0 \
				and other.alert != Alert.FLEEING:
			out.append(other)
	return out


func _pack_alive() -> int:
	return _pack_members().size()


## A target one of its pack within PACK_WAKE_REACH is fighting (824), or null.
func _pack_target() -> GridEntity:
	for other in _pack_members():
		if other.alert == Alert.FIGHTING and is_instance_valid(other.target) and other.target.spawned \
				and World.distance(tile, other.tile) <= PACK_WAKE_REACH:
			return other.target
	return null


## Whether it waits its turn (824): it is the one its target faces while
## another of its pack could go in, or "in_reach" of its pack are at it
## already and it is not.
func _pack_waits() -> bool:
	var others := _pack_members()
	if _in_front() and not others.is_empty():
		return true
	if _in_strike_reach(target):
		return false
	var at := 0
	for other in others:
		if other.target == target and other._in_strike_reach(target):
			at += 1
	return at >= int(pack_rules["in_reach"])


## Waiting its turn (824): in the ring "hover" cells off its target, facing it.
func _hover() -> void:
	if World.tick < next_move_tick:
		return
	var ring: Array = pack_rules["hover"]
	var d := World.distance(tile, target.tile)
	if d < int(ring[0]):
		if _step_back():
			return
	elif d > int(ring[1]):
		var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now())
		if not path.is_empty() and World.distance(path[0], target.tile) >= int(ring[0]):
			World.try_move(self, path[0] - tile)
			return
	World.face(self, Senses.way_toward(tile, target.tile))


## Its mate (806 amended (9)'s band rules): one of its pack where it has one
## (824), else of its side.
## Decision 898: whether a told strike of its on [param cells] would cut a
## living mate, up or down (_mate_of: its pack, else its side; an animal's herd, and
## a herdless beast has none): World.telegraph begins none such. Bands and
## packs of the living spare their mates; the draugr spends his dead
## (Draugr's override).
func tell_cuts_mate(cells: Array[Vector2i]) -> bool:
	for body in World._bodies_in(self, cells):
		if spares(body):
			return true
	return false


## Decision 898: whether its told strikes spare [param other]: a living
## mate, up or down (one kneeling in the line cannot step out). Its tell
## never begins through one (tell_cuts_mate), and one never steps into its
## told cells (World._into_mates_tell). A herdless beast has none; the
## draugr spares nobody (his override).
func spares(other: GridEntity) -> bool:
	if self is Animal and (self as Animal).herd == "":
		return false
	return other is Monster and other != self and other.hp > 0 and _mate_of(other)


func _mate_of(other: GridEntity) -> bool:
	if pack_id != "":
		return other is Monster and (other as Monster).pack_id == pack_id
	return _same_side(other)


## FLANK goes round only while it may (806 amended (9)): a band fighter only
## while a mate of its side is beside its target; any other always. Never
## while it has been struck within flank_patience_ticks (899: it circles for
## an opening, is cut, turns and fights from her front; ui-design's fists
## trial had the robber she punched going round her two seconds).
func _flanks_now() -> bool:
	return not _struck_lately() and (not band_fights or _mate_at_target())


## Decision 899: a blow on it from anyone within flank_patience_ticks
## (note_struck's struck_by and struck_tick).
func _struck_lately() -> bool:
	return is_instance_valid(struck_by) and World.tick - struck_tick <= flank_patience_ticks


## Whether its walk to [param to] is at most FLANK_DETOUR steps longer than
## straight; worked out once for where it stands and the cell.
func _short_way(to: Vector2i) -> bool:
	if _detour_mark.size() == 3 and _detour_mark[0] == tile and _detour_mark[1] == to:
		return _detour_mark[2]
	var straight := World.distance(tile, to)
	var ok := straight <= 1
	if not ok:
		var path := World.find_path(tile, to, false, null, (straight + FLANK_DETOUR) * 8, false, {}, opens_doors_now())
		ok = not path.is_empty() and path.size() <= straight + FLANK_DETOUR
	_detour_mark = [tile, to, ok]
	return ok


## Another of its side, spawned and not running, beside its target.
func _mate_at_target() -> bool:
	if target == null:
		return false
	for direction in World.DIRECTIONS:
		var other := World.get_entity_at(target.tile + direction) as Monster
		if other != null and other != self and other.spawned and other.alert != Alert.FLEEING \
				and other.tile == target.tile + direction and _mate_of(other):
			return true
	return false


## Another of its side who could join it (806 amended (9)): spawned, alive,
## not running, within its call's reach or after the same target.
func _mate_near() -> bool:
	for entity in World.monsters():
		var other := entity as Monster
		if other != null and other != self and other.spawned and other.hp > 0 and other.alert != Alert.FLEEING \
				and _mate_of(other) and (World.distance(tile, other.tile) <= call_reach or target != null and other.target == target):
			return true
	return false


## The nearest living mate of its side in the zone, not running; null for none.
func _nearest_mate() -> Monster:
	var best: Monster = null
	var best_d := INF
	for entity in World.monsters():
		var other := entity as Monster
		if other == null or other == self or not other.spawned or other.hp <= 0 or other.alert == Alert.FLEEING \
				or not _mate_of(other):
			continue
		var d := float(World.distance(tile, other.tile))
		if d < best_d:
			best = other
			best_d = d
	return best


## It would break (_should_flee): true when it does. A band fighter runs only
## to call its band, once a fight, toward its nearest mate, and comes back
## (_flee_tick); with no mate left, or once run, it fights on.
func _breaks() -> bool:
	if not band_fights:
		_flee(target.tile)
		return true
	if _ran_to_call:
		return false
	var mate := _nearest_mate()
	if mate == null:
		return false
	_ran_to_call = true
	_called_tick = -100000
	_call_for_help()
	var rally := target
	_flee(target.tile, false)
	_way_out = NO_TILE  # Not out of the level: to its mate, and back.
	_rally = rally
	_call_to = mate.tile
	_alert_until = World.tick + CALL_RUN_TICKS
	return true


## FLANK (790 amended (10)): whether the strike it is about to make is its
## backstab. Chosen by clearly_behind when it has no choice standing for this
## target, then kept till a blow begins (_strike clears it) or
## STRIKE_CHOICE_TICKS pass.
func _chooses_backstab() -> bool:
	if World.tick > _strike_chosen_until or _strike_chosen_on != target:
		_strike_behind = clearly_behind(self, target)
		_strike_chosen_until = World.tick + STRIKE_CHOICE_TICKS
		_strike_chosen_on = target
	return _strike_behind


## Whether [param by] stands clearly behind [param of] (790 amended (10)): its
## centre more than about 110 degrees round from where [param of] faces
## (clearly_behind_offset). Not World.is_behind, the rear half, which stays
## the player's (a bonus, the coordinator's).
static func clearly_behind(by: GridEntity, of: GridEntity) -> bool:
	return clearly_behind_offset(World.body_centre(by) - World.body_centre(of), of.facing)


## Whether [param offset] (a foe's centre less its target's) lies clearly
## behind a target facing [param facing]: normalised, so the rule is the
## same at any distance; no offset or no facing is never behind.
static func clearly_behind_offset(offset: Vector2, facing: Vector2i) -> bool:
	if offset.is_zero_approx() or facing == Vector2i.ZERO:
		return false
	return offset.normalized().dot(Vector2(facing).normalized()) < CLEARLY_BEHIND_DOT


## FLANK: beside its target's front (where it faces, or either side of it).
func _in_front() -> bool:
	return (World.body_centre(self) - World.body_centre(target)).normalized().dot(Vector2(target.facing).normalized()) > 0.5


## Whether it can strike [param other] from where it stands (decision 699,
## enemy-ai's side): beside it on the grid, as ever; by the bodies'
## reach (World.in_reach) where a free body is in it.
func _in_strike_reach(other: GridEntity) -> bool:
	if World.free_body(other) or World.free_body(self):
		return World.in_reach(self, other)
	return World.can_melee(tile, other.tile)


## The cells it could strike its free target from (World.strike_cells_at,
## decision 699) where it will meet it (_lead_centre), worked out again only
## when that has moved STRIKE_REPLAN cells since, or its target or its own
## cell changed.
func _strike_cells() -> Array[Vector2i]:
	var centre := _lead_centre()
	if _strike_plan.get("target") != target or _strike_plan.get("from") != tile 			or (_strike_plan["centre"] as Vector2).distance_to(centre) > STRIKE_REPLAN:
		_strike_plan = {"target": target, "from": tile, "centre": centre, "cells": World.strike_cells_at(self, centre, target)}
	return _strike_plan["cells"]


## Where to meet its moving free target (lead-the-target): its centre run
## on (_run_on) to the first point it can itself be in reach of by then at
## its own pace, a diagonal its 1.5; LEAD_MAX_TICKS on at most. A target
## standing still: where it stands.
func _lead_centre() -> Vector2:
	var reach := World.reach_limit(self) - 0.5  # From a cell's middle: a little short of the limit.
	var path := _run_on(LEAD_MAX_TICKS)
	for k in range(1, path.size()):
		var off := (path[k] - Vector2(tile)).abs()
		var cells := maxf(0.0, maxf(off.x, off.y) - reach)
		var slant := minf(cells, minf(off.x, off.y))
		if (cells - slant + 1.5 * slant) * move_ticks <= k:
			return path[k]
	return path[-1]


## Its free target's centre now and on each of the next [param ticks] ticks
## (lead-the-target): run on along its way, turning as it has been turning
## (a circle stays a circle), stopping short of a wall; no farther ahead
## than LEAD_STEADY_FACTOR times the ticks it has held that course. A target standing
## still, or on the grid: only where it is.
func _run_on(ticks: int) -> PackedVector2Array:
	var at := World.body_centre(target)
	var out := PackedVector2Array([at])
	var way := target.free_way if World.free_body(target) else Vector2.ZERO
	var since := World.tick - _lead_tick
	if since > 0:
		var turn := 0.0
		if since <= 4 and _lead_way.length() > 0.01 and way.length() > 0.01:
			turn = _lead_way.angle_to(way) / since
		# A course held (straight, or turning as it was) is led far; a jink
		# starts it again, so a zig-zag is not chased side to side.
		_lead_steady = _lead_steady + since if absf(turn - _lead_turn) <= LEAD_TURN_MAX and absf(turn) <= LEAD_TURN_MAX else 0
		_lead_turn = clampf(turn, -LEAD_TURN_MAX, LEAD_TURN_MAX)
		_lead_way = way
		_lead_tick = World.tick
	if way.length() < 0.05:
		return out
	for k in mini(ticks, LEAD_STEADY_FACTOR * _lead_steady):
		way = way.rotated(_lead_turn)
		if not World.is_walkable(Vector2i((at + way).round())):
			break
		at += way
		out.append(at)
	return out


## HEAVY against a moving free body (lead-the-target): whether, wound up
## now, its blow would land on where the body will be as it falls, from
## where it stands (World.strike_cells_at holds its cell).
func _meets_in_stride() -> bool:
	if tactic != Tactic.HEAVY or not World.free_body(target) or target.free_way.length() < 0.05:
		return false
	var path := _run_on(windup_ticks)
	return path.size() > windup_ticks and World.strike_cells_at(self, path[-1], target).has(tile)


## Where its arrow is aimed (699): from where its shots start to its
## target's body (a free body's centre; on the grid, its cell's).
func _aim_angle() -> float:
	return (World.body_centre(target) - World.shot_origin(self)).angle()


## [param need] others already at its target, or its target under half its hp.
func _target_beset(need := 1) -> bool:
	if target.max_hp > 0 and target.hp * 2 < target.max_hp:
		return true
	var at := 0
	if World.free_body(target):
		# A free body's: those in reach of its centre (699), the cells round it.
		var middle := Vector2i(World.body_centre(target).round())
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var other := World.get_entity_at(middle + Vector2i(dx, dy))
				if other != null and other != self and other is Monster and World.in_reach(other, target):
					at += 1
					if at >= need:
						return true
		return false
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
	if target == null and raid == "" and nearest_sought > sight_range + LOOK_MARGIN_TILES + (alert_sight if senses.alerted else 0) \
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
		if d > sight_range * times + (alert_sight if senses.alerted else 0) or entity.protected or World.is_downed(entity):
			continue  # Too far, in its spawn grace, or downed (no finishing blows: decision 544).
		if keeps_room and not _room.has_point(at) and not _answering(entity):
			continue  # Outside the room it keeps (unless it struck it just now).
		if holds_post >= 0 and home != NO_TILE and World.distance(at, home) > holds_post + 1 and not _answering(entity):
			continue  # Beyond a chief's post and a blow's reach: none of his.
		if lurks and lurking() and not _answering(entity):
			continue  # A lurker waits for its side to engage.
		if entity is Player or (entity is Companion and entity.keeper != null):
			if not _given_up.is_empty() and _letting_be(entity):
				continue
			if in_truce():
				continue  # Its camp's truce holds (799): nobody has struck the band.
			# Its target it follows, cone or not (it turns as it goes); one that struck it, felt.
			if _answering(entity) or senses.sees(entity, d, entity != target, times) \
					and _noticed(entity, d, sight_range * times + (alert_sight if senses.alerted else 0)):
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
			if waiting(entity):
				continue
			var d := World.distance(tile, entity.tile)
			# One that struck it (a guard, 784) it answers whatever its cone.
			if d <= sight_range and d < nearest_distance and (_answering(entity) or senses.sees(entity, d, entity != target)):
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
			if waiting(entity):
				continue
			var d := World.distance(tile, entity.tile)
			if d <= sight_range and d < nearest_distance and not entity.protected \
					and (not keeps_room or _room.has_point(entity.tile) or _answering(entity)) \
					and (_answering(entity) or senses.sees(entity, d, entity != target)):
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
	elif _glimpsed != NO_TILE and alert == Alert.IDLE and not lurking():
		_follow(_glimpsed, Alert.SUSPICIOUS, SUSPICIOUS_TICKS,
				false, "glimpses something at %s (%d cells)" % [_glimpsed, World.distance(tile, _glimpsed)])
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
	if lurks and (kind == &"call" or kind == &"fight") and source is Monster and source != self and _same_side(source):
		_rouse()  # Its side engaged near it: out of the dark.
	if lurking():
		return  # Unroused, a lurker goes after no noise: it stays in the dark.
	if in_truce():
		return  # Its camp's truce holds (799): it minds no din till the band is struck.
	if kind == &"call" and source is Monster and _same_side(source):
		# Its side calling for help: after whom they fight.
		var caller := source as Monster
		_listening_until = -1
		_follow(caller.target.tile if is_instance_valid(caller.target) else caller.tile, Alert.HUNTING, HUNT_TICKS,
				false, "hears a call from %s at %s (%d cells)" % [caller.name, caller.tile, World.distance(tile, caller.tile)])
		return
	if at == tile and kind == &"fight" and is_instance_valid(source) and source != self:
		var striker := source as GridEntity
		_given_up.erase(striker.get_instance_id())
		_quarry = striker
		at = striker.tile
	if urgent:
		_listening_until = -1
	_follow(at, Alert.HUNTING if urgent else Alert.SUSPICIOUS, HUNT_TICKS if urgent else SUSPICIOUS_TICKS,
			false, "hears %s at %s (%d cells)" % [str(kind).replace("_", " "), at, World.distance(tile, at)])


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
## [param guess] is no reason to open a door to it. [param why], what
## rouses it from idle, goes to the server log (_alert_note).
func _follow(lead: Vector2i, level: Alert, ticks: int, guess := false, why := "") -> void:
	if alert == Alert.IDLE:
		_post = tile
		if not why.is_empty():
			_alert_note(why)
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


## Why it leaves idle (806 amended (19)): one server line as it does, so a
## move toward someone always says why (playtest's joined crypt walk,
## 11-12: robbers came with no line). A band's rally has its own [band]
## line, and nothing prints while it stays roused. Nobody's name but a
## monster's: the box's journal is read by grep (alert_who).
var alert_why := ""
var alert_notes := 0
func _alert_note(why: String) -> void:
	alert_why = why
	alert_notes += 1
	print("[alert] %s %s" % [name, why])


## Who it saw, as the log may name it: a monster by its name; a player, a
## companion, a resident by trade, never by name or id.
static func alert_who(e: GridEntity) -> String:
	if e is Monster:
		return str(e.name)
	if e is Companion:
		return "a companion"
	if e is Resident:
		return "a %s" % (e as Resident).trade if not (e as Resident).trade.is_empty() else "a resident"
	if e is Player:
		return "a player"
	return "something"


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
		return not _room.has_point(tile) and not (is_instance_valid(target) and _answering(target) and _room.grow(ANSWER_REACH).has_point(tile))
	if holds_post >= 0 and home != NO_TILE:
		return World.distance(tile, home) > holds_post  # A chief at his post: from it, not from where he took up the chase.
	return _post != NO_TILE and World.distance(tile, _post) > leash


## Lets [param who] be for GIVE_UP_TICKS (null: nobody in particular), and
## goes back to where it idles.
func _give_up(who: GridEntity) -> void:
	if who != null and is_instance_valid(who):
		_given_up[who.get_instance_id()] = World.tick + GIVE_UP_TICKS
	_calm()
	_returning = idle != Idle.NONE


## The standoff (806 amended (8), STANDOFF_TICKS), asked where its fight
## step stalls (holding back, no way in): true when, stalled that long since
## it last stepped or struck, it watches instead (_watch). A guard in reach
## with a way in presses in once (false: on with the fight).
func _standing_off() -> bool:
	var mark := [tile, next_attack_tick, raised]
	if mark != _standoff_mark:
		_standoff_mark = mark
		_standoff_from = World.tick
		return false
	if World.tick - _standoff_from < STANDOFF_TICKS:
		return false
	_standoff_from = World.tick
	if not _pressing and idle == Idle.GUARD and home != NO_TILE \
			and World.distance(target.tile, home) <= GUARD_REACH \
			and not World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now()).is_empty():
		_pressing = true
		return false
	_watch(target)
	return true


## Lets [param who] be WATCH_TICKS (the standoff's way out, 806 amended (8)):
## back to its post, roused by a blow or by them within WATCH_ROUSE of it.
func _watch(who: GridEntity) -> void:
	_watched = who.get_instance_id()
	_watched_from = home if idle == Idle.GUARD and home != NO_TILE else tile
	_give_up(who)
	_given_up[_watched] = World.tick + WATCH_TICKS
	_pressing = false
	target = null
	slot = NO_TILE
	_drop_windup()


## The one it watches from its post (_watch), while let be and in its sight
## range with a clear line; else null.
func _watched_one() -> GridEntity:
	if _watched < 0 or _given_up.get(_watched, -1) < World.tick:
		return null
	var who := instance_from_id(_watched) as GridEntity
	if who == null or not is_instance_valid(who) or who.zone != zone \
			or World.distance(tile, who.tile) > sight_range or not World.has_clear_line(tile, who.tile):
		return null
	return who


## Whether it lets [param entity] be (given up on it, a while yet, and it is
## not back near where it took up the chase; one it watches, not near its
## post, _watch).
func _letting_be(entity: GridEntity) -> bool:
	var id := entity.get_instance_id()
	var until: int = _given_up.get(id, -1)
	if until < World.tick:
		_given_up.erase(id)
		if id == _watched:
			_watched = -1
		return false
	if id == _watched:
		return World.distance(entity.tile, _watched_from) > WATCH_ROUSE
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


## The fight's feel for [param kind] (673 step 2): FIGHT_DEFAULTS, under
## KINDS_PATH's "fight" block (fight_block, which the tuning panel sets),
## under the kind's row's "fight".
static func fight_for(kind: String) -> Dictionary:
	var out := FIGHT_DEFAULTS.duplicate(true)
	_merge_fight(out, fight_block())
	var row: Dictionary = kinds().get(kind, {})
	_merge_fight(out, row.get("fight", {}))
	return out


## KINDS_PATH's "fight" block as read (or set_fight_block's), {} for none.
static func fight_block() -> Dictionary:
	if _fight_block == null:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KINDS_PATH)) if FileAccess.file_exists(KINDS_PATH) else null
		_fight_block = (parsed["fight"] as Dictionary).duplicate(true) if parsed is Dictionary and parsed.get("fight") is Dictionary else {}
	return _fight_block


## The block set in place (the tuning panel's loader; null: read the file
## again). Spawns from now on take it.
static func set_fight_block(block: Variant) -> void:
	_fight_block = (block as Dictionary).duplicate(true) if block is Dictionary else null


## The tuning panel's source "monsters" (673 step 2; Tuning.register_source,
## Main's): [param path] "monsters.fight.<name>" (flee_below's as
## "monsters.fight.flee_below.<temper>") the block's value now, or
## "monsters.<kind>.fight.<name>" a kind's own (null where it has none);
## null for an unknown one.
static func tuning_value(path: String) -> Variant:
	var parts := path.split(".")
	if parts.size() < 3 or parts[0] != "monsters":
		return null
	var given: Dictionary
	var at := 2
	if parts[1] == "fight":
		given = fight_for("")
	elif parts[2] == "fight" and kinds().has(parts[1]) and parts.size() >= 4:
		given = kinds()[parts[1]].get("fight", {})
		at = 3
	else:
		return null
	var name := parts[at]
	if not FIGHT_DEFAULTS.has(name):
		return null
	if name == "flee_below":
		var temper_name := parts[at + 1] if parts.size() > at + 1 else ""
		return given.get(name, {}).get(temper_name) if given.get(name) is Dictionary else null
	return given.get(name)


## Sets [param path] (tuning_value's) to [param value]: the block's key
## merged and set (set_fight_block), or a kind's own in its row; false for
## an unknown one. New spawns take it.
static func set_tuning_value(path: String, value: Variant) -> bool:
	var parts := path.split(".")
	var at := 2 if parts.size() >= 3 and parts[1] == "fight" else 3
	if parts.size() <= at or parts[0] != "monsters" or at == 3 and (parts[2] != "fight" or not kinds().has(parts[1])):
		return false
	var name := parts[at]
	if not FIGHT_DEFAULTS.has(name) or not (value is int or value is float):
		return false
	var block: Dictionary = (fight_block() if at == 2 else kinds()[parts[1]].get("fight", {}) as Dictionary).duplicate(true)
	if name == "flee_below":
		if parts.size() <= at + 1 or not TEMPER_NAMES.has(parts[at + 1]):
			return false
		var by_temper: Dictionary = block.get(name, {}) if block.get(name) is Dictionary else {}
		by_temper[parts[at + 1]] = float(value)
		block[name] = by_temper
	else:
		block[name] = int(value) if name in FIGHT_INTS else float(value)
	if at == 2:
		set_fight_block(block)
	else:
		kinds()[parts[1]]["fight"] = block
	return true


## The panel's rows for the block (673 step 2): each value, its range,
## enemy-ai's, taken by new spawns.
static func tuning_fields() -> Array:
	var out: Array = []
	for name: String in FIGHT_DEFAULTS:
		var span: Array = FIGHT_SPANS[name]
		if name == "flee_below":
			for temper_name: String in TEMPER_NAMES:
				out.append({"path": "monsters.fight.flee_below." + temper_name, "group": "Monsters", "min": span[0], "max": span[1], "owner": "enemy-ai", "takes": "spawn"})
		else:
			out.append({"path": "monsters.fight." + name, "group": "Monsters", "min": span[0], "max": span[1], "owner": "enemy-ai", "takes": "spawn"})
	return out


static func _merge_fight(into: Dictionary, given: Variant) -> void:
	if not given is Dictionary:
		return
	for key: String in given:
		if not FIGHT_DEFAULTS.has(key):
			push_warning("[monsters] fight: %s is none of %s" % [key, FIGHT_DEFAULTS.keys()])
		elif key == "flee_below":
			if given[key] is Dictionary:
				for temper_name: String in given[key]:
					if TEMPER_NAMES.has(temper_name):
						into[key][temper_name] = float(given[key][temper_name])
		else:
			into[key] = int(given[key]) if key in FIGHT_INTS else float(given[key])


## Sets its fight's vars from [param rules] (fight_for).
func _apply_fight(rules: Dictionary) -> void:
	for key: String in rules:
		if key == "flee_below":
			for temper_name: String in rules[key]:
				flee_below[TEMPER_NAMES[temper_name]] = float(rules[key][temper_name])
		else:
			set(key, rules[key])


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
		if kind == "fight":
			continue  # Not a kind: the fight's feel (fight_block, 673 step 2).
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
			"picks_up": bool(row.get("picks_up", false)), "bound": bool(row.get("bound", false)), "art": str(row.get("art", "")),
			"lifts": row.get("lifts"),
			"label": str(row.get("label", "")), "plural": str(row.get("plural", "")), "fearless": bool(row.get("fearless", false)),
			"never_lies": bool(row.get("never_lies", false)), "band_fights": bool(row.get("band_fights", false)), "holds_off": bool(row.get("holds_off", false)), "boss": bool(row.get("boss", false)),
			"felled_by_surprise": bool(row.get("felled_by_surprise", false)),
			"fight": (row["fight"] as Dictionary).duplicate(true) if row.get("fight") is Dictionary else {},
			"pack": (row["pack"] as Dictionary).duplicate(true) if row.get("pack") is Dictionary else null,  # 824.
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
			"aim_hold_max": maxi(0, int(row.get("aim_hold_max", 0))),
			# A kind's own moves' numbers (GreatBear's swipe, slam and charge; 780 amended (2); a robber's lunge, 790 amended (4)).
			"moves": (row["moves"] as Dictionary).duplicate(true) if row.get("moves") is Dictionary else {},
			# Its sight, hearing and notice (decision 784): Monster._take_senses.
			"senses": (row["senses"] as Dictionary).duplicate() if row.get("senses") is Dictionary else {},
			# Its party (780 amended (8)): GreatBear's hp and combat's flank guard by who joins its fight.
			"party": (row["party"] as Dictionary).duplicate() if row.get("party") is Dictionary else {},
			# An apex creature (780 amended (4)): companions keep off it (is_apex).
			"apex": bool(row.get("apex", false)),
			# Its lair and its land (Apex, 780 amended (13)).
			"lair": (row["lair"] as Dictionary).duplicate(true) if row.get("lair") is Dictionary else {},
			# Its escort (Apex, 780 amended (15)): the old grey's pack.
			"escort": (row["escort"] as Dictionary).duplicate(true) if row.get("escort") is Dictionary else {}}
	return out


## Whether [param kind] is an apex creature, its row's "apex" (decision 780
## amended (4); the great bear): companions warn of it and keep their distance.
static func is_apex(kind: String) -> bool:
	return bool(kinds().get(kind, {}).get("apex", false))


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


## Whether it is a named foe [param by] (a player) has struck (806 amended
## (12), the coordinator's ruling: "a named foe who has been struck by a
## player fights that player, alone or not; a temper roll may shape how he
## fights, never whether"): its roll's holding back is gone for them. Dread
## (_dreads_target, 420's bane) still holds it back.
func _struck_named(by: GridEntity) -> bool:
	return named_id != "" and is_instance_valid(by) and _struck_by_players.has(by.get_instance_id())


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
## for the cautious at a dread holder, or a coward against two or more near
## that its band (band_min strong) no longer outnumbers, or alone against
## them with fewer, a dread holder counted as two).
func _should_flee() -> bool:
	if fearless:
		return false
	var dreaded := _dreads_target()
	var below := float(flee_below.get(temper, FLEE_BELOW[temper]))
	if dreaded and temper == Temper.CAUTIOUS:
		below = maxf(below, dread_flee_below)
	if max_hp > 0 and hp < max_hp * below:
		return true
	if temper != Temper.COWARDLY:
		return false
	var odds := _band_odds()
	if odds.y < 2:
		return false
	if odds.x >= band_min:
		return odds.x <= odds.y
	# Fewer than a band: alone within COWARD_ODDS_TILES, as before 698.
	for dy in range(-COWARD_ODDS_TILES, COWARD_ODDS_TILES + 1):
		for dx in range(-COWARD_ODDS_TILES, COWARD_ODDS_TILES + 1):
			var other := World.get_entity_at(tile + Vector2i(dx, dy))
			if other != null and other != self and other is Monster:
				return false  # Not alone.
	return true


## Its band against its foes (decision 698; Jeff on v0.1.186, the barrow: "the
## grave robbers tend to scatter upon us entering the room not putting up a
## fight even though theres 4 of them"): x, itself and those of its side
## within BAND_TILES not running; y, the players and companions as near, its
## dreaded target counted as two.
func _band_odds() -> Vector2i:
	var foes := 0
	var dreaded := _dreads_target()
	for entity in World.sought():
		if World.distance(tile, entity.tile) <= BAND_TILES:
			foes += 2 if dreaded and entity == target else 1
	var band := 1
	if foes > 0:
		# The cells within BAND_TILES (698 amended): a monster holds its cell,
		# so this counts the same as going through every monster, at a few
		# hundred looks in place of the zone's thousands.
		for dy in range(-BAND_TILES, BAND_TILES + 1):
			for dx in range(-BAND_TILES, BAND_TILES + 1):
				var other := World.get_entity_at(tile + Vector2i(dx, dy)) as Monster
				if other != null and other != self and other.spawned and other.alert != Alert.FLEEING \
						and other.tile == tile + Vector2i(dx, dy) and _same_side(other):
					band += 1
	return Vector2i(band, foes)


## Whether its band, band_min strong or more, outnumbers the foes about it
## (_band_odds): it holds. No
## foe near, nothing to hold against; an animal's herd runs together.
func _band_holds() -> bool:
	if self is Animal:
		return false
	var odds := _band_odds()
	return odds.y > 0 and odds.x >= band_min and odds.x > odds.y


## It breaks: away from [param threat] for FLEE_TICKS (more while the threat
## is near); one that breaks of itself ([param routs]: hurt, outnumbered,
## not routed) is a rout to those of its side who hear it, who may break
## too. A routed one does not rout others again, or a rout would echo.
func _flee(threat: Vector2i, routs := true) -> void:
	if alert == Alert.IDLE:
		_post = tile
	alert = Alert.FLEEING
	_flee_from = threat
	_rally = null
	_call_to = NO_TILE
	_alert_until = World.tick + flee_ticks
	target = null
	slot = NO_TILE
	_drop_windup()
	_bash_key = NO_DOOR
	_lead = NO_TILE
	move_ticks = _pace
	_way_out = NO_TILE
	if not World.outdoor and not bound and _wary and not self is Animal and not at_home():
		_way_out = _pick_way_out(_foe_cell(threat))
	if routs:
		_cry(&"rout", Senses.NOISE_ROUT)


## Whether its level is its home (702 amended; playtest's Hollowfell tour:
## the Blood Rot fled out the mine's mouth and left it empty): its kind is
## in the level's "home_kinds". Routed there it never takes a way out; it
## flees deeper, to its post or away, and rallies as anywhere.
func at_home() -> bool:
	var given: Variant = _zone_config().get("home_kinds", [])
	return given is Array and str(spawn_spec.get("kind", "")) in given


## FLEEING: a step away from what it runs from, toward its post if that is
## away from it; recovering (SUSPICIOUS, then back) once nobody has been
## near for FLEE_TICKS.
func _flee_tick() -> void:
	if _way_out != NO_TILE:
		_escape_tick()
		return
	for entity in World.sought():
		if _rally == null and World.distance(tile, entity.tile) <= flee_near_tiles:
			_alert_until = World.tick + flee_ticks
			_flee_from = entity.tile
			break
	if World.tick >= _alert_until and _rally != null:
		# Its band called (806 amended (9)): back at the one it ran from.
		var back := _rally
		_rally = null
		_call_to = NO_TILE
		alert = Alert.SUSPICIOUS
		if is_instance_valid(back) and back.spawned:
			_follow(back.tile, Alert.SUSPICIOUS, SUSPICIOUS_TICKS)
		return
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


## Routed indoors (decision 702): on for its way out till it is beside it,
## and gone from the level by it, as one who got away (not dead: no drops,
## the band's purse kept, its spawn back after its time like any). A way
## barred since: another, or the plain flee.
func _escape_tick() -> void:
	if World.distance(tile, _way_out) <= 1 and World.can_melee(tile, _way_out):
		print("[monster] %s got away by %s, step %d" % [name, _way_out, World.tick])
		if not named_id.is_empty():
			for entity in World.sought():
				if entity is Player and World.distance(tile, entity.tile) <= sight_range:
					World.named_note(self, "fled_from", entity)  # Decision 716: whom it fled.
		World.despawn(self)
		return
	if World.is_stunned(self) or World.tick < next_move_tick:
		return
	if _idle_step(_way_out, ESCAPE_SEARCH_TILES):
		return
	_way_out = _pick_way_out(_foe_cell(_flee_from))
	if _way_out == NO_TILE:
		_alert_until = World.tick + flee_ticks  # No way out: it flees as ever.
	next_move_tick = World.tick + CHASE_RETRY_TICKS


## The cell of the nearest foe it can see, else [param fallback] (a rout
## heard is where the one who broke was, not the foe).
func _foe_cell(fallback: Vector2i) -> Vector2i:
	var best := fallback
	var best_d := INF
	for entity in World.sought():
		var d := float(World.distance(tile, entity.tile))
		if d <= sight_range and d < best_d:
			best = entity.tile
			best_d = d
	return best


## The nearest way out by its path (World.ways_out) that does not take it
## past [param foe]: no cell of it within ESCAPE_CLEAR_TILES of the foe and
## nearer it than where it stands. NO_TILE when there is none.
func _pick_way_out(foe: Vector2i) -> Vector2i:
	var best := NO_TILE
	var best_size := INF
	var start := World.distance(tile, foe)
	for at in World.ways_out():
		var path: Array[Vector2i] = []  # Typed: a bare [] in a ternary is untyped and fails the assign.
		if World.distance(tile, at) > 1:
			path = World.find_path(tile, at, false, null, ESCAPE_SEARCH_TILES, false, {}, opens_doors_now())
		if path.is_empty() and World.distance(tile, at) > 1 or path.size() >= best_size:
			continue
		var past := false
		for cell in path:
			var d := World.distance(cell, foe)
			if d <= ESCAPE_CLEAR_TILES and d < start:
				past = true
				break
		if not past:
			best = at
			best_size = path.size()
	return best


## Where it runs to: its post if that is farther from the threat than it
## is, else the farthest walkable tile of a few straight away from it.
func _flee_goal() -> Vector2i:
	if _call_to != NO_TILE and _call_to != tile \
			and World.distance(_call_to, _flee_from) >= World.distance(tile, _flee_from):
		return _call_to  # Running to call its band (806 amended (9)): to its mate.
	if _post != NO_TILE and _post != tile \
			and World.distance(_post, _flee_from) > World.distance(tile, _flee_from) + 1:
		return _post
	var away := Vector2i(signi(tile.x - _flee_from.x), signi(tile.y - _flee_from.y))
	if away == Vector2i.ZERO:
		away = -facing
	for n in range(flee_tiles, 0, -1):
		for way: Vector2i in [away, Vector2i(away.x, 0), Vector2i(0, away.y)]:
			var at := tile + way * n
			if way != Vector2i.ZERO and World.is_walkable(at) and World.is_free(at) and not World.is_link_cell(at):
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
## a cautious one under ROUT_HURT of its hp, unless its band still
## outnumbers the foes (decision 698).
func _heard_rout() -> bool:
	if senses.last_tick <= _rout_tick:
		return false
	var since := _rout_tick
	_rout_tick = int(senses.heard.back()["tick"])
	if temper == Temper.BOLD or band_fights:
		return false  # A band fighter runs only to call (806 amended (9)).
	for noise: Dictionary in senses.heard:
		if int(noise["tick"]) <= since or noise["kind"] != &"rout":
			continue
		var source: Variant = noise["source"]
		if source == self or not is_instance_valid(source) or not _same_side(source):
			continue
		if temper == Temper.COWARDLY or (max_hp > 0 and hp < max_hp * rout_hurt):
			if _band_holds():
				return false  # Its band still outnumbers them: it stands.
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


## Whether it has a grave: the cell it was laid on, its home (631 amended,
## Jeff: "skeletons still spawning in niches and lying down on ground,
## clipping through walls"; dungeon lays it on open floor). With none it
## wanders where it stands.
func _settle_grave() -> bool:
	if grave != NO_TILE:
		return true
	grave = home
	if grave == NO_TILE:
		idle = Idle.WANDER
		return false
	return true


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
	if not other.holds_cell:
		return false  # Gone (573 amended (4)): nothing there to fight.
	if other is Player or (other is Companion and (other as Companion).keeper != null):
		return true
	if other is Resident:
		# A camp trader (799, npc's Resident.camp_trader) is nobody's foe.
		return "town" in foes and not waiting(other) and not camp_trader(other)
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
	if keeps_room and not _room.has_point(entity.tile) and not _answering(entity):
		return false
	if entity is Player or (entity is Companion and (entity as Companion).keeper != null):
		return not in_truce() and (_given_up.is_empty() or not _letting_be(entity))
	if raid != "" or "town" in foes:
		if entity in World.townsfolk() and not camp_trader(entity):
			return true
	return _may_fight(entity)


## Whether either of it and [param entity] is out of any fight: gone, dead,
## lying in its grave, downed or in its spawn grace (threatens); nor a
## sought one waiting to be found (waiting).
func _may_threaten(entity: GridEntity) -> bool:
	return spawned and hp > 0 and not laid and entity != null and is_instance_valid(entity) and entity != self \
			and entity.spawned and entity.hp > 0 and not entity.protected and not World.is_downed(entity) and not waiting(entity)


## Whether [param entity] is a camp trader (decision 799, npc's
## Resident.camp_trader: the trader's place key, "" for townsfolk): no
## monster's foe, whoever holds the camp.
static func camp_trader(entity: GridEntity) -> bool:
	if not entity is Resident:
		return false
	var key: Variant = entity.get("camp_trader")
	return key is String and not (key as String).is_empty()


## The truce camp whose band it is (799): a camp place of its zone with
## "truce", held by its side, its home within the radius; "" for none.
## Looked up once, after it is spawned and placed.
func truce_camp() -> String:
	if _truce_camp != "?":
		return _truce_camp
	if not spawned or home == NO_TILE or World.holdings == null or World.zone == null:
		return ""
	_truce_camp = ""
	if self is Animal:
		return _truce_camp
	var factions := World.holdings.factions
	var side := factions.of_kind(World.kind_of(self))
	if side == Factions.NOBODY:
		return _truce_camp
	for id in World.holdings.places_in(World.zone.name):
		var place := World.holdings.place(id)
		if place.get("kind") != "camp" or not place.get("truce", false):
			continue
		var off: Vector2i = home - place["cell"]
		var radius := int(place["radius"])
		if off.x * off.x + off.y * off.y <= radius * radius and factions.same_side(side, World.holdings.holder(id)):
			_truce_camp = id
			break
	return _truce_camp


## Whether its camp's truce holds (799): it is of a truce camp's band, its
## side still holds the camp, and nobody has struck the band since the camp
## last changed hands.
func in_truce() -> bool:
	var id := truce_camp()
	if id.is_empty():
		return false
	var factions := World.holdings.factions
	if not factions.same_side(factions.of_kind(World.kind_of(self)), World.holdings.holder(id)):
		return false
	return not truce_broken.has(id) or World.holdings.since(id) > truce_broken[id]


## A player or their companion struck one of [param id]'s band (799): the
## whole band fights, till the camp falls and is retaken.
static func break_truce(id: String) -> void:
	if id.is_empty() or World.holdings == null:
		return
	if not truce_broken.has(id) or World.holdings.since(id) > truce_broken[id]:
		print("[truce] %s: struck, the band turns" % id)
	truce_broken[id] = World.holdings.now()


## Whether [param entity] is a sought newcomer waiting to be found (613,
## enemy-ai's side; npc's meta "sought_waiting", set from their body's spawn
## till the escort starts): no monster or beast minds them, holder or not.
static func waiting(entity: GridEntity) -> bool:
	return entity.has_meta("sought_waiting")


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


## Whether it answers [param entity]: it struck it within ANSWER_TICKS, and
## stands within ANSWER_REACH of its room (a room keeper's) or of it.
func _answering(entity: GridEntity) -> bool:
	if entity == null or entity != struck_by or not is_instance_valid(entity) or World.tick - struck_tick > ANSWER_TICKS:
		return false
	if keeps_room and _room.has_area():
		return _room.grow(ANSWER_REACH).has_point(entity.tile)
	return World.distance(tile, entity.tile) <= ANSWER_REACH + 1


## [param by] struck it (World.damage): answered for ANSWER_TICKS, and no
## longer let be.
func note_struck(by: GridEntity) -> void:
	# A guard's blow is answered too (784; npc's guards who fight, 771).
	if not is_instance_valid(by) or by == self or not (by is Player or by is Companion or by is Monster or by is Resident):
		return
	struck_by = by
	struck_tick = World.tick
	if by is Player:
		_struck_by_players[by.get_instance_id()] = true
	_given_up.erase(by.get_instance_id())
	_rouse()
	if (by is Player or by is Companion) and in_truce():
		break_truce(_truce_camp)


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


## At rest at its grave, or stilled (the draugr laid to rest, step 3): it
## stands still, turned its home's way, till rise, kept in its props so a
## restart finds it resting. Standing, not lying (631 amended): its
## down_until is left alone, so the views draw it at its idle, inside its
## cell, and it wakes with no getting up.
func lay_down() -> void:
	laid = true
	target = null
	_provoked = null
	alert = Alert.IDLE
	_drop_windup()
	_keep_prop("laid", true)
	if tile == grave or tile == home:
		World.face(self, home_facing)


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
	var watched := _watched_one()
	if watched != null:
		var way := Senses.way_toward(tile, watched.tile)
		if way != Vector2i.ZERO and facing != way:
			World.face(self, way)  # Watching the one it let be from its post (806 amended (8)).
		_glancing = true
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
		if at == tile or not World.is_walkable(at) or not World.is_free(at) or World.is_fire(at) or World.is_link_cell(at) or _shuns(at):
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


## Whether it keeps off [param at] when it wanders (Animal's: the din,
## decision 740). Never, for a monster.
func _shuns(_at: Vector2i) -> bool:
	return false


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
			if World.is_walkable(at) and not World.is_fire(at) and not World.is_link_cell(at) and at not in route \
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
				if World.distance(at, gather_point) != reach or not World.is_walkable(at) or World.is_fire(at) or World.is_link_cell(at):
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
		if to == _idle_failed_to and World.tick < _idle_retry_tick:
			return false  # No way there a moment ago: no search again yet.
		_idle_path = World.find_path(tile, to, false, null, max_tiles, false, {}, opens_doors_now())
		_idle_path_to = to
		if _idle_path.is_empty():
			_idle_failed_to = to
			_idle_retry_tick = World.tick + IDLE_PLAN_RETRY_TICKS
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
	if practice_still:
		if never_dies and hp < max_hp and World.tick - hurt_tick >= Tuning.DUMMY_REFILL_TICKS:
			hp = max_hp
		return
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
## Its band's fight near it (RALLY_WALK): idle or wary, every RALLY_EVERY
## ticks, it asks the nearest mate fighting within its walk to be sent for.
func _rally_look() -> void:
	if not rallies or World.tick < _rally_look_at or alert == Alert.FLEEING or alert == Alert.HUNTING or in_truce() or lurking():
		return
	_rally_look_at = World.tick + RALLY_EVERY
	_rally_for = 0
	var nearest: Monster = null
	for each in World.monsters():
		var mate := each as Monster
		if mate == null or mate == self or not mate._rallies() or not mate.spawned or mate.hp <= 0 or mate.alert != Alert.FIGHTING \
				or not is_instance_valid(mate.target) or World.distance(tile, mate.tile) > RALLY_WALK or not _same_side(mate):
			continue
		if not knows_of_fight(tile, mate.tile):
			continue
		if nearest == null or World.distance(tile, mate.tile) < World.distance(tile, nearest.tile):
			nearest = mate
	if nearest == null or nearest._rally_asked.has(get_instance_id()):
		return
	# The walk may open doors, as it would to answer (806 amended (17)): hearing
	# decides whether it knows; a door it can't open (opens_doors) stops it.
	var way := World.find_path(tile, nearest.tile, true, self, RALLY_WALK * 8, false, {}, opens_doors)
	if way.is_empty() or way.size() > RALLY_WALK:
		return
	var fight := _rally_party(nearest.target)
	if int(_rally_fight_next.get(fight, -1)) < World.tick:
		_rally_fight_next[fight] = World.tick + RALLY_GAP
	nearest._rally_asked[get_instance_id()] = [self, way.size()]


## Whether one at [param from] would know of a fight at [param at] (806
## amended (17)): it sees it, in its line of sight (a wall or a shut door
## stops it) within RALLY_SEE, or hears it within RALLY_HEAR through
## anything (World.distance). Static, so a layout check (870's first_alone)
## can ask the same question on a laid level.
static func knows_of_fight(from: Vector2i, at: Vector2i) -> bool:
	var apart := World.distance(from, at)
	return apart <= RALLY_HEAR or apart <= RALLY_SEE and World.has_line_of_sight(from, at)


## One of the rally's (RALLY_WALK): a band fighter, or a boss of theirs
## who makes a stand (Brand among his robbers, the coordinator's ruling).
func _rallies() -> bool:
	return band_fights or stands


## A fight's key for the rally: a companion's fight is her player's.
static func _rally_party(foe: GridEntity) -> int:
	if foe is Companion and is_instance_valid((foe as Companion).keeper):
		return (foe as Companion).keeper.get_instance_id()
	return foe.get_instance_id() if is_instance_valid(foe) else 0


## Fighting, it sends for the next of its band who asked (_rally_look):
## nearest first, RALLY_GAP apart, never while RALLY_MOST fight its foe.
func _rally_send() -> void:
	var fight := _rally_party(target)
	if World.tick < int(_rally_fight_next.get(fight, -1)):
		return
	var fighting := 0
	for each in World.monsters():
		var mate := each as Monster
		if mate == null or not mate._rallies() or not mate.spawned or mate.hp <= 0:
			continue
		if mate.alert == Alert.FIGHTING and is_instance_valid(mate.target) and _rally_party(mate.target) == fight or mate.alert == Alert.HUNTING and mate._rally_for == fight:
			fighting += 1  # At it, or sent and on the way.
	if fighting >= RALLY_MOST:
		return
	var pick := -1
	var walk := 1 << 30
	for id: int in _rally_asked.keys():
		var asked: Monster = _rally_asked[id][0] as Monster if is_instance_valid(_rally_asked[id][0]) else null
		if asked == null or not asked.spawned or asked.hp <= 0 or asked.target != null or asked.alert == Alert.FIGHTING:
			_rally_asked.erase(id)
			continue
		if int(_rally_asked[id][1]) < walk:
			walk = int(_rally_asked[id][1])
			pick = id
	if pick < 0:
		return
	var sent: Monster = _rally_asked[pick][0]
	_rally_asked.erase(pick)
	_rally_fight_next[fight] = World.tick + RALLY_GAP
	sent._follow(target.tile, Alert.HUNTING, HUNT_TICKS)
	sent._rally_for = fight
	print("[band] %s comes to %s's fight (%d cells)" % [sent.name, name, walk])


## The band's share of a party (the coordinator's ruling): at least
## HOLD_SHARE_LEAST, and one more than its bodies (806 amended (18): RUN3 on
## gen 118 measured 3 on one body and on two, against 4 and 4 before; three
## or more bodies were not measured).
const HOLD_SHARE_LEAST := 3
const HOLD_SHARE_OVER_BODIES := 1
const HOLD_NEAR := 3
const HOLD_FAR := 4
const HOLD_SHIFT_TICKS := 30
## How long a place must stand open before a holder takes it: a mate who
## loses sight of her for a tick is no place open.
const HOLD_OPEN_TICKS := 2


## [param foe]'s party (_rally_party's): its player and the companions he
## keeps who are up, or the foe alone.
static func _party_bodies(foe: GridEntity) -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	if not is_instance_valid(foe):
		return out
	var keeper: GridEntity = (foe as Companion).keeper if foe is Companion and is_instance_valid((foe as Companion).keeper) else foe
	if keeper.spawned:
		out.append(keeper)
	for entity in World.sought():
		if entity is Companion and (entity as Companion).keeper == keeper and entity.spawned and entity.hp > 0:
			out.append(entity)
	if out.is_empty():
		out.append(foe)
	return out


## How many of its band a party of [param bodies] may have on it at once.
static func _hold_share(bodies: int) -> int:
	return maxi(HOLD_SHARE_LEAST, bodies + HOLD_SHARE_OVER_BODIES)


## Whether it holds off its target's party now (holds_off): the share on it
## already, and it the newest there (a standing boss never); one of the
## party struck it, or is in reach and facing it, and it fights.
func _holds_now() -> bool:
	if stands or not is_instance_valid(target):
		_holding = false
		return false
	var party := _rally_party(target)
	var bodies := _party_bodies(target)
	if is_instance_valid(struck_by) and World.tick - struck_tick <= ANSWER_TICKS and _rally_party(struck_by) == party:
		_holding = false
		return false  # She struck it: hers to fight.
	for body in bodies:
		if World.in_reach(body, self) and body.facing == Senses.way_toward(body.tile, tile):
			_holding = false
			return false  # She closed on it, facing it: it fights.
	if _joined_party != party:
		_joined_party = party
		_joined_tick = World.tick
	var at: Array[Monster] = []
	for each in World.monsters():
		var mate := each as Monster
		if mate == null or mate == self or not mate._rallies() or not mate.spawned or mate.hp <= 0 or mate._holding:
			continue
		if mate.alert != Alert.FIGHTING:
			continue
		if is_instance_valid(mate.target) and _rally_party(mate.target) == party or mate.target == null and mate._joined_party == party:
			at.append(mate)  # At her, or lost sight of her this tick and still at her fight.
	var share := _hold_share(bodies.size())
	if _holding:
		_hold_open = _hold_open + 1 if at.size() < share else 0
		if _hold_open >= HOLD_OPEN_TICKS:
			_holding = false  # A place open (a fall, a flight): in.
			_hold_open = 0
			_joined_tick = World.tick
		return _holding
	if at.size() < share:
		return false
	# Over the share with it: the newest steps back (a standing boss never).
	for mate in at:
		if not mate.stands and (mate._joined_tick > _joined_tick or mate._joined_tick == _joined_tick and mate.id > id):
			return false  # Another is newer: he steps back, not it.
	_holding = true
	_drop_windup()
	slot = NO_TILE
	return true


## Holding off (_holds_now): HOLD_NEAR to HOLD_FAR cells from its target, in
## sight of it and facing it; a cell along every HOLD_SHIFT_TICKS.
func _hold_off() -> void:
	if World.is_stunned(self) or World.tick < next_move_tick:
		World.face(self, Senses.way_toward(tile, target.tile))
		return
	var d := World.distance(tile, target.tile)
	var sees := World.has_line_of_sight(tile, target.tile)
	if d < HOLD_NEAR:
		_step_back()
	elif d > HOLD_FAR or not sees:
		var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES, false, {}, opens_doors_now())
		if not path.is_empty() and World.distance(path[0], target.tile) >= HOLD_NEAR:
			World.try_move(self, path[0] - tile)
	elif World.tick >= _hold_shift_at:
		_hold_shift_at = World.tick + HOLD_SHIFT_TICKS
		var start := (id + World.tick / HOLD_SHIFT_TICKS) % World.DIRECTIONS.size()
		for k in World.DIRECTIONS.size():
			var way: Vector2i = World.DIRECTIONS[(start + k) % World.DIRECTIONS.size()]
			var to := tile + way
			var dt := World.distance(to, target.tile)
			if dt < HOLD_NEAR or dt > HOLD_FAR or not World.is_free(to) or not World.has_line_of_sight(to, target.tile):
				continue
			if World.try_move(self, way):
				break
	World.face(self, Senses.way_toward(tile, target.tile))


## A stand's (stands): it never flees, nor breaks at a rout or a dread.
func _stand_fast() -> void:
	for t: int in flee_below:
		flee_below[t] = 0.0
	dread_flee_below = 0.0


## Its kind, as its row names it (the den rule's log lines).
func _kind() -> String:
	return str(spawn_spec.get("kind", ""))


## A line of its den-rule walk (Apex.to_den's "log"): a stand's, its name's.
func _log_move(move: String, how: String) -> void:
	print("[%s] %s %s at %s -> %s (%d/%d)" % [move, given_name if not given_name.is_empty() else _kind(), move, tile, how, hp, max_hp])


func _drop_windup() -> void:
	if not _windup.is_empty():
		_world_winding(_windup["direction"], 0)
	_windup = {}
	_end_ambush(false)


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
