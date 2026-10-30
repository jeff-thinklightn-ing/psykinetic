extends Node
## Authoritative grid simulation (autoload "World").
##
## Owns terrain and tile occupancy, runs the fixed 10 Hz tick, and is the only
## code allowed to move entities. Every mutation is gated behind
## Net.is_authority(), which is multiplayer.is_server() for anything that was
## not launched as a client. See docs/design.md.
##
## On a client nothing here simulates. World is then a read-only mirror: the
## tick arrives by RPC, entities arrive through MultiplayerSpawner /
## MultiplayerSynchronizer, and occupancy is rebuilt from their tiles. The
## mirror_* functions are the only writers and refuse to run on the server.
##
## Zones: the server holds every loaded map as a Zone (zones), and World
## works on one at a time (zone, switched by enter): terrain, doors,
## entities, occupancy, fields and the tick are the zone's. step() runs each
## awake zone in turn; an order from a client is carried out in the zone of
## the entity it is for. Outside those, the zone is the one the local
## player is in (home), so a host's view and input see their own zone. A
## client has the one zone its player is in, and never switches.

signal ticked(tick: int)
signal entity_moved(entity: GridEntity, from: Vector2i, to: Vector2i)
## [param cause] is &"attack", &"shot", &"impact" or &"fire".
signal entity_damaged(entity: GridEntity, amount: int, source: GridEntity, cause: StringName)
signal entity_pushed(entity: GridEntity, by: GridEntity, direction: Vector2i, tiles: int, impact: int, stopped_by: String)
## A blow's push resolved (apply_blow, decision 592): [param result]'s
## moved, distance, cells, stopped_by, impact_damage, struck, knocked_down
## and speed, for combat's hit-stop, sound and stagger. Server only.
signal blow_resolved(source: GridEntity, target: GridEntity, result: Dictionary)
## A lunge resolved (lunge, decision 596): [param result]'s cells, stopped_by,
## struck and impact_damage. Server only.
signal lunge_resolved(entity: GridEntity, result: Dictionary)
## A rush ended (rush, decision 604) for [param reason] ("arrived", "blow",
## "knocked", "brace", "body", "wall", "stunned") at [param at]; [param
## result] as lunge_resolved's. Every reason but "arrived" is an
## interruption. Server only.
signal rush_ended(entity: GridEntity, reason: String, at: Vector2i, result: Dictionary)
## A sweep resolved (sweep, decision 605): each struck body's {body, result}.
## Server only.
signal swept(source: GridEntity, struck: Array)
## A thing thrown down a line (hurl, decision 606) by [param by], landed at
## [param to], [param hit] the body it struck or null. Server only (the
## views hear it through GridEntity.hurled).
signal hurled(by: GridEntity, item_id: String, to: Vector2i, hit: GridEntity)
## A body launched (launch, decision 598): [param result] as
## blow_resolved's. Server only.
signal launched(by: GridEntity, body: GridEntity, result: Dictionary)
signal entity_despawned(entity: GridEntity)
## Reduced to 0 hp by [param cause] (&"attack", &"shot", &"impact", &"fire"), just
## before it is removed.
signal entity_died(entity: GridEntity, cause: StringName)
## A named enemy's moment for npc's memory of it (decision 716): [param kind]
## met, fought, killed_by, killed, fled_from (with [param player_id], a
## player's id) or rose ("" for nobody).
signal named_event(named_id: String, kind: String, player_id: String)
## Beaten down and spared (spared): left at 1 hp, taken by [param by] (a
## raid group's id), not killed. Whoever keeps it (Main, a companion's
## record) takes it off the map.
signal entity_taken(entity: GridEntity, by: String)
## Beaten down and downed (downed, decision 544): a blessed body left at 1
## hp, lying for [param ticks] in which a blessed hand may bring it back
## (try_channel); then it dies as ever (cause &"bled").
signal entity_downed(entity: GridEntity, source: GridEntity, ticks: int)
## A channel (try_channel, decision 544): [param by] began bringing back the
## downed [param body] (&"started"), did (&"done"), or was broken off
## (&"broken"). Server only.
signal channel_changed(by: GridEntity, body: GridEntity, state: StringName)
## [param each] fell asleep: nobody is in it now (World.step).
signal zone_slept(each: Zone)
## [param each] woke: someone came into it (World.step).
signal zone_woke(each: Zone)
## A door opened, closed, was damaged or broke; [param by] did it.
signal door_changed(door: Door, by: GridEntity)
## A door came, or its open or hp changed, on this peer (the server's
## change or a replicated one): views redraw that door.
signal door_shown(door: Door)
## Something went into or out of [param entity]'s slots (try_transfer,
## set_slots). Server only.
signal slots_changed(entity: GridEntity)
## The things on [param cell] of zone [param zone_name] (the one World is
## in) changed: something put down, spilt or thrown there (from
## [param thrown_from], else NO_CELL), or taken away. Main keeps its
## GroundPile; economy banks what lands on stockpile ground. Server only.
signal ground_changed(zone_name: String, cell: Vector2i, thrown_from: Vector2i)
## A player's gold changed (add_gold, a sale, a purchase): Main tells their
## client. Server only.
signal gold_changed(player_id: String, gold: int)
## [param by] traded at [param shop] (or was refused, [param why] said):
## Main sends them the shop again. Server only.
## A player put a thing into a resident's hands (try_transfer): a gift (decision 443).
signal handed(by: GridEntity, to: GridEntity, item: String, uid: int)
signal traded(by: GridEntity, shop: GridEntity, why: String)
## A move of things between slots refused for the armour slot's rule
## (decision 622): [param why] is said to whoever moved them (Main).
signal slot_refused(by: GridEntity, why: String)
## A GroundPile came, changed or went, for the views (any peer).
signal pile_shown(pile: GroundPile)
## Bandaging (try_bandage): [param by] began on [param patient] (state
## &"started"), finished (&"done": it mends from now), was broken off
## (&"interrupted"), or the mending ended (&"mended", by null). Server only.
signal bandage_changed(by: GridEntity, patient: GridEntity, state: StringName)
## A buff ([param kind], Items.BUFF_KINDS) on [param entity] began
## (&"started"), was topped up (&"renewed") or wore off (&"faded"): for
## companions to mention, and the views.
signal buff_changed(entity: GridEntity, kind: String, state: StringName)
## [param by] let a drawn bow go at [param at], drawn [param strength] (0
## to 1, World.draw_of): for combat to shoot (decision 329).
## [param by] let its drawn bow go at [param angle] (radians on the grid)
## with its draw at [param step] (the verb's steps; decision 583).
signal loosed(by: GridEntity, angle: float, step: int)
## A bow held at full draw till the holder's stamina ran out (decision 669):
## let down, nothing loosed.
signal draw_given_up(by: GridEntity)
## [param by]'s lob (decision 677) came down on [param cell], striking
## [param hit] (null for none).
signal lob_landed(by: GridEntity, cell: Vector2i, hit: GridEntity)
signal pile_gone(pile: GroundPile)
## [param target]'s guard met a blow or a shot from [param source]
## (decision 340): taken on it, or [param broken] by it.
signal guard_met(target: GridEntity, source: GridEntity, broken: bool)
## [param by] bashed [param target] with its shield (decision 379):
## [param opened], the target's guard was up and is open now.
signal shield_bashed(by: GridEntity, target: GridEntity, opened: bool)
## [param target] was knocked down by [param source]'s blow (decision 343).
signal knocked_down(target: GridEntity, source: GridEntity)
## [param holder]'s braced spear stopped [param charger]'s charge (decision
## 344).
signal braced_against(holder: GridEntity, charger: GridEntity)
## A thing in [param entity]'s slot took its name for life (decision 365):
## [param text] as it reads ("Wren's dagger").
signal item_named(entity: GridEntity, uid: int, text: String)
## A named thing is kept from its namer (decision 370) by [param entity],
## or is back with its namer ([param kept] false).
signal item_kept(entity: GridEntity, uid: int, kept: bool)
## [param uid] went from [param from]'s hands to [param to]'s (a player, a
## companion: "given" in its history); a companion's card takes a gift
## between her and her player as a fact (293 amended).
signal item_given(from: GridEntity, to: GridEntity, uid: int)
## [param uid], in [param entity]'s hands, grew (decision 417): [param mark]
## "bane", "grudge" or "avenged", against [param kind].
signal item_grew(entity: GridEntity, uid: int, mark: String, kind: String)
## [param by] took up the bundle [param taken] and put down the one it held,
## [param left], in its place (decision 375).
signal bundle_swapped(by: GridEntity, taken: int, left: int)
## The fixed heat and light changed (the map, a door): views that draw
## them redraw.
signal fields_changed_signal
## A player's command that is not a move, attack or shove: (name, args), for
## Main to act on. "say" {text} is chat.
signal command_received(entity: GridEntity, command: String, args: Dictionary)
## A walking step into [param occupant] was refused: it would not be pushed.
signal entity_bumped(mover: GridEntity, occupant: GridEntity, direction: Vector2i)
## Server: a move by [param entity] that failed because the cell ahead is
## no floor (a wall's far side, void, off the map): an edge link's trigger.
signal walked_off(entity: GridEntity, direction: Vector2i)
## A player's step onto a level link's cell refused (someone stood on it):
## Main takes the link all the same (decision 571).
signal link_bumped(entity: GridEntity, at: Vector2i)
## A step into a burial niche's edge (niche_edges) refused by it: a press
## on the niche (608: the hidden door is found so; Main says what gives).
signal niche_pressed(entity: GridEntity, key: Vector3i)
## An attack or a swing at air: [param direction] is where it went.
signal entity_swung(entity: GridEntity, direction: Vector2i)

const TICK_RATE := 10
const TICK_DT := 1.0 / TICK_RATE
## Ticks run per frame at most; beyond this the sim slows down instead of spiralling.
const MAX_CATCHUP_TICKS := 5
## How often a monster thinks, by how far it is from the nearest player or
## companion in its zone (Chebyshev tiles): NEAR (within the view's widest
## reach, Client3D.ZOOM_MAX) every tick, MID every MID_EVERY_TICKS (staggered by id), FAR not
## at all: the world tick moves it on instead (_world_tick). A monster with
## a target (a fight) is always NEAR, wherever it is. Each monster's tier is looked at again every TIER_EVERY_TICKS.
## With nobody standing in the zone (a player dead, waiting to respawn) it
## is measured from where they last stood; a zone that has never had anyone
## (a test room) thinks at the full rate everywhere.
enum Tier { NEAR, MID, FAR }
const NEAR_TILES := 22
const MID_TILES := 60
const MID_EVERY_TICKS := 4
const TIER_EVERY_TICKS := 5
const WAKE_SPREAD_TICKS := 20
## Beyond this many tiles of every player and companion a monster is on
## nobody's screen (the view's widest reach is 24 to 28): idling there it
## walks only straight (Monster._idle_step), with no search for a way.
const VIEW_TILES := 30
## The world tick: every so many steps, every zone, awake or asleep, moves
## its far monsters (all of them, asleep) on by that much time in one go
## (Monster._world_tick: real walks at their pace, no hits). It runs with
## nobody connected too. Its work is cut in WORLD_TICK_SLICES, a monster
## in each by id, one slice every WORLD_TICK_STEPS / WORLD_TICK_SLICES
## steps; a slice's monsters are queued, and each step goes through the
## queue for WORLD_TICK_BUDGET_USEC at most, each monster moved on by the
## time since its own last world tick: many walks owed at once (a fight's
## worth of monsters walking back) wait their turn rather than hold up a
## step.
const WORLD_TICK_STEPS := 300
const WORLD_TICK_SLICES := 10
const WORLD_TICK_BUDGET_USEC := 2000
## How many plans that take several searches (a patrol's own loop) are
## worked out in one step, all zones together (take_plan): a crowd that
## comes near at once (players arriving) plans over a few steps, not in
## one.
const PLANS_PER_STEP := 8
## A world tick's walk looks at most this many tiles for each tile it
## could walk in its time (World.walk).
const WALK_SEARCH_PER_STEP := 8
## Orthogonals first so ties in pathfinding prefer straight steps.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1),
]
const FIRE_DAMAGE := 2
## A creature burns where the heat (Fields) is at least this: in fire, or
## hemmed in by it. A fire cell alone gives Fields.FIRE.heat.
const HEAT_BURN := 9.0
## The eight compass points, clockwise from north.
const COMPASS: Array[String] = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
## A body pushed off a ledge takes this much impact per level it falls.
const FALL_IMPACT_PER_LEVEL := 3
## Clamp on mover_mass / target_mass when scaling push travel and impact.
const MASS_RATIO_MIN := 0.5
const MASS_RATIO_MAX := 1.5
## A pushed body is drawn sliding this many ticks a tile, at most
## MAX_PUSH_SLIDE_TICKS: slow enough to read as being thrown. The sim moves
## it at once; only the drawing and the stun after it wait.
const PUSH_SLIDE_TICKS_PER_TILE := 2
const MAX_PUSH_SLIDE_TICKS := 6
## NET_DISPLAY_DELAY_TICKS: how far in the past a client draws everything it
## does not predict, so a replicated tile change is in hand before its slide
## has to begin: 150 ms, room for a link's latency and jitter (decision 161).
const NET_DISPLAY_DELAY_TICKS := 1.5
## The live value: settings.cfg's display_delay_ms overrides the default.
var display_delay_ticks := NET_DISPLAY_DELAY_TICKS
## A client's display clock (ticks) runs at the tick rate on its own, and
## each server tick as it arrives says how far off it is: half of that is
## made up by running up to CLOCK_SLEW faster or slower, so a late or
## bunched packet neither freezes nor jumps what is drawn. More than a tick
## off (behind after a stall or a burst of lost ticks), it runs up to
## CLOCK_SLEW_FAR fast to catch up: what came due meanwhile is drawn
## faster in turn (GridEntity._catch_up), where setting the clock would
## jump every slide under way to its end. More than CLOCK_SNAP_TICKS off (a
## reconnect), it is set outright (decision 350).
const CLOCK_PULL := 0.5
const CLOCK_SLEW := 0.1
const CLOCK_SLEW_FAR := 0.5
const CLOCK_SNAP_TICKS := 10.0
## The display clock never runs more than this ahead of the last tick that
## came: with none coming (the server stalled, the link held them up) it
## waits, and what is drawn rests on what is known instead of running on
## to be set back, every slide under way jumping back with it, when the
## next tick comes (decision 350). Late ticks of up to 150 ms are inside it.
const CLOCK_LEAD_MAX := 2.5
## A diagonal step takes this many times the ticks of an orthogonal one, so
## world speed is roughly constant in every direction (a diagonal cell is
## sqrt(2) as long). Steps may take a fraction of a tick: the movement
## timer carries the fraction (see try_move), so a 2.5-tick step is
## taken on ticks 0, 3, 5, 8, 10... and drawn at its exact times.
const DIAGONAL_TICK_SCALE := 1.5
## A step into a ford (decision 505) takes this many times as long: wading.
const FORD_TICK_SCALE := 2.0
## Tall grass (decision 508): the cover of a cell of it standing (0..1;
## Senses reads cover_at), a step into it so many times as long, and a body
## of TRAMPLE_MASS or more stepping off it flattens it for TRAMPLE_DAYS
## (no cover, no slowing), standing again on the world tick after.
const TALL_GRASS_COVER := 0.7
const TALL_GRASS_TICK_SCALE := 1.25
const TRAMPLE_MASS := 40.0
const TRAMPLE_DAYS := 2.0
# Path costs are integers proportional to ticks. The +1 only breaks ties in
# favour of straight lines; fire is a detour worth five steps.
## What the terrain lets a walker who opens doors do across one step (see
## _path_step): not go, go, go through a door edge (open or not: its state
## is asked each time, a closed one costing PATH_DOOR_EXTRA), or, a
## diagonal past a door edge, whatever that door's state allows now (a
## closed one stops it), asked of the terrain each time.
enum { PATH_STEP_BLOCKED, PATH_STEP_OPEN, PATH_STEP_DOOR, PATH_STEP_ASK }
## find_path's heap keys: the order a tile was first opened in, in the low
## bits, under its f.
const PATH_ORDER_BITS := 24
const PATH_STEP_COST := 1000
const PATH_DIAGONAL_COST := int(PATH_STEP_COST * DIAGONAL_TICK_SCALE)
const PATH_DIAGONAL_EXTRA := 1
const PATH_FIRE_EXTRA := 5000
## The cost of a burning cell to those that keep off fire (decision 707,
## find_path's fire_extra: her heel, errands and Guide, a resident's walk
## by a Heel): forty steps, so she goes the long way round, yet not a
## wall: with no other way she crosses.
const PATH_FIRE_AVOID := 40000
## A closed door on the way costs a step: it is opened by walking into it.
const PATH_DOOR_EXTRA := PATH_STEP_COST

## Share of the shove force that a melee attack carries.
const ATTACK_FORCE_FACTOR := 0.5
## How far off a player can still get at their companion's pack (cells).
const COMPANION_REACH := 2
## Things on one cell of ground at most; more spill to the nearest cell with
## room, at most GROUND_SPILL away (put_on_ground).
const GROUND_PER_CELL := 4
const GROUND_SPILL := 3
## No cell: what put_on_ground gives when there is nowhere to put a thing.
const NO_CELL := Vector2i(-99999, -99999)
## Throwing (try_throw): reach is THROW_PER_STRENGTH x strength / the square
## root of the weight, 1 to THROW_MAX cells; the thing flies as a hurl at
## throw_speed (606 amended).
const THROW_MAX := 6
## Bandaging (try_bandage): BANDAGE_TICKS to bandage, out of combat (no
## hostile within BANDAGE_SAFE cells, not hurt for BANDAGE_CALM_TICKS);
## then BANDAGE_HEAL hp come back, one every BANDAGE_REGEN_TICKS.
const BANDAGE_TICKS := 20
const BANDAGE_SAFE := 6
const BANDAGE_CALM_TICKS := 30
const BANDAGE_HEAL := 10
const BANDAGE_REGEN_TICKS := 10
const THROW_PER_STRENGTH := 0.5
## A thing put down or landing makes a thud monsters hear (Senses), a heavy
## one from THUD_HEAVY_KG.
const THUD_HEAVY_KG := 5.0
## A bow loosed is heard this far (World.shoot): a soft twang, the shooter's
## own cell its source.
const NOISE_BOW := 3
## A guard broken (decision 340): its holder stunned this long, and no
## raising a guard again until GUARD_BROKEN_TICKS have passed.
const GUARD_BREAK_STUN := 8
const GUARD_BROKEN_TICKS := 20
## A body knocked down (decision 343) is pushed as if it weighed this much
## of its mass: lying, it cannot brace.
const DOWN_MASS_FACTOR := 0.5
## A spear is braced (decision 344) once its holder has stood this
## many ticks without a step; a creature charging into its reach is then
## stopped, struck for BRACE_DAMAGE_FACTOR times the blow and pushed back
## by the blow and its own momentum, turned (brace_restitution, decision 592).
const BRACE_TICKS := 5
## The least status of lore's name forms that names things (decision 365;
## Lore.name_forms): "agreed" in play; tests and clips use "draft".
var name_least := "agreed"
## How a thing kept from its namer is marked where it is shown (decision
## 370; the pack panel tints a slot that says it).
const KEPT_MARK := "ill-starred"
const BRACE_DAMAGE_FACTOR := 2.0
## Mass multiplier for being pushed while at 0 stamina.
const EXHAUSTED_MASS_FACTOR := 0.5

# Exported vars, not consts: GDScript cannot export constants.
## The knockback model (decision 592): every value from PHYSICS_RULES,
## read at start (load_physics_rules), so combat and Jeff tune them there.
## A "force" is the speed a push gives its body, in cells a tick over
## slide_per_speed: a shove's is strength x the shover's mass x
## shove_scale / the body's pushed mass (push_force).
const PHYSICS_RULES := "res://levels/physics.json"
## What a swing costs and what being winded does (decision 597): every value
## from COMBAT_RULES, read at start (load_combat_rules), drafts for Jeff.
const COMBAT_RULES := "res://levels/combat.json"
## A swing costs ceil(swing_base + swing_per_kg x the weapon's weight x
## ref_mass / the wielder's own mass) stamina (swing_cost); one that
## strikes nobody whiff_scale times that.
## The server's own salt for the arrow's roll in its cone (decision 620;
## scatter): drawn at boot and never sent, so a client can't foresee where
## a shot goes. Tests set it.
var shot_salt := randi()
var swing_base := 3.0
var swing_per_kg := 2.0
var ref_mass := 70.0
var whiff_scale := 1.25
## Winded from 0 stamina until it is back at recover_at: steps take
## winded_move_scale times the ticks, blows winded_blow_scale of their
## damage (the push fades by stamina in push_force alone, physics'), regen
## waits winded_regen_delay ticks.
var recover_at := 25
var winded_move_scale := 1.5
var winded_blow_scale := 0.5
## Melee reach where a free body is in it (decision 699): a plain blow
## lands while the two centres are at most this past both bodies' edges
## (2 x FREE_RADIUS), 1.5 at 0.9; a reach verb's is its cells less 0.1.
var melee_reach := 0.9
## A sword's lead (338 amended): its blow, begun in reach, lands at
## contact on a target that has got at most this past reach meanwhile, so
## no sidestep slips a slash, and only a step straight back from its edge
## does (2.0 at 0.9 and 0.5).
var lead_slack := 0.5
var winded_regen_delay := 20
## A boss's moves (decision 603), by name: "spin", "throw", "charge", each a
## Dictionary of its numbers (levels/combat.json's "moves"; drafts for Jeff).
var moves := {
	"spin": {"windup": 15, "length": 2.0, "half_angle": 180.0, "fists_length": 1.0, "damage_scale": 2.5,
		"down_ticks": 15, "needs": 50, "leaves": 10, "weight_impulse": 20.0, "impulse_scale": 1.06},
	"throw": {"windup": 12, "length": 8.0, "width": 1, "damage_scale": 2.0, "cost": 40, "speed": 14.0},
	"charge": {"roar": 6, "cells": 12},
}
@export var shove_scale := 0.1
## A pushed body slides this many cells per unit of speed, at most
## max_travel (a sanity limit: bodies under about 16 kg are all flattened
## by it, the one place mass is), speed lost as it goes.
@export var slide_per_speed := 1.5
@export var max_travel := 10
## Moving into a blow adds momentum_scale (the share of a body's momentum
## a swing carries) x the attacker's mass x its
## step's velocity (cells a tick; body_velocity) over the target's mass,
## for momentum_ticks after its step ends; only forward along the blow
## (moving across it angles the push, backing away takes nothing off).
@export var momentum_scale := 0.25
@export var momentum_ticks := 3
## A sliding body meeting another: the one met goes on at
## (1 + restitution) m1 u / (m1 + m2), the mover stops behind it, and the
## energy lost is shared between them as impact.
@export var restitution := 0.2
## Impact hp per unit of energy (1/2 m u^2, u the speed left) when a body
## is stopped by a wall, a door, a step up or a body.
@export var impact_per_energy := 0.075
## A braced spear is a stiff stop: a charger's whole momentum (not a
## blow's share of it) comes back at it (1 + this) times, 1 at most, an
## elastic stop (_meets_brace).
@export var brace_restitution := 1.0
## A lunge (decision 596): ticks a cell (a run's step is about 2), and the
## least speed a charge going through bodies keeps going at.
@export var lunge_ticks_per_cell := 1.0
@export var lunge_min_speed := 0.5
## A rush (decision 604) ends when the hits on it leave its speed this or
## less: a charge this slow is no charge.
@export var rush_stop_speed := 0.1
## A swing's own weight in its impulse (swing_impulse, decision 605): the
## thing's kilos times this.
@export var swing_speed := 20.0
## The pack's throw (try_throw, 606 amended): the thing's speed, cells a
## tick, its weight times this the impulse on a body it strikes.
@export var throw_speed := 2.0
## The load (decision 676; Jeff: items are physical, the effect falls out
## of the physics): a load's share of what carries it (load_capacity) over
## load_free slows what that part does by load_k a share over (load_scale):
## the body's the walk, the arms' the draw, the whole the breath. The bands
## the pack sheet names, as the whole load's share: light under load_free,
## burdened under load_heavy, heavy under load_overloaded, overloaded past.
@export var load_k := 0.5
@export var load_free := 0.15
@export var load_heavy := 0.3
@export var load_overloaded := 0.5
## What the arms carry against, as a share of the body's own mass: an 80 kg
## body's arms 16 kg, so a bow and its arrows (1.6 kg) sit under load_free.
const ARMS_SHARE := 0.2
## How much of the body's load a held draw's drain feels beside the arms'.
const DRAIN_BODY_SHARE := 0.25
## A worn piece's clank (decision 676 step 1b; Jeff: "armor should add a
## clank sound that scares prey"): cells of noise a kg of its material makes
## a step at a walk (armour_noise): plate clanks, mail jingles, leather and
## cloth make none. Its own noise, &"clank", beside the step's.
@export var clank_plate := 0.25
@export var clank_mail := 0.2
## The pace a clank is measured at: a player's walk, ticks a cell.
const CLANK_WALK_TICKS := 2.5
## Under a shout (Senses.NOISE_SHOUT): a monster goes to look, not to hunt.
const CLANK_MAX := 19
## Free movement (decision 688; Jeff's pick 3 of free-movement.md): a
## player's body has a centre of its own (GridEntity.free_pos) and moves any
## way at once, the world staying on cells; since 703 the only way a player
## walks (free_body). Monsters, animals, residents and companions keep the
## grid.
## A free body is a circle of this radius, in cells, against cell edges
## and others' cells (688).
const FREE_RADIUS := 0.3
## How strong a free body's walk must be to give up its wind-up (392
## amended): half a full intent, not within WIND_UP_KEEP_ANGLE of its target.
const WIND_UP_LEAVE_INTENT := 0.5
## Degrees off its target a free body's walk may press and keep its
## wind-up, strictly within (392 amended (2): at 45 every WASD key at the
## default yaw, a diagonal, kept it against a foe on an axis). The client
## holds its own view by the same two (ui's).
const WIND_UP_KEEP_ANGLE := 30.0
## How far past its cell's edge a free body's centre goes before it holds
## the next cell (688): a body on a border does not flicker between two.
const FREE_HYSTERESIS := 0.1
## The most a free body moves between collision checks, in cells (688),
## under its radius, so it never passes through an edge.
const FREE_SUBSTEP := 0.2
## The most real time a free body may bank, in ticks (688).
const FREE_BANK_TICKS := 3.0
## The most input commands waiting on one free body (688).
const FREE_INPUTS_MAX := 64
## A free body pressing into its own companion bumps her at most this
## often, in ticks (688): her yield hears it.
const FREE_BUMP_TICKS := 5
## A free body pushed into a wall nearer head on than this (the cosine of
## its way off the wall's normal; 30 degrees) is stopped by it; at more of a
## slant it slides along it (688 amended (2)).
const FREE_GLANCE_COS := 0.87
## A free body held pressing against an edge it cannot cross this many
## ticks (0.2 s) is a step refused there (688 amended (4)): the hidden
## niche's press, the map's edge walked off. Its intent must lean at least
## FREE_PRESS_LEAN into the edge (60 degrees off along it), so brushing
## past a wall presses nothing.
const FREE_PRESS_TICKS := 2
const FREE_PRESS_LEAN := 0.5
## Free movement's wire (decision 689).
const FreeNet := preload("res://net/free_net.gd")
## SHOVE_COST_BASE and SHOVE_COST_SCALE: a shove costs
## base + force x target_mass x scale stamina.
@export var shove_cost_base := 5.0
@export var shove_cost_scale := 0.15
## STAMINA_REGEN: stamina regained on a tick spent resting or walking.
@export var stamina_regen := 2
## A creature that is thrown into a wall or another entity, or is the one run
## into, is stunned for base + round(remaining speed x per_force) ticks.
@export var stun_ticks_base := 4
@export var stun_ticks_per_force := 3.0
## A creature knocked back (it moved) is stunned at least this many ticks
## past the end of its slide, wall or no wall: a beat to double over before
## it can act again.
@export var knockback_stun_ticks := 7
## An attack's blow (after ATTACK_FORCE_FACTOR and momentum) pushes only
## from this speed up; a lighter one only hurts. Shoves, tosses, throws and falls are not
## held to it (decision 305).
@export var knockback_min_force := 1.5
## Ticks after attacking, shoving or being thrown before regen resumes.
## 0 means only the tick of the exertion itself is lost.
@export var stamina_regen_delay := 10

var tick := 0
## Fraction of the way from the last tick to the next one, in [0, 1). Read by
## rendering, as tick + tick_alpha. On a client it is the display clock's
## lead on the last tick received, which may run a little past 1 or below 0.
var tick_alpha := 0.0
## A client's display clock, in ticks, and what it has yet to make up: see
## CLOCK_PULL.
var _clock := 0.0
var _clock_drift := 0.0
## Server: the tick whose half was last sent (Net.tick_send_hz 20).
var _half_sent := -1

var _floor: Dictionary[Vector2i, bool] = {}
## find_path's grid, this zone's (Zone.grid_rect, grid_steps): the floor's
## bounds and a pace beyond (Rect2i(): not worked out yet), each cell in it
## an index; and its memo, for a cell's index * 8 + one of DIRECTIONS,
## PATH_STEP_* + 1 by the terrain alone (0: not yet). Let go whenever the
## terrain is set or cleared.
var _grid_rect := Rect2i()
var _grid_steps := PackedByteArray()
## find_path's own, by cell index, for any zone: whether a cell was opened
## or closed in search number _search (the search it holds the number of),
## and its cost, the cell it came from and the order it was opened in, so
## nothing is emptied between searches.
var _search := 0
var _search_opened := PackedInt32Array()
var _search_closed := PackedInt32Array()
var _search_cost := PackedInt32Array()
var _search_from := PackedInt32Array()
var _search_order := PackedInt32Array()
## _carried_heat's memo: for which (tick, entity count), and its answer.
var _carried_heat_key := Vector2i(-1, -1)
var _carried_heat_now := false
## Whether an entity holds the key to a lock (entity, lock id) -> bool: set
## by the items; till then nobody does (has_key).
var key_check: Callable = func(_entity: GridEntity, _lock: String) -> bool: return false
## Whether an entity has something to shoot (entity) -> bool: always for now,
## a bow needing no arrows (gear is not used up). The hook for arrows kept
## and picked up again, if they come (decision 335).
var quiver_check: Callable = func(entity: GridEntity) -> bool: return World.bundle_slot(entity) >= 0
## Whether a blow that would kill spares its target instead (target,
## source, cause) -> who takes it ("" to kill as ever): set by Raids, so a
## raider takes a companion captive (decision 314). Unset, nobody is.
var spared: Callable
## Whether a blow that would kill leaves its target downed instead (target,
## source, cause) -> the ticks it lies downed (0 to die as ever): set by
## Main for the draugr's blessed (decision 544). Asked after spared. Unset,
## nobody is.
var downed: Callable
## The draugr beaten in a pact (decision 548): (player ids, difficulty) ->
## how many blessed; Main's bless (544). Unset, nobody is blessed.
var bless: Callable
## The charges the players in a zone hold, summed: (zone name) -> int;
## Main's charges_in_zone (573). Unset, none.
var charges_in: Callable
## The draugr's deal [param player_id] paid for in [param zone] and has not
## won (548 amended): (player id, zone name) -> {level, paid_step}, {} for
## none; Main's paid_deal_of, from the player's record. Unset, none.
var paid_deal: Callable
## The draugr's deal paid for, or won (548 amended): (player id, zone name,
## level) -> void, the level "" erasing it; Main's set_deal_paid, on the
## player's record. Unset, nothing is kept.
var deal_paid: Callable
## Puts an entity of a spec ({kind, name, tile, props, idle...}) into the
## zone World is in, as a level's are (Main's _spawn); null if it cannot.
## Unset (a test that builds its own), nothing is spawned.
var spawn_spec: Callable
## A taken companion freed where she is (player id, town place or "" for
## beside her player): Main's companion_freed. Raids calls it for those a
## beaten group carried (decision 314).
var companion_freed: Callable
## carried_lights' memo: for which (tick, entity count), and the list.
var _carried_lights_key := Vector2i(-1, -1)
var _carried_lights: Array[GridEntity] = []
var _fire: Dictionary[Vector2i, bool] = {}
## Heights (cell -> 1..6 levels; 0 is absent), stairs (cell -> the way it
## climbs: to the orthogonal neighbour one level up) and water (not walkable,
## not a wall). See Level.
var _height: Dictionary[Vector2i, int] = {}
var _stairs: Dictionary[Vector2i, Vector2i] = {}
## The ground's elevation in metres (decision 525), row by row over
## _relief_size cells: relief.png's, or the whole levels' (Relief). Steps,
## falls and pace read it; _relief_given (the level gave relief.png) has
## sight read it in metres too.
var _relief := PackedFloat32Array()
var _relief_size := Vector2i.ZERO
var _relief_given := false
var _water: Dictionary[Vector2i, bool] = {}
## Fords (decision 505): shallow water walked through at FORD_TICK_SCALE;
## floor.
var _fords: Dictionary[Vector2i, bool] = {}
## A solid building's cells (terrain "solid", decision 550): no floor, and
## they stop sight and light as a wall does.
var _solid: Dictionary[Vector2i, bool] = {}
## Each cell's cover (decision 508), row by row over _cover_rect (0 off
## it): TALL_GRASS_COVER on tall grass, 0 elsewhere; a trampled cell
## (_trampled_here) has none while it is flat.
var _cover := PackedFloat32Array()
var _cover_rect := Rect2i()
## Trampled tall grass (decision 508): level -> {cell: the world step it
## stands again}. Saved in the snapshot; the server's, told to the clients
## in its zone ("grass"). _trampled_here is this zone's level's.
var trampled: Dictionary[String, Dictionary] = {}
var _trampled_here: Dictionary = {}
## Tall grass of [param level] was trampled ([param flat]) or stood again
## ([param stood]), flat [x, y, ...]; on a client, also after a full
## "grass" message (both empty): terrain redraws the trodden path.
signal grass_changed(level: String, flat: PackedInt32Array, stood: PackedInt32Array)
## Torches on their posts (cells), for what a companion sees around her.
var _torches: Dictionary[Vector2i, bool] = {}
## Edge key -> the kind of the burial niche cut into it (terrain "niches",
## 608): "a" to "d" art-kit's pieces, "hidden" the first hall's hidden door.
var niche_edges: Dictionary[Vector3i, String] = {}
## Edge key -> that niche's floor cell (608 amended: the clues' marker, hidden_niche).
var niche_cells: Dictionary[Vector3i, Vector2i] = {}
## Heat and light per cell (Fields).
var fields := Fields.new()
## The level's north, as a cell offset (level.json "north"; up in the
## layout by default). Every direction told to a companion is a compass
## point worked out from it (compass).
var north := Vector2i(0, -1)
## Under the sky (level.json "outdoor"): its outline is a forest's edge,
## not a wall. Only words and looks change; the edge blocks as a wall does.
var outdoor := false
## Light a body through on a line (has_clear_line): bodies do not stop it.
var _through_bodies := false
## The eye height of the line of sight being walked (has_line_of_sight), -1
## when none: a wall lower than the eye does not stop it.
var _eye := -1.0
## Walls and doors are edges between cells, keyed as Terrain.edge_key says;
## open edges are absent. Blocking is a property of the edge you cross.
var _edges: Dictionary[Vector3i, int] = {}
## The Door node for each door edge, on every peer (doors register
## themselves). A door edge with no node yet counts as a closed door.
var _doors: Dictionary[Vector3i, Door] = {}
var _occupancy: Dictionary[Vector2i, GridEntity] = {}
## Always in ascending id order: ids are handed out in spawn order.
var _entities: Array[GridEntity] = []
## _entities' players and companions, and its monsters, in its order;
## made again when _entities changes (_roster_changed).
var _sought: Array[GridEntity] = []
## Those sought that hear by Senses (companions): noise tells them too.
var _hearers: Array[GridEntity] = []
var _monsters: Array[GridEntity] = []
var _townsfolk: Array[GridEntity] = []
## The zone's entities that have a turn (GridEntity.acts), in id order.
var _actors: Array[GridEntity] = []
var _roster_current := false
var _hits: Array[Hit] = []
var _next_id := 1
var _accumulator := 0.0
## Feel tuning's frame step (decision 673): a tick to stop at, time held
## again once it is played (Engine.time_scale 0); -1 for none.
var pause_at_tick := -1

## Server: every loaded zone by name, and the one World is working on.
var zones: Dictionary[String, Zone] = {}
## Level -> {edge key: what it was}: the wall edges of town buildings whose
## walls are not up yet (decision 566, maps' side), taken out of the level's
## edges until they are.
var _walls_down: Dictionary[String, Dictionary] = {}
## The damaged roofs (decision 383): "<level>/<x>,<y>" (the roof's rect's
## top-left, so an edit to the level's list moves none) -> true. Saved in
## the snapshot; the server's (environment's storms damage, economy's
## repairs mend: damage_roof, repair_roof).
var roofs_damaged: Dictionary[String, bool] = {}
## The draugr laid to rest (decisions 548, 580): zone name -> {"until":
## World.steps, "side": a faction}; that side's monsters in that zone lie
## still till then (Monster._mind_the_rest), asleep or awake, his own zone or
## one his level "stills". Kept through a room reset (Main._start_level),
## never saved: a restart ends every rest (573 amended (4), Jeff's).
var dead_rest: Dictionary[String, Dictionary] = {}
## The named enemies' records by id (decision 716; NamedEnemy.new_record's,
## npc's card, memories and track on them). Kept through a room reset
## (Main's) and saved.
var named: Dictionary[String, Dictionary] = {}
## Main's (714): whether a named one's trophy is due,
## (player_id, named_id, trophy) -> bool, player_id "" for "is it out to be
## won"; and its record of one won, (player_id, named_id, trophy). Unset,
## World's own: once ever (_trophy_due).
var trophy_due: Callable
var trophy_taken: Callable
## A roof of [param level] was damaged or mended (Main tells the peers).
signal roof_changed(level: String)
## A client's: each town's buildings as the server told ("town"), for
## open_roofs, which has no Towns there.
var towns_seen := {}
var zone := Zone.new()
## Server: which zone each peer's player is in: what that client is sent
## (peer_sees) and which zone's tick it gets.
var peer_zone: Dictionary[int, String] = {}
## World switched from one zone to another (Main swaps its per-zone state).
signal zone_switched(from: Zone, to: Zone)
## Every awake zone has stepped once (Main's snapshot timer).
## A danger area shown on the ground before its blow (decision 602; every
## boss's): telegraph() starts one, end_telegraph() ends it. Main tells the
## zone ("telegraph").
signal telegraph_started(id: int, data: Dictionary)
signal telegraph_ended(id: int, landed: bool)
## As telegraph_ended, with the zone it showed in (Main tells that zone).
signal telegraph_ended_in(zone_name: String, id: int, landed: bool)
signal stepped
## So many steps, all zones together.
var steps := 0
## Server: who holds which place (Holdings), the world tick's to change;
## made by Main at boot, from the levels and the snapshot. Null on a client.
var holdings: Holdings = null
## Server: the town's stores (Stockpile), which depots bank into; made by
## Main at boot, from the snapshot. Null on a client.
var stockpile: Stockpile = null
## Server: the town's work (Production), moved on by the world tick's first
## slice; made by Main at boot, from the snapshot. Null on a client.
var production: Production = null
## Server: how each town grows (Towns), choosing its buildings on the same
## slice; made by Main at boot, from the snapshot. Null on a client.
var towns: Towns = null
## (counter) -> the town a temple counter is in (decision 434; Main: the
## temple building whose rect holds it, its "town"); unset, the stockpile
## place over its tile.
var counter_town := Callable()
## The last refusal at a counter, for counter_order.
var _counter_why := ""
## Server: the wildlife's herds (Herds, decision 367), moved on by the
## world tick's first slice; made by Main at boot. Null on a client.
var herds: Herds = null
## Server: what grows wild to be gathered (Forage, decision 502: herbs),
## laid by the world tick's first slice; made by Main at boot. Null on a
## client.
var forage: Forage = null
## The forest felled and growing back (decision 591; Main makes it).
var clearing: Clearing = null
## Raid groups on the world map (decision 328), server only; null on a client.
var raid_groups: WorldRaids = null
## Trade routes and their caravans (decision 504), server only; null on a
## client.
var trade: TradeRoutes = null
## How rich in game each cell of the world is (decision 368), for Herds;
## server only, null on a client.
var richness: WorldRichness = null
## Server: prices, players' gold and trade with the town (Economy); made by
## Main at boot, from the snapshot. Null on a client.
var economy: Economy = null
## Server: raid groups in played zones as real monsters (Raids, decision
## 313); maps hands them over (enter) and takes them back.
var raids := Raids.new()
## Server: every thing in the world, with its history (ItemBook). Main
## replaces it at boot with the snapshot's.
var items := ItemBook.new(steps_now)
## Uids that level entities held when the room was reset: ended as lost
## unless the rebuild puts them back (end_unclaimed_items).
var _unclaimed: Array[int] = []
## Server: bandaging under way, bandager -> {patient, until, from, tile,
## exerted}; and the mending, patient -> {left, next, from} (_tend_wounds).
var _bandaging: Dictionary[GridEntity, Dictionary] = {}
## Server: the downed (decision 544), lying till their downed_until; and
## channels under way, channeler -> {body, until, from, tile, exerted}.
var _downed: Dictionary[GridEntity, bool] = {}
var _channels: Dictionary[GridEntity, Dictionary] = {}
## Server: whoever has a buff on (GridEntity.buffs), so only they are
## looked at for fading.
var _buffed: Dictionary[GridEntity, bool] = {}
var _mending: Dictionary[GridEntity, Dictionary] = {}
## The longest a thing's story line runs in its slot's note (story_line).
const STORY_LONGEST := 80
## Whoever is rushing (rush, decision 604): its state, for _tend_rushes.
var _rushers: Dictionary[GridEntity, Dictionary] = {}
## Free bodies whose push's slide is being shown (688 amended (2)), for
## _tend_free_kicks.
var _free_kicked: Dictionary[GridEntity, bool] = {}
## Whoever is winding up a blow (try_wind_up), for _tend_wind_ups.
var _winders: Dictionary[GridEntity, bool] = {}


## An attack or shove accepted this tick, waiting for the resolve phase.
class Hit:
	var source: GridEntity
	## A shove's hit (no guard meets it), else a blow.
	var shove := false
	## The blow's push before knockback_min_force: what a guard pays for
	## and what breaks it (decision 340).
	var raw_force := 0.0
	## Landed, it knocks the target down this long (a giant axe's;
	## decision 343). 0 for none.
	var down_ticks := 0
	## Landed on a creature, the deed it counts as for the thing in the
	## source's right hand (decision 365: struck, behind, downed, braced;
	## felled if it kills); "" for none (a shove).
	var deed := ""
	## A shield bash's (decision 379): the ticks it staggers; 0 for any
	## other hit.
	var bash := 0
	## A wound-up blow's (decision 392): it breaks any guard it meets.
	var crushing := false
	## A piercing blow's (a backstab or a reach verb's): worn armour's
	## deflect_pierce turns some of it (armour, combat's side).
	var pierce := false
	var target: GridEntity
	var source_id := 0
	var source_name := ""
	var target_name := ""
	## Where the target stood relative to the source when the hit was accepted.
	var direction := Vector2i.ZERO
	## Which way the target is pushed. The same as direction unless tossed.
	var push_direction := Vector2i.ZERO
	## The line it is pushed along (decision 592): push_direction, angled
	## by the source's momentum; ZERO, push_direction's own.
	var push_way := Vector2.ZERO
	var damage := 0
	var force := 0.0


## A slow tick's breakdown (decision 469): microseconds by part of the tick
## going now, each part timed where it runs (part()). A tick over
## SLOW_TICK_USEC, or a frame over SLOW_FRAME_USEC whose ticks were quick (a
## mind's answer, a save: work outside the sim), is told in one line, at
## most one every SLOW_SAY_MSEC with how many it stands for, so journald
## names the cause of a bad minute on the box.
const SLOW_TICK_USEC := 50000
const SLOW_FRAME_USEC := 100000
const SLOW_SAY_MSEC := 10000
var tick_parts: Dictionary[String, int] = {}
var _slow_count := 0
var _slow_frames := 0
var _slow_worst := 0
var _slow_worst_tick := 0
var _slow_worst_parts: Dictionary[String, int] = {}
var _slow_worst_frame := 0
var _slow_said := -SLOW_SAY_MSEC
var _frame_at := 0
var _last_ticks_usec := 0


## Adds the time since [param since] (Time.get_ticks_usec) to this tick's
## [param name] part; the time now, to time the next part from.
func part(name: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	tick_parts[name] = tick_parts.get(name, 0) + now - since
	return now


func _parts_total() -> int:
	var total := 0
	for name: String in tick_parts:
		total += tick_parts[name]
	return total


## Counts a tick of [param usec] or a frame of [param frame_usec] outside
## the sim; the line told now, or "" (none slow, or one told within
## SLOW_SAY_MSEC).
func _note_slow(usec: int, frame_usec: int) -> String:
	if usec > SLOW_TICK_USEC:
		_slow_count += 1
		if usec > _slow_worst:
			_slow_worst = usec
			_slow_worst_tick = tick
			_slow_worst_parts = tick_parts.duplicate()
	elif frame_usec > SLOW_FRAME_USEC:
		_slow_frames += 1
		_slow_worst_frame = maxi(_slow_worst_frame, frame_usec)
	if _slow_count + _slow_frames == 0 or Time.get_ticks_msec() - _slow_said < SLOW_SAY_MSEC:
		return ""
	_slow_said = Time.get_ticks_msec()
	var line := "[net] slow:"
	if _slow_count > 0:
		var order := _slow_worst_parts.keys()
		order.sort_custom(func(a: String, b: String) -> bool: return _slow_worst_parts[a] > _slow_worst_parts[b])
		var top: Array[String] = []
		for name: String in order.slice(0, 6):
			top.append("%s %.1f" % [name, _slow_worst_parts[name] / 1000.0])
		line += " %d tick%s over %d ms, the worst %.1f ms (tick %d): %s" % [_slow_count, "" if _slow_count == 1 else "s",
			SLOW_TICK_USEC / 1000, _slow_worst / 1000.0, _slow_worst_tick, ", ".join(top)]
	if _slow_frames > 0:
		line += "%s %d frame%s over %d ms outside the sim, the worst %.1f ms" % ["" if _slow_count == 0 else ";",
			_slow_frames, "" if _slow_frames == 1 else "s", SLOW_FRAME_USEC / 1000, _slow_worst_frame / 1000.0]
	print(line)
	_slow_count = 0
	_slow_frames = 0
	_slow_worst = 0
	_slow_worst_frame = 0
	return line


func _process(delta: float) -> void:
	if not Net.is_authority():
		# Mirror: no sim, only the display clock, running on smoothly.
		var advance := delta * TICK_RATE
		var most := advance * (CLOCK_SLEW if absf(_clock_drift) <= 1.0 else CLOCK_SLEW_FAR)
		var slew := clampf(_clock_drift, -most, most)
		_clock = minf(_clock + advance + slew, tick + CLOCK_LEAD_MAX)
		_clock_drift -= slew
		tick_alpha = _clock - tick
		return
	if Net.test_holds(tick):
		_accumulator = 0.0
		return
	_accumulator += delta
	var steps := 0
	var frame_start := Time.get_ticks_usec()
	var frame_usec := frame_start - _frame_at if _frame_at > 0 else 0
	_frame_at = frame_start
	var ticks_usec := 0
	while _accumulator >= TICK_DT:
		_accumulator -= TICK_DT
		if steps < MAX_CATCHUP_TICKS:
			var started := Time.get_ticks_usec()
			tick_parts.clear()
			step()
			var took := Time.get_ticks_usec() - started
			ticks_usec += took
			Net.stats.record_tick(took, tick)
			_note_slow(took, 0)
			steps += 1
			if pause_at_tick >= 0 and tick >= pause_at_tick:
				pause_at_tick = -1  # 673: the step played; held again.
				Engine.time_scale = 0.0
				_accumulator = 0.0
				break
	# The frame before this one, less its ticks (timed above): slow for
	# something outside the sim.
	if frame_usec - _last_ticks_usec > SLOW_FRAME_USEC:
		_note_slow(0, frame_usec - _last_ticks_usec)
	_last_ticks_usec = ticks_usec
	tick_alpha = _accumulator / TICK_DT
	if Net.tick_send_hz >= 20 and steps == 0 and tick_alpha >= 0.5 and _half_sent != tick:
		# Net.tick_send_hz 20: the clock's half ticks go out too.
		_half_sent = tick
		for peer in Net.sendable_peers():
			_net_half_tick.rpc_id(peer, tick)


## Advances the sim one tick: every awake zone (one with a player in it)
## steps once, in turn; a zone with nobody sleeps, moved on only by the
## world tick, every WORLD_TICK_STEPS. Driven by _process; tests call it
## directly.
func step() -> void:
	if not Net.is_authority():
		return
	var was := zone
	var t := Time.get_ticks_usec()
	if zones.is_empty():
		fields.update_weather(steps)
		_step_zone()
	for each: Zone in zones.values():
		var awake := _is_awake(each)
		if awake and not each.awake:
			_woke(each, (Time.get_ticks_msec() - each.asleep_since) / 1000.0)
			each.asleep_since = -1
		elif not awake and each.awake:
			each.asleep_since = Time.get_ticks_msec()
			each.awake = false
			zone_slept.emit(each)
		each.awake = awake
		if awake:
			enter(each)
			# This zone's weather on the clock (Weather; Fields keeps it).
			fields.update_weather(steps)
			_step_zone()
	enter(was)
	t = Time.get_ticks_usec()
	raids.step()
	t = part("raids", t)
	steps += 1
	# The sky's light on the new hour (DayNight; the light field reads it).
	DayNight.update()
	t = part("sky", t)
	var every := WORLD_TICK_STEPS / WORLD_TICK_SLICES
	if steps % every == 0:
		world_tick(steps / every % WORLD_TICK_SLICES)
	if production != null:
		production.returns_due(production.now())  # The fallen back on time (396 amended).
	t = Time.get_ticks_usec()
	_world_tick_due(WORLD_TICK_BUDGET_USEC)
	t = part("far and sleeping monsters", t)
	enter(was)
	stepped.emit()
	part("after the tick (snapshot, sky)", t)


## The world tick, every zone in turn (the one World is in if there are no
## zones): its far monsters, or all of them in a zone asleep, moved on by
## the time since each one's last; only those of [param slice] (id modulo
## WORLD_TICK_SLICES), queued for _world_tick_due, or all of them at once
## for -1. Called by step, a slice at a time; tests call it directly.
func world_tick(slice := -1) -> void:
	var t := Time.get_ticks_usec()
	if production != null and slice <= 0:
		# The towns choose what to build first, so its build job is taken
		# on the same tick.
		if towns != null:
			towns.tick()
		production.tick()
		# Then its residents buy what they need (decision 353).
		if economy != null:
			economy.tick()
		# Then what they do on the side (decision 393: the thief's lift) and
		# what they tell each other (decision 422: gossip).
		Townsfolk.tick(production, stockpile, economy)
		Townsfolk.gossip(production)
		Offers.tick()  # Promises to them that lapse (decision 435).
		if raid_groups != null:
			raid_groups.world_tick()
		if trade != null:
			trade.world_tick()
		t = part("towns, production, economy", t)
	if herds != null and slice <= 0:
		herds.tick()
		t = part("herds", t)
	if forage != null and slice <= 0:
		forage.tick()
		t = part("forage", t)
	if clearing != null and slice <= 0:
		clearing.tick()
		t = part("clearing", t)
	if slice <= 0:
		_regrow()  # Trampled tall grass stands again (decision 508).
	var was := zone
	var each_zone: Array[Zone] = []
	each_zone.assign(zones.values())
	if each_zone.is_empty():
		each_zone.append(zone)
	for each in each_zone:
		enter(each)
		if slice <= 0:
			for entity in _entities.duplicate():
				if _names_things(entity):
					_consider_names(entity)  # Time held counts up quietly (decision 365).
		var near := _tier_origins()
		for entity in monsters().duplicate():
			if slice >= 0 and entity.id % WORLD_TICK_SLICES != slice:
				continue
			if _alive(entity) and (not each.awake or _tier(entity, near) == Tier.FAR):
				if slice < 0:
					_world_tick_one(entity)
				elif not entity.world_queued:
					entity.world_queued = true
					_world_due.append([each, entity])
	enter(was)


## The monsters a world tick slice queued, [zone, monster], in order, and
## how far through them it is.
var _world_due: Array = []
var _world_due_at := 0


## Goes through the queued world tick for [param budget_usec] at most.
func _world_tick_due(budget_usec: int) -> void:
	var started := Time.get_ticks_usec()
	while _world_due_at < _world_due.size() and Time.get_ticks_usec() - started < budget_usec:
		var due: Array = _world_due[_world_due_at]
		_world_due_at += 1
		var monster: GridEntity = due[1]
		if not is_instance_valid(monster):
			continue
		monster.world_queued = false
		var each: Zone = due[0]
		if zones.get(each.name) != each and not (zones.is_empty() and each == zone):
			continue  # Its zone is gone.
		enter(each)
		# Near someone since it was queued: the full tick has it.
		if _alive(monster) and (not each.awake or _tier(monster, _tier_origins()) == Tier.FAR):
			_world_tick_one(monster)
	if _world_due_at >= _world_due.size():
		_world_due.clear()
		_world_due_at = 0


## [param monster]'s world tick: the time since its last (WORLD_TICK_STEPS
## for its first), WORLD_TICK_STEPS twice at most.
func _world_tick_one(monster: GridEntity) -> void:
	var since: int = WORLD_TICK_STEPS if monster.world_step < 0 else steps - monster.world_step
	monster.world_step = steps
	monster._world_tick(mini(since, WORLD_TICK_STEPS * 2) * TICK_DT)


## Whether [param each] is awake, or will be at the next step: someone has
## just come in (each.awake follows at the step). Regen asks this before
## laying a level again (decision 465).
func zone_awake(each: Zone) -> bool:
	return each.awake or _is_awake(each)


## Whether [param each] has a player in it: one standing there, or a
## connected peer whose player belongs there (dead, waiting to respawn).
func _is_awake(each: Zone) -> bool:
	if each.name in peer_zone.values():
		return true
	var entities: Array[GridEntity] = each.entities if each != zone else _entities
	for entity in entities:
		if entity is Player and entity.spawned:
			return true
	return false


## [param each] wakes after [param seconds] asleep, as the world tick left
## it (it ran while the zone slept); from here it runs at the full tick,
## each monster as near as it is to whoever came.
func _woke(each: Zone, seconds: float) -> void:
	print("[zone] %s wakes after %.0f s asleep" % [each.name, seconds])
	zone_woke.emit(each)
	# Every monster's tier looked at afresh, so those near whoever came wake
	# in turn (_tier).
	for entity in each.entities if each != zone else _entities:
		if entity is Monster:
			entity.tier_tick = -1


## One tick of the zone World is in.
func _step_zone() -> void:
	var t := Time.get_ticks_usec()
	tick += 1
	for entity in _entities:
		if entity.protected and tick >= entity.protected_until_tick:
			entity.protected = false
		if entity.sheltered and not is_sheltered(entity):
			# Its grace ended by an act, or a companion's player's shelter
			# over: hers goes with it (decision 661).
			entity.sheltered = false
			if entity.shelter_lead != null:
				entity.protected = false
			entity.shelter_lead = null
	# 1. Act, in ascending id: those that have a turn (a crate has none). The
	# roster is made anew when the entities change, so one despawned
	# mid-tick leaves this one as it was.
	var near := _tier_origins()
	_take_roster()
	_clear_links()
	_tend_rushes()  # Each rush's next cell when due (decision 604).
	_tend_free_kicks()  # Pushed free bodies' slides shown, stunned or not (688 amended (2)).
	t = part("tiers, roster", t)
	for entity in _actors:
		# Not its turn by the tier it has, and that tier not due to be
		# looked at again: passed over here, without a call (most of a
		# crowded map's monsters, most ticks). The same answer as _thinks.
		if entity.tiered and entity.tier_tick >= 0 and tick - entity.tier_tick < TIER_EVERY_TICKS \
				and (tick + entity.id) % TIER_EVERY_TICKS != 0 and entity.target == null \
				and (entity.tier == Tier.FAR or entity.tier == Tier.MID and (tick + entity.id) % MID_EVERY_TICKS != 0):
			continue
		# A stunned entity skips its turn; its orders wait for it.
		if _alive(entity) and not is_stunned(entity) and _thinks(entity, near):
			entity._sim_tick()
			# Its turn's time, by what it is (decision 469).
			t = part("act: monsters" if entity is Monster else "act: companions" if entity is Companion 					else "act: players" if entity is Player else "act: others", t)
	t = Time.get_ticks_usec()
	# 2. Hits (attacks and shoves) queued during the act phase.
	_tend_wind_ups()  # Wound-up blows struck when due (decision 392).
	_tend_boss_moves()  # A boss's spin, throw and charge (decision 603).
	_tend_draws()  # A bow held at full draw tires the arms (decision 669).
	_tend_lobs()  # Lobbed arrows come down when due (decision 677).
	_resolve_hits()
	t = part("hits", t)
	# 3. Hazard tiles; what ails (burning, bleeding; decision 375).
	_apply_hazards()
	_tend_ailments()
	t = part("hazards, ailments", t)
	# 4. Stamina comes back for whoever did not exert themselves this tick.
	_regen_stamina()
	# 5. Bandaging and mending; buffs wearing off.
	_tend_wounds()
	_tend_downed()
	_fade_buffs()
	t = part("stamina, wounds, buffs", t)
	var timed := _parts_total()
	ticked.emit(tick)
	# Its listeners' own parts (Main's respawns, residents...) are their
	# own; this part is what they did not time.
	var listeners := Time.get_ticks_usec() - t - (_parts_total() - timed)
	tick_parts["on each tick, the rest"] = tick_parts.get("on each tick, the rest", 0) + listeners
	t = Time.get_ticks_usec()
	# 6. The tick counter goes once per tick to the clients in this zone.
	for peer in Net.sendable_peers():
		if peer_sees(peer, zone.name):
			_net_tick.rpc_id(peer, tick)
	part("net", t)


## Where the zone's players and companions stand, that a monster's tier
## is measured from, or where they last stood; empty if nobody ever has
## (every monster NEAR).
func _tier_origins() -> Array[Vector2i]:
	var near: Array[Vector2i] = []
	for entity in sought():
		if entity.spawned:
			near.append(entity.tile)
	if near.is_empty():
		return zone.tier_origins
	zone.tier_origins = near
	return near


## Whether [param entity] thinks this tick (see Tier).
func _thinks(entity: GridEntity, near: Array[Vector2i]) -> bool:
	if not entity is Monster:
		return true
	match _tier(entity, near):
		Tier.NEAR:
			return true
		Tier.MID:
			return (tick + entity.id) % MID_EVERY_TICKS == 0
	return false


## [param entity]'s tier (a monster's), looked at again every
## TIER_EVERY_TICKS, staggered by id; NEAR in a fight or with nobody to
## measure from. One that comes out of FAR (or is looked at the first time)
## is woken (Monster._woke_up), so a crowd that someone's arrival brings
## near starts idling over WAKE_SPREAD_TICKS, not all on one tick.
func _tier(entity: GridEntity, near: Array[Vector2i]) -> Tier:
	var monster := entity as Monster
	# One fleeing keeps every tick as one with a target does (enemy-ai, Jeff's
	# hunting: "the stag started to run and phase glitch while at a distance"):
	# on MID past NEAR_TILES it stepped every MID_EVERY_TICKS, twice its pace.
	if near.is_empty() or monster.target != null or monster.alert == Monster.Alert.FLEEING:
		monster.tier = Tier.NEAR
		monster.tier_tick = tick
		monster.beyond_view = false
		monster.nearest_sought = -1
		return Tier.NEAR
	if monster.tier_tick >= 0 and tick - monster.tier_tick < TIER_EVERY_TICKS \
			and (tick + entity.id) % TIER_EVERY_TICKS != 0:
		return monster.tier as Tier
	var nearest := MID_TILES + 1
	for at in near:
		nearest = mini(nearest, distance(entity.tile, at))
	var was: int = monster.tier if monster.tier_tick >= 0 else Tier.FAR
	# One walking where a player can still see it (VIEW_TILES) keeps every tick
	# too: on MID its step waited for a think, ceil(pace / MID_EVERY_TICKS) of
	# them, and the client's tween at its pace ran, stopped and ran again.
	var walking := entity.next_move_tick + MID_EVERY_TICKS >= tick
	monster.tier = Tier.NEAR if nearest <= NEAR_TILES or nearest <= VIEW_TILES and walking \
			else Tier.MID if nearest <= MID_TILES else Tier.FAR
	if monster.tier != Tier.FAR:
		monster.far_since = -1
	elif monster.far_since < 0:
		monster.far_since = tick
	monster.tier_tick = tick
	monster.beyond_view = nearest > VIEW_TILES
	monster.nearest_sought = nearest
	monster.tier_comings = zone.comings
	if was == Tier.FAR and monster.tier != Tier.FAR:
		monster._woke_up()  # Thinking again: its idling starts in turn.
	return monster.tier as Tier


## The cells of this zone [param entity] may not walk: held by a faction
## not its own (Holdings.blocked_cells; a monster's faction is its kind's,
## Factions.of_kind), each with the place holding it. None with no holdings.
func held_against(entity: GridEntity) -> Dictionary:
	if holdings == null:
		return {}
	var kind := str(entity.spawn_spec.get("kind", ""))
	return holdings.blocked_cells(zone.name, holdings.factions.of_kind(kind) if holdings.factions != null else Factions.NOBODY)


## Whether a creature may step from [param from] the way [param direction]
## points by the terrain (walls, corners, ledges; doors it opens) and not
## into fire: what find_path would let it, but for who stands there.
func terrain_step_open(from: Vector2i, direction: Vector2i) -> bool:
	return not _terrain_blocks_step(from, direction, true) and not is_burning(from + direction)


var _plans_step := -1
var _plans_left := 0


## Whether one more plan of PLANS_PER_STEP may be worked out this step;
## counts it if so.
func take_plan() -> bool:
	if _plans_step != steps:
		_plans_step = steps
		_plans_left = PLANS_PER_STEP
	if _plans_left <= 0:
		return false
	_plans_left -= 1
	return true


## A walk for the world tick: [param entity] along a real way toward
## [param to], as far as [param ticks] of its own steps take it (diagonals
## as World.step_ticks costs them), done at once:
## nobody is near to see it go. It goes through doors as a creature does,
## and shuts them behind it: they are left as they were (no light and heat
## to work out again for a walk nobody sees). It stops where its time runs
## out; with no way there (the tile taken, or
## farther than it could look in that time) it gets as near as it can. The
## search looks at WALK_SEARCH_PER_STEP tiles for each step it could take.
## Nobody walks over ground another faction holds (held_against): it goes
## round, or as near as it can get, the edge; one standing in such ground
## already has met its holders there and does not walk (what comes of
## meeting them is the world tick's, later). True if it got there.
func walk(entity: GridEntity, to: Vector2i, ticks: float) -> bool:
	if not entity.spawned:
		return false
	if entity.tile == to:
		return true
	var reach := floori(ticks / step_ticks(entity, Vector2i(1, 0)))
	if reach <= 0:
		return false
	var walls := held_against(entity)
	if walls.has(entity.tile):
		return false
	var path := find_path(entity.tile, to, false, entity, reach * WALK_SEARCH_PER_STEP, true, walls, opens_doors_now(entity))
	var at := entity.tile
	var spent := 0.0
	for next in path:
		var direction := next - at
		var cost := step_ticks(entity, direction, at)
		if spent + cost > ticks:
			break
		spent += cost
		at = next
	if at != entity.tile:
		_relocate(entity, at)
		entity._world_slide_from(at, tick, 0.0)
	return at == to


# --- Zones (server) -----------------------------------------------------------

## Forgets every zone (a server restart, in a test): World back to one
## empty zone of no name.
func clear_zones() -> void:
	enter(Zone.new())
	reset()
	zones.clear()
	peer_zone.clear()


## A new, empty zone called [param zone_name] (Main fills it).
func add_zone(zone_name: String) -> Zone:
	var made := Zone.new(zone_name)
	zones[zone_name] = made
	return made


## Damages roof [param index] of level [param level] (its "roofs" in
## level.json): a third of it broken open to the sky (Level.broken_cells).
## Whether it was standing.
func damage_roof(level: String, index: int) -> bool:
	return _set_roof(level, index, true)


## Mends roof [param index] of [param level]. Whether it was damaged.
func repair_roof(level: String, index: int) -> bool:
	return _set_roof(level, index, false)


func roof_damaged(level: String, index: int) -> bool:
	var rects := _roof_rects(level)
	return index >= 0 and index < rects.size() and roofs_damaged.has(_roof_key(level, rects[index]))


## A client's: [param level]'s damaged roofs are [param damaged] (their
## indices, the "roofs" message); the sky opened over them as the server's.
func roofs_told(level: String, damaged: Array) -> void:
	var told: Dictionary[int, bool] = {}
	for index: Variant in damaged:
		told[int(index)] = true
	var rects := _roof_rects(level)
	for index in rects.size():
		var key := _roof_key(level, rects[index])
		if told.has(index):
			roofs_damaged[key] = true
		else:
			roofs_damaged.erase(key)
	open_roofs(level)


## The indices of [param level]'s damaged roofs, for the "roofs" message.
func damaged_roofs(level: String) -> Array[int]:
	var out: Array[int] = []
	var rects := _roof_rects(level)
	for index in rects.size():
		if roofs_damaged.has(_roof_key(level, rects[index])):
			out.append(index)
	return out


func _set_roof(level: String, index: int, damaged: bool) -> bool:
	var rects := _roof_rects(level)
	if index < 0 or index >= rects.size():
		return false
	var key := _roof_key(level, rects[index])
	if roofs_damaged.has(key) == damaged:
		return false
	if damaged:
		roofs_damaged[key] = true
	else:
		roofs_damaged.erase(key)
	open_roofs(level)
	roof_changed.emit(level)
	return true


static func _roof_key(level: String, rect: Rect2i) -> String:
	return "%s/%d,%d" % [level, rect.position.x, rect.position.y]


## Level [param level]'s roofs' rects, in order: its zone's if loaded, else
## WorldMap's (the level alone read, its parse kept by its digest).
func _roof_rects(level: String) -> Array:
	var fields_of := _fields_of(level)
	if fields_of != null and fields_of.level == level:
		return fields_of.roofs
	var read: Array[Rect2i] = []
	var names: Array[String] = [level]
	for roof: Dictionary in WorldMap.build(names).areas.get(level, {}).get("roofs", []):
		read.append(roof["rect"])
	return read


func _fields_of(level: String) -> Fields:
	if fields.level == level:
		return fields
	return zones[level].fields if zones.has(level) else null


## Opens to the sky what is broken over [param level]'s cells: its damaged
## roofs', and its damaged town buildings' (Towns, decision 297), a third
## of each (Level.broken_cells). On a damage or mend, a town's change, and
## its terrain read.
func open_roofs(level: String) -> void:
	var fields_of := _fields_of(level)
	if fields_of == null or fields_of.level != level:
		return
	var open: Dictionary[Vector2i, bool] = {}
	for rect: Rect2i in fields_of.roofs:
		if roofs_damaged.has(_roof_key(level, rect)):
			for cell in Level.broken_cells(rect):
				open[cell] = true
	for building: Dictionary in fields_of.town_buildings:
		var told: Dictionary = towns.buildings_of(building["town_id"]) if towns != null else towns_seen.get(building["town_id"], {})
		if str(told.get(building["use"], {}).get("state", "")) == Towns.DAMAGED:
			for cell in Level.broken_cells(building["rect"]):
				open[cell] = true
	fields_of.set_open(open)
	if fields_of == fields:
		fields_changed()
	_open_walls(level, fields_of)


## A town's plot laid on loaded [param level] (591 step 2): its kind's
## [param building] (Level.plot_building) one of its town buildings, its
## [param edges] (Level.plot_edges) laid where none stand, then open until
## its walls are up (_open_walls), as a zone load would lay it.
func add_plot(level: String, building: Dictionary, edges: Dictionary) -> void:
	var fields_of := _fields_of(level)
	var zone_of: Zone = zones.get(level)
	if fields_of == null or fields_of.level != level:
		return
	var at: Dictionary = _edges if fields_of == fields else (zone_of.edges if zone_of != null else {})
	var laid: Array[Vector3i] = []
	for key: Vector3i in edges:
		if not at.has(key):
			at[key] = edges[key]
			laid.append(key)
	fields_of.town_buildings.append({"rect": building["rect"], "use": building["use"], "town_id": building["town_id"],
		"outline": Level.building_outline(building), "plot": true, "laid": laid, "edges": edges})
	if fields_of == fields:
		_grid_rect = Rect2i()
		_grid_steps = PackedByteArray()
	elif zone_of != null:
		zone_of.grid_rect = Rect2i()
		zone_of.grid_steps = PackedByteArray()
	_open_walls(level, fields_of)


## A town's plot on [param rect] dropped from loaded [param level] (649,
## maps' side; add_plot's reverse): its building no longer one of the
## town buildings, the edges it laid taken out (any changed since kept),
## whether standing or held down while its walls were not up.
func unplot(level: String, rect: Rect2i) -> void:
	var fields_of := _fields_of(level)
	var zone_of: Zone = zones.get(level)
	if fields_of == null or fields_of.level != level:
		return
	var at: Dictionary = _edges if fields_of == fields else (zone_of.edges if zone_of != null else {})
	var down: Dictionary = _walls_down.get_or_add(level, {})
	for i in range(fields_of.town_buildings.size() - 1, -1, -1):
		var building: Dictionary = fields_of.town_buildings[i]
		if not building.get("plot", false) or not rect.encloses(building["rect"]):
			continue
		fields_of.town_buildings.remove_at(i)
		var edges: Dictionary = building["edges"]
		for key: Vector3i in building["laid"]:
			down.erase(key)
			if at.get(key) == edges[key]:
				at.erase(key)
	if fields_of == fields:
		_grid_rect = Rect2i()
		_grid_steps = PackedByteArray()
	elif zone_of != null:
		zone_of.grid_rect = Rect2i()
		zone_of.grid_steps = PackedByteArray()
	_open_walls(level, fields_of)


## [param level]'s town buildings whose walls are not up (Towns.walls_up,
## decision 566: below the walls stage, or only planned) with their outline
## open both ways: their wall edges taken out of the level's edges (kept in
## _walls_down), and put back once the walls are up. The server reads its
## Towns, a client the "town" message's "walls" (World.towns_seen), so its
## prediction walks the same; with no word, the walls stand. On a town's
## change and its terrain read, beside open_roofs.
func _open_walls(level: String, fields_of: Fields) -> void:
	var zone_of: Zone = zones.get(level)
	var edges: Dictionary = _edges if fields_of == fields else (zone_of.edges if zone_of != null else {})
	var down: Dictionary = _walls_down.get_or_add(level, {})
	var want: Dictionary[Vector3i, bool] = {}
	for building: Dictionary in fields_of.town_buildings:
		var told: Dictionary = towns.buildings_of(building["town_id"]) if towns != null else towns_seen.get(building["town_id"], {})
		if bool(told.get(building["use"], {}).get("walls", true)):
			continue
		for key: Vector3i in building.get("outline", []):
			want[key] = true
	var changed := false
	for key: Vector3i in down.keys():
		if not want.has(key):
			edges[key] = down[key]
			down.erase(key)
			changed = true
	for key: Vector3i in want:
		if edges.get(key, Terrain.Edge.OPEN) == Terrain.Edge.WALL:
			down[key] = Terrain.Edge.WALL
			edges.erase(key)
			changed = true
	if not changed:
		return
	# The paths' step cache read the old edges.
	if fields_of == fields:
		_grid_rect = Rect2i()
		_grid_steps = PackedByteArray()
	elif zone_of != null:
		zone_of.grid_rect = Rect2i()
		zone_of.grid_steps = PackedByteArray()


## Works on [param to] from now on: its state swapped into World's fields,
## the zone left keeping its own. Returns the zone World was in, to go back
## to (enter(was)).
func enter(to: Zone) -> Zone:
	var from := zone
	if to == null or to == from:
		return from
	from.tick = tick
	from.floor = _floor
	from.fire = _fire
	from.height = _height
	from.stairs = _stairs
	from.relief = _relief
	from.relief_size = _relief_size
	from.relief_given = _relief_given
	from.water = _water
	from.fords = _fords
	from.solid = _solid
	from.cover = _cover
	from.cover_rect = _cover_rect
	from.torches = _torches
	from.niche_edges = niche_edges
	from.niche_cells = niche_cells
	from.fields = fields
	from.north = north
	from.outdoor = outdoor
	from.edges = _edges
	from.doors = _doors
	from.occupancy = _occupancy
	from.entities = _entities
	from.hits = _hits.duplicate()
	from.grid_rect = _grid_rect
	from.grid_steps = _grid_steps
	zone = to
	tick = to.tick
	_floor = to.floor
	_fire = to.fire
	_height = to.height
	_stairs = to.stairs
	_relief = to.relief
	_relief_size = to.relief_size
	_relief_given = to.relief_given
	_water = to.water
	_fords = to.fords
	_solid = to.solid
	_cover = to.cover
	_cover_rect = to.cover_rect
	_torches = to.torches
	niche_edges = to.niche_edges
	niche_cells = to.niche_cells
	fields = to.fields
	_trampled_here = _trampled_of(fields.level)
	north = to.north
	outdoor = to.outdoor
	_edges = to.edges
	_doors = to.doors
	_occupancy = to.occupancy
	_entities = to.entities
	_roster_changed()
	_hits.assign(to.hits)
	_grid_rect = to.grid_rect
	_grid_steps = to.grid_steps
	_carried_heat_key = Vector2i(-1, -1)
	_carried_lights_key = Vector2i(-1, -1)
	zone_switched.emit(from, to)
	return from


## enter() by name; null and no change for a zone that is not loaded.
func enter_named(zone_name: String) -> Zone:
	return enter(zones[zone_name]) if zones.has(zone_name) else zone


## The zone the local player is in (a host's own view), else the one World
## is in.
func home() -> Zone:
	var mine: String = peer_zone.get(Net.local_id, "")
	return zones.get(mine, zone)


## Whether [param peer] is sent what is in zone [param zone_name]: its
## player is there. Something in no zone (a client's, or before zones) is
## everyone's.
func peer_sees(peer: int, zone_name: String) -> bool:
	return zone_name.is_empty() or peer_zone.get(peer, "") == zone_name


## The peers whose players are in zone [param zone_name].
func peers_in(zone_name: String) -> Array[int]:
	var peers: Array[int] = []
	for peer: int in peer_zone:
		if peer_zone[peer] == zone_name:
			peers.append(peer)
	return peers


## Asks every entity and door of zone [param zone_name] whether
## [param peer] may see it now (after peer_zone changed): the spawner then
## spawns or despawns them on that client.
func update_visibility(peer: int, zone_name: String) -> void:
	var each: Zone = zones.get(zone_name)
	if each == null or peer not in multiplayer.get_peers():
		return
	var entities: Array[GridEntity] = _entities if each == zone else each.entities
	var doors: Dictionary[Vector3i, Door] = _doors if each == zone else each.doors
	for entity in entities:
		if is_instance_valid(entity) and entity.sync != null:
			entity.sync.update_visibility(peer)
	for door: Door in doors.values():
		if is_instance_valid(door) and door.sync != null:
			door.sync.update_visibility(peer)
	for pile: GroundPile in each.piles.values():
		if is_instance_valid(pile) and pile.sync != null:
			pile.sync.update_visibility(peer)


# --- Mutations (server only) --------------------------------------------------

func reset() -> void:
	if not Net.is_authority():
		return
	for id: int in _telegraphs.keys():
		end_telegraph(id, false)  # Decision 602: none outlives the room.
	raids.hand_back(zone.name)  # Its raiders go with the room: back to maps.
	for entity in _entities:
		if is_instance_valid(entity) and entity.owner_peer == 0 and entity.keeper_peer == 0:
			# A level's chest goes with the room; a snapshot may bring it back.
			for uid in entity.slot_items:
				if uid != 0:
					items.place(uid, "")
					_unclaimed.append(uid)
	for cell: Vector2i in zone.ground:
		for uid in zone.ground[cell]:
			items.place(uid, "")
			_unclaimed.append(uid)
	zone.ground.clear()
	zone.ground_gold.clear()  # 601 amended: a snapshot may bring it back.
	zone.piles.clear()
	# Its monsters kept as records go with the room too, their things as a
	# level entity's do.
	for record: Dictionary in record_list():
		for uid: Variant in record["entry"].get("items", []):
			if (uid is int or uid is float) and int(uid) != 0:
				items.place(int(uid), "")
				_unclaimed.append(int(uid))
	zone.records = {}
	zone.recalls_due.clear()
	for entity in _entities:
		if is_instance_valid(entity):
			_forget_jobs(entity)  # As despawn does (decision 572 amended (2)).
			entity._world_remove()
	_entities.clear()
	_roster_changed()
	zone.comings += 1
	_occupancy.clear()
	_hits.clear()
	_rushers.clear()
	_free_kicked.clear()
	_grid_rect = Rect2i()
	_grid_steps = PackedByteArray()
	_floor.clear()
	_fire.clear()
	_edges.clear()
	_height.clear()
	_stairs.clear()
	_relief = PackedFloat32Array()
	_relief_size = Vector2i.ZERO
	_relief_given = false
	_water.clear()
	_fords.clear()
	_solid.clear()
	_cover = PackedFloat32Array()
	_cover_rect = Rect2i()
	_next_id = 1
	dead_rest.clear()
	named.clear()
	zone.tier_origins = []
	tick = 0
	tick_alpha = 0.0
	_accumulator = 0.0


# --- Far monsters kept as records (decision 352) -------------------------------

## Records are kept by square of this many cells (Zone.records), so those
## within a reach of someone are found without going through them all.
const RECORD_CHUNK := 16
## The kinds with a world-tick store of their own: objects with
## takes(monster) -> bool, retire(monster) and recall_near(at, reach). A
## monster Main retires that one takes goes to it instead of a record; and
## when someone is near a cell, each is asked to make what it keeps there
## (docs/design.md, Zones: keepers; wildlife's herds, W4).
var keepers: Array[Object] = []


## [param record] kept in the zone World is in (Main._retire).
func add_record(record: Dictionary) -> void:
	var chunk := _record_chunk(record)
	if not zone.records.has(chunk):
		zone.records[chunk] = []
	zone.records[chunk].append(record)


## The zone's records within [param reach] of [param at], taken out of it
## (Main._recall_near recalls them).
func take_records_near(at: Vector2i, reach: int) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	var low := Vector2i(floori(float(at.x - reach) / RECORD_CHUNK), floori(float(at.y - reach) / RECORD_CHUNK))
	var high := Vector2i(floori(float(at.x + reach) / RECORD_CHUNK), floori(float(at.y + reach) / RECORD_CHUNK))
	for cy in range(low.y, high.y + 1):
		for cx in range(low.x, high.x + 1):
			var chunk := Vector2i(cx, cy)
			if not zone.records.has(chunk):
				continue
			var kept: Array = []
			for record: Dictionary in zone.records[chunk]:
				if distance(record_tile(record), at) <= reach:
					taken.append(record)
				else:
					kept.append(record)
			if kept.is_empty():
				zone.records.erase(chunk)
			else:
				zone.records[chunk] = kept
	return taken


## Every record of the zone World is in, in no particular order (saving),
## those waiting to be made again (Zone.recalls_due) too.
func record_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = zone.recalls_due.duplicate()
	for chunk: Vector2i in zone.records:
		for record: Dictionary in zone.records[chunk]:
			list.append(record)
	return list


## The zone's records, as a snapshot had them (Main._start_level): the
## things they hold are theirs again, so a rebuild does not end them as lost.
func set_records(list: Array) -> void:
	zone.records = {}
	zone.recalls_due.clear()
	for record: Dictionary in list:
		add_record(record)
		var holder := "%s/%s" % [zone.name, record["entry"].get("name", "")]
		var label := str(record["entry"].get("label", "")) if str(record["entry"].get("label", "")) != "" else str(record["entry"].get("name", ""))
		for uid: Variant in record["entry"].get("items", []):
			if (uid is int or uid is float) and int(uid) != 0 and items.has(int(uid)):
				items.place(int(uid), holder, holder, label)


## Where [param record] stands.
static func record_tile(record: Dictionary) -> Vector2i:
	var tile: Variant = Snapshot.vector(record["entry"].get("tile"))
	return tile if tile is Vector2i else Vector2i.ZERO


static func _record_chunk(record: Dictionary) -> Vector2i:
	var tile := record_tile(record)
	return Vector2i(floori(float(tile.x) / RECORD_CHUNK), floori(float(tile.y) / RECORD_CHUNK))


## A cell of the zone World is in felled to floor or grown back to a trunk
## (Clearing, decision 591): [param on] floor or not, the walk's caches
## dropped and the fields round it marked to be worked out again.
func set_floor(cell: Vector2i, on: bool) -> void:
	if on:
		_floor[cell] = true
	else:
		_floor.erase(cell)
	_grid_rect = Rect2i()
	_grid_steps = PackedByteArray()
	fields_changed([cell])


## Edges [param changes] (key -> Terrain.Edge, OPEN taking one away) set in
## the walk (591 amended: Level.relay_outline's, a felled cell's walls gone).
func set_edges(changes: Dictionary) -> void:
	if changes.is_empty():
		return
	var near: Array[Vector2i] = []
	for key: Vector3i in changes:
		if int(changes[key]) == Terrain.Edge.OPEN:
			_edges.erase(key)
		else:
			_edges[key] = int(changes[key])
		near.append(Vector2i(key.x, key.y))
	_grid_rect = Rect2i()
	_grid_steps = PackedByteArray()
	fields_changed(near)


## [param terrain] is what Terrain.parse returns.
func load_terrain(terrain: Dictionary) -> void:
	if not Net.is_authority():
		return
	_set_terrain(terrain)


func _set_terrain(terrain: Dictionary) -> void:
	zone.terrain_loads += 1
	_grid_rect = Rect2i()
	_grid_steps = PackedByteArray()
	_floor.clear()
	_fire.clear()
	_edges.clear()
	_height.clear()
	_stairs.clear()
	_relief = PackedFloat32Array()
	_relief_size = Vector2i.ZERO
	_relief_given = false
	_water.clear()
	_fords.clear()
	_solid.clear()
	_torches.clear()
	for cell: Vector2i in terrain.get("torches", []):
		_torches[cell] = true
	niche_edges.clear()
	niche_cells.clear()
	for niche: Dictionary in terrain.get("niches", []):
		niche_edges[niche["edge"]] = str(niche["kind"])
		niche_cells[niche["edge"]] = niche["cell"]
	north = terrain.get("north", Vector2i(0, -1))
	outdoor = bool(terrain.get("outdoor", false))
	fields.load(terrain)
	fields.update_weather(DayNight.now())
	open_roofs(fields.level)
	fields_changed()
	var heights: Dictionary = terrain.get("heights", {})
	for cell: Vector2i in heights:
		_height[cell] = int(heights[cell])
	var stairs: Dictionary = terrain.get("stairs", {})
	for cell: Vector2i in stairs:
		_stairs[cell] = stairs[cell]
	for cell: Vector2i in terrain.get("water", []):
		_water[cell] = true
	for cell: Vector2i in terrain.get("solid", []):
		_solid[cell] = true
	for cell: Vector2i in terrain.get("fords", []):
		_fords[cell] = true
	_load_cover(terrain)
	for t: Vector2i in terrain["floor"]:
		_floor[t] = true
	_load_relief(terrain)
	for t: Vector2i in terrain["fire"]:
		_fire[t] = true
	var edges: Dictionary = terrain["edges"]
	for key: Vector3i in edges:
		_edges[key] = edges[key]
	# The edges are the level's again: its unbuilt walls opened anew (566).
	_walls_down.erase(fields.level)
	_open_walls(fields.level, fields)


## Doors register on every peer: the server reads and changes them, a client
## reads them for prediction and drawing.
## A GroundPile entered the tree (server and client): the zone it is in
## knows it by cell, and the views are told.
func register_pile(pile: GroundPile) -> void:
	var each: Zone = zones.get(pile.zone, zone) if Net.is_authority() else zone
	each.piles[pile.tile] = pile
	pile_shown.emit(pile)


func unregister_pile(pile: GroundPile) -> void:
	for each: Zone in ([zone] if not Net.is_authority() else zones.values()):
		if each.piles.get(pile.tile) == pile:
			each.piles.erase(pile.tile)
	pile_gone.emit(pile)


func register_door(door: Door) -> void:
	_doors[door.key] = door
	fields_changed()
	door_shown.emit(door)


func unregister_door(door: Door) -> void:
	if _doors.get(door.key) == door:
		_doors.erase(door.key)
		fields_changed()


## The fixed heat and light must be worked out again (a door, the map):
## all of it, or ([param near]) only what reaches those cells.
func fields_changed(near: Array[Vector2i] = []) -> void:
	if near.is_empty():
		fields.mark_dirty()
	else:
		fields.mark_dirty_near(near)
	fields_changed_signal.emit()


## Heat at [param at] (Fields): at least HEAT_BURN burns.
func heat_at(at: Vector2i) -> float:
	return fields.heat_at(self, at)


## Light at [param at], 0 dark to 1; [param carried]: with carried
## lanterns; [param sky]: with the sky's light outdoors (Fields.light_at).
func light_at(at: Vector2i, carried := true, sky := true) -> float:
	return fields.light_at(self, at, carried, sky)


## How far one sees from [param cell] under the weather, a share of one's
## sight range: 1 indoors or under a roof (Fields.update_weather).
func weather_sight_at(cell: Vector2i) -> float:
	return fields.weather_sight if fields.under_sky(cell) else 1.0


## How far a noise at [param cell] carries under the weather, a share of
## its radius: 1 indoors or under a roof.
func weather_hearing_at(cell: Vector2i) -> float:
	return fields.weather_hearing if fields.under_sky(cell) else 1.0


## Whether a creature standing at [param at] burns. Asked of every cell a
## path or a flood looks at: with nobody carrying heat (as now, always) it
## is the map's heat alone, a lookup, where heat_at goes through every
## entity each time.
func is_burning(at: Vector2i) -> bool:
	if not _carried_heat():
		return fields.map_heat_at(self, at) >= HEAT_BURN
	return heat_at(at) >= HEAT_BURN


## Whether anything carries heat (Fields.any_carried_heat), worked out once
## a tick (and again if the entities change in number).
func _carried_heat() -> bool:
	var key := Vector2i(tick, _entities.size())
	if key != _carried_heat_key:
		_carried_heat_key = key
		_carried_heat_now = fields.any_carried_heat(self)
	return _carried_heat_now


## The players and companions carrying a lit lantern (Senses.is_lit),
## worked out once a tick (and again if the entities change in number).
## Not a copy: read it, do not change it.
func carried_lights() -> Array[GridEntity]:
	var key := Vector2i(tick, _entities.size())
	if key != _carried_lights_key:
		_carried_lights_key = key
		_carried_lights = []
		for entity in sought():
			if entity.emit_light > 0.0 and entity.spawned:
				_carried_lights.append(entity)
	return _carried_lights


## A noise of [param kind] at [param at], heard [param radius] cells off
## (half that with no clear line to it: through a wall or a closed door):
## told now to every monster and companion that hears it (Senses.hear), not
## one listening every tick. A small one looks only at the cells in reach;
## a big one goes through the monsters. [param source] does not hear itself.
func noise(at: Vector2i, radius: int, kind: StringName, source: GridEntity = null) -> void:
	if not Net.is_authority() or radius <= 0:
		return
	if kind != &"speech":
		# Rain and wind cover it (Weather); speech is chat between players
		# too, and keeps its reach.
		var cover := weather_hearing_at(at)
		if cover < 1.0:
			radius = maxi(1, roundi(radius * cover))
	# Companions are few: each one in reach hears.
	_take_roster()
	for entity in _hearers:
		if maxi(absi(entity.tile.x - at.x), absi(entity.tile.y - at.y)) <= radius:
			_hear(entity, at, radius, kind, source)
	if (2 * radius + 1) * (2 * radius + 1) <= monsters().size():
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var listener := _occupancy.get(at + Vector2i(dx, dy)) as Monster
				if listener != null:
					_hear(listener, at, radius, kind, source)
	else:
		for entity in monsters():
			var d := maxi(absi(entity.tile.x - at.x), absi(entity.tile.y - at.y))
			if d <= radius:
				_hear(entity as Monster, at, radius, kind, source)
	# A bane's bearer (decision 420) is heard bane_notice times farther by the
	# kind it is the bane of.
	var banes := banes_held(source)
	if not banes.is_empty():
		var far := ceili(radius * float(Items.growth()["bane_notice"]))
		for entity in monsters():
			var d := maxi(absi(entity.tile.x - at.x), absi(entity.tile.y - at.y))
			if d > radius and d <= far and kind_of(entity) in banes:
				_hear(entity as Monster, at, far, kind, source)


func _hear(listener: GridEntity, at: Vector2i, radius: int, kind: StringName, source: GridEntity) -> void:
	var senses: Senses = listener.get("senses")
	if listener == source or senses == null or not listener.spawned:
		return
	var d := maxi(absi(listener.tile.x - at.x), absi(listener.tile.y - at.y))
	var muffled := d > 0 and not has_clear_line(at, listener.tile)
	if muffled and d * 2 > radius:
		return  # Through a wall or a closed door: only half as far.
	senses.hear(at, radius, kind, source, muffled)


## Which way the heat at [param at] comes from, as a compass point ("" for none).
func heat_from(at: Vector2i) -> String:
	var toward := fields.heat_from(self, at)
	return compass(toward) if toward.length() > 0.01 else ""


## The compass point [param offset] (a cell offset) lies toward, by the
## level's north: "north-east".
func compass(offset: Vector2) -> String:
	return COMPASS[bearing_index(offset)]


## 0 north .. 7 north-west, clockwise, for [param offset].
func bearing_index(offset: Vector2) -> int:
	var up := Vector2(north)
	var east := Vector2(-up.y, up.x)  # A quarter turn clockwise on the map.
	var degrees := rad_to_deg(atan2(offset.dot(east), offset.dot(up)))
	return posmod(roundi(degrees / 45.0), 8)


## The door on edge [param key], or null.
func door_on(key: Vector3i) -> Door:
	return _doors.get(key)


## The zone's hidden niche (608 amended: the marker every clue to the hidden
## door points at): {cell (its floor cell, the one stepped from), edge (its
## door's edge key), open (the door found: open)}; {} in a zone with none.
func hidden_niche() -> Dictionary:
	for key: Vector3i in niche_edges:
		if niche_edges[key] == "hidden":
			var door := door_on(key)
			return {"cell": niche_cells.get(key, Terrain.edge_cells(key)[0]), "edge": key, "open": door != null and door.open}
	return {}


func get_doors() -> Array[Door]:
	var doors: Array[Door] = []
	doors.assign(_doors.values())
	return doors


## A creature standing on either side of a door opens or closes it. Takes
## the entity's step time, like a move. False if it cannot.
func try_toggle_door(entity: GridEntity, key: Vector3i) -> bool:
	if not Net.is_authority():
		return false
	if not entity.spawned or not entity.is_creature() or is_stunned(entity) \
			or tick < entity.next_move_tick:
		return false
	var door: Door = _doors.get(key)
	if door == null or door.is_broken() or entity.tile not in Terrain.edge_cells(key):
		return false
	if not door.open and door.lock != "" and not has_key(entity, door.lock):
		noise(entity.tile, Senses.NOISE_RATTLE, &"door_rattle", entity)
		return false  # Locked, and no key: it rattles.
	_set_door(door, not door.open, entity)
	entity.next_move_tick = tick + entity.move_ticks
	return true


## Whether [param entity] may open [param door] by walking into it: a
## creature, with the key to its lock if it has one, and a monster only if
## it opens doors and will now (Monster.opens_doors_now).
func may_open(entity: GridEntity, door: Door) -> bool:
	if not entity.is_creature():
		return false
	if door.lock != "" and not has_key(entity, door.lock):
		return false
	return opens_doors_now(entity)


## Whether [param entity]'s walks go through closed doors now (a monster's
## own say; any other creature does).
func opens_doors_now(entity: GridEntity) -> bool:
	return (entity as Monster).opens_doors_now() if entity is Monster else entity.is_creature()


## Whether [param entity] holds the key to [param lock]: key_check, which
## the items say (none of anyone's till they do).
func has_key(entity: GridEntity, lock: String) -> bool:
	return bool(key_check.call(entity, lock))


## A blow at a closed door from beside it (a monster that cannot open it,
## breaking through): [param amount] of damage, wood only (_hit_door), at
## the cost of an attack's cooldown, as a swing that way. False if it
## cannot now.
func try_bash_door(entity: GridEntity, key: Vector3i, amount: int) -> bool:
	if not Net.is_authority():
		return false
	if not entity.spawned or not entity.is_creature() or is_stunned(entity) \
			or tick < entity.next_attack_tick or tick < entity.next_move_tick:
		return false
	var door: Door = _doors.get(key)
	var sides := Terrain.edge_cells(key)
	if door == null or door.is_open() or entity.tile not in sides:
		return false
	var direction: Vector2i = (sides[1] if entity.tile == sides[0] else sides[0]) - entity.tile
	entity.next_attack_tick = tick + entity.attack_ticks
	_halt_for_blow(entity, entity.next_attack_tick)
	entity._world_set_facing(direction)
	entity._world_swung(direction)
	_hit_door(door, amount, entity)
	return true


## A door held shut (573 amended: the Hall of Fallen Souls' door behind the
## first player in): closed and locked with [param lock], a key nobody
## holds, so it rattles and no walk opens it; stone while held, so no blow
## breaks it. Let go, the lock is lifted and it stays closed till someone
## opens it.
func hold_door(door: Door, held: bool, lock: String) -> void:
	if door == null:
		return
	if held:
		door.open = false
		door.lock = lock
		door.body_material = GridEntity.BodyMaterial.STONE
	elif door.lock == lock:
		door.lock = ""


func _set_door(door: Door, open: bool, by: GridEntity) -> void:
	if door.open == open:
		return
	door.open = open
	if _logs_for(by):
		_log("door: %s %s %s" % [by.name, "opened" if open else "closed", door.name])
	noise(by.tile, Senses.NOISE_DOOR, &"door", by)
	door_changed.emit(door, by)
	var partner := door_partner(door)
	if partner != null and partner.open != open and not partner.is_broken():
		partner.open = open
		door_changed.emit(partner, by)


## The other leaf of [param door]'s double door (725): in a generated
## level's halls each pair of door edges side by side (Level.door_pairs,
## as the client draws them) swings as one; null elsewhere, for a locked
## door or a niche's (608), or for one with no partner.
func door_partner(door: Door) -> Door:
	if door == null or door.lock != "" or not Level.regenerates(door.zone):
		return null
	var each: Zone = zones.get(door.zone, zone) if Net.is_authority() else zone
	var doors: Dictionary[Vector3i, Door] = _doors if each == zone else each.doors
	var free := func(key: Vector3i) -> bool: return doors.has(key) and doors[key].lock == "" and not niche_edges.has(key)
	var pairs := Level.door_pairs(doors.keys(), free)
	for first: Vector3i in pairs:
		if first == door.key:
			return doors.get(pairs[first])
		if pairs[first] == door.key:
			return doors.get(first)
	return null


## Impact on a door, from a push against it: wood breaks once its hp is
## spent; anything else takes nothing.
func _hit_door(door: Door, amount: int, by: GridEntity) -> void:
	if door.is_broken() or door.body_material != GridEntity.BodyMaterial.WOOD or amount <= 0:
		return
	door.hp = maxi(door.hp - amount, 0)
	_log("door: %s takes %d from %s (%d left)" % [door.name, amount, by.name, door.hp])
	var at: Vector2i = Terrain.edge_cells(door.key)[0]
	if door.is_broken():
		_log("door: %s broke" % door.name)
		door.open = true
		noise(at, Senses.NOISE_DOOR_BROKEN, &"door_broken", by)
	else:
		noise(at, Senses.NOISE_DOOR_STRUCK, &"door_struck", by)
	door_changed.emit(door, by)


## [param by] moves what is in [param from]'s slot [param from_slot] into
## [param to]'s slot [param to_slot], swapping with whatever is there. Each
## side is [param by] itself or something it can reach (reaches); the slot
## taken from must hold something. [param by] is a player or a companion,
## alike. Each instance moves with its id and its history is written: a
## new carrier, "found" the first time anyone carries it, "given" from one
## carrier to another. False, and nothing moves, otherwise.
## A stack (decision 619) moves whole, or [param count] of its units (0:
## all): onto an empty slot that many split off, onto a stack they join (as
## many as it has room for), onto anything else the stacks swap whole. A
## depot or a shop takes that many, one by one; the priest one.
func try_transfer(by: GridEntity, from: GridEntity, from_slot: int, to: GridEntity, to_slot: int, count := 0) -> bool:
	if not Net.is_authority():
		return false
	if not _can_handle(by) or not reaches(by, from) or not reaches(by, to):
		return false
	if from_slot < 0 or from_slot >= from.slots.size() or to_slot < 0 or to_slot >= to.slots.size():
		return false
	if from == to and from_slot == to_slot:
		return false
	var item := from.slots[from_slot]
	if item.is_empty():
		return false
	if from is Chest and (from as Chest).temple and from != to and not _collects(by, from, from_slot):
		traded.emit(by, from, "that waits for someone else")
		return false
	if from != to and soulbound(slot_uid(from, from_slot)):
		return false  # Never given to the priest, banked or sold (decision 573 amended).
	if to is Chest and (to as Chest).temple:
		return _hand_to_priest(by, from, from_slot, to)
	if to is Chest and (to as Chest).depot:
		return _each_unit(from, from_slot, count, func() -> bool: return _bank(by, from, from_slot, to))
	if to is Chest and (to as Chest).shop:
		return _each_unit(from, from_slot, count, func() -> bool: return _sell(by, from, from_slot, to))
	var uid := slot_uid(from, from_slot)
	var other_uid := slot_uid(to, to_slot)
	if from != to and (soulbound(uid) or soulbound(other_uid)):
		return false  # It stays with its player (decision 573 amended).
	# A companion may turn a thing down (decision 555: grave goods, or her
	# bond gone sullen); she says why.
	if from != to and to.has_method("turns_down") and not str(to.call("turns_down", by, uid, other_uid)).is_empty():
		return false
	# A split onto an empty slot, or units joining a stack (decision 619).
	var all := slot_count(from, from_slot)
	var some := all if count <= 0 else mini(count, all)
	if other_uid != 0 and stacks_onto(other_uid, uid, 1, false) or other_uid == 0 and some < all:
		return _move_units(by, from, from_slot, to, to_slot, some) > 0
	_fit_uids(from)
	_fit_uids(to)
	# New arrays, so each synchronizer sees a change.
	var taken := from.slots.duplicate()
	var taken_uids := from.slot_items.duplicate()
	var other := to.slots[to_slot]
	taken[from_slot] = other
	taken_uids[from_slot] = other_uid
	if from == to:
		taken[to_slot] = item
		taken_uids[to_slot] = uid
		if not hands_allow(from, taken):
			return _refused(by, from, taken)
		from.slots = taken
		from.slot_items = taken_uids
	else:
		var given := to.slots.duplicate()
		var given_uids := to.slot_items.duplicate()
		given[to_slot] = item
		given_uids[to_slot] = uid
		if not hands_allow(from, taken):
			return _refused(by, from, taken)
		if not hands_allow(to, given):
			return _refused(by, to, given)
		from.slots = taken
		from.slot_items = taken_uids
		to.slots = given
		to.slot_items = given_uids
		# Each unit of a stack goes with its first (decision 619).
		for each in [uid] + Array(items.stack_of(uid)):
			_moved_item(each, from, to)
			if to is Resident and by is Player and from != to:
				handed.emit(by, to, item, each)  # A gift to one of the town's people (decision 443).
		for each in ([other_uid] + Array(items.stack_of(other_uid))) if other_uid != 0 else []:
			_moved_item(each, to, from)
		if from is Chest and (from as Chest).temple and towns != null:
			towns.release_held(temple_town(from), owner_of(by), uid)
	_log("slots: %s moved %s from %s %d to %s %d%s" % [by.name, item, from.name, from_slot, to.name, to_slot,
		"" if other.is_empty() else " (swapping %s)" % other])
	_slots_changed(from)
	if to != from:
		_slots_changed(to)
	for side in [from, to]:
		if side is Chest:
			noise(side.tile, Senses.NOISE_RUMMAGE, &"rummage", by)
			break
	return true


## [param by] takes the thing in [param from]'s slot [param slot] out of the
## slots altogether (to the stockpile, to be eaten...): its uid, and the
## slot is empty; 0, and nothing moves, if it cannot (try_transfer's
## rules). Whoever has it now says where it is (items.place) or ends it.
func take_item(by: GridEntity, from: GridEntity, slot: int) -> int:
	if not Net.is_authority() or not _can_handle(by) or not reaches(by, from):
		return 0
	if slot < 0 or slot >= from.slots.size() or from.slots[slot].is_empty():
		return 0
	_log("slots: %s took %s out of %s %d" % [by.name, from.slots[slot], from.name, slot])
	return _take_out(from, slot)


## The thing in [param from]'s slot [param slot] out of its slots, no
## questions asked (take_item's after its rules; hurl's): its uid, the slot
## empty, nowhere till its new holder says (items.place). Of a stack
## (decision 619), one unit, the rest staying.
func _take_out(from: GridEntity, slot: int) -> int:
	if slot < 0 or slot >= from.slots.size() or from.slots[slot].is_empty():
		return 0
	if soulbound(slot_uid(from, slot)):
		return 0  # Not dropped, thrown, eaten or banked (decision 573 amended).
	var uid := _unit_out(from, slot)
	items.place(uid, "")
	_slots_changed(from)
	return uid


## [param by] puts the instance [param uid] (from the stockpile...) into
## [param to]'s empty slot [param slot], or onto the stack there it joins
## (decision 619). False, and nothing moves, if it cannot (try_transfer's
## rules; an unknown uid; a full slot).
func put_item(by: GridEntity, to: GridEntity, slot: int, uid: int) -> bool:
	if not Net.is_authority() or not _can_handle(by) or not reaches(by, to):
		return false
	var id := items.id_of(uid)
	if id.is_empty() or not Items.exists(id) or slot < 0 or slot >= to.slots.size():
		return false
	if not to.slots[slot].is_empty():
		if not stacks_onto(slot_uid(to, slot), uid):
			return false
		_join(to, slot, uid)
		var holder := _carrier_of(to)
		items.place(uid, holder_key(to), holder[0], holder[1])
		_taken(uid, to, "")
		_log("slots: %s put %s onto %s %d (%d)" % [by.name, id, to.name, slot, slot_count(to, slot)])
		_slots_changed(to)
		return true
	_fit_uids(to)
	var given := to.slots.duplicate()
	var given_uids := to.slot_items.duplicate()
	given[slot] = id
	given_uids[slot] = uid
	if not hands_allow(to, given):
		return false
	to.slots = given
	to.slot_items = given_uids
	var carrier := _carrier_of(to)
	items.place(uid, holder_key(to), carrier[0], carrier[1])
	_taken(uid, to, "")
	_log("slots: %s put %s into %s %d" % [by.name, id, to.name, slot])
	_slots_changed(to)
	return true


## Whether [param slots] (what [param entity]'s would be) keep to the
## hands: in a carrier's hands (Items.RIGHT_HAND, LEFT_HAND) only things
## that can be held; a two-handed one only in the right hand, the left
## then empty; and to the armour slot (worn_refusal). Anything else (a
## chest) has no hands.
func hands_allow(entity: GridEntity, slots: PackedStringArray) -> bool:
	if not has_hands(entity) or slots.size() < Items.HANDED:
		return true
	if not worn_refusal(entity, slots).is_empty():
		return false
	var right := slots[Items.RIGHT_HAND]
	var left := slots[Items.LEFT_HAND]
	for held in [right, left]:
		if not held.is_empty() and int(Items.def(held).get("hands", 0)) == 0:
			return false
	if not left.is_empty() and int(Items.def(left)["hands"]) == 2:
		return false
	return right.is_empty() or int(Items.def(right)["hands"]) < 2 or left.is_empty()


## Why [param slots] (what [param entity]'s would be) break the armour
## slot's rule (decision 622): only armour in it ("only armour is worn
## there"), and armour never in a hand ("armour is worn, not held"; its
## catalog hands 0 says so too); "" if they keep to it, or for anything
## without hands.
func worn_refusal(entity: GridEntity, slots: PackedStringArray) -> String:
	if not has_hands(entity) or slots.size() < Items.CARRIED:
		return ""  # No armour slot: nothing worn to keep to.
	if not slots[Items.ARMOUR].is_empty() and Items.armour_of(slots[Items.ARMOUR]).is_empty():
		return "only armour is worn there"
	for hand in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		if not slots[hand].is_empty() and not Items.armour_of(slots[hand]).is_empty():
			return "armour is worn, not held"
	return ""


## False, a move refused: [param by] is told why if it broke the armour
## slot's rule for [param entity]'s [param slots] (slot_refused).
## [param by] equips what is in [param carrier]'s pack slot [param slot]
## (decision 722; Jeff: "double click equips item, for weapons that swaps
## weapon into the correct hand, for armor that swaps armor into armor slot.
## if you have an no inventory room it doesn't work"): armour to the armour
## slot, a shield to the left hand, a held thing to the right (a two-handed
## one empties the left too); what was there goes to the pack, into the
## slot it left and then the first free ones. A hand or the armour slot
## given: it is taken off into the pack. [param carrier] is [param by] or a
## companion it reaches. "" when done, else why (said through slot_refused);
## nothing moves then. Server only.
func try_equip(by: GridEntity, carrier: GridEntity, slot: int) -> String:
	if not Net.is_authority() or not _can_handle(by) or not reaches(by, carrier) or not has_hands(carrier):
		return "not yours to change"
	if slot < 0 or slot >= carrier.slots.size() or carrier.slots[slot].is_empty():
		return "nothing there"
	var id := carrier.slots[slot]
	var slots := carrier.slots.duplicate()
	var uids := slot_uids(carrier)
	var why := ""
	if not Items.is_pack(slot):
		var free := free_pack_slot(carrier)
		if free < 0:
			why = "no room in your pack for the %s" % Items.name_of(id)
		else:
			slots[free] = id
			uids[free] = uids[slot]
			slots[slot] = ""
			uids[slot] = 0
	else:
		var targets: Array[int] = []  # Where it goes first, then what else must be emptied.
		if not Items.armour_of(id).is_empty():
			targets = [Items.ARMOUR]
		elif Items.has_tag(id, "shield"):
			targets = [Items.LEFT_HAND]
			if not slots[Items.RIGHT_HAND].is_empty() and int(Items.def(slots[Items.RIGHT_HAND]).get("hands", 1)) == 2:
				targets.append(Items.RIGHT_HAND)
		elif int(Items.def(id).get("hands", 0)) == 2:
			targets = [Items.RIGHT_HAND, Items.LEFT_HAND]
		elif int(Items.def(id).get("hands", 0)) == 1:
			targets = [Items.RIGHT_HAND]
		else:
			why = "the %s can't be held or worn" % Items.name_of(id)
		if why.is_empty():
			var out_ids: Array[String] = []
			var out_uids: Array[int] = []
			for target in targets:
				if not slots[target].is_empty():
					out_ids.append(slots[target])
					out_uids.append(uids[target])
					slots[target] = ""
					uids[target] = 0
			slots[targets[0]] = id
			uids[targets[0]] = uids[slot]
			slots[slot] = ""
			uids[slot] = 0
			for i in out_ids.size():
				var into := slot if i == 0 else -1
				if into < 0:
					for each: int in Items.PACK_SLOTS:
						if each < slots.size() and slots[each].is_empty():
							into = each
							break
				if into < 0:
					why = "no room in your pack for the %s" % Items.name_of(out_ids[i])
					break
				slots[into] = out_ids[i]
				uids[into] = out_uids[i]
	if why.is_empty() and not hands_allow(carrier, slots):
		why = worn_refusal(carrier, slots)
		if why.is_empty():
			why = "the %s can't be held so" % Items.name_of(id)
	if not why.is_empty():
		slot_refused.emit(by, why)
		return why
	carrier.slots = slots
	carrier.slot_items = uids
	_log("slots: %s equipped %s on %s from %d" % [by.name, id, carrier.name, slot])
	_slots_changed(carrier)
	return ""


func _refused(by: GridEntity, entity: GridEntity, slots: PackedStringArray) -> bool:
	var why := worn_refusal(entity, slots)
	if not why.is_empty():
		slot_refused.emit(by, why)
	return false


## The armour [param entity] wears (decision 622): Items.armour_of its
## armour slot's thing, {look, stats}; {} for none. What reads a stat
## (combat's deflections, the bow's draw) reads this.
func worn_armour(entity: GridEntity) -> Dictionary:
	if not is_instance_valid(entity) or entity.slots.size() <= Items.ARMOUR:
		return {}
	return Items.armour_of(entity.slots[Items.ARMOUR])


## [param amount] of a blow on [param target] after its worn armour's
## [param stat] (decision 622, combat's side: "deflect_shot" for a shot,
## after a shield; "deflect_pierce" for a backstab or a reach verb's blow,
## after the guard): that share turned, rounded, at least 1 through. 0
## stays 0; no armour, the amount.
func armour_turns(target: GridEntity, amount: int, stat: String) -> int:
	var share := clampf(float(worn_armour(target).get(stat, 0.0)), 0.0, 1.0)
	if amount <= 0 or share <= 0.0:
		return amount
	return maxi(1, amount - roundi(amount * share))


## The share of its breath [param entity]'s whole load leaves it (decision
## 676, in place of 622's armour kg / 100): 1 over load_scale of the arms'
## and the body's together against its own mass; 1 under load_free.
func load_breath(entity: GridEntity) -> float:
	return 1.0 / load_scale(entity.load_arms + entity.load_body, load_capacity(entity))


## A weapon (a thing with a verb) lying on [param monster]'s cell or a
## cell beside it in reach, that it has a free hand for (decision 347):
## that cell, else NO_CELL. Cheap: at most nine ground lookups. For the
## monster's AI to ask before try_pick_up_weapon.
func weapon_near(monster: GridEntity) -> Vector2i:
	if not monster is Monster or not monster.spawned:
		return NO_CELL
	for cell: Vector2i in [monster.tile] + Array(DIRECTIONS).map(func(d: Vector2i) -> Vector2i: return monster.tile + d):
		if not zone.ground.has(cell) or cell != monster.tile and not can_melee(monster.tile, cell):
			continue
		if _weapon_index(monster, cell) >= 0:
			return cell
	return NO_CELL


## The first weapon in the pile on [param cell] that [param monster] has a
## free hand for and lifts (its kind's "lifts"), by its index there; -1 for none.
func _weapon_index(monster: GridEntity, cell: Vector2i) -> int:
	var ids := ground_at(cell)
	var uids := ground_uids(cell)
	var lifts: float = (monster as Monster).lifts if monster is Monster else INF
	for i in ids.size():
		if not Items.verb_of(ids[i]).is_empty() and _free_hand(monster, ids[i]) >= 0 and not axe_bound(uids[i]) \
				and Items.weight_of(ids[i]) <= lifts:
			return i
	return -1


## The hand [param entity] could hold [param id] in (Items.RIGHT_HAND,
## LEFT_HAND), -1 for none: a two-handed thing only with both hands empty,
## in the right; a monster with no hands yet has both free.
func _free_hand(entity: GridEntity, id: String) -> int:
	var hands := int(Items.def(id).get("hands", 0))
	if hands == 0:
		return -1
	var right := entity.slots[Items.RIGHT_HAND] if entity.slots.size() >= Items.HANDED else ""
	var left := entity.slots[Items.LEFT_HAND] if entity.slots.size() >= Items.HANDED else ""
	if not right.is_empty() and int(Items.def(right).get("hands", 1)) == 2:
		return -1
	if hands == 2:
		return Items.RIGHT_HAND if right.is_empty() and left.is_empty() else -1
	if right.is_empty():
		return Items.RIGHT_HAND
	return Items.LEFT_HAND if left.is_empty() else -1


## [param monster] takes up a weapon lying beside it (weapon_near) into a
## free hand (decision 347): its slots become a carrier's if they were
## not (the pack, then the hands; decision 338), the thing's history says
## who took it up, and it weighs on the monster's mass. The monster's AI
## decides when (a monster kind's "picks_up"). False, cheaply, with none
## near or no free hand.
func try_pick_up_weapon(monster: GridEntity) -> bool:
	if not Net.is_authority() or not monster is Monster or not monster.spawned or monster.hp <= 0 or is_stunned(monster):
		return false
	var cell := weapon_near(monster)
	if cell == NO_CELL:
		return false
	var index := _weapon_index(monster, cell)
	var id := ground_at(cell)[index]
	var hand := _free_hand(monster, id)
	var uid := take_from_ground(cell, index)
	if uid == 0:
		return false
	if monster.slots.size() != Items.CARRIED:
		var kept := Items.tidy(monster.slots, Items.CARRIED)
		_fit_uids(monster)
		var uids := monster.slot_items.duplicate()
		uids.resize(Items.CARRIED)
		monster.slots = kept
		monster.slot_items = uids
	var given := monster.slots.duplicate()
	var given_uids := monster.slot_items.duplicate()
	given[hand] = id
	given_uids[hand] = uid
	monster.slots = given
	monster.slot_items = given_uids
	items.place(uid, holder_key(monster), holder_key(monster), _label_of(monster))
	items.note(uid, "taken up", "by %s" % _label_of(monster), zone.name, monster.tile)
	_taken(uid, monster, "")
	_log("pick up: %s takes up %s from %s" % [monster.name, id, cell])
	_slots_changed(monster)
	return true


## A player or a companion: something with hands (Items.HANDED slots or more).
func has_hands(entity: GridEntity) -> bool:
	return (entity is Player or entity.keeper_peer != 0) and entity.slots.size() >= Items.HANDED


## Whether [param entity] fights with what is in its hands: one with hands
## (has_hands), or a monster given them (its kind's or its entry's
## "wields", Level; decision 338). Only for fighting: a monster's hands are
## not a carrier's (nobody hands it things or bandages it).
func holds_in_hands(entity: GridEntity) -> bool:
	return has_hands(entity) or entity is Monster and entity.slots.size() >= Items.HANDED


## The verb [param attacker]'s blow is struck with (decision 338): its
## wielded weapon's (Items.verb_of), or its kind's own with it (a monster's
## row's "blows", 603 amended: the draugr's axe), but for a bow, which is
## no club (its numbers are the shot's); {} for bare hands.
func blow_verb(attacker: GridEntity) -> Dictionary:
	var id := wielded(attacker)
	var own: Variant = (attacker as Monster).blows.get(id) if attacker is Monster and not id.is_empty() else null
	var verb: Dictionary = own if own is Dictionary else Items.verb_of(id)
	return {} if verb.get("kind") == "ranged" else verb


## [param attacker]'s time between blows: its attack_ticks times its
## weapon's speed (blow_verb; a dagger quicker, a giant axe slower).
func attack_ticks_of(attacker: GridEntity) -> int:
	return maxi(1, roundi(attacker.attack_ticks * float(blow_verb(attacker).get("speed", 1.0))))


## Whether [param attacker] stands behind [param target]: on the side
## away from where it faces (as a flanker's backstab reads it).
func is_behind(attacker: GridEntity, target: GridEntity) -> bool:
	return (body_centre(attacker) - body_centre(target)).dot(Vector2(target.facing)) < 0.0  # Centres (699).


## [param entity]'s slots changed: its mass follows what it carries (its
## base_mass and the things' weights), a stance whose thing left the hand
## ends, and slots_changed is emitted.
func _slots_changed(entity: GridEntity) -> void:
	_show_counts(entity)
	var worn: Variant = entity.get("worn")
	if worn is String:
		var now := entity.slots[Items.ARMOUR] if entity.slots.size() > Items.ARMOUR else ""
		if now != worn:
			entity.set("worn", now)  # The armour worn, replicated for the views (decision 622).
	_weigh(entity)
	if not entity.raised.is_empty() and off_hand(entity) != entity.raised:
		entity.raised = ""  # What it needed left the hand.
	_show_notes(entity)
	slots_changed.emit(entity)


## [param entity]'s mass: its base_mass (taken the first time) and what its
## slots hold (a chest, fixed in place, stays as it is).
func _weigh(entity: GridEntity) -> void:
	if entity.base_mass < 0.0:
		entity.base_mass = entity.mass
	var carried := 0.0
	if not entity is Chest:
		for slot in entity.slots.size():
			carried += Items.weight_of(entity.slots[slot]) * slot_count(entity, slot)  # Each unit (decision 619).
	entity.mass = entity.base_mass + carried + buff(entity, "mass")
	var load := load_of(entity)
	entity.load_arms = load["arms"]
	entity.load_body = load["body"]


## What [param entity] carries where (decision 676), kg to 0.1: {arms: its
## hands' things and its armour's arm share ("on": {arms, body} in the
## armour's row; none given, all on the body), body: the rest of its armour
## and its pack}. A chest carries nothing: it stands.
func load_of(entity: GridEntity) -> Dictionary:
	var arms := 0.0
	var body := 0.0
	if not entity is Chest:
		for slot in entity.slots.size():
			var kg := Items.weight_of(entity.slots[slot]) * slot_count(entity, slot)
			if slot == Items.LEFT_HAND or slot == Items.RIGHT_HAND:
				arms += kg
			elif slot == Items.ARMOUR:
				var share := clampf(float(Items.armour_of(entity.slots[slot]).get("on", {}).get("arms", 0.0)), 0.0, 1.0)
				arms += kg * share
				body += kg * (1.0 - share)
			else:
				body += kg
	return {"arms": snappedf(arms, 0.1), "body": snappedf(body, 0.1)}


## What [param entity]'s load is measured against (decision 676): its own
## mass, without what it carries or has eaten (the base mass the server
## takes; a client, which never weighs, has the spawned mass, the same).
func load_capacity(entity: GridEntity) -> float:
	return maxf(entity.base_mass if entity.base_mass > 0.0 else entity.mass, 1.0)


## The multiple a load of [param kg] against [param capacity] kg slows what
## it carries by (decision 676): 1 + load_k x its share past load_free; 1
## under it.
func load_scale(kg: float, capacity: float) -> float:
	return 1.0 + load_k * maxf(0.0, kg / maxf(capacity, 0.001) - load_free)


## [param entity]'s walk's multiple from its body's load (decision 676).
func walk_load(entity: GridEntity) -> float:
	return load_scale(entity.load_body, load_capacity(entity))


## [param entity]'s draw's multiple from its arms' load (decision 676):
## plate's arm share on top of a bow and arrows draws slower.
func arms_load(entity: GridEntity) -> float:
	return load_scale(entity.load_arms, load_capacity(entity) * ARMS_SHARE)


## The band [param entity]'s whole load is in (decision 676), for the pack
## sheet: "light", "burdened", "heavy" or "overloaded".
func load_band(entity: GridEntity) -> String:
	var share := (entity.load_arms + entity.load_body) / load_capacity(entity)
	if share < load_free:
		return "light"
	if share < load_heavy:
		return "burdened"
	return "heavy" if share < load_overloaded else "overloaded"


## Takes everything out of [param container] at once (economy banking a
## cart that reached the stockpile; a crate breaking): their uids, the
## slots empty. Whoever has them now says where they are (or ends them).
func empty_container(container: GridEntity) -> Array[int]:
	var uids: Array[int] = []
	if not Net.is_authority() or not is_instance_valid(container):
		return uids
	for slot in container.slots.size():
		var uid := slot_uid(container, slot)
		if uid != 0:
			var more := items.stack_of(uid)
			items.set_stack(uid, PackedInt32Array())
			for each in [uid] + Array(more):
				items.place(each, "")
				uids.append(each)
	if uids.is_empty():
		return uids
	var empty := PackedStringArray()
	empty.resize(container.slots.size())
	var none := PackedInt32Array()
	none.resize(container.slots.size())
	container.slots = empty
	container.slot_items = none
	_log("slots: %s emptied of %d things" % [container.name, uids.size()])
	_slots_changed(container)
	return uids


## The instance in [param entity]'s slot [param slot]: 0 for an empty slot;
## made now (ItemBook.mint, "stocked" there) for a thing that has none yet,
## as a level's chest has until someone first needs it.
func slot_uid(entity: GridEntity, slot: int) -> int:
	if slot < 0 or slot >= entity.slots.size() or entity.slots[slot].is_empty():
		return 0
	_fit_uids(entity)
	var uid := entity.slot_items[slot]
	if uid != 0 and items.id_of(uid) == entity.slots[slot]:
		return uid
	uid = items.mint(entity.slots[slot], "stocked", _label_of(entity), entity.zone, entity.tile, style_from(entity))
	items.mark_grave(uid, grave_from(entity), entity.zone, entity.tile)  # Decision 555.
	var carrier := _carrier_of(entity)
	items.place(uid, holder_key(entity), carrier[0], carrier[1])
	entity.slot_items[slot] = uid
	return uid


## The make of what [param entity] holds or keeps (decision 474): its
## props' "style" (a level's item_style, or its marker's own, put there by
## Level); "" for none.
static func style_from(entity: GridEntity) -> String:
	var props: Variant = entity.spawn_spec.get("props", {}) if is_instance_valid(entity) else {}
	return str(props.get("style", "")) if props is Dictionary else ""


## The grave goods source [param entity] is (decision 555): its label when
## its props say "grave" (a level's grave_goods, or its marker's own, put
## there by Level), else "".
func grave_from(entity: GridEntity) -> String:
	var props: Variant = entity.spawn_spec.get("props", {}) if is_instance_valid(entity) else {}
	return _label_of(entity) if props is Dictionary and props.get("grave") == true else ""


## Every slot's instance (slot_uid), made where missing: what a save keeps.
func slot_uids(entity: GridEntity) -> PackedInt32Array:
	for slot in entity.slots.size():
		slot_uid(entity, slot)
	return entity.slot_items.duplicate()


# --- Stacks (decision 619) ------------------------------------------------------

## Every unit in [param entity]'s [param slot] (decision 619): its first
## (slot_uid) and those stacked with it; none for an empty slot.
func slot_units(entity: GridEntity, slot: int) -> Array[int]:
	var units: Array[int] = []
	var first := slot_uid(entity, slot)
	if first != 0:
		units.append(first)
		units.append_array(Array(items.stack_of(first)))
	return units


## How many things [param entity]'s [param slot] holds: 0 empty, 1 alone,
## more for a stack (decision 619). Any peer: a client reads slot_counts.
func slot_count(entity: GridEntity, slot: int) -> int:
	if slot < 0 or slot >= entity.slots.size() or entity.slots[slot].is_empty():
		return 0
	if not Net.is_authority() or items == null:
		return entity.slot_counts[slot] if slot < entity.slot_counts.size() else 1
	var first := entity.slot_items[slot] if slot < entity.slot_items.size() else 0
	return 1 + (items.stack_of(first).size() if first != 0 else 0)


## [param entity]'s units of [param id] (decision 619), slot by slot:
## what a price in things (the healer's 5 herbs) is paid from.
func units(entity: GridEntity, id: String) -> Array[int]:
	var found: Array[int] = []
	for slot in entity.slots.size():
		if entity.slots[slot] == id:
			found.append_array(slot_units(entity, slot))
	return found


## How many [param id] [param entity] carries, stacks counted unit by unit.
func count_of(entity: GridEntity, id: String) -> int:
	var count := 0
	for slot in entity.slots.size():
		if entity.slots[slot] == id:
			count += slot_count(entity, slot)
	return count


## The slot of [param entity]'s that unit [param uid] is in, first or
## stacked; -1 for none.
func slot_of_unit(entity: GridEntity, uid: int) -> int:
	if uid == 0:
		return -1
	for slot in entity.slots.size():
		if uid in slot_units(entity, slot):
			return slot
	return -1


## Takes [param uids], each one of [param entity]'s units (units), out of
## its slots: those taken, nowhere till their new holder says.
func take_units(entity: GridEntity, uids: Array[int]) -> Array[int]:
	var taken: Array[int] = []
	for uid in uids:
		var slot := slot_of_unit(entity, uid)
		if slot >= 0 and not soulbound(uid) and _unit_out(entity, slot, uid) == uid:
			items.place(uid, "")
			taken.append(uid)
	if not taken.is_empty():
		_slots_changed(entity)
	return taken


## Whether the instance [param uid] may join the stack [param first] heads
## (decision 619): the same kind, one that stacks, both clean alike (no
## name, binding, curse, blessing or mark, the same style and grave), and,
## if [param room], [param more] more fit.
func stacks_onto(first: int, uid: int, more := 1, room := true) -> bool:
	if first == 0 or uid == 0 or first == uid or not items.has(first) or not items.has(uid):
		return false
	var id := items.id_of(first)
	if id != items.id_of(uid) or Items.stack_of(id) <= 1:
		return false
	if not _plain(first) or not _plain(uid) or items.style_of(first) != items.style_of(uid) \
			or items.grave_of(first) != items.grave_of(uid) or items.is_starter(first) != items.is_starter(uid):
		return false  # Starter gear (736) stacks only with its own kind, so a stack is all one or the other.
	return not room or 1 + items.stack_of(first).size() + more <= Items.stack_of(id)


## Whether [param uid] has nothing of its own a stack would hide.
func _plain(uid: int) -> bool:
	return items.name_of(uid).is_empty() and items.bound_to(uid).is_empty() and items.kept_from(uid).is_empty() \
		and items.blessed_for(uid).is_empty() and items.bane_of(uid).is_empty() and items.grudge_of(uid).is_empty() \
		and items.short_of(uid) >= 1.0 and items.condition_of(uid) < 0


## [param uid] joins the stack in [param entity]'s [param slot] (stacks_onto
## said it may); the caller places it and says the slots changed.
func _join(entity: GridEntity, slot: int, uid: int) -> void:
	var first := slot_uid(entity, slot)
	var more := items.stack_of(first)
	more.append(uid)
	items.set_stack(first, more)


## One unit out of [param entity]'s [param slot] (decision 619): [param uid]
## if given, else the stack's last; the slot empty once its last unit goes,
## its next the first when the first goes. Its uid (0: nothing there); the
## caller places it and says the slots changed.
func _unit_out(entity: GridEntity, slot: int, uid := 0) -> int:
	var first := slot_uid(entity, slot)
	if first == 0:
		return 0
	var more := items.stack_of(first)
	if uid == 0:
		uid = more[more.size() - 1] if not more.is_empty() else first
	if uid != first:
		var at := more.find(uid)
		if at < 0:
			return 0
		more.remove_at(at)
		items.set_stack(first, more)
		return uid
	var left := entity.slots.duplicate()
	var left_uids := entity.slot_items.duplicate()
	items.set_stack(first, PackedInt32Array())
	if more.is_empty():
		left[slot] = ""
		left_uids[slot] = 0
	else:
		left_uids[slot] = more[0]
		items.set_stack(more[0], more.slice(1))
	entity.slots = left
	entity.slot_items = left_uids
	return first


## [param some] units from [param from]'s [param from_slot] into [param to]'s
## [param to_slot], empty or a stack they join, while there is room: how
## many moved (try_transfer's split and join).
func _move_units(by: GridEntity, from: GridEntity, from_slot: int, to: GridEntity, to_slot: int, some: int) -> int:
	var id := from.slots[from_slot]
	if to.slots[to_slot].is_empty():
		var trial := to.slots.duplicate()
		trial[to_slot] = id
		if not hands_allow(to, trial):
			return 0
	var moved := 0
	while moved < some and slot_count(from, from_slot) > 0:
		var uid := slot_uid(from, from_slot)
		var more := items.stack_of(uid)
		uid = more[more.size() - 1] if not more.is_empty() else uid
		if not to.slots[to_slot].is_empty() and not stacks_onto(slot_uid(to, to_slot), uid):
			break
		_unit_out(from, from_slot, uid)
		if to.slots[to_slot].is_empty():
			var given := to.slots.duplicate()
			var given_uids := to.slot_items.duplicate()
			given[to_slot] = id
			given_uids[to_slot] = uid
			to.slots = given
			to.slot_items = given_uids
		else:
			_join(to, to_slot, uid)
		if from != to:
			_moved_item(uid, from, to)
			if to is Resident and by is Player:
				handed.emit(by, to, id, uid)  # Decision 443, a unit at a time.
		moved += 1
	if moved == 0:
		return 0
	_log("slots: %s moved %d %s from %s %d to %s %d" % [by.name, moved, id, from.name, from_slot, to.name, to_slot])
	_slots_changed(from)
	if to != from:
		_slots_changed(to)
	return moved


## Does [param one] (a counter's take of one unit) up to [param count] times
## (0: the whole stack) while [param from]'s [param from_slot] holds some:
## whether any was done.
func _each_unit(from: GridEntity, from_slot: int, count: int, one: Callable) -> bool:
	var some := slot_count(from, from_slot) if count <= 0 else mini(count, slot_count(from, from_slot))
	var done := 0
	while done < some and slot_count(from, from_slot) > 0 and bool(one.call()):
		done += 1
	return done > 0


## [param entity]'s slot_counts (replicated) follow its stacks: empty while
## no slot holds more than one (decision 619).
func _show_counts(entity: GridEntity) -> void:
	var counts := PackedInt32Array()
	counts.resize(entity.slots.size())
	var any := false
	for slot in entity.slots.size():
		counts[slot] = slot_count(entity, slot)
		any = any or counts[slot] > 1
	if not any:
		counts = PackedInt32Array()
	if counts != entity.slot_counts:
		entity.slot_counts = counts


## A new [param id] bound for life to [param owner] (a holder_key; decision
## 544), minted for [param entity] (who it is made for, the companion's
## token's bearer or the player) at [param at_zone] [param tile]. Its uid,
## not yet in any slot: put_item places it.
func mint_bound(id: String, owner: String, entity: GridEntity, at_zone := "", tile := Vector2i(-1, -1)) -> int:
	var uid := items.mint(id, "bound", _label_of(entity) if is_instance_valid(entity) else "", at_zone, tile)
	items.bind(uid, owner, at_zone, tile)
	return uid


## The Encolpion Amulet (decision 573 amended; 714: Jeff, "amulet replaces
## the draugr deal but works the same way"; it was the Draugr's Totem, and
## a saved totem reads as one, Items.RENAMED): the one item that holds a
## player's resurrection charges.
const TOTEM := "encolpion_amulet"
## A holy knight's remains (decision 714): won in the barrow's sepulcher,
## bound to its finder, given to Aldous to charge the amulet.
const RELIC := "holy_remains"


## A relic of [param knight], won at deal [param tier], minted bound to
## [param finder] (decision 714; dungeon's sepulcher puts it in its slots).
## Its uid, not yet in any slot; 0 for no finder. Server only.
func mint_relic(knight: String, tier: int, finder: GridEntity) -> int:
	if not Net.is_authority() or not is_instance_valid(finder):
		return 0
	var uid := mint_bound(RELIC, holder_key(finder), finder, finder.zone, finder.tile)
	items.mark_relic(uid, knight, tier)
	return uid


## The knight and tier [param uid] carries, if it is a relic: {knight,
## tier}, else {} (decision 714). Read it before consume ends the uid.
func relic_of(uid: int) -> Dictionary:
	return items.relic_of(uid) if items.id_of(uid) == RELIC else {}


## [param uid] taken out of [param entity]'s slots and ended, [param why]
## its last event (decision 714: a relic laid on the altar), past the
## soulbound rule that keeps it from any other taking. False, nothing done,
## when [param entity] does not hold it. Server only.
func consume(entity: GridEntity, uid: int, why: String) -> bool:
	if not Net.is_authority() or uid == 0 or not is_instance_valid(entity):
		return false
	for slot in entity.slots.size():
		if slot_uid(entity, slot) == uid or uid in items.stack_of(slot_uid(entity, slot)):
			if _unit_out(entity, slot, uid) != uid:
				return false
			_slots_changed(entity)
			items.end(uid, why)
			return true
	return false


## [param player_id]'s amulet gone, wherever it is (ui's quest reset; 672
## amended, items' side): ended "reset", out of the slots that hold it. What
## was cleared, a line each; [] for none. Won again, it is minted again.
func reset_totem(player_id: String) -> Array[String]:
	var cleared: Array[String] = []
	if not Net.is_authority() or player_id.is_empty():
		return cleared
	var uid := totem_of(player_id)
	while uid != 0:
		var line := "%s (uid %d, %d charges)" % [Items.name_of(TOTEM), uid, items.charges_of(uid)]
		var held := false
		for entity: GridEntity in get_entities():
			if consume(entity, uid, "reset"):
				held = true
				break
		if not held:
			items.end(uid, "reset")
		cleared.append(line + " taken")
		uid = totem_of(player_id)
	return cleared


## Whether [param uid] never leaves its bound carrier (tag "soulbound",
## bound: the Draugr's Totem): never traded, given, sold, dropped, thrown
## or taken out of their slots (try_transfer, take_item), and kept through
## a death, as everything a player carries is.
func soulbound(uid: int) -> bool:
	return uid != 0 and Items.has_tag(items.id_of(uid), "soulbound") and not items.bound_to(uid).is_empty()


## [param player_id]'s Draugr's Totem, wherever it is: its uid, 0 for
## none.
func totem_of(player_id: String) -> int:
	var owner := "player:" + player_id
	for uid: int in items._book:
		if items.id_of(uid) == TOTEM and items.bound_to(uid) == owner:
			return uid
	return 0


## The charges [param uid] (a totem) holds.
func totem_charges(uid: int) -> int:
	return items.charges_of(uid)


## One of [param uid]'s charges spent: false, and nothing spent, at none.
func totem_spend(uid: int) -> bool:
	if items.charges_of(uid) <= 0:
		return false
	items.set_charges(uid, items.charges_of(uid) - 1)
	_totem_shown(uid)
	return true


## [param amount] charges put on [param uid] up to [param capacity]: how
## many it took (the rest spill, decision 573).
func totem_add(uid: int, amount: int, capacity: int) -> int:
	if not items.has(uid) or amount <= 0:
		return 0
	var took := clampi(capacity - items.charges_of(uid), 0, amount)
	items.set_charges(uid, items.charges_of(uid) + took)
	_totem_shown(uid)
	return took


## [param player]'s Draugr's Totem: theirs if they have one, else a new
## one, bound to them for life and put in their pack (with no room, the
## pack's last thing goes to the ground at their feet; the totem never
## does). Its uid; 0 for no player.
func mint_totem(player: GridEntity) -> int:
	var player_id: Variant = player.get("player_id") if is_instance_valid(player) else null
	if not Net.is_authority() or player_id is not String or str(player_id).is_empty():
		return 0
	var have := totem_of(player_id)
	if have != 0:
		return have
	var uid := mint_bound(TOTEM, holder_key(player), player, player.zone, player.tile)
	items.set_charges(uid, 0)
	var slot := into_pack(player, uid)
	_log("totem: %s's Draugr's Totem in slot %d" % [player.name, slot])
	return uid


## [param uid] put in [param player]'s pack: its first free slot, else the
## last pack slot holding nothing soulbound, what was there put down at
## their feet; never a bound thing moved. A pack all bound: [param uid] put
## down at their feet itself (still bound, theirs alone to take), -1. The
## slot it went in. Server only: the amulet's (573 amended) and the
## sepulcher's relic (714, dungeon's side (2)).
func into_pack(player: GridEntity, uid: int) -> int:
	var slot := free_pack_slot(player)
	if slot < 0:
		var pack := Items.PACK_SLOTS.filter(func(i: int) -> bool: return i < player.slots.size())
		pack.reverse()
		var plain := pack.filter(func(i: int) -> bool: return not soulbound(slot_uid(player, i)))
		if plain.is_empty():
			put_on_ground(uid, player.tile)
			return -1
		slot = plain[0]
		var out := slot_uid(player, slot)
		var slots := player.slots.duplicate()
		var uids := slot_uids(player)
		slots[slot] = ""
		uids[slot] = 0
		set_slots(player, slots, uids)
		put_on_ground(out, player.tile)
	put_item(player, player, slot, uid)
	return slot


## The slot notes of whoever carries [param uid] said again: its charges
## changed.
func _totem_shown(uid: int) -> void:
	for entity in _entities:
		if is_instance_valid(entity) and uid in entity.slot_items:
			_show_notes(entity)
			return


## Whether [param entity] carries, in any slot, an [param id] bound to
## [param owner] (decision 544): a half bound to anyone else does nothing.
func carries_bound(entity: GridEntity, id: String, owner: String) -> bool:
	if not is_instance_valid(entity) or owner.is_empty():
		return false
	for slot in entity.slots.size():
		if entity.slots[slot] == id and items.bound_to(slot_uid(entity, slot)) == owner:
			return true
	return false


## Where [param entity]'s things are, in an item's history: "player:<id>",
## "companion:<keeper id>:<name>", or "<zone>/<name>".
func holder_key(entity: GridEntity) -> String:
	var player_id: Variant = entity.get("player_id")
	if player_id is String and not player_id.is_empty():
		return "player:" + player_id
	var keeper_id: Variant = entity.get("keeper_id")
	if keeper_id is String and not keeper_id.is_empty():
		return "companion:%s:%s" % [keeper_id, entity.name]
	if entity is Monster and not (entity as Monster).named_id.is_empty():
		return "named:" + (entity as Monster).named_id  # Decision 716: the same holder every life.
	return "%s/%s" % [entity.zone, entity.name]


## Whether [param entity] is a named holder, who can name what it carries
## (decision 365): a player or a companion, or a named enemy (716). Any
## other monster is known by its kind.
func _names_things(entity: GridEntity) -> bool:
	var who := _carrier_of(entity)[0]
	return who.begins_with("player:") or who.begins_with("companion:") or who.begins_with("named:")


# --- Named enemies (decision 716) -------------------------------------------------

## [param id]'s record, made (NamedEnemy.new_record, of [param kind]) at
## its first spawn.
func named_enter(id: String, kind: String) -> Dictionary:
	if not named.has(id):
		named[id] = NamedEnemy.new_record(id, kind)
		print("[named] %s is %s, strength %s" % [id, named[id]["name"], named[id]["strength"]])
	return named[id]


## [param id]'s record (npc reads its card, memories and track); {} for none.
func named_record(id: String) -> Dictionary:
	return named.get(id, {})


## [param id]'s record set (npc writes its card, memories and track). Its
## strength stays what it was: it never grows.
func set_named_record(id: String, record: Dictionary) -> void:
	if not named.has(id):
		return
	var strength: Variant = named[id].get("strength")
	named[id] = record.duplicate(true)
	named[id]["strength"] = strength


## Whether a level slot's spawn [param spec] may spawn now: a named one
## alive, or its days dead past (NamedEnemy.rise_steps from its death). Any
## other spawn may.
func named_may_rise(spec: Dictionary) -> bool:
	var id := str(spec.get("named", ""))
	if id.is_empty() or not named.has(id) or bool(named[id].get("alive", true)):
		return true
	return steps >= int(named[id].get("returns_at", 0))


## [param monster] (a named one) has [param kind] (named_event's) with
## [param other]: told when other is a player; met and fought once a life.
func named_note(monster: Monster, kind: String, other: GridEntity) -> void:
	if not is_instance_valid(other) or not other is Player or monster.named_id.is_empty():
		return
	var player_id := str(other.get("player_id"))
	if kind in ["met", "fought"]:
		if monster.named_noted.has(kind + "/" + player_id):
			return
		monster.named_noted[kind + "/" + player_id] = true
	named_event.emit(monster.named_id, kind, player_id)


## A blow between a named one and a player: fought, each way, and killed
## when the named one's blow brought the player to 0.
func _named_fight(target: GridEntity, source: GridEntity) -> void:
	if target is Monster and not (target as Monster).named_id.is_empty():
		named_note(target as Monster, "fought", source)
	elif source is Monster and not (source as Monster).named_id.is_empty():
		named_note(source as Monster, "fought", target)
		if target.hp == 0:
			named_note(source as Monster, "killed", target)


## [param monster] (a named one) dies: its weapon kept for its next life,
## its record dead till NamedEnemy.rise_steps on, killed_by told. Its
## trophy (its row's "trophy", 714), struck down by a player for
## whom it is due (trophy_due), is not kept: it falls with the rest of it.
func _named_fell(monster: Monster, by: GridEntity) -> void:
	var trophy := str(NamedEnemy.def(monster.named_id).get("trophy", ""))
	var player_id := _trophy_winner(by)
	if not trophy.is_empty() and monster.slots.size() > Items.RIGHT_HAND and monster.slots[Items.RIGHT_HAND] == trophy \
			and not player_id.is_empty() and _trophy_due(player_id, monster.named_id, trophy):
		_trophy_taken(player_id, monster.named_id, trophy)
		print("[named] %s's %s falls for %s" % [monster.named_id, trophy, player_id])
	else:
		_keep_named_weapon(monster)
	var record := named_enter(monster.named_id, str(monster.spawn_spec.get("kind", "")))
	record["alive"] = false
	record["returns_at"] = steps + NamedEnemy.rise_steps(monster.named_id)
	print("[named] %s fell, rises at step %d" % [record["name"], record["returns_at"]])
	named_note(monster, "killed_by", by)


## [param monster]'s right hand's thing out of its hands and kept for it
## (NamedEnemy.KEPT): never dropped, its time held stopped till it rises.
func _keep_named_weapon(monster: Monster) -> void:
	var uid := slot_uid(monster, Items.RIGHT_HAND)
	if uid == 0:
		return
	var slots := monster.slots.duplicate()
	var uids := monster.slot_items.duplicate()
	slots[Items.RIGHT_HAND] = ""
	uids[Items.RIGHT_HAND] = 0
	monster.slots = slots
	monster.slot_items = uids
	_slots_changed(monster)
	items.place(uid, NamedEnemy.KEPT % monster.named_id)
	named_enter(monster.named_id, str(monster.spawn_spec.get("kind", "")))["weapon_uid"] = uid


## [param monster] (a named one) in the world: up again if it was dead (rose
## told), its kept weapon back in its right hand in place of what its spawn
## gave it. Its trophy (its row's "trophy", 714), when due to be
## won (trophy_due with no player), is made for its hand instead, unless
## the one it kept is the trophy; else it has its kept one, or its kind's.
func _named_arrived(monster: Monster) -> void:
	var record := named_enter(monster.named_id, str(monster.spawn_spec.get("kind", "")))
	record["level"] = zone.name
	if not bool(record.get("alive", true)):
		record["alive"] = true
		record["lives"] = int(record.get("lives", 1)) + 1
		print("[named] %s rose, life %d" % [record["name"], record["lives"]])
		named_event.emit(monster.named_id, "rose", "")
	if monster.slots.size() <= Items.RIGHT_HAND:
		return
	var uid := int(record.get("weapon_uid", 0))
	var kept := uid != 0 and items.has(uid) and items.at_of(uid) == NamedEnemy.KEPT % monster.named_id
	var trophy := str(NamedEnemy.def(monster.named_id).get("trophy", ""))
	if not trophy.is_empty() and not (kept and items.id_of(uid) == trophy) and _trophy_due("", monster.named_id, trophy):
		_named_hand(monster, items.mint(trophy, "stocked", _label_of(monster), zone.name, monster.tile), "its trophy in its hand")
	elif kept:
		_named_hand(monster, uid, "its named holder's own came back")


## [param uid] in [param monster]'s right hand, what its spawn gave it there
## ended ([param why]).
func _named_hand(monster: Monster, uid: int, why: String) -> void:
	_fit_uids(monster)
	var given := monster.slot_items[Items.RIGHT_HAND]
	if given != 0 and given != uid and items.has(given):
		items.end(given, "lost", why, zone.name, monster.tile)
	var slots := monster.slots.duplicate()
	var uids := monster.slot_items.duplicate()
	slots[Items.RIGHT_HAND] = items.id_of(uid)
	uids[Items.RIGHT_HAND] = uid
	monster.slots = slots
	monster.slot_items = uids
	var carrier := _carrier_of(monster)
	items.place(uid, holder_key(monster), carrier[0], carrier[1])
	_slots_changed(monster)


## The player a named one's trophy falls for when [param by] strikes it
## down: a player, or a companion's keeper; "" for anyone else.
func _trophy_winner(by: GridEntity) -> String:
	if not is_instance_valid(by):
		return ""
	if by is Player:
		return str((by as Player).player_id)
	if by is Companion and is_instance_valid((by as Companion).keeper) and (by as Companion).keeper is Player:
		return str(((by as Companion).keeper as Player).player_id)
	return ""


## Whether [param named_id]'s [param trophy] is due to [param player_id]
## ("" for anyone: is it out to be won), by Main.trophy_due (714:
## once per barrow generation; Jeff's pick may make it once a day per
## player there, nowhere else). Without Main, once ever.
func _trophy_due(player_id: String, named_id: String, trophy: String) -> bool:
	if trophy_due.is_valid():
		return bool(trophy_due.call(player_id, named_id, trophy))
	return not named_record(named_id).has("trophy_won")


## [param named_id]'s [param trophy] won by [param player_id]: Main's
## trophy_taken keeps it; without Main, its record does.
func _trophy_taken(player_id: String, named_id: String, trophy: String) -> void:
	if trophy_taken.is_valid():
		trophy_taken.call(player_id, named_id, trophy)
	elif named.has(named_id):
		named[named_id]["trophy_won"] = 0


## [param entity] did a deed of [param kind] (Items.DEEDS) with the thing
## in its slot [param slot] (decision 365): its carrier row counts it, and
## the thing may take its name now.
func _credit(entity: GridEntity, slot: int, kind: String) -> void:
	if not Net.is_authority() or not is_instance_valid(entity) or not _names_things(entity) \
			or slot < 0 or slot >= entity.slot_items.size() or entity.slot_items[slot] == 0:
		return
	items.deed(entity.slot_items[slot], _carrier_of(entity)[0], kind)
	_consider_name(entity, slot)


## Every slot of [param entity]'s that may take a name (_consider_name).
func _consider_names(entity: GridEntity) -> void:
	for slot in mini(entity.slots.size(), entity.slot_items.size()):
		if entity.slot_items[slot] != 0:
			_consider_name(entity, slot)


## The gear in [param entity]'s slot [param slot] takes its name for life
## (decision 365) when its carrier has held it Items.naming()'s held_days
## of the world clock and done its deeds with it (ItemBook.name_due): lore's
## first holder form at name_least (Lore.name_forms), filled with the
## carrier's name, and the strength of its most-done deed
## (Items.strength_from). No form counting yet (none agreed): no name.
func _consider_name(entity: GridEntity, slot: int) -> void:
	var uid := entity.slot_items[slot]
	var id := items.id_of(uid)
	if not Items.is_gear(id) or not items.name_of(uid).is_empty():
		return
	var naming := Items.naming()
	var due := items.name_due(uid, roundi(float(naming["held_days"]) * DayNight.day_steps), int(naming["deeds"]),
			int(naming.get("deeds_alone", 0)))
	if due.is_empty() or str(due["name"]).is_empty():
		return
	var earned := not items.grows(uid)
	if earned:
		# Its character comes with the threshold, named or not yet (decision 472).
		items.give_character(uid, "named", entity.zone, entity.tile)
	var forms := Lore.name_forms("holder", name_least)
	var name := {"form": str(forms[0]["id"]), "holder": str(due["name"]), "who": str(due["who"]), "made_step": steps} if not forms.is_empty() else {}
	var text := Lore.render_name(name, id, PackedStringArray(Items.def(id)["tags"]), Items.name_of(id), name_least) if not name.is_empty() else ""
	if text.is_empty():
		if earned:
			item_grew.emit(entity, uid, "character", "")  # No name to tell it by yet.
		return
	name["text"] = text
	var strength := Items.strength_from(due["deeds"])
	items.set_name(uid, name, strength, entity.zone, entity.tile)
	_log("named: %s's %s is %s%s" % [entity.name, id, text, " (%s)" % strength if not strength.is_empty() else ""])
	_show_notes(entity)
	item_named.emit(entity, uid, text)


## How [param uid] reads where it is shown (decision 365): its name,
## rendered for what it is now (a reforged thing keeps its name), and its
## strength ("Wren's dagger (quiet)"); "" for a thing with no name.
func item_title(uid: int) -> String:
	if not relic_of(uid).is_empty():
		return "the holy remains of %s" % relic_of(uid)["knight"]  # Decision 714.
	var name := items.name_of(uid)
	if name.is_empty():
		return ""
	var id := items.id_of(uid)
	var text := Lore.render_name(name, id, PackedStringArray(Items.def(id)["tags"]), Items.name_of(id), name_least)
	if text.is_empty():
		text = str(name.get("text", ""))
	var marks: Array[String] = []
	if not items.strength_of(uid).is_empty():
		marks.append(items.strength_of(uid))
	if not items.kept_from(uid).is_empty():
		marks.append(KEPT_MARK)  # Kept from its namer (decision 370).
	return text + (" (%s)" % ", ".join(marks) if not marks.is_empty() else "")


## [param uid] came into [param to]'s slots, from [param from_key]'s hand
## ("" for none: the ground, a chest, the stockpile; decision 370): a
## named thing taken by anyone but its namer, not from its namer's hand,
## is kept from its namer; one that reaches its namer's hands is back.
func _taken(uid: int, to: GridEntity, from_key: String) -> void:
	var namer := str(items.name_of(uid).get("who", ""))
	var taker := _carrier_of(to)[0]
	if taker.is_empty() or taker == from_key:
		return
	# A blessed thing (decision 424): given by its owner, the blessing goes
	# with it; taken by anyone else, it is lost, and it may be kept again.
	var owner := items.blessed_for(uid)
	if not owner.is_empty() and taker != owner:
		if from_key == owner:
			items.pass_blessing(uid, taker)
			return
		items.unbless(uid, to.zone, to.tile)
		_log("blessing: %s's %s is no longer blessed" % [to.name, items.id_of(uid)])
	elif not owner.is_empty():
		return  # Back with whom it is blessed for.
	if namer.is_empty():
		return
	if taker == namer:
		if not items.kept_from(uid).is_empty():
			items.lift(uid, to.zone, to.tile)
			_log("kept: %s is back with %s" % [items.id_of(uid), to.name])
			item_kept.emit(to, uid, false)
		return
	if not items.kept_from(uid).is_empty() or from_key == namer:
		return  # Kept already; or a gift.
	items.keep(uid, taker, _label_of(to), to.zone, to.tile)
	_log("kept: %s keeps %s from its namer" % [to.name, items.id_of(uid)])
	item_kept.emit(to, uid, true)


## The most ill (decision 370; ItemBook.ill_of) [param entity] has from
## the things it carries now, 0..1. What it does waits on Jeff (Items.curse()'s
## below_baseline); nothing reads it yet.
func ill_of(entity: GridEntity) -> float:
	var who := _carrier_of(entity)[0]
	var most := 0.0
	if who.is_empty():
		return most
	for uid in entity.slot_items:
		if uid != 0:
			most = maxf(most, items.ill_of(uid, who))
	return most


## [param entity]'s slot_notes (replicated) follow its things' names
## (decision 365) and conditions (decision 375): "bundle of arrows, 6 of
## 10", "Wren's bow (quick)".
func _show_notes(entity: GridEntity) -> void:
	var names := PackedStringArray()
	names.resize(entity.slots.size())
	var any := false
	for slot in mini(entity.slots.size(), entity.slot_items.size()):
		if entity.slot_items[slot] != 0:
			names[slot] = item_note(entity.slot_items[slot])
			# A stack's count is drawn on its slot from slot_counts (619, ui's
			# side), not said in the note. The tally (decision 415) and the
			# story (decision 421), each on a line of its own under the
			# thing's name, found by its first word.
			for line in [kills_line(entity.slot_items[slot]), story_line(entity.slot_items[slot]), starter_line(entity.slot_items[slot])]:
				if not line.is_empty():
					names[slot] = "%s\n%s" % [names[slot] if not names[slot].is_empty() else Items.name_of(entity.slots[slot]), line]
			any = any or not names[slot].is_empty()
	if not any:
		names = PackedStringArray()
	if names != entity.slot_notes:
		entity.slot_notes = names


## How [param uid] reads in a slot's note: its title (item_title) and its
## condition ("bundle of arrows, 6 of 10"; decision 375); "" for a plain
## thing.
func item_note(uid: int) -> String:
	var note := item_title(uid)
	var more := PackedStringArray()
	if not items.style_of(uid).is_empty():
		if note.is_empty():
			note = "%s %s" % [items.style_of(uid), Items.name_of(items.id_of(uid))]  # "dwarven dagger" (decision 474).
		else:
			more.append(items.style_of(uid))
	if items.condition_of(uid) >= 0:
		more.append("%d of %d" % [items.condition_of(uid), Items.condition_max(items.id_of(uid))])
	if items.short_of(uid) < 1.0:
		more.append("short measure")  # Decision 493.
	if not items.bound_to(uid).is_empty():
		more.append("bound")  # Decision 544.
	if items.is_grave(uid):
		more.append("grave goods")  # Decision 555.
	if items.id_of(uid) == TOTEM:
		more.append("%d charge%s" % [items.charges_of(uid), "" if items.charges_of(uid) == 1 else "s"])  # Decision 573 amended.
	if not items.bane_of(uid).is_empty():
		more.append("%s-bane" % items.bane_of(uid))  # Decision 417.
	if not items.grudge_of(uid).is_empty():
		more.append("vengeance on %s" % _plural(str(items.grudge_of(uid)["kind"])))
	if not items.blessed_for(uid).is_empty():
		more.append("blessed")  # Decision 424.
	if not more.is_empty():
		note = "%s, %s" % [note if not note.is_empty() else Items.name_of(items.id_of(uid)), ", ".join(more)]
	return note  # A kind's "about" is the tip's (ui's ItemTip), not the note's.


## What [param uid] has felled, as its slot's note shows it (decision 415):
## "felled 14: 9 imps, 4 wolves, 1 brute", the most first; "" for nothing.
func kills_line(uid: int) -> String:
	var felled := items.felled_of(uid)
	if felled.is_empty():
		return ""
	var kinds: Array = felled.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return felled[a] > felled[b] or felled[a] == felled[b] and a < b)
	var parts := PackedStringArray()
	var total := 0
	for kind: String in kinds:
		total += int(felled[kind])
		parts.append("%d %s" % [felled[kind], kind if int(felled[kind]) == 1 else _plural(kind)])
	return "felled %d: %s" % [total, ", ".join(parts)]


## [param uid]'s starter line, as its slot's note shows it on a line of its
## own (decision 736): "starter gear: no one will buy it"; "" for anything else.
func starter_line(uid: int) -> String:
	return "starter gear: no one will buy it" if items.is_starter(uid) else ""


## [param uid]'s story, as its slot's note shows it (decision 421, for
## ui's tooltip): "story: carried by Wren for 3 days; named for Wren; kept
## from Wren", from its history: its longest carrier (a day or more, in the
## world clock's days), its naming or else how it came to be (made, hunted),
## a keeping, its vengeances. Parts dropped from the end until it is at most
## STORY_LONGEST; "" for nothing to tell.
func story_line(uid: int) -> String:
	var history := items.history(uid)
	if history.is_empty():
		return ""
	var parts := PackedStringArray()
	var rows: Array = history["carriers"].filter(func(row: Dictionary) -> bool: return not str(row.get("name", "")).is_empty())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["held"]) > int(b["held"]))
	var days := int(rows[0]["held"]) / maxi(DayNight.day_steps, 1) if not rows.is_empty() else 0
	if days >= 1:
		parts.append("carried by %s for %d day%s" % [rows[0]["name"], days, "" if days == 1 else "s"])
	var name := items.name_of(uid)
	if not name.is_empty():
		parts.append("named for %s" % name["holder"])
	else:
		var origin := ""
		for event: Dictionary in history["events"]:
			if origin.is_empty() and event["kind"] == "made" and not str(event["what"]).is_empty():
				origin = "made by %s" % event["what"]
			elif origin.is_empty() and event["kind"] == "cached" and not str(event["what"]).is_empty():
				origin = "found in %s" % event["what"]  # A cache's find (decision 599).
			elif origin.is_empty() and event["kind"] == "hunted":
				origin = "from %s's hunt" % event["what"] if not str(event["what"]).is_empty() else "from a hunt"
		if not origin.is_empty():
			parts.append(origin)
	if not items.style_of(uid).is_empty():
		parts.append("%s work" % items.style_of(uid))  # Decision 474.
	if items.short_of(uid) < 1.0:
		parts.append("short measure")  # Decision 493.
	if items.is_grave(uid):
		parts.append("taken from the grave")  # Decision 555.
	if not items.kept_from(uid).is_empty() and not name.is_empty():
		parts.append("kept from %s" % name["holder"])
	if not items.blessed_for(uid).is_empty():
		parts.append("blessed at the temple")  # Decision 424.
	for event: Dictionary in history["events"]:
		if event["kind"] == "reforged":
			parts.append("reforged from a %s" % Items.name_of(str(event["what"]).get_slice(" into ", 0)))  # Decision 432.
			break
	for event: Dictionary in history["events"]:
		if event["kind"] == "avenged":
			parts.append("avenged on %s" % _plural(str(event["what"])))
	while not parts.is_empty() and ("story: " + "; ".join(parts)).length() > STORY_LONGEST:
		parts.remove_at(parts.size() - 1)
	return "" if parts.is_empty() else "story: " + "; ".join(parts)


## The kind a body felled counts as (decision 415): a monster's or an
## animal's own (its spawn kind), "person" for a player or a companion; ""
## for anything else.
func kind_of(entity: GridEntity) -> String:
	if entity is Player or entity is Companion:
		return "person"
	if entity is Monster:
		return str(entity.spawn_spec.get("kind", ""))
	return ""


static func _plural(kind: String) -> String:
	match kind:
		"person":
			return "people"
		"wolf":
			return "wolves"
		"deer", "sheep":
			return kind
	return kind + "s"


## The thing in [param entity]'s slot [param slot] felled [param victim]
## (decision 415): its tally counts it, whoever holds it, and its note shows it.
func _felled_with(entity: GridEntity, slot: int, victim: GridEntity) -> void:
	if not is_instance_valid(entity) or slot < 0 or slot >= entity.slot_items.size() or entity.slot_items[slot] == 0:
		return
	var uid := entity.slot_items[slot]
	var kind := kind_of(victim)
	items.fell(uid, kind)
	# Growth (decision 417): enough of one kind and it is their bane; one of
	# its grudge's kind pays the grudge down.
	var growth := Items.growth()
	if not kind.is_empty() and items.bane_of(uid).is_empty() and int(items.felled_of(uid).get(kind, 0)) >= int(growth["bane_after"]):
		items.set_bane(uid, kind, zone.name, entity.tile)
		_log("growth: %s's %s is %s-bane" % [entity.name, items.id_of(uid), kind])
		item_grew.emit(entity, uid, "bane", kind)
		items.drop_grudge(uid, zone.name, entity.tile)  # One growth per thing (decision 473).
	if not kind.is_empty() and str(items.grudge_of(uid).get("kind", "")) == kind \
			and items.pay_grudge(uid, int(growth["grudge_paid"]), zone.name, entity.tile):
		_log("growth: %s's %s has its vengeance on %s" % [entity.name, items.id_of(uid), _plural(kind)])
		item_grew.emit(entity, uid, "avenged", kind)
	_show_notes(entity)


## Whether a thing in [param entity]'s hands is the bane of [param kind]
## (decision 417): that kind dreads its bearer and notices it further
## (Items.growth's bane_notice); enemy-ai reads it, as holder_dread.
func holder_bane(entity: GridEntity, kind: String) -> bool:
	if kind.is_empty():
		return false  # No kind (a monster without one): nothing is its bane or grudge.
	return _in_hands_any(entity, func(uid: int) -> bool: return items.bane_of(uid) == kind)


## The kinds the things in [param entity]'s hands are the bane of (decision
## 417); none for a monster.
func banes_held(entity: GridEntity) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(entity) or entity is Monster or not holds_in_hands(entity):
		return out
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		if slot < entity.slot_items.size() and entity.slot_items[slot] != 0:
			var kind := items.bane_of(entity.slot_items[slot])
			if not kind.is_empty() and kind not in out:
				out.append(kind)
	return out


## Whether a thing in [param entity]'s hands holds a grudge against
## [param kind] (decision 417): that kind seeks its bearer first (enemy-ai
## reads it), and its blows stagger them.
func holder_grudge(entity: GridEntity, kind: String) -> bool:
	if kind.is_empty():
		return false  # No kind (a monster without one): nothing is its bane or grudge.
	return _in_hands_any(entity, func(uid: int) -> bool: return str(items.grudge_of(uid).get("kind", "")) == kind)


## Whether [param test] holds for a thing in [param entity]'s hands.
func _in_hands_any(entity: GridEntity, test: Callable) -> bool:
	if not is_instance_valid(entity) or not holds_in_hands(entity):
		return false
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		if slot < entity.slot_items.size() and entity.slot_items[slot] != 0 and test.call(entity.slot_items[slot]):
			return true
	return false


## [param who] (a player or a companion) lost [param amount] hp to
## [param by] (decisions 417, 473): each thing with character in its hands
## counts the harm by [param by]'s kind (ItemBook.hurt), and takes a grudge
## against it once that kind has done it Items.growth's grudge_after, more
## than any other kind has. One growth per thing: a bane takes no grudge.
func _take_grudges(who: GridEntity, by: GridEntity, amount: int) -> void:
	if not (who is Player or who is Companion) or not by is Monster or not holds_in_hands(who):
		return
	var kind := kind_of(by)
	if kind.is_empty() or amount <= 0:
		return
	var after := int(Items.growth()["grudge_after"])
	var took := false
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		var uid := who.slot_items[slot] if slot < who.slot_items.size() else 0
		if uid == 0 or not items.grows(uid):
			continue
		items.hurt(uid, kind, amount)
		if not items.grudge_of(uid).is_empty() or not items.bane_of(uid).is_empty():
			continue
		var tally := items.hurt_of(uid)
		var most := int(tally.get(kind, 0))
		if most < after or tally.values().any(func(hp: Variant) -> bool: return int(hp) > most):
			continue
		items.set_grudge(uid, kind, zone.name, who.tile)
		_log("growth: %s's %s takes a grudge against %s" % [who.name, items.id_of(uid), _plural(kind)])
		item_grew.emit(who, uid, "grudge", kind)
		took = true
	if took:
		_show_notes(who)


## The strength (decision 365) of the thing in [param entity]'s slot
## [param slot]; "" for none. Whoever holds it, a monster too.
func slot_strength(entity: GridEntity, slot: int) -> String:
	if not is_instance_valid(entity) or slot < 0 or slot >= entity.slot_items.size() or entity.slot_items[slot] == 0:
		return ""
	return items.strength_of(entity.slot_items[slot])


## Whether [param entity] holds a thing with the dread strength (decision
## 365; a namer's felled most): for enemy-ai, which decides how a cautious
## or cowardly monster takes it.
func holder_dread(entity: GridEntity) -> bool:
	if not holds_in_hands(entity):
		return false
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		if bool(Items.strength_value(slot_strength(entity, slot), "dread", false)):
			return true
	return false


## [param entity] leaves the world (despawn): a named holder's things stop
## counting its time held until it is back (set_slots places them again),
## so time away names nothing (decision 365).
func _let_go_things(entity: GridEntity) -> void:
	if not _names_things(entity):
		return
	for uid in entity.slot_items:
		if uid != 0:
			items.place(uid, items.at_of(uid))


## Ends, as lost, what the room's level entities held when it was reset
## (reset) and the rebuild did not put back (set_slots). Main calls it
## once the room is rebuilt.
func end_unclaimed_items() -> void:
	for uid in _unclaimed:
		if items.has(uid) and items.at_of(uid).is_empty():
			items.end(uid, "lost", "", zone.name)
	_unclaimed.clear()


func steps_now() -> int:
	return steps


## A player, or a companion (keeper_peer: not named, companion.gd uses
## World), alive: who may move things.
func _can_handle(by: GridEntity) -> bool:
	return is_instance_valid(by) and by.spawned and by.hp > 0 and (by is Player or by.keeper_peer != 0)


## [carrier key, name] for an item's history: "" for a chest (a place, not
## a carrier).
func _carrier_of(entity: GridEntity) -> Array[String]:
	if entity is Chest or entity is Cargo:
		return ["", ""]
	return [holder_key(entity), _label_of(entity)]


func _label_of(entity: GridEntity) -> String:
	var label := str(entity.spawn_spec.get("label", ""))
	return label if not label.is_empty() else String(entity.name)


## slot_items as long as slots (0 for none yet).
func _fit_uids(entity: GridEntity) -> void:
	if entity.slot_items.size() != entity.slots.size():
		entity.slot_items.resize(entity.slots.size())


## [param uid] went from [param from]'s slots to [param to]'s: where it is
## now, and the history: "found" the first time anyone carries it, "given"
## from one carrier to another.
func _moved_item(uid: int, from: GridEntity, to: GridEntity) -> void:
	var giver := _carrier_of(from)
	var taker := _carrier_of(to)
	var carried_before: bool = not items.history(uid).get("carriers", []).is_empty()
	items.place(uid, holder_key(to), taker[0], taker[1])
	_taken(uid, to, giver[0])
	if taker[0].is_empty() or giver[0] == taker[0]:
		return
	if not giver[0].is_empty():
		items.note(uid, "given", "%s to %s" % [giver[1], taker[1]], to.zone, to.tile)
		item_given.emit(from, to, uid)
	elif not carried_before:
		items.note(uid, "found", "%s by %s" % [_label_of(from), taker[1]], from.zone, from.tile)


## Whether [param by] can get at [param entity]'s slots: its own; a chest
## in its zone next to it with no wall or closed door between; or, within
## COMPANION_REACH and in sight, a player's own companion's pack or a
## companion's own player's.
func reaches(by: GridEntity, entity: GridEntity) -> bool:
	if entity == by:
		return true
	if not is_instance_valid(entity) or not entity.spawned or entity.zone != by.zone:
		return false
	if entity is Chest or entity is Cargo:
		return can_melee(by.tile, entity.tile)
	var near := entity.hp > 0 and distance(by.tile, entity.tile) <= COMPANION_REACH and has_line_of_sight(by.tile, entity.tile)
	if entity.keeper_peer != 0:  # A companion (not named: companion.gd uses World).
		return by.owner_peer != 0 and entity.keeper_peer == by.owner_peer and near
	if entity is Player and by.keeper_peer != 0:
		return entity.owner_peer == by.keeper_peer and near
	return false


## [param by] puts [param from]'s [param from_slot] into [param depot]: banked
## in the stockpile its tile is in, the slot emptied, if the town holds that
## stockpile; refused (false, nothing moves) if not. A resource item
## (Items.yield_of) is banked as its yield and its instance ended; gear is
## banked as itself, its instance kept at the store.
func _bank(by: GridEntity, from: GridEntity, from_slot: int, depot: GridEntity) -> bool:
	if from == depot:
		return false
	var area := depot.zone if not depot.zone.is_empty() else zone.name
	var place := Stockpile.place_at(holdings, area, depot.tile)
	var item := from.slots[from_slot]
	var yields := Items.yield_of(item)
	if stockpile == null or place.is_empty() \
			or yields.keys().any(func(what: Variant) -> bool: return str(what) not in Stockpile.RESOURCES):
		_log("slots: %s refused %s: no stockpile the town holds there" % [depot.name, item])
		return false
	var uid := slot_uid(from, from_slot)
	if not yields.is_empty() and items.is_grave(uid) and owner_of(by).begins_with("player:"):
		_log("slots: %s refused %s: grave goods, only the fence takes them" % [depot.name, item])  # 586.
		return false
	uid = _unit_out(from, from_slot)  # One of a stack (decision 619).
	_bank_thing(place, uid, _label_of(by), _label_of(from), depot.zone, depot.tile, owner_of(by))
	_log("slots: %s banked %s from %s %d at %s" % [by.name, item, from.name, from_slot, place])
	_slots_changed(from)
	return true


## Banks the instance [param uid] (held by nothing now) at stockpile
## [param place], brought [param who] someone from [param from]: a resource
## item as its yield (its instance ended, "banked"), gear as itself.
func _bank_thing(place: String, uid: int, who: String, from: String, at_zone: String, tile: Vector2i, by_id := "") -> void:
	var yields := items.yields_of(uid)  # A short one's share (decision 493).
	if yields.is_empty():
		stockpile.bank(place, uid, who, from, at_zone, tile, "banked", by_id)
		return
	# A player's raw goods (or their companion's) are a sale at the delivery
	# price (decision 498; Jeff: "players bank goods for gold"). A counter
	# sale has no by_id: it was paid there.
	if economy != null and by_id.begins_with("player:"):
		var player_id := by_id.trim_prefix("player:")
		var paid := economy.bank_sale(place, player_id, yields)
		if paid > 0:
			add_gold(player_id, paid, "banked %s" % [yields])
	for what: String in yields:
		stockpile.deposit(place, what, int(yields[what]), who, from, by_id)
	items.end(uid, "banked", "%s by %s" % [place, who], at_zone, tile)


## Gives player [param player_id] [param amount] gold (taken, under 0) for
## [param why]: gold picked up ("picked up"), a sale... Their gold now; 0
## with no economy (a client). The one way players' gold changes.
func add_gold(player_id: String, amount: int, why := "") -> int:
	if economy == null or player_id.is_empty():
		return 0
	var now_gold := economy.add_gold(player_id, amount, why)
	gold_changed.emit(player_id, now_gold)
	return now_gold


## [param from_id] gives [param to_id] [param amount] gold (614,
## Economy.give_gold): gold_changed for both. The amount given, 0 if none.
func give_gold(from_id: String, to_id: String, amount: int, from_name := "", to_name := "") -> int:
	if economy == null:
		return 0
	var given := economy.give_gold(from_id, to_id, amount, from_name, to_name)
	if given > 0:
		gold_changed.emit(from_id, economy.gold(from_id))
		gold_changed.emit(to_id, economy.gold(to_id))
	return given


## Player [param player_id]'s gold (0 on a client).
func gold_of(player_id: String) -> int:
	return economy.gold(player_id) if economy != null else 0


## Shop counter [param shop]'s fence state (decision 586): the counter
## in the fence's town nearest his home (residents.json settled) is his,
## Economy.FENCE_NIGHT by night, FENCE_DAY by day; "" for any other, or with
## the fence away.
func fence_state(shop: GridEntity) -> String:
	var place := shop_place(shop)
	var by := economy.fence_by() if economy != null and not place.is_empty() else ""
	var entry: Dictionary = Townsfolk.settled().get(by, {}) if not by.is_empty() else {}
	var home: Variant = entry.get("home", [])
	if str(entry.get("town", "")) != place or not home is Array or (home as Array).size() < 2:
		return ""
	var at := Vector2i(int(home[0]), int(home[1]))
	var nearest: GridEntity = null
	for each in get_entities():
		if each is Chest and (each as Chest).shop and each.zone == shop.zone and shop_place(each) == place \
				and (nearest == null or distance(each.tile, at) < distance(nearest.tile, at)
					or distance(each.tile, at) == distance(nearest.tile, at) and str(each.name) < str(nearest.name)):
			nearest = each
	if nearest != shop:
		return ""
	return Economy.FENCE_NIGHT if economy.is_night() else Economy.FENCE_DAY


## The town's place a shop counter [param shop] stands in, if the town
## holds it: "" if not.
func shop_place(shop: GridEntity) -> String:
	if not shop is Chest or not (shop as Chest).shop or stockpile == null:
		return ""
	return Stockpile.place_at(holdings, shop.zone if not shop.zone.is_empty() else zone.name, shop.tile)


# --- The temple counter (decision 434) ----------------------------------------------

## The town temple counter [param counter] is in ("" if none).
func temple_town(counter: GridEntity) -> String:
	if counter_town.is_valid():
		return str(counter_town.call(counter))
	return Stockpile.place_at(holdings, counter.zone if not counter.zone.is_empty() else zone.name, counter.tile)


## Whose a thing [param by] hands in is, as a carrier key: a player's own;
## a companion's, her player's (it goes back to them).
func owner_of(by: GridEntity) -> String:
	var keeper_id: Variant = by.get("keeper_id")
	if not by is Player and keeper_id is String and not keeper_id.is_empty():
		return "player:" + keeper_id
	return holder_key(by)


## Whether [param by] may take what is in temple counter [param counter]'s
## [param slot]: it is held for them.
func _collects(by: GridEntity, counter: GridEntity, slot: int) -> bool:
	return towns != null and slot_uid(counter, slot) in towns.held(temple_town(counter), owner_of(by))


## What kind of counter [param counter] is: "temple", "shop" or "".
func counter_kind(counter: GridEntity) -> String:
	if counter is Chest and (counter as Chest).temple:
		return "temple"
	if counter is Chest and (counter as Chest).shop:
		return "shop"
	return ""


## The town of counter [param counter] ("" for none).
func counter_place(counter: GridEntity) -> String:
	match counter_kind(counter):
		"temple":
			return temple_town(counter)
		"shop":
			return shop_place(counter)
	return ""


## The offering for blessing a thing of [param id] (rules' bless).
func bless_offering(id: String) -> int:
	var rule: Dictionary = production.rules.get("bless", {})
	return maxi(ceili(float(economy.value_of(id)) * float(rule.get("offering", 0.5))), int(rule.get("least", 1)))


## The fee for reforging into [param to_id] (rules' reforge, decision 438).
func reforge_fee(to_id: String) -> int:
	var rule: Dictionary = production.rules.get("reforge", {})
	return maxi(ceili(float(economy.value_of(to_id)) * float(rule.get("fee", 0.5))), int(rule.get("least", 1)))


## The workshop a counter's work is done at: a temple's priest, a shop
## counter's smith (his building's, Towns.kind_for).
func _counter_workshop(counter: GridEntity, town: String) -> String:
	if counter_kind(counter) == "temple":
		return "%s:temple" % town
	var trade := str(production.rules.get("reforge", {}).get("trade", "smith"))
	var kind := towns.kind_for(trade) if towns != null else ""
	return "%s:%s" % [town, kind if not kind.is_empty() else trade]


## Player [param by] at counter [param counter] (decision 438, ui's
## counter screen): what can be done to each thing they carry, priced,
## {counter, kind, town, gold, jobs: [{slot, uid, id, effect, to_id, price,
## materials, steps, ok, why}], working: [{uid, id, effect, to_id, left,
## left_seconds}], waiting: [{uid, id, effect}], why}.
func counter_view(by: GridEntity, counter: GridEntity, why := "") -> Dictionary:
	var town := counter_place(counter)
	var owner := owner_of(by)
	var who := owner.trim_prefix("player:")
	var out := {"counter": str(counter.get_path()), "kind": counter_kind(counter), "town": town,
		"gold": economy.gold(who) if economy != null else 0, "jobs": [], "working": [], "waiting": [], "why": why}
	if town.is_empty() or production == null or economy == null:
		return out
	var workshop := _counter_workshop(counter, town)
	var manned := production.manned(workshop)
	for slot in by.slots.size():
		var id := str(by.slots[slot])
		if id.is_empty():
			continue
		var uid := slot_uid(by, slot)
		if out["kind"] == "temple":
			var price := bless_offering(id)
			var whyn := "" if manned else "there is no priest at the temple now"
			if whyn.is_empty() and economy.gold(who) < price:
				whyn = "the offering is %d gold" % price
			out["jobs"].append({"slot": slot, "uid": uid, "id": id, "effect": "bless", "to_id": id, "price": price,
				"materials": {}, "steps": int(production.rules.get("bless", {}).get("steps", 600)), "ok": whyn.is_empty(), "why": whyn})
			continue
		for to_id in Items.reforge_targets(id):
			var cost := Items.reforge_cost(id, to_id)
			var price := reforge_fee(to_id)
			out["jobs"].append({"slot": slot, "uid": uid, "id": id, "effect": "reforge", "to_id": to_id, "price": price,
				"materials": cost["from"], "steps": int(cost["steps"]), "ok": true, "why": ""})
			var entry: Dictionary = out["jobs"].back()
			entry["why"] = _reforge_refusal(by, uid, town, workshop, cost, price)
			entry["ok"] = str(entry["why"]).is_empty()
	for id in production.jobs():
		var job := production.job(id)
		if job.get("kind") == "work" and str(job.get("for", "")) == owner and job.get("town") == town:
			var left := maxi(int(job["needed"]) - int(job["worked"]), 0)
			var worked_on: int = job["uids"][0] if not (job["uids"] as Array).is_empty() else 0
			out["working"].append({"uid": worked_on, "id": items.id_of(worked_on), "effect": job["effect"], "to_id": job["to_id"],
				"left": left, "left_seconds": roundi(left * TICK_DT)})
	if towns != null:
		for uid in towns.held(town, owner):
			out["waiting"].append({"uid": uid, "id": items.id_of(uid), "effect": "bless" if items.blessed_for(uid) == owner else "reforge"})
	return out


## Why [param by] can't have [param uid] reforged at [param town] now
## ("" if they can).
func _reforge_refusal(by: GridEntity, uid: int, town: String, workshop: String, cost: Dictionary, fee: int) -> String:
	if items.name_of(uid).is_empty():
		return "only a named thing can be reforged"
	if not production.manned(workshop):
		return "there is no smith at the forge now"
	for what: String in cost.get("from", {}):
		var short := int(cost["from"][what]) - stockpile.count(town, what)
		if short > 0:
			return "the town lacks %d %s" % [short, what]
	if economy.gold(owner_of(by).trim_prefix("player:")) < fee:
		return "the fee is %d gold" % fee
	return ""


## Player [param by] orders [param effect] ("bless", "reforge" into
## [param to_id]) on what is in their [param slot] at [param counter]: ""
## if it was taken, else why not.
func counter_order(by: GridEntity, counter: GridEntity, slot: int, effect: String, to_id := "") -> String:
	if not Net.is_authority() or not reaches(by, counter) or slot < 0 or slot >= by.slots.size() or str(by.slots[slot]).is_empty():
		return "nothing to hand over"
	var kind := counter_kind(counter)
	if effect == "bless" and kind == "temple":
		_counter_why = ""
		return "" if _hand_to_priest(by, by, slot, counter) else _counter_why
	if effect != "reforge" or kind != "shop":
		return "that is not done here"
	var town := counter_place(counter)
	var owner := owner_of(by)
	var id := str(by.slots[slot])
	var uid := slot_uid(by, slot)
	if to_id not in Items.reforge_targets(id):
		return "a %s can't become that" % Items.name_of(id)
	var cost := Items.reforge_cost(id, to_id)
	var fee := reforge_fee(to_id)
	var workshop := _counter_workshop(counter, town)
	var why := _reforge_refusal(by, uid, town, workshop, cost, fee)
	if not why.is_empty():
		return why
	var who := owner.trim_prefix("player:")
	var taken := by.slots.duplicate()
	var taken_uids := by.slot_items.duplicate()
	taken[slot] = ""
	taken_uids[slot] = 0
	if production.open_work(workshop, uid, "reforge", owner, to_id, cost["from"], int(cost["steps"]), fee, who) == 0:
		return "there is no smith at the forge now"
	by.slots = taken
	by.slot_items = taken_uids
	economy.add_gold(who, -fee, "a reforge at %s" % town)
	stockpile.deposit(town, "gold", fee, "reforge:%s" % who, "a fee for a reforge")
	items.note(uid, "handed in", "at %s's forge by %s, to be a %s, %d gold paid" % [town, _label_of(by), Items.name_of(to_id), fee],
		counter.zone, counter.tile)
	_log("forge: %s handed in %s at %s to become %s for %d gold" % [by.name, id, town, to_id, fee])
	_slots_changed(by)
	gold_changed.emit(who, economy.gold(who))
	return ""


## Player [param by] collects [param uid], held for them at
## [param counter]'s town, into their first free slot: "" if they did,
## else why not.
func counter_collect(by: GridEntity, counter: GridEntity, uid: int) -> String:
	if not Net.is_authority() or not reaches(by, counter) or towns == null:
		return "nothing to collect here"
	var town := counter_place(counter)
	var owner := owner_of(by)
	if uid not in towns.held(town, owner):
		return "that waits for someone else"
	var slots := by.slots.duplicate()
	var free := -1
	for i in slots.size():
		if str(slots[i]).is_empty():
			slots[i] = items.id_of(uid)
			if hands_allow(by, slots):
				free = i
				break
			slots[i] = ""
	if free < 0:
		return "no room to carry it"
	# If the counter shows it (a temple's slots), it leaves there first.
	_fit_uids(counter)
	var shown := Array(counter.slot_items).find(uid)
	if shown >= 0:
		var counter_slots := counter.slots.duplicate()
		var counter_uids := counter.slot_items.duplicate()
		counter_slots[shown] = ""
		counter_uids[shown] = 0
		counter.slots = counter_slots
		counter.slot_items = counter_uids
		_slots_changed(counter)
	_fit_uids(by)
	var uids := by.slot_items.duplicate()
	uids[free] = uid
	by.slots = slots
	by.slot_items = uids
	towns.release_held(town, owner, uid)
	_moved_item(uid, counter, by)
	_log("counter: %s collected %s at %s" % [by.name, items.id_of(uid), town])
	_slots_changed(by)
	return ""


## [param by] hands [param from]'s [param from_slot] to the priest at
## temple counter [param counter], with an offering (rules' bless.offering
## of its value, at least bless.least) from their player's gold into the
## treasury: a bless job (Production.open_work), the thing held for them
## when done (Towns). Refused, nothing moves, and they are told why: no
## priest there, or not enough gold.
func _hand_to_priest(by: GridEntity, from: GridEntity, from_slot: int, counter: GridEntity) -> bool:
	var town := temple_town(counter)
	var owner := owner_of(by)
	var who := owner.trim_prefix("player:")
	var workshop := "%s:temple" % town
	var item := from.slots[from_slot]
	if from == counter or not owner.begins_with("player:") or town.is_empty() or production == null or economy == null:
		_counter_why = "nobody takes things here"
		traded.emit(by, counter, _counter_why)
		return false
	if not production.manned(workshop):
		_counter_why = "there is no priest at the temple now"
		traded.emit(by, counter, _counter_why)
		return false
	var offering := bless_offering(item)
	if economy.gold(who) < offering:
		_counter_why = "the offering is %d gold" % offering
		traded.emit(by, counter, _counter_why)
		return false
	var uid := _unit_out(from, from_slot)  # One of a stack (decision 619).
	economy.add_gold(who, -offering, "an offering at %s's temple" % town)
	stockpile.deposit(town, "gold", offering, "offering:%s" % who, "an offering for a blessing")
	production.open_work(workshop, uid, "bless", owner)
	items.note(uid, "handed in", "at %s's temple by %s, %d gold offered" % [town, _label_of(by), offering], counter.zone, counter.tile)
	_log("temple: %s handed in %s at %s for %d gold" % [by.name, item, town, offering])
	_slots_changed(from)
	gold_changed.emit(who, economy.gold(who))
	traded.emit(by, counter, "")
	return true


## Temple counter [param counter] shows what its town holds for
## [param by] (Main, while they are within reach; null when nobody is): the
## slots not theirs put back to the town's keeping, empty ones filled with
## theirs. Only they can take them (try_transfer); what else is in it
## stays.
func show_held(counter: GridEntity, by: GridEntity) -> void:
	if towns == null or not (counter is Chest and (counter as Chest).temple):
		return
	var town := temple_town(counter)
	var mine: Array[int] = []
	if by != null:
		mine = towns.held(town, owner_of(by))
	_fit_uids(counter)
	var slots := counter.slots.duplicate()
	var uids := counter.slot_items.duplicate()
	var changed := false
	var anyone: Array[int] = []
	for each in towns.held_owners(town):
		anyone.append_array(towns.held(town, each))
	for i in slots.size():
		var uid := int(uids[i])
		# Only what the town holds for someone else goes back; anything
		# else in the counter stays as it is.
		if uid != 0 and uid in anyone and uid not in mine:
			items.place(uid, "temple:%s" % town)
			slots[i] = ""
			uids[i] = 0
			changed = true
	for uid in mine:
		if uid in uids:
			continue
		var free := slots.find("")
		if free < 0:
			break
		slots[free] = items.id_of(uid)
		uids[free] = uid
		items.place(uid, holder_key(counter))
		changed = true
	if changed:
		counter.slots = slots
		counter.slot_items = uids
		_slots_changed(counter)


## Why a shop or a maker won't take starter gear (736).
const STARTER_REFUSED := "starter gear: no one will buy it"


## A player [param by] puts [param from]'s [param from_slot] into shop
## counter [param shop]: the town buys it (Economy.sell) if it will, a raw
## banked as its yield, gear into the shop to sell on; refused (false,
## nothing moves) if it won't, and [param by] told why (traded).
func _sell(by: GridEntity, from: GridEntity, from_slot: int, shop: GridEntity) -> bool:
	var place := shop_place(shop)
	if not by is Player or (by as Player).player_id.is_empty() or place.is_empty() or economy == null:
		traded.emit(by, shop, "no shop the town holds here")
		return false
	var who := (by as Player).player_id
	var item := from.slots[from_slot]
	var uid := slot_uid(from, from_slot)
	if is_starter(uid):  # The starter vendor's (736): no one buys it back.
		traded.emit(by, shop, STARTER_REFUSED)
		return false
	var deal := economy.sell(who, place, item, items.is_grave(uid), -1, fence_state(shop))  # Grave goods: the fence's, by night (586).
	if not deal["ok"]:
		_log("shop: %s refused %s at %s: %s" % [by.name, item, place, deal["why"]])
		traded.emit(by, shop, str(deal["why"]))
		return false
	_sold(by, from, from_slot, uid, place, who, int(deal["paid"]), shop)
	gold_changed.emit(who, economy.gold(who))
	traded.emit(by, shop, "")
	return true


## [param from]'s [param from_slot], thing [param uid], sold by player
## [param who] for [param paid] gold to [param place]'s shop counter
## [param shop]: out of the slot, gear onto the shelf, a raw banked as
## its yield.
func _sold(by: GridEntity, from: GridEntity, from_slot: int, uid: int, place: String, who: String, paid: int,
		shop: GridEntity) -> void:
	var item := from.slots[from_slot]
	_unit_out(from, from_slot, uid)  # That unit, of a stack (decision 619).
	if Items.yield_of(item).is_empty():
		items.place(uid, "")
		items.note(uid, "sold", "to %s by %s for %d gold" % [place, who, paid])
		stockpile.stock_shop(place, uid, "sold:%s" % who)
	else:
		_bank_thing(place, uid, "sold:%s" % who, _label_of(from), shop.zone, shop.tile)
	_log("shop: %s sold %s at %s for %d gold" % [by.name, item, place, paid])
	_slots_changed(from)


## Player [param by], within reach of shop counter [param shop], buys
## [param uid] from the town's shop there: into the first of their slots
## it fits (the pack, then the hands), paid from their gold. False, and
## nothing changes, if it isn't for sale, they can't pay or have no room;
## they are told why (traded).
func try_buy(by: GridEntity, shop: GridEntity, uid: int) -> bool:
	if not Net.is_authority():
		return false
	var place := shop_place(shop)
	if not by is Player or (by as Player).player_id.is_empty() or place.is_empty() or economy == null \
			or not reaches(by, shop):
		traded.emit(by, shop, "no shop the town holds here")
		return false
	var id := items.id_of(uid)
	var slot := -1
	_fit_uids(by)
	for i in by.slots.size():
		if by.slots[i].is_empty():
			var given := by.slots.duplicate()
			given[i] = id
			if hands_allow(by, given):
				slot = i
				break
	if slot < 0 or id.is_empty():
		traded.emit(by, shop, "no room to carry it" if not id.is_empty() else "that is no longer for sale")
		return false
	var who := (by as Player).player_id
	var deal := economy.buy(who, place, uid, -1, fence_state(shop))
	if not deal["ok"]:
		traded.emit(by, shop, str(deal["why"]))
		return false
	put_item(by, by, slot, uid)
	_log("shop: %s bought %s at %s for %d gold" % [by.name, id, place, deal["price"]])
	gold_changed.emit(who, economy.gold(who))
	traded.emit(by, shop, "")
	return true


## Player [param by], within reach of shop counter [param shop], barters
## (decision 560): their things [param give] (uids in their slots) to the
## town, [param take] (uids off its shelf) from it, each at the price the
## barter message showed, all or nothing. [param balance] is the gold they
## saw (what they get, less what they pay): refused, "the prices have
## moved", when Economy.barter_quote's differs. Grave goods fenced. The
## gives go first, then each take into the first slot it fits once the
## gives are out. "" when done, else why nothing moved. With [param maker]
## (a worker id; decision 562, [param shop] their body) the barter is with
## that maker: their own make off their town's shelf, the gives bought from
## their purse (Economy.maker_quote) into their store.
func try_barter(by: GridEntity, shop: GridEntity, give: Array, take: Array, balance: int, maker := "") -> String:
	if not Net.is_authority():
		return "not here"
	var place := shop_place(shop) if maker.is_empty() 			else str(production.worker(maker).get("town", "")) if production != null else ""
	if not by is Player or (by as Player).player_id.is_empty() or place.is_empty() or economy == null 			or not reaches(by, shop):
		return "no shop the town holds here" if maker.is_empty() else "nobody to trade with here"
	if give.is_empty() and take.is_empty():
		return "nothing to trade"
	give = give.map(func(uid: Variant) -> int: return int(uid))
	take = take.map(func(uid: Variant) -> int: return int(uid))
	var who := (by as Player).player_id
	var uids := slot_uids(by)
	var gives: Array = []
	var from_slots: Array[int] = []
	var handing: Array[int] = []
	for uid: int in give:
		var slot := slot_of_unit(by, uid)  # A unit of a stack too (decision 619).
		if uid == 0 or slot < 0 or uid in handing:
			return "that is no longer in your pack"
		if is_starter(uid):  # The starter vendor's (736), to a shop or a maker alike.
			return STARTER_REFUSED
		handing.append(uid)
		from_slots.append(slot)
		gives.append({"id": by.slots[slot], "fenced": items.is_grave(uid)})
	var quote := economy.barter_quote(place, who, gives, take, fence_state(shop)) if maker.is_empty() else economy.maker_quote(maker, who, gives, take)
	if not quote["ok"]:
		return str(quote["why"])
	if int(quote["balance"]) != balance:
		return "the prices have moved"
	# Room for the takes once the gives are out: a stack of the kind with
	# room first (decision 619), else an empty slot.
	var after := by.slots.duplicate()
	var counts: Array[int] = []
	for i in after.size():
		counts.append(slot_count(by, i))
	for slot in from_slots:
		counts[slot] -= 1
		if counts[slot] <= 0:
			after[slot] = ""
	var to_slots: Array[int] = []
	for uid: int in take:
		var id := items.id_of(uid)
		var slot := -1
		for i in after.size():
			if after[i] == id and counts[i] < Items.stack_of(id) and stacks_onto(slot_uid(by, i), uid, 1, false):
				slot = i
				break
		for i in (after.size() if slot < 0 else 0):
			if after[i].is_empty():
				var given := after.duplicate()
				given[i] = id
				if hands_allow(by, given):
					slot = i
					break
		if slot < 0:
			return "no room to carry it"
		after[slot] = id
		counts[slot] = maxi(counts[slot], 0) + 1
		to_slots.append(slot)
	for i in from_slots.size():
		if not maker.is_empty():
			if economy.maker_sell(maker, who, str(gives[i]["id"]), int(quote["gives"][i])):
				_sold(by, by, from_slots[i], int(give[i]), place, who, int(quote["gives"][i]), shop)
			continue
		var deal := economy.sell(who, place, str(gives[i]["id"]), bool(gives[i]["fenced"]), int(quote["gives"][i]))
		if deal["ok"]:
			_sold(by, by, from_slots[i], int(give[i]), place, who, int(deal["paid"]), shop)
	for i in take.size():
		var deal := economy.buy(who, place, int(take[i]), int(quote["takes"][i]))
		if deal["ok"]:
			var into := to_slots[i]
			if not by.slots[into].is_empty() and not stacks_onto(slot_uid(by, into), int(take[i])):
				into = room_for(by, int(take[i]))  # The stack it was to join was given away whole.
			put_item(by, by, into, int(take[i]))
			_log("shop: %s bought %s at %s for %d gold" % [by.name, deal["id"], place, deal["price"]])
	gold_changed.emit(who, economy.gold(who))
	return ""


## Who last put each thing on the ground (a drop or a throw), by uid, for
## the stockpile's ledger; gone when it is taken off again.
var _put_down_by: Dictionary[int, String] = {}


func _ready() -> void:
	key_check = holds_key
	ground_changed.connect(_on_ground_for_stockpile)
	entity_moved.connect(_on_moved_for_stockpile)
	entity_pushed.connect(_on_pushed_for_stockpile)
	entity_despawned.connect(func(entity: GridEntity) -> void: _pushed_by.erase(entity))
	load_physics_rules(FileAccess.get_file_as_string(PHYSICS_RULES))
	load_combat_rules(FileAccess.get_file_as_string(COMBAT_RULES))


## The knockback model's numbers (decision 592) from [param text], the
## rules file's JSON: each key it gives sets its value; one missing, or not
## a number at least 0, keeps the default (and is warned about).
func load_physics_rules(text: String) -> void:
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if data is not Dictionary:
		push_warning("World: %s unreadable; the physics defaults hold" % PHYSICS_RULES)
		return
	# The file's names where they differ from the vars'.
	var names := {"knockback_min_speed": "knockback_min_force", "stun_ticks_per_speed": "stun_ticks_per_force"}
	for key: String in data:
		var field: String = names.get(key, key)
		var given: Variant = data[key]
		if not field in ["shove_scale", "knockback_min_force", "slide_per_speed", "max_travel", "momentum_scale",
				"momentum_ticks", "restitution", "impact_per_energy", "brace_restitution", "stun_ticks_base",
				"stun_ticks_per_force", "knockback_stun_ticks", "lunge_ticks_per_cell", "lunge_min_speed", "rush_stop_speed", "swing_speed", "throw_speed",
				"load_k", "load_free", "load_heavy", "load_overloaded", "clank_plate", "clank_mail"]:
			push_warning("World: %s's %s is not a physics rule" % [PHYSICS_RULES, key])
		elif (given is int or given is float) and float(given) >= 0.0:
			set(field, int(given) if get(field) is int else float(given))
		else:
			push_warning("World: %s's %s is %s; %s kept" % [PHYSICS_RULES, key, given, get(field)])


## The swing's cost and being winded (decision 597) from [param text], the
## rules file's JSON, as load_physics_rules: a key it gives sets its value;
## one unknown, or not a number at least 0, keeps the default (warned).
func load_combat_rules(text: String) -> void:
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if data is not Dictionary:
		push_warning("World: %s unreadable; the combat defaults hold" % COMBAT_RULES)
		return
	for key: String in data:
		var given: Variant = data[key]
		if key == "moves" and given is Dictionary:
			for move: String in given:
				if given[move] is Dictionary and moves.has(move):
					moves[move].merge(given[move], true)  # Decision 603.
				else:
					push_warning("World: %s's moves.%s is not a move" % [COMBAT_RULES, move])
			continue
		if not key in ["swing_base", "swing_per_kg", "ref_mass", "whiff_scale", "recover_at", "winded_move_scale",
				"winded_blow_scale", "winded_regen_delay", "melee_reach", "lead_slack"]:
			push_warning("World: %s's %s is not a combat rule" % [COMBAT_RULES, key])
		elif (given is int or given is float) and float(given) >= 0.0:
			set(key, int(given) if get(key) is int else float(given))
		else:
			push_warning("World: %s's %s is %s; %s kept" % [COMBAT_RULES, key, given, get(key)])


## The stamina a swing by [param entity] costs (decision 597): by the weight
## of what it strikes with (wielded; fists 0) against its own mass (without
## what it carries); [param whiff], striking nobody, whiff_scale times it.
func swing_cost(entity: GridEntity, whiff := false) -> int:
	var id := wielded(entity)
	var weight := Items.weight_of(id) if not id.is_empty() else 0.0
	var own := entity.base_mass if entity.base_mass > 0.0 else entity.mass
	var cost := swing_base + swing_per_kg * weight * ref_mass / maxf(own, 1.0)
	return ceili(cost * (whiff_scale if whiff else 1.0))


## [param entity] pays for a swing (decision 597), if it pays for swings at
## all (pays_swings: players and companions; a monster by its row's
## "swing_stamina"); never below 0.
func _pay_swing(entity: GridEntity, whiff: bool) -> void:
	if entity.max_stamina > 0 and entity.pays_swings:
		entity.stamina = maxi(0, entity.stamina - swing_cost(entity, whiff))


## Whether [param entity] is winded (decision 597): out of stamina, and not
## yet back to recover_at.
func is_winded(entity: GridEntity) -> bool:
	return is_instance_valid(entity) and entity.winded


## The telegraphs showing now (decision 602): id -> {source, kind, shape,
## from_tick, lands_tick}.
var _telegraphs: Dictionary[int, Dictionary] = {}
var _next_telegraph := 1


## [param source] shows [param shape] (Telegraph's) on the ground, a
## [param kind] ("spin", "throw", "charge": the views' and sounds' word) for
## [param ticks] till it lands (decision 602): its id, 0 if the shape does
## not read. The blow that follows strikes telegraph_cells(shape), the cells
## drawn. Server only.
func telegraph(source: GridEntity, kind: String, shape: Dictionary, ticks: int) -> int:
	if not Net.is_authority() or not Telegraph.valid(shape) or not is_instance_valid(source):
		return 0
	var id := _next_telegraph
	_next_telegraph += 1
	var cells := []
	for cell in telegraph_cells(shape):
		cells.append([cell.x, cell.y])  # Sent as struck, so a view draws exactly what will hit.
	var data := {"id": id, "source": str(source.get_path()), "kind": kind, "shape": shape, "cells": cells,
		"from_tick": tick, "lands_tick": tick + maxi(0, ticks), "zone": source.zone}
	_telegraphs[id] = {"source": source, "data": data}
	telegraph_started.emit(id, data)
	return id


## Telegraph [param id] over: [param landed], its blow struck; false, given
## up (a wind-up broken, its source gone). Unknown ids are let be.
func end_telegraph(id: int, landed: bool) -> void:
	if not _telegraphs.has(id):
		return
	var zone_name := str(_telegraphs[id]["data"]["zone"])
	_telegraphs.erase(id)
	telegraph_ended.emit(id, landed)
	telegraph_ended_in.emit(zone_name, id, landed)


## The telegraphs showing now, by id: their data as sent (decision 602).
func telegraphs() -> Dictionary:
	var out := {}
	for id: int in _telegraphs:
		out[id] = _telegraphs[id]["data"]
	return out


## [param shape]'s cells on this ground (decision 602): Telegraph.cells, less
## any cell that is not floor (walkable or water) or that a wall or a closed
## door stands between it and the shape's origin (as sight is stopped:
## _sight_crosses_edge); a line ends at the first such cell. Both the drawing
## and the blow read it.
func telegraph_cells(shape: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := Telegraph.origin_of(shape) if Telegraph.valid(shape) else Vector2i.ZERO
	for cell in Telegraph.cells(shape):
		if cell == origin or (is_walkable(cell) or is_water(cell)) and _clear_between(origin, cell):
			out.append(cell)
		elif str(shape["kind"]) == "line":
			break
	return out


## Whether nothing stops sight cell by cell from [param from] to
## [param to] (a straight line, Bresenham's), every cell between floor.
func _clear_between(from: Vector2i, to: Vector2i) -> bool:
	var span: Vector2i = (to - from).abs()
	var s := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var err: int = span.x - span.y
	var at := from
	while at != to:
		var e2: int = 2 * err
		var step := Vector2i.ZERO
		if e2 > -span.y:
			err -= span.y
			step.x = s.x
		if e2 < span.x:
			err += span.x
			step.y = s.y
		if _sight_crosses_edge(at, step):
			return false
		at += step
		if at != to and not (is_walkable(at) or is_water(at)):
			return false
	return true


## A boss's move under way (decision 603): entity -> {move: "spin" | "throw"
## | "charge", telegraph: id, lands: tick, ...}.
var _boss_moves: Dictionary[GridEntity, Dictionary] = {}
## A boss's thrown weapon (decision 603): entity -> {uid, cell, disarmed}.
var _axes: Dictionary[GridEntity, Dictionary] = {}


## [param by] winds up its spin (decision 603; the draugr's, Jeff's
## "telegraphed wind up spin that he stands still, winds up for 1.5
## seconds"): it stands, a cone telegraph round it (moves.spin: length,
## half_angle either side of its facing: 180, a whole disc, 603 amended
## (7)), and windup ticks on
## every body in the cone's cells takes damage_scale times its blow, its
## guard broken, pushed outward by its weapon (apply_blow at
## swing_impulse) and knocked down; then it is spent: its stamina at
## leaves (a percentage), winded. A stun or a knockdown before then gives it
## up. Needs stamina at least needs, not winded; disarmed, the sweep is its
## fists' (fists_length). False, nothing begun, if it cannot.
func try_spin(by: GridEntity) -> bool:
	var move: Dictionary = moves["spin"]
	if not _boss_can_begin(by) or by.stamina < int(move["needs"]):
		return false
	var shape := _spin_shape(by)
	var id := telegraph(by, "spin", shape, int(move["windup"]))
	_boss_moves[by] = {"move": "spin", "telegraph": id, "lands": tick + int(move["windup"]), "shape": shape, "from": by.tile}
	by._world_winding(by.facing, int(move["windup"]))
	by._world_note_exertion(tick)
	_log("spin: %s winds up, %d ticks" % [by.name, int(move["windup"])])
	return true


## The bodies [param by]'s spin would strike now (decision 603): any body in
## its cone's cells, whoever it is.
func spin_targets(by: GridEntity) -> Array[GridEntity]:
	return _bodies_in(by, telegraph_cells(_spin_shape(by)))


func _spin_shape(by: GridEntity) -> Dictionary:
	var move: Dictionary = moves["spin"]
	var facing := Vector2(by.facing) if by.facing != Vector2i.ZERO else Vector2(1, 0)
	var length := float(move["fists_length"]) if _axe_slot(by) < 0 else float(move["length"])
	return Telegraph.cone(by.tile, facing, length, float(move["half_angle"]))


## [param by] winds up the overhead throw of its two-handed weapon at
## [param at] (decision 603; Jeff's "he winds up and throws it, you can tell
## the direction ... by a longer narrow cone"): a line telegraph from it
## toward [param at], fixed now (moves.throw: length, width); windup ticks
## on, the weapon flies down it: the first body on the line takes
## damage_scale times its blow and is launched; the weapon lies in the cell
## before that body, else at the line's end. Costs cost. False, nothing
## begun, if it cannot (winded, short of stamina, nothing two-handed in
## hand, no line).
func try_axe_throw(by: GridEntity, at: Vector2i) -> bool:
	var move: Dictionary = moves["throw"]
	if not _boss_can_begin(by) or by.stamina < int(move["cost"]) or _axe_slot(by) < 0 or at == by.tile:
		return false
	var shape := _throw_shape(by, at)
	if telegraph_cells(shape).is_empty():
		return false
	by.stamina = maxi(0, by.stamina - int(move["cost"]))
	by._world_set_facing(Vector2i(signi(at.x - by.tile.x), signi(at.y - by.tile.y)))
	var id := telegraph(by, "throw", shape, int(move["windup"]))
	_boss_moves[by] = {"move": "throw", "telegraph": id, "lands": tick + int(move["windup"]), "shape": shape, "from": by.tile}
	by._world_winding(by.facing, int(move["windup"]))
	by._world_note_exertion(tick)
	_log("throw: %s winds up at %s" % [by.name, at])
	return true


func _throw_shape(by: GridEntity, at: Vector2i) -> Dictionary:
	var move: Dictionary = moves["throw"]
	return Telegraph.line(by.tile, Vector2(at - by.tile).normalized(), float(move["length"]), int(move["width"]))


## The first body on [param by]'s throw toward [param at] (decision 603),
## or null.
func axe_line_hit(by: GridEntity, at: Vector2i) -> GridEntity:
	if at == by.tile:
		return null
	for cell in telegraph_cells(_throw_shape(by, at)):
		for body in bodies_struck_at(cell):
			if body != by and body.spawned:
				return body
	return null


## [param by] charges to its thrown weapon to take it up (decision 603;
## Jeff's "after he throws the axe he uses charges to the axe to pick it
## up, if you are able to interrupt the charge he is disarmed"): a line
## telegraph to the weapon's cell for moves.charge's roar ticks, then a rush
## along it (physics' rush, decision 604, when it is in; else a cell a tick
## here). Reaching the cell with the weapon there, it takes it up; stopped
## short (a blow, a body, a brace, a wall, a stun) or the weapon gone from
## its cell, it is disarmed (is_disarmed). False, nothing begun, if it
## cannot (no weapon lying, disarmed).
func try_axe_charge(by: GridEntity) -> bool:
	var axe: Dictionary = _axes.get(by, {})
	if axe.is_empty() or bool(axe.get("disarmed", false)) or not _boss_can_begin(by, true):
		return false
	var cell: Vector2i = axe["cell"]
	if cell == by.tile:
		_take_axe(by)
		return true
	var move: Dictionary = moves["charge"]
	var shape := Telegraph.line(by.tile, Vector2(cell - by.tile).normalized(), Vector2(cell - by.tile).length())
	var id := telegraph(by, "charge", shape, int(move["roar"]))
	_boss_moves[by] = {"move": "charge", "telegraph": id, "lands": tick + int(move["roar"]), "to": cell, "steps": 0,
		"rushing": false}
	by._world_note_exertion(tick)
	_log("charge: %s roars, toward its weapon at %s" % [by.name, cell])
	return true


## Where [param by]'s weapon is (decision 603): {where: "hand" (two-handed,
## in its hands), "ground" (thrown, lying at cell), "gone" (taken from where
## it lay, or never had), cell, uid}.
func axe_state(by: GridEntity) -> Dictionary:
	var slot := _axe_slot(by)
	if slot >= 0:
		return {"where": "hand", "cell": by.tile, "uid": slot_uid(by, slot)}
	var axe: Dictionary = _axes.get(by, {})
	if axe.is_empty():
		return {"where": "gone", "cell": NO_CELL, "uid": 0}
	var cell: Vector2i = axe["cell"]
	var there := ground_uids(cell).has(int(axe["uid"]))
	return {"where": "ground" if there else "gone", "cell": cell, "uid": int(axe["uid"])}


## Whether [param by]'s charge to its weapon was stopped (decision 603): it
## fights without it till it walks back to it (603 amended:
## _tend_disarmed).
func is_disarmed(by: GridEntity) -> bool:
	return bool(_axes.get(by, {}).get("disarmed", false))


## Whether [param uid] is a boss's thrown weapon, bound to it while it lies
## (603 amended; Jeff: "player can't pick up the axe mid fight, its
## magically bound to him, only fulfilling the pact lets you take the
## axe"): only he takes it up (_take_axe); nobody picks it up, arms with
## it or banks it. Free once he is gone (_forget_jobs: killed, it lies as
## loot); taken back to his hands when his fight ends (recall_axe).
func axe_bound(uid: int) -> bool:
	for by: GridEntity in _axes:
		if int(_axes[by]["uid"]) == uid:
			return true
	return false


## [param by]'s thrown weapon back in its hands from wherever it lies (603
## amended: his fight over, won or lost, the bound axe goes home with him;
## the pact's prize is his row's "yields"). Nothing when none lies.
func recall_axe(by: GridEntity) -> void:
	if not _axes.has(by):
		return
	_boss_moves.erase(by)
	var axe: Dictionary = _axes[by]
	var cell: Vector2i = axe["cell"]
	var index := ground_uids(cell).find(int(axe["uid"]))
	if index < 0 or _axe_slot(by) >= 0:
		_axes.erase(by)
		return
	var uid := take_from_ground(cell, index)
	if uid != 0:
		_hand_set(by, Items.RIGHT_HAND, uid)
	_axes.erase(by)
	_log("axe: %s's weapon comes back to it" % by.name)


## [param by]'s move under way given up at once, nothing of it landing
## (603 amended (3); Jeff's fight: the draugr's spin swept after he yielded):
## a spin's or a throw's telegraph ended unlanded and its wind-up shown over;
## a charge stopped as a body in its way stops it (its rush ended,
## _charge_over "stopped"); any other telegraph of his ended unlanded too.
## His mind calls it as he yields or goes to rest. Nothing when none is under way.
func drop_boss_move(by: GridEntity) -> void:
	if not Net.is_authority():
		return
	if _boss_moves.has(by):
		var job: Dictionary = _boss_moves[by]
		if str(job["move"]) == "charge":
			_end_rush(by, "stopped")  # Under way: _on_rush_ended ends the charge.
			if _boss_moves.has(by):
				_charge_over(by, job, "stopped")  # Still roaring: no rush yet.
		else:
			_boss_moves.erase(by)
			end_telegraph(int(job["telegraph"]), false)
			if is_instance_valid(by):
				by._world_winding(by.facing, 0)
			_log("%s: %s gives it up (dropped)" % [job["move"], by.name])
	for id: int in _telegraphs.keys():
		if _telegraphs.has(id) and _telegraphs[id]["source"] == by:
			end_telegraph(id, false)


## Each tick, each bow held at or past full draw (decision 669; Jeff:
## "holding at max nock .. starts draining stamina"): its verb's drain off
## the holder's stamina, an exertion (so none comes back while held); at 0
## the arms give out: the bow is let down, the arrow kept, nothing loosed
## (draw_given_up; winded, 597, follows from the 0). Only for those who pay
## for their swings; another zone's on its own tick.
func _tend_draws() -> void:
	for entity in _entities:
		if entity.raised != "draw" or entity.max_stamina <= 0 or not entity.pays_swings or not _alive(entity):
			continue
		var verb := Items.verb_of(drawn_with(entity))
		if verb.is_empty() or int(verb.get("drain", 0)) <= 0 or draw_step(entity) < int(verb.get("full", 0)):
			continue
		entity.stamina = maxi(0, entity.stamina - _carried(int(verb["drain"]) * draw_drain_load(entity), tick))  # The load drains it faster (676).
		entity._world_note_exertion(tick)
		if entity.stamina == 0:
			entity.raised = ""
			_log("draw: %s's arms give out; the bow let down" % entity.name)
			draw_given_up.emit(entity)


## The multiple a held draw's drain runs at from the load (decision 676;
## Jeff: "mass that drains stamina from archery a little faster"): the
## arms' share past load_free, and DRAIN_BODY_SHARE of the body's, by
## load_k; 1 for a bow and arrows alone.
func draw_drain_load(entity: GridEntity) -> float:
	var capacity := load_capacity(entity)
	var arms := maxf(0.0, entity.load_arms / (capacity * ARMS_SHARE) - load_free)
	var body := maxf(0.0, entity.load_body / capacity - load_free)
	return 1.0 + load_k * (arms + DRAIN_BODY_SHARE * body)


## [param rate] (a fraction a tick, or more) as whole units on [param n]'s
## count: a rate of 1.6 gives 1, 2, 2, 1, 2..., summing to the rate over
## the ticks, with no state kept.
static func _carried(rate: float, n: int) -> int:
	return floori(rate * (n + 1)) - floori(rate * n)


## Whether [param by] is in the middle of something (decision 603): a move
## winding up, a charge under way, a heavy wind-up (392), stunned or lying.
func boss_busy(by: GridEntity) -> bool:
	return _boss_moves.has(by) or not by.wind_up.is_empty() or is_stunned(by) or is_down(by)


## Whether [param by] may begin a move now: alive, not mid-move, stunned,
## lying, or winded ([param winded_ok]: the charge, which costs nothing).
func _boss_can_begin(by: GridEntity, winded_ok := false) -> bool:
	if not Net.is_authority() or not _alive(by) or _boss_moves.has(by) or not by.wind_up.is_empty():
		return false
	if is_stunned(by) or is_down(by) or (by.winded and not winded_ok):
		return false
	return tick >= by.next_move_tick


## The hand [param by]'s two-handed weapon is in, -1 for none.
func _axe_slot(by: GridEntity) -> int:
	if not holds_in_hands(by):
		return -1
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		var id := by.slots[slot]
		if not id.is_empty() and int(Items.def(id).get("hands", 1)) == 2:
			return slot
	return -1


## The bodies standing on [param cells], [param by] not among them.
func _bodies_in(by: GridEntity, cells: Array[Vector2i]) -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	for cell in cells:
		for body in bodies_struck_at(cell):
			if body != by and _alive(body) and body not in out:
				out.append(body)
	return out


## The cell a blow finds [param body] in (enemy-ai's free-walk audit): a
## body on the grid's own; a free body's the cell under its centre, held or
## not (699, combat's side: a telegraph by the centre's cell, so a body seen
## out of the red is spared and one seen in it struck).
func struck_cell(body: GridEntity) -> Vector2i:
	if not free_body(body):
		return body.tile
	return Vector2i(body_centre(body).round())


## Who a blow at [param cell] strikes (struck_cell): its holder unless that
## is a free body gone from it, and any free body whose centre has strayed
## into it; [] for nobody.
func bodies_struck_at(cell: Vector2i) -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	var holder: GridEntity = _occupancy.get(cell)
	if holder != null and struck_cell(holder) == cell:
		out.append(holder)
	for each in sought():
		if each != holder and each.tile != cell and free_body(each) and struck_cell(each) == cell:
			out.append(each)
	return out


## Each tick, each move under way (decision 603): given up if its maker was
## stunned, knocked down or moved off its cell while winding up; struck when
## due; a charge tended.
func _tend_boss_moves() -> void:
	for by: GridEntity in _boss_moves.keys():
		if not _alive(by):
			_boss_moves.erase(by)
			continue
		if by.zone != zone.name:
			continue  # Another zone's: its own step tends it, on its own tick.
		var job: Dictionary = _boss_moves[by]
		if str(job["move"]) == "charge":
			_tend_charge(by, job)
			continue
		if is_stunned(by) or is_down(by) or by.tile != job["from"]:
			_boss_moves.erase(by)
			end_telegraph(int(job["telegraph"]), false)
			by._world_winding(by.facing, 0)
			_log("%s: %s gives it up" % [job["move"], by.name])
			continue
		if tick < int(job["lands"]):
			continue
		_boss_moves.erase(by)
		end_telegraph(int(job["telegraph"]), true)
		if str(job["move"]) == "spin":
			_spin_lands(by, job["shape"])
		else:
			_throw_lands(by, job["shape"])
	_tend_disarmed()


## A disarmed boss come back to its weapon (603 amended: "fists until he
## reaches the axe"): standing on its cell or beside it (in reach), not mid
## anything, it takes it up and is armed again. Its mind walks it there.
func _tend_disarmed() -> void:
	for by: GridEntity in _axes.keys():
		if not bool(_axes[by].get("disarmed", false)) or not _alive(by) or boss_busy(by) or by.zone != zone.name:
			continue  # (Another zone's: its own step, its own ground.)
		var cell: Vector2i = _axes[by]["cell"]
		if by.tile == cell or distance(by.tile, cell) == 1 and can_melee(by.tile, cell):
			_take_axe(by)


## The spin's sweep (decision 603): every body in its cells struck, guard
## broken, pushed outward and knocked down; then its maker spent.
func _spin_lands(by: GridEntity, shape: Dictionary) -> void:
	var move: Dictionary = moves["spin"]
	var slot := _axe_slot(by)
	var id := by.slots[slot] if slot >= 0 else ""
	var impulse := blow_impulse(by, blow_verb(by)) + (Items.weight_of(id) if not id.is_empty() else 0.0) * float(move["weight_impulse"])
	if has_method("swing_impulse") and not id.is_empty():
		impulse = float(call("swing_impulse", by, id))  # Physics' (605), when it is in.
	impulse *= float(move.get("impulse_scale", 1.0))  # Jeff's knob (a wall's impact grows with its square).
	var struck := 0
	for body in _bodies_in(by, telegraph_cells(shape)):
		if not can_target(by, body):
			continue
		var amount := maxi(1, roundi(by.attack_damage * float(move["damage_scale"])))
		var met: Variant = _meet_guard(body, by, amount, 99.0, false, true)
		if met != null:
			amount = met[0]
		damage(body, amount, by, &"attack")
		if _alive(body):
			apply_blow(by, body, {"impulse": impulse, "direction": Vector2(body.tile - by.tile), "no_floor": true})  # It throws (603 amended (4)).
		if _alive(body):
			knock_down(body, by, int(move["down_ticks"]))
		struck += 1
	by.stamina = mini(by.stamina, roundi(by.max_stamina * float(move["leaves"]) / 100.0))
	by.winded = by.max_stamina > 0
	by._world_note_exertion(tick)
	by._world_swung(by.facing)
	entity_swung.emit(by, by.facing)
	noise(by.tile, Senses.NOISE_FIGHT, &"fight", by)
	_log("spin: %s sweeps, %d struck; spent at %d" % [by.name, struck, by.stamina])


## The throw's flight (decision 603): down the line's cells, the first body
## struck and launched (physics' launch, 598, when it is in), the weapon
## lying in the cell before it or at the line's end.
func _throw_lands(by: GridEntity, shape: Dictionary) -> void:
	var move: Dictionary = moves["throw"]
	var slot := _axe_slot(by)
	if slot < 0:
		return
	if has_method("hurl"):
		_hurl_lands(by, slot, shape)  # Physics' (606), when it is in.
		return
	var hit: GridEntity = null
	var rest := by.tile
	for cell in telegraph_cells(shape):
		for body in bodies_struck_at(cell):
			if body != by and _alive(body):
				hit = body
				break
		if hit != null:
			break
		rest = cell
	var weight := Items.weight_of(by.slots[slot])
	var uid := slot_uid(by, slot)
	if uid == 0:
		return
	_hand_set(by, slot, 0)
	var lay := put_on_ground(uid, rest, by.tile)
	_axes[by] = {"uid": uid, "cell": lay if lay != NO_CELL else rest, "disarmed": false}
	by._world_shot(Vector2(rest if hit == null else hit.tile), &"ground" if hit == null else &"body")  # 583's shot: a point and what stopped it.
	noise(by.tile, Senses.NOISE_FIGHT, &"fight", by)
	if hit != null and can_target(by, hit):
		damage(hit, maxi(1, roundi(by.attack_damage * float(move["damage_scale"]))), by, &"attack")
		if _alive(hit):
			var impulse := weight * float(move["speed"])
			if has_method("launch"):
				call("launch", by, hit, Vector2(hit.tile - by.tile), impulse)
			else:
				apply_blow(by, hit, {"impulse": impulse, "direction": Vector2(hit.tile - by.tile)})
	_log("throw: %s throws, %s; it lies at %s" % [by.name, hit.name if hit != null else "nothing hit", _axes[by]["cell"]])


## The throw by physics' hurl (606): it flies the weapon down the line and
## launches the first body; the damage is this side's, the weapon lies where
## hurl says.
func _hurl_lands(by: GridEntity, slot: int, shape: Dictionary) -> void:
	var move: Dictionary = moves["throw"]
	var uid := slot_uid(by, slot)
	var result: Dictionary = call("hurl", by, slot, Telegraph.facing_of(shape), int(float(move["length"])), float(move["speed"]))
	var hit: Variant = result.get("hit")
	if hit is GridEntity and _alive(hit) and can_target(by, hit):
		damage(hit, maxi(1, roundi(by.attack_damage * float(move["damage_scale"]))), by, &"attack")
	var landed: Variant = result.get("landed")
	if landed is Vector2i and uid != 0:
		_axes[by] = {"uid": uid, "cell": landed, "disarmed": false}
	noise(by.tile, Senses.NOISE_FIGHT, &"fight", by)
	_log("throw: %s hurls, %s; it lies at %s" % [by.name, (hit as GridEntity).name if hit is GridEntity else "nothing hit", landed])


## A charge under way (decision 603): the roar, then the rush; physics'
## (604) tells its end by rush_ended, else a cell a tick here: a refused
## step ends it ("body", "wall"), as a stun does.
func _tend_charge(by: GridEntity, job: Dictionary) -> void:
	if bool(job["rushing"]):
		return  # Physics' rush is under way; _on_rush_ended ends it.
	if is_stunned(by) or is_down(by):
		_charge_over(by, job, "stunned")
		return
	if tick < int(job["lands"]):
		return
	if _telegraphs.has(int(job["telegraph"])):
		end_telegraph(int(job["telegraph"]), true)
	var to: Vector2i = job["to"]
	if axe_state(by)["where"] != "ground":
		_charge_over(by, job, "gone")
		return
	if by.tile == to:
		_charge_over(by, job, "arrived")
		return
	if has_method("rush"):
		if not has_signal("rush_ended") or not is_connected("rush_ended", _on_rush_ended):
			connect("rush_ended", _on_rush_ended)
		job["rushing"] = bool(call("rush", by, Vector2(to - by.tile), distance(by.tile, to), {"through": true, "to": to}))
		if not job["rushing"]:
			_charge_over(by, job, "wall")
		return
	var step := (to - by.tile).clamp(Vector2i(-1, -1), Vector2i(1, 1))
	by.next_move_tick = 0
	if int(job["steps"]) >= int(moves["charge"]["cells"]) or not try_move(by, step):
		_charge_over(by, job, "body" if _occupancy.has(by.tile + step) else "wall")
		return
	job["steps"] = int(job["steps"]) + 1
	if by.tile == to:
		_charge_over(by, job, "arrived")


## Physics' rush over (604): a charge's end, by its reason.
func _on_rush_ended(entity: GridEntity, reason: String, _at: Variant = null, _result: Variant = null) -> void:
	if _boss_moves.has(entity) and str(_boss_moves[entity]["move"]) == "charge":
		_charge_over(entity, _boss_moves[entity], reason)


## A charge over (decision 603): [param reason] "arrived", it takes its
## weapon up if it still lies there; anything else, disarmed.
func _charge_over(by: GridEntity, job: Dictionary, reason: String) -> void:
	_boss_moves.erase(by)
	if _telegraphs.has(int(job["telegraph"])):
		end_telegraph(int(job["telegraph"]), false)
	if reason == "arrived" and by.tile == job["to"] and axe_state(by)["where"] == "ground":
		_take_axe(by)
		return
	if _axes.has(by):
		_axes[by]["disarmed"] = true
	_log("charge: %s stopped (%s): disarmed" % [by.name, reason])


## [param by] takes its weapon up from its cell into its hands.
func _take_axe(by: GridEntity) -> void:
	var axe: Dictionary = _axes.get(by, {})
	if axe.is_empty():
		return
	var cell: Vector2i = axe["cell"]
	var index := ground_uids(cell).find(int(axe["uid"]))
	if index < 0:
		return
	var uid := take_from_ground(cell, index)
	if uid != 0:
		_hand_set(by, Items.RIGHT_HAND, uid)
		_axes.erase(by)
		_log("charge: %s takes its weapon up" % by.name)


## [param by]'s hand [param slot] holds [param uid] (0: emptied), by
## set_slots, as a monster's hands are filled (a monster takes nothing
## through try_transfer's rules).
func _hand_set(by: GridEntity, slot: int, uid: int) -> void:
	var contents := by.slots.duplicate()
	var uids := Array(by.slot_items)
	uids.resize(contents.size())
	contents[slot] = items.id_of(uid) if uid != 0 else ""
	uids[slot] = uid
	set_slots(by, contents, uids)


## Who last pushed each crate or cart, by entity, for the stockpile's
## ledger when it is unloaded there.
var _pushed_by: Dictionary[GridEntity, String] = {}


func _on_pushed_for_stockpile(entity: GridEntity, by: GridEntity, _direction: Vector2i, _tiles: int, _impact: int,
		_stopped_by: String) -> void:
	if entity is Cargo and is_instance_valid(by):
		_pushed_by[entity] = _label_of(by)


## A crate or cart (Cargo) moved onto [param to]: if that is stockpile
## ground the town holds, what it carries is banked once the move is done.
func _on_moved_for_stockpile(entity: GridEntity, _from: Vector2i, to: Vector2i) -> void:
	if not Net.is_authority() or stockpile == null or not entity is Cargo:
		return
	var area := entity.zone if not entity.zone.is_empty() else zone.name
	if not Stockpile.place_at(holdings, area, to).is_empty():
		_bank_cargo.call_deferred(entity)


## Banks everything [param cargo] carries, if it still stands on stockpile
## ground the town holds; the crate or cart stays, empty, for the town to
## send out again. A thing whose yield the stockpile has no count for is
## put down beside it instead.
func _bank_cargo(cargo: GridEntity) -> void:
	if not is_instance_valid(cargo) or not cargo.spawned or stockpile == null:
		return
	var area := cargo.zone if not cargo.zone.is_empty() else zone.name
	var place := Stockpile.place_at(holdings, area, cargo.tile)
	var there: Zone = zones.get(area, zone if zone.name == area else null)
	if place.is_empty() or there == null:
		return
	var was := enter(there)
	var label := _label_of(cargo)
	var who: String = _pushed_by.get(cargo, "")
	_pushed_by.erase(cargo)
	for uid in empty_container(cargo):
		var yields := Items.yield_of(items.id_of(uid))
		if yields.keys().any(func(what: Variant) -> bool: return str(what) not in Stockpile.RESOURCES):
			put_on_ground(uid, cargo.tile)
			continue
		_bank_thing(place, uid, who, label, area, cargo.tile)
	_log("cargo: %s unloaded into %s at %s" % [cargo.name, place, cargo.tile])
	enter(was)


## Something landed on (or left) [param cell] of [param zone_name]: if it
## lies on stockpile ground the town holds, it is banked once the change is
## done (deferred: taking it off now would change the ground again while
## the others handling this change are still at it).
func _on_ground_for_stockpile(zone_name: String, cell: Vector2i, _thrown_from: Vector2i) -> void:
	if not Net.is_authority() or stockpile == null or Stockpile.place_at(holdings, zone_name, cell).is_empty():
		return
	_bank_ground.call_deferred(zone_name, cell)


## Banks everything on [param cell] of [param zone_name], if it still lies
## on stockpile ground the town holds; a resource item as its yield, gear
## as itself, taken off the ground as it goes in.
func _bank_ground(zone_name: String, cell: Vector2i) -> void:
	var there: Zone = zones.get(zone_name, zone if zone.name == zone_name else null)
	if there == null or stockpile == null:
		return
	var place := Stockpile.place_at(holdings, zone_name, cell)
	if place.is_empty():
		return
	var was := enter(there)
	var uids := ground_uids(cell)
	for index in range(uids.size() - 1, -1, -1):
		var uid := uids[index]
		if axe_bound(uid):
			continue  # A boss's, while it lies (603 amended).
		var yields := Items.yield_of(items.id_of(uid))
		if yields.keys().any(func(what: Variant) -> bool: return str(what) not in Stockpile.RESOURCES):
			continue  # A yield the stockpile has no count for: it stays where it is.
		var who: String = _put_down_by.get(uid, "")
		take_from_ground(cell, index)
		_bank_thing(place, uid, who, "the ground at %d,%d" % [cell.x, cell.y], zone_name, cell)
		_log("ground: %s banked at %s from %s" % [items.id_of(uid) if items.has(uid) else "a resource", place, cell])
	enter(was)


## The things lying on [param cell] of the zone World is in: their ids,
## the top (the last put down) last. A client has no Zone.ground (the
## server keeps the things): it reads the cell's replicated GroundPile, so
## its hover says "F  pick up" over a deer's remains as over anything.
func ground_at(cell: Vector2i) -> PackedStringArray:
	if not Net.is_authority():
		var pile: GroundPile = zone.piles.get(cell)
		return pile.ids if is_instance_valid(pile) else PackedStringArray()
	var ids := PackedStringArray()
	for uid in zone.ground.get(cell, PackedInt32Array()):
		ids.append(items.id_of(uid))
	return ids


## Their instances (ItemBook uids), as ground_at.
func ground_uids(cell: Vector2i) -> PackedInt32Array:
	return zone.ground.get(cell, PackedInt32Array()).duplicate()


## Whether [param by] can reach [param cell] to pick up or put down: its own
## cell, or one beside it with no wall or closed door between.
func reaches_cell(by: GridEntity, cell: Vector2i) -> bool:
	return cell == by.tile or can_melee(by.tile, cell)


## [param by] puts what is in its slot [param slot] down on [param at] (its
## own cell if null; one it reaches): a stack whole, or [param count] of its
## units (decision 619). A full cell (GROUND_PER_CELL) spills to the nearest
## with room. False, and nothing moves, if it cannot.
func try_drop(by: GridEntity, slot: int, at: Variant = null, count := 0) -> bool:
	if not Net.is_authority() or not _can_handle(by):
		return false
	var cell: Vector2i = by.tile if at == null else at
	if not reaches_cell(by, cell) or slot < 0 or slot >= by.slots.size() or by.slots[slot].is_empty():
		return false
	var id := by.slots[slot]
	var some := slot_count(by, slot) if count <= 0 else mini(count, slot_count(by, slot))
	var landed := NO_CELL
	for i in some:
		if _ground_room(cell, slot_uid(by, slot)) == NO_CELL:
			break
		var uid := take_item(by, by, slot)
		if uid == 0:
			break
		_put_down_by[uid] = _label_of(by)
		landed = put_on_ground(uid, cell)
	if landed == NO_CELL:
		return false
	_log("ground: %s put %s down at %s" % [by.name, id, landed])
	_thud(landed, id, by)
	return true


## [param by] picks up the thing at [param index] (-1: the top one) on
## [param cell], one it reaches, into a free hand that can hold it, else
## its pack. False, and nothing moves, if it cannot (nothing there, no room).
func try_pick_up(by: GridEntity, cell: Vector2i, index := -1) -> bool:
	if not Net.is_authority() or not _can_handle(by) or not reaches_cell(by, cell):
		return false
	var there: PackedInt32Array = zone.ground.get(cell, PackedInt32Array())
	if there.is_empty():
		return false
	if index < 0:
		# The top thing not bound to a boss (603 amended): his axe lying on a
		# pile keeps nobody from the rest of it.
		index = there.size() - 1
		while index >= 0 and axe_bound(there[index]):
			index -= 1
		if index < 0:
			return false
	if index >= there.size():
		return false
	var uid := there[index]
	if axe_bound(uid):
		return false  # Bound to its boss while it lies (603 amended).
	if _swap_bundle(by, cell, index):
		return true
	if not _pick_unit(by, cell, index):
		return false
	# The rest of its kind lying there, as many as there is room for
	# (decision 619): a bunch of herbs is picked up all at once.
	var id := items.id_of(uid)
	var i := ground_uids(cell).size() - 1
	while Items.stack_of(id) > 1 and i >= 0:
		var each := ground_uids(cell)[i]
		if items.id_of(each) == id and not axe_bound(each):
			_pick_unit(by, cell, i)
		i -= 1
	return true


## [param by] picks up the thing at [param index] on [param cell] into the
## slot it has room for (room_for): false, nothing moved, if none.
func _pick_unit(by: GridEntity, cell: Vector2i, index: int) -> bool:
	var uid := ground_uids(cell)[index]
	var slot := room_for(by, uid)
	if slot < 0:
		return false
	take_from_ground(cell, index)
	var carried_before: bool = not items.history(uid).get("carriers", []).is_empty()
	put_item(by, by, slot, uid)
	if not carried_before:
		items.note(uid, "found", "on the ground by %s" % _label_of(by), zone.name, cell)
	_log("ground: %s picked up %s at %s" % [by.name, items.id_of(uid), cell])
	return true


## A bundle of arrows taken up by [param by] holding a bow and a bundle
## (decision 375; Jeff: "player can swap it out for a fresh one, or decide
## to keep their better one"): the held bundle is put down where the new
## one lay, and the new one goes into its hand. False, nothing done, for
## anything else.
func _swap_bundle(by: GridEntity, cell: Vector2i, index: int) -> bool:
	var uid := ground_uids(cell)[index]
	if Items.ammo_of(items.id_of(uid)).is_empty() or drawn_slot(by) < 0:
		return false
	var hand := Items.LEFT_HAND if drawn_slot(by) == Items.RIGHT_HAND else Items.RIGHT_HAND
	if Items.ammo_of(by.slots[hand]).is_empty():
		return false
	take_from_ground(cell, index)
	var left := take_item(by, by, hand)
	put_item(by, by, hand, uid)
	put_on_ground(left, cell)
	_log("ground: %s swaps %s for %s at %s" % [by.name, items.id_of(left), items.id_of(uid), cell])
	bundle_swapped.emit(by, uid, left)
	return true


## The slot [param entity] would take the instance [param uid] into: a
## stack it joins (decision 619; the hands, then the pack), else
## free_slot_for's; -1 for none.
func room_for(entity: GridEntity, uid: int) -> int:
	var order: Array = [Items.RIGHT_HAND, Items.LEFT_HAND] + Items.PACK_SLOTS if has_hands(entity) else range(entity.slots.size())
	for slot: int in order:
		if slot < entity.slots.size() and stacks_onto(slot_uid(entity, slot), uid):
			return slot
	return free_slot_for(entity, items.id_of(uid))


## The slot [param entity] would take [param id] into: a free hand that
## can hold it (the right first; a two-handed thing both hands free), else
## the first free pack slot; -1 for none.
func free_slot_for(entity: GridEntity, id: String) -> int:
	if has_hands(entity):
		for hand in [Items.RIGHT_HAND, Items.LEFT_HAND]:
			if entity.slots[hand].is_empty():
				var trial := entity.slots.duplicate()
				trial[hand] = id
				if hands_allow(entity, trial):
					return hand
	if has_hands(entity):
		return free_pack_slot(entity)
	for slot in entity.slots.size():
		if entity.slots[slot].is_empty():
			return slot
	return -1


## [param uid] and every unit of its stack marked starter gear (decision
## 736: what a town's starter vendor sells). Server only.
func mark_starter(uid: int) -> void:
	if not Net.is_authority() or not items.has(uid):
		return
	items.mark_starter(uid)
	for unit in items.stack_of(uid):
		items.mark_starter(unit)


## Whether [param uid] (a slot's, its whole stack alike) is starter gear
## (decision 736): sell, barter, buy-backs and the fence refuse it.
func is_starter(uid: int) -> bool:
	return items.is_starter(uid)


## [param player_id]'s own chest (Locker, decision 722) where it stands
## open now; null for none.
func locker_of(player_id: String) -> Locker:
	for entity: GridEntity in _entities:
		if entity is Locker and (entity as Locker).player_id == player_id:
			return entity as Locker
	return null


## [param entity]'s first empty pack slot (Items.PACK_SLOTS, decision 722);
## -1 for none.
func free_pack_slot(entity: GridEntity) -> int:
	for slot: int in Items.PACK_SLOTS:
		if slot < entity.slots.size() and entity.slots[slot].is_empty():
			return slot
	return -1


## Puts the instance [param uid] on [param cell], or the nearest cell with
## room (on the floor, dry, fewer than GROUND_PER_CELL there) within
## GROUND_SPILL: where it went, NO_CELL if nowhere (it stays where it was).
## For whatever lays things down: a drop, a throw, later loot.
func put_on_ground(uid: int, cell: Vector2i, thrown_from := NO_CELL) -> Vector2i:
	var landed := _ground_room(cell, uid)
	if landed == NO_CELL or not items.has(uid):
		return NO_CELL
	var there: PackedInt32Array = zone.ground.get(landed, PackedInt32Array()).duplicate()
	there.append(uid)
	# A stack laid down whole (a body's, decision 619) lies as its units.
	for more in items.stack_of(uid):
		there.append(more)
		items.place(more, "%s@%d,%d" % [zone.name, landed.x, landed.y])
	items.set_stack(uid, PackedInt32Array())
	zone.ground[landed] = there
	items.place(uid, "%s@%d,%d" % [zone.name, landed.x, landed.y])
	ground_changed.emit(zone.name, landed, thrown_from)
	return landed


## Takes the thing at [param index] off [param cell]: its uid (0 if none).
## Whoever has it now says where it is.
func take_from_ground(cell: Vector2i, index: int) -> int:
	var there: PackedInt32Array = zone.ground.get(cell, PackedInt32Array()).duplicate()
	if index < 0 or index >= there.size():
		return 0
	var uid := there[index]
	there.remove_at(index)
	_put_down_by.erase(uid)
	if there.is_empty():
		zone.ground.erase(cell)
	else:
		zone.ground[cell] = there
	items.place(uid, "")
	ground_changed.emit(zone.name, cell, NO_CELL)
	return uid


## The whole gold lying on [param cell] of the zone World is in (601
## amended: a count on the cell's pile, never a thing). Any peer: a client
## reads the cell's replicated GroundPile, as ground_at.
func ground_gold(cell: Vector2i) -> int:
	if not Net.is_authority():
		var pile: GroundPile = zone.piles.get(cell)
		return pile.gold if is_instance_valid(pile) else 0
	return int(zone.ground_gold.get(cell, 0))


## Lays [param gold] whole gold on [param cell] of zone [param zone_name]
## (601 amended; Jeff: "consolidate gold coins to being stackable ... not
## taking up a pack slot"): added to what lies there, taking no place
## among its things; the cell itself if it is ground, else the nearest
## that is (_ground_room's search). The cell it went to, NO_CELL (and the
## gold gone) for none, 0 or less, or a zone not loaded. Server only.
func drop_gold(zone_name: String, cell: Vector2i, gold: int) -> Vector2i:
	var into: Zone = zone if zone_name.is_empty() or zone_name == zone.name else zones.get(zone_name)
	if not Net.is_authority() or gold <= 0 or into == null:
		return NO_CELL
	var was := zone
	enter(into)
	var landed := cell if is_walkable(cell) and not is_water(cell) and not is_link_cell(cell) else _ground_room(cell)
	if landed != NO_CELL:
		zone.ground_gold[landed] = int(zone.ground_gold.get(landed, 0)) + gold
		_log("ground: %d gold laid at %s" % [gold, landed])
		ground_changed.emit(zone.name, landed, NO_CELL)
	enter(was)
	return landed


## [param by] (a player) picks up all the gold on [param cell], one it
## reaches, into its record's gold (add_gold, "picked up"; 601 amended:
## no slot). The gold taken, 0 (nothing moves) if it cannot.
func try_pick_up_gold(by: GridEntity, cell: Vector2i) -> int:
	if not Net.is_authority() or not by is Player or (by as Player).player_id.is_empty() or economy == null \
			or not _can_handle(by) or not reaches_cell(by, cell):
		return 0
	var gold := int(zone.ground_gold.get(cell, 0))
	if gold <= 0:
		return 0
	zone.ground_gold.erase(cell)
	add_gold((by as Player).player_id, gold, "picked up")
	_log("ground: %s picked up %d gold at %s" % [by.name, gold, cell])
	ground_changed.emit(zone.name, cell, NO_CELL)
	return gold


## The gold an old coin purse [param uid] held (601 amended: gold is a
## count now, never a thing): its own roll (decision 601), else the old
## catalog's 10; 0 for anything else. For the migration of a saved one.
func purse_gold(uid: int) -> int:
	if items.id_of(uid) != OLD_PURSE:
		return 0
	var own := items.legacy_gold(uid)
	return own if own >= 0 else OLD_PURSE_GOLD


## The retired coin purse (601 amended) and the gold a saved one without
## its own held (its old catalog yield).
const OLD_PURSE := "coin_purse"
const OLD_PURSE_GOLD := 10


## [param by] throws what is in one of its hands ([param slot]) toward
## [param target]: a hurl (606 amended) along the line to it, as far as
## throw_reach, over water, until a wall, a closed door or higher ground
## stops it or it hits a body; the body is launched at the thing's weight x
## throw_speed (by mass: a 10 kg rock moves a 25 kg imp a cell), staggered,
## and hurt by the thing's energy. It lands on the last dry cell it reached,
## before a body it hit. False, and nothing moves, if it cannot.
func try_throw(by: GridEntity, slot: int, target: Vector2i) -> bool:
	if not Net.is_authority() or not _can_handle(by) or is_stunned(by):
		return false
	if not has_hands(by) or slot not in [Items.RIGHT_HAND, Items.LEFT_HAND] or by.slots[slot].is_empty() or target == by.tile:
		return false
	# A hurl (606 amended) toward the cell aimed at, as far as the arm sends
	# the thing, at throw_speed: a body hit is launched by mass, staggered,
	# and hurt by the thing's energy; the thing falls before it.
	var reach := mini(throw_reach(by, by.slots[slot]), distance(by.tile, target))
	var out := hurl(by, slot, Vector2(target - by.tile), reach, throw_speed, {"lands": "before", "hurts": true})
	return out["thrown"]


## A thud where [param id] came down at [param cell] (put down or thrown
## by [param by]), heard as far as its weight says.
func _thud(cell: Vector2i, id: String, by: GridEntity) -> void:
	if cell != NO_CELL:
		var heavy := Items.weight_of(id) >= THUD_HEAVY_KG
		noise(cell, Senses.NOISE_THUD_HEAVY if heavy else Senses.NOISE_THUD_LIGHT, &"thud", by)


## The weapon [param entity] fights with: what is in its right hand if it
## has a verb (Items.verb_of), else its left hand's, else "" (bare hands,
## or no hands). A guard (block) counts only if nothing else is held: a
## shield in the left hand guards (guard) while the right hand fights.
func wielded(entity: GridEntity) -> String:
	if not holds_in_hands(entity):
		return ""
	var guard_only := ""
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		var id := entity.slots[slot]
		var kind := str(Items.verb_of(id).get("kind", "")) if not id.is_empty() else ""
		if kind == "block":
			guard_only = id if guard_only.is_empty() else guard_only
		elif not kind.is_empty():
			return id
	return guard_only


## [param entity]'s guard: the block verb of what it holds (the shield
## over a sword's, the larger absorb), {} for none.
func guard(entity: GridEntity) -> Dictionary:
	var best := {}
	if holds_in_hands(entity):
		for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
			var verb := Items.verb_of(entity.slots[slot]) if not entity.slots[slot].is_empty() else {}
			if verb.get("kind") == "block" and float(verb["absorb"]) > float(best.get("absorb", -1.0)):
				best = verb
	return best


## What [param entity]'s right button does with what it holds (decision
## 329): "block" with a block verb in its left hand (a shield), "draw"
## with a ranged one in a hand (a bow, held in both), "" for neither: the
## button shoves and tosses, as with empty hands.
func off_hand(entity: GridEntity) -> String:
	if not holds_in_hands(entity):
		return ""
	var left := entity.slots[Items.LEFT_HAND]
	if not left.is_empty() and Items.verb_of(left).get("kind") == "block":
		return "block"
	if not drawn_with(entity).is_empty() and quiver_check.call(entity):
		return "draw"  # A bow with arrows to shoot (decision 375).
	return ""


## The hand [param entity]'s bundle of arrows is in, the one its bow is not
## (decision 375), while it has condition left; -1 for none.
func bundle_slot(entity: GridEntity) -> int:
	var bow := drawn_slot(entity)
	if bow < 0:
		return -1
	var other := Items.LEFT_HAND if bow == Items.RIGHT_HAND else Items.RIGHT_HAND
	if Items.ammo_of(entity.slots[other]).is_empty():
		return -1
	if other < entity.slot_items.size() and entity.slot_items[other] != 0 and items.condition_of(entity.slot_items[other]) == 0:
		return -1  # Spent: the fletcher mends it.
	return other


## A blunt hit on [param entity] (decision 375: a blunt weapon's blow, an
## impact, a knockdown) wears the bundle of arrows in its hands by one.
func _wear_bundle(entity: GridEntity) -> void:
	if not Net.is_authority() or not _alive(entity) or not holds_in_hands(entity):
		return
	for slot in [Items.RIGHT_HAND, Items.LEFT_HAND]:
		if slot < entity.slot_items.size() and not Items.ammo_of(entity.slots[slot]).is_empty():
			var uid := slot_uid(entity, slot)
			if items.condition_of(uid) > 0:
				items.set_condition(uid, items.condition_of(uid) - 1)
				_log("wear: %s's %s %d of %d" % [entity.name, entity.slots[slot], items.condition_of(uid), Items.condition_max(entity.slots[slot])])
				if entity.raised == "draw" and off_hand(entity) != "draw":
					entity.raised = ""  # Spent.
				_show_notes(entity)
			return


## [param entity] is ailed by [param kind] ("burn", "bleed"; decision
## 375) for [param ticks], losing [param amount] hp every [param every];
## a new one replaces a shorter. Burning is for what fire hurts (FLESH,
## WOOD), bleeding for creatures.
func afflict(entity: GridEntity, kind: String, ticks: int, every: int, amount: int) -> void:
	if not Net.is_authority() or not _alive(entity) or ticks <= 0 or amount <= 0 or is_sheltered(entity):
		return  # (Arriving, decision 661: nothing takes hold.)
	if kind == "bleed" and not entity.is_creature() or kind == "burn" and not entity.is_breakable():
		return
	var until := tick + ticks
	if int(entity.ailments.get(kind, [0])[0]) >= until:
		return
	var ailing := entity.ailments.duplicate()
	ailing[kind] = [until, maxi(every, 1), amount]
	entity.ailments = ailing
	_log("ail: %s %s for %d ticks" % [entity.name, kind, ticks])


## [param entity]'s [param kind] ailment ends now (a bandage stops bleeding).
func cure(entity: GridEntity, kind: String) -> void:
	if entity.ailments.has(kind):
		var ailing := entity.ailments.duplicate()
		ailing.erase(kind)
		entity.ailments = ailing


## What ails the zone's entities hurts them, every so often, until it ends.
func _tend_ailments() -> void:
	for entity in _entities.duplicate():
		if entity.ailments.is_empty() or not _alive(entity):
			continue
		for kind: String in entity.ailments.keys():
			var ail: Array = entity.ailments[kind]
			if tick >= int(ail[0]):
				cure(entity, kind)
			elif (int(ail[0]) - tick) % int(ail[1]) == 0:
				# No blow: the wound breaks no calm, so a bleeding body can be
				# bandaged (calm, BANDAGE_CALM_TICKS; decision 375).
				var hurt: int = entity.hurt_tick
				damage(entity, int(ail[2]), null, &"fire" if kind == "burn" else &"bleed")
				entity.hurt_tick = hurt
				if not _alive(entity):
					break


## The ranged thing in [param entity]'s hands (left first), "" for none.
func drawn_with(entity: GridEntity) -> String:
	var slot := drawn_slot(entity)
	return entity.slots[slot] if slot >= 0 else ""


## The hand [param entity]'s bow is in (drawn_with); -1 for none.
func drawn_slot(entity: GridEntity) -> int:
	if not holds_in_hands(entity):
		return -1
	for slot in [Items.LEFT_HAND, Items.RIGHT_HAND]:
		var id := entity.slots[slot]
		if not id.is_empty() and Items.verb_of(id).get("kind") == "ranged":
			return slot
	return -1


## [param by] raises its off hand (the right button pressed): [param kind]
## "block" or "draw", as off_hand says it can; "" lowers it (released). A
## stance is only shown and kept: combat (the roadmap's weapons as verbs)
## reads it. False if it holds nothing for it. A [param lob] draw (decision
## 677, the right button) aims at the sky, loosed by try_lob; one drawn the
## other way already is kept, false.
func try_stance(by: GridEntity, kind: String, lob := false) -> bool:
	if not Net.is_authority() or not is_instance_valid(by):
		return false
	if kind.is_empty():
		by.raised = ""
		by.lobbing = false
		return true
	if kind != off_hand(by) or kind == "draw" and not quiver_check.call(by):
		return false
	if kind == "block" and tick < by.guard_broken_until or is_stunned(by):
		return false  # A broken guard comes back up only after a while; nothing is raised reeling or lying.
	if by.raised == "draw" and kind == "draw" and by.lobbing != lob:
		return false  # One draw at a time (677).
	if by.raised != kind:
		by.raised = kind
		by.raised_tick = tick
		by.lobbing = lob and kind == "draw"
		if kind == "draw":
			stand_firm(by)
	return true


## [param by] stopped where it stands (583 amended; Jeff: "the point of
## shift is to stand firm and start nocking"): a free body's walk halted,
## an attack walked to dropped.
func stand_firm(by: GridEntity) -> void:
	if free_body(by):
		halt(by, tick)  # A free body's walk stops where it is (688).
	by.action_order = GridEntity.Order.NONE
	by.action_target = null


## How far [param entity]'s bow is drawn, 0 to 1: nothing until its verb's
## draw_min ticks, full at draw_full (its longest step); 0 when not
## drawing. For the pull's pose and the creak; what it shoots is its step.
func draw_of(entity: GridEntity) -> float:
	if not is_instance_valid(entity) or entity.raised != "draw":
		return 0.0
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty():
		return 0.0
	var drawn := tick - entity.raised_tick
	var quick := _draw_quick(entity)
	if drawn < roundi(int(verb["draw_min"]) * quick):
		return 0.0
	return clampf(float(drawn) / draw_full_ticks(entity), 0.0, 1.0)


## A quick bow (decision 365) draws in less time, and one drawn by loaded
## arms in more (decision 676: arms_load, the armour's arm share on top of
## the bow and its arrows; it took the place of the armour's "draw"): its
## ticks' multiple.
func _draw_quick(entity: GridEntity) -> float:
	return float(Items.strength_value(slot_strength(entity, drawn_slot(entity)), "draw", 1.0)) * arms_load(entity)


## The multiple of its bow's draw ticks [param entity] draws in (_draw_quick):
## the views' pull reads it as the sim does.
func draw_quick(entity: GridEntity) -> float:
	return _draw_quick(entity)


## The last of its bow's steps [param entity] can reach (decisions 622
## step 2, 669): the bow's last step. Armour caps no reach (622 amended;
## Jeff: "items shouldnt have direct impacts, they should just form stats
## like weight/mass"); the arms' load scales the ticks (676).
func step_cap(entity: GridEntity) -> int:
	return (Items.verb_of(drawn_with(entity)).get("steps", []) as Array).size() - 1


## The ticks [param entity]'s bow takes to full draw (decision 669: its
## verb's full step), quickness counted: where the pull is full.
func draw_full_ticks(entity: GridEntity) -> float:
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty():
		return 1.0
	return maxf(1.0, Items.step_ticks(verb, int(verb["full"])) * _draw_quick(entity))


## The step [param entity]'s drawn bow has reached (decisions 583, 669;
## Items.step_at over its ticks drawn, quickness counted): 0, the verb's
## first, at draw_min ticks, one more as each of its draw_steps passes,
## held at the bow's last (step_cap); -1 before
## draw_min or when not drawing.
func draw_step(entity: GridEntity) -> int:
	if not is_instance_valid(entity) or entity.raised != "draw":
		return -1
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty():
		return -1
	var held := float(tick - entity.raised_tick) / maxf(0.01, _draw_quick(entity))
	if entity.lobbing:
		held -= float(verb.get("lob_draw_min", verb["draw_min"])) - float(verb["draw_min"])  # 677: the lob's first step later.
	var step := Items.step_at(verb, held)
	return -1 if step < 0 else mini(step, step_cap(entity))


## The cells a shot from [param entity]'s bow drawn to [param step]
## reaches (decision 669): that step's; 0 for no step.
func reach_at(entity: GridEntity, step: int) -> int:
	var steps: Array = Items.verb_of(drawn_with(entity)).get("steps", [])
	if step < 0 or steps.is_empty():
		return 0
	return int(steps[mini(step, steps.size() - 1)])


## The cells [param entity]'s drawn bow reaches now (its step's;
## decisions 583, 669); 0 before draw_min or when
## not drawing. What the views show.
func range_of(entity: GridEntity) -> int:
	return reach_at(entity, draw_step(entity))


## The cells within which [param entity]'s drawn bow strikes at full
## strength (decision 669): full draw's reach,
## shown on the aim once it is drawn past full draw; 0 before full draw or
## when not drawing.
func full_range_of(entity: GridEntity) -> int:
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty() or draw_step(entity) < int(verb.get("full", 0)):
		return 0
	return reach_at(entity, int(verb["full"]))


## The damage multiple of a shot from [param entity]'s bow drawn to
## [param step] striking a body [param away] cells off (Items.damage_for;
## decision 669).
func shot_strength(entity: GridEntity, step: int, away: int) -> float:
	return Items.damage_for(Items.verb_of(drawn_with(entity)), step, away)


## The cells the bow in [param entity]'s hands reaches at its longest step
## (step_cap; decisions 622 step 2, 669); 0 with none.
func longest_range(entity: GridEntity) -> int:
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty() or (verb.get("steps", []) as Array).is_empty():
		return int(verb.get("cells", 0))
	return reach_at(entity, step_cap(entity))


## The half-angle in radians of the cone [param entity]'s drawn bow
## looses in now (decision 620; Items.spread_at from its hold, which
## replicates, so a client's cone is the server's), narrowed by a steady
## buff (decision 642: buffs replicate too); -1 when not drawing.
func spread_of(entity: GridEntity) -> float:
	if not is_instance_valid(entity) or entity.raised != "draw":
		return -1.0
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty():
		return -1.0
	var steady := clampf(buff(entity, "steady"), 0.0, 1.0)
	return Items.spread_at(verb, float(tick - entity.raised_tick) / maxf(0.01, _draw_quick(entity))) * (1.0 - steady)


## The angle [param by]'s arrow flies at, aimed at [param angle] in a cone
## of half-angle [param spread] (decision 620): the aim plus spread times
## half the sum of two rolls in -1..1 (most near the aim, the edge rare),
## seeded by shot_salt, its name and the tick. No spread, the aim.
func scatter(by: GridEntity, angle: float, spread: float) -> float:
	if spread <= 0.0 or not is_instance_valid(by):
		return angle
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%d/%s/%d" % [shot_salt, by.name, tick])
	return angle + spread * (roll.randf_range(-1.0, 1.0) + roll.randf_range(-1.0, 1.0)) / 2.0


## [param by] lets its drawn bow go at [param angle] (radians on the grid,
## Vector2.angle(): 0 east, PI / 2 south; the right button released):
## loosed is emitted with its step (draw_step) and the aim, and it shoots
## (shoot) along a line rolled in its cone (scatter, spread_of; decision
## 620), facing the aim; before the first step, nothing. The stance ends
## either way.
func try_loose(by: GridEntity, angle: float) -> bool:
	if not Net.is_authority() or not is_instance_valid(by) or by.raised != "draw" or by.lobbing or not is_finite(angle):
		return false
	var step := draw_step(by)
	var spread := spread_of(by)  # Before the stance ends: after it, none.
	by.raised = ""
	if step < 0:
		return false
	var flown := scatter(by, angle, spread)
	_log("loose: %s at %.2f rad, flies %.2f (cone %.2f), step %d" % [by.name, angle, flown, spread, step])
	loosed.emit(by, angle, step)
	shoot(by, flown, step, angle)
	return true


## The radius in cells of the circle [param entity]'s lob comes down in
## now (decision 677): its verb's lob_circle at its step; -1 when not
## lobbing or before the first step.
func lob_radius(entity: GridEntity) -> float:
	if not is_instance_valid(entity) or entity.raised != "draw" or not entity.lobbing:
		return -1.0
	var step := draw_step(entity)
	var circle: Array = Items.verb_of(drawn_with(entity)).get("lob_circle", [])
	if step < 0 or circle.is_empty():
		return -1.0
	return float(circle[mini(step, circle.size() - 1)])


## The radius in cells of the circle [param entity]'s lob aimed at [param
## cell] comes down in (677 amended (3); Jeff: "with short range shots the
## cone moves around wildly"): lob_radius scaled by the aim's share of the
## reach drawn (lob_aim over range_of), so a near lob's circle is as narrow
## for its distance as a far one's, at least lob_volley_min; -1 as
## lob_radius. The server rolls the falls in it and the aim draws it.
func lob_circle_at(entity: GridEntity, cell: Vector2i) -> float:
	var radius := lob_radius(entity)
	var reach := range_of(entity)
	if radius < 0.0 or reach <= 0:
		return radius
	var share := minf(1.0, Vector2(lob_aim(entity, cell)).distance_to(shot_origin(entity)) / float(reach))
	return maxf(float(Items.verb_of(drawn_with(entity)).get("lob_volley_min", 1.0)), radius * share)


## The cell [param entity]'s lob aimed at [param cell] is aimed at (decision
## 677): that cell, drawn in along the line to the reach drawn so far
## (range_of); its own cell before the first step.
func lob_aim(entity: GridEntity, cell: Vector2i) -> Vector2i:
	var reach := range_of(entity)
	var start := shot_origin(entity)  # A free body's centre (688).
	var way := Vector2(cell) - start
	if reach <= 0:
		return entity.tile
	if way.length() > float(reach):
		way = way.normalized() * float(reach)
	return Vector2i((start + way).round())


## Whether a lob may come down on [param cell] (decision 677): ground under
## open sky, never a wall's cell, a roof's or indoors.
func lob_open(cell: Vector2i) -> bool:
	return is_walkable(cell) and fields.under_sky(cell)


## Where an arrow lobbed from [param from] to [param to] is [param t] (0 to
## 1) of its flight (decision 677; the views fly it, physics reads it): the
## line between, lifted on a parabola [param apex] times the ground
## covered at its height.
static func lob_point(from: Vector3, to: Vector3, t: float, apex := 0.25) -> Vector3:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	return from.lerp(to, t) + Vector3.UP * 4.0 * apex * flat * t * (1.0 - t)


## The ticks an arrow lobbed [param cells] off by a bow of [param verb] is
## aloft (decision 677): lob_flight plus lob_per_cell each cell, at least 1.
static func lob_ticks(verb: Dictionary, cells: int) -> int:
	return maxi(1, roundi((float(verb.get("lob_flight", 0.6)) + float(verb.get("lob_per_cell", 0.05)) * cells) * TICK_RATE))


## Lobs in the air (decision 677; try_lob, _tend_lobs): {by, zone, cell,
## at (the zone's tick it comes down), amount, down, slot}.
var _lobs: Array[Dictionary] = []


## [param by] lets its lobbed bow go (decision 677; Jeff: "right click hold
## and release to fire"): aimed at [param cell] (lob_aim), it comes down in
## a cell rolled in its circle (lob_circle_at; the aim if that one is closed),
## lob_ticks later, when whoever stands there is struck (_tend_lobs). Its
## loose costs lob_cost stamina. Before the first step, or with the aim
## not open to the sky (lob_open), nothing, the arrow kept. The stance
## ends either way.
func try_lob(by: GridEntity, cell: Vector2i) -> bool:
	if not Net.is_authority() or not is_instance_valid(by) or by.raised != "draw" or not by.lobbing:
		return false
	var verb := Items.verb_of(drawn_with(by))
	var step := draw_step(by)
	var aimed := lob_aim(by, cell)
	var radius := lob_circle_at(by, cell)
	by.raised = ""
	by.lobbing = false
	if step < 0 or verb.is_empty() or aimed == by.tile or not lob_open(aimed):
		return false
	var falls := volley_falls(aimed, radius, int(verb.get("lob_volley", 3)),
			hash("lob/%d/%s/%d" % [shot_salt, by.name, tick]))
	if by.max_stamina > 0 and by.pays_swings:
		by.stamina = maxi(0, by.stamina - int(verb.get("lob_cost", 0)))
		by._world_note_exertion(tick)
	var ticks := lob_ticks(verb, distance(by.tile, aimed))
	var way := Vector2(aimed - by.tile).normalized()
	by._world_set_facing(Vector2i(roundi(way.x), roundi(way.y)))
	_lobs.append({"by": by, "zone": zone.name, "falls": falls, "at": tick + ticks, "next": 0, "struck": {},
		"amount": maxi(1, roundi(by.attack_damage * float(verb["damage"]) * float(verb.get("lob_damage", 1.0)))),
		"down": int(verb.get("lob_down", 0)), "slot": drawn_slot(by)})
	_log("lob: %s at %s, %d falls in a circle %.1f (step %d) from %d ticks" % [by.name, aimed, falls.size(), radius, step, ticks])
	by._world_lobbed(aimed, ticks, radius, falls)
	noise(by.tile, NOISE_BOW, &"bow", by)
	return true


## A volley's [param count] falls in the circle [param radius] about
## [param centre] (677 amended (2)), rolled by [param seed]: points in cell
## units, each in a cell open to the sky (lob_open), rolled again a few
## times, else the centre.
func volley_falls(centre: Vector2i, radius: float, count: int, seed_value: int) -> PackedVector2Array:
	var roll := RandomNumberGenerator.new()
	roll.seed = seed_value
	var falls := PackedVector2Array()
	for i in count:
		var at := Vector2(centre)
		for attempt in 4:
			var point := Vector2(centre) + Vector2.from_angle(roll.randf() * TAU) * radius * sqrt(roll.randf())
			if lob_open(Vector2i(point.round())):
				at = point
				break
		falls.append(at)
	return falls


## Each tick, the volleys due in this zone come down (decision 677; 677
## amended (2): a fall a tick from "at"): whoever's struck cell holds a
## fall's point then (struck_cell: a free body by its centre, 699) takes
## one arrow's damage (no guard meets it; armour's deflect_shot does), and
## the first of a volley to strike a body knocks it down lob_down ticks (a
## draugr staggers: knock_down); a friend is spared, as by a flat shot.
## Nobody there, a thud. lob_landed each fall either way.
func _tend_lobs() -> void:
	for lob: Dictionary in _lobs.duplicate():
		if lob["zone"] != zone.name:
			continue
		var falls: PackedVector2Array = lob["falls"]
		while int(lob["next"]) < falls.size() and tick >= int(lob["at"]) + int(lob["next"]):
			_lob_falls(lob, Vector2i(falls[int(lob["next"])].round()))
			lob["next"] = int(lob["next"]) + 1
		if int(lob["next"]) >= falls.size():
			_lobs.erase(lob)


func _lob_falls(lob: Dictionary, cell: Vector2i) -> void:
	var by: GridEntity = lob["by"] if is_instance_valid(lob["by"]) else null
	var hit: GridEntity = null
	for body in bodies_struck_at(cell) if by != null else []:
		if body != by and _alive(body):
			hit = body
			break
	if hit == null or not can_target(by, hit) or spares(by, hit) or not hit.is_breakable():
		noise(cell, Senses.NOISE_THUD_LIGHT, &"thud", by)
		lob_landed.emit(by, cell, null)
		return
	var amount := armour_turns(hit, int(lob["amount"]), "deflect_shot")
	_log("lob: %s's hits %s at %s for %d" % [by.name, hit.name, cell, amount])
	if amount > 0 and not is_sheltered(hit):
		damage(hit, amount, by, &"shot")
		if hit.is_creature():
			_credit(by, int(lob["slot"]), "felled" if not _alive(hit) else "shot")
			if not _alive(hit):
				_felled_with(by, int(lob["slot"]), hit)
		if _alive(hit) and not (lob["struck"] as Dictionary).has(hit):
			knock_down(hit, by, int(lob["down"]))
		(lob["struck"] as Dictionary)[hit] = true
	lob_landed.emit(by, cell, hit)


## [param by]'s shot at [param angle], its bow drawn to [param step]
## (decision 583; 335 before it). Along the ray from its cell's centre
## (shot_aim), as far as that step's cells, it hits the first body there; a
## wall, a closed door, higher ground or the map's end stops it first, and
## past its range it comes down. A body it may not attack (can_target) or a
## friend it spares (spares) stops it unharmed. Damage is its blow
## (attack_damage) times the bow's damage times its damage_for (decision
## 669: the step's up to full draw, past it the band the body stands in),
## at least 1, cause &"shot"; no push. It faces the
## shot (or [param aimed], where it aimed, when its arrow strayed), is heard
## NOISE_BOW about it, and the views draw the arrow's flight to where it
## stopped and what stopped it (GridEntity.shot). The body struck, or null.
func shoot(by: GridEntity, angle: float, step: int, aimed := NAN) -> GridEntity:
	if not Net.is_authority() or not is_instance_valid(by) or step < 0 or not is_finite(angle):
		return null
	var verb := Items.verb_of(drawn_with(by))
	if verb.is_empty():
		return null
	step = mini(step, (verb["steps"] as Array).size() - 1)
	var aim := shot_aim(by, angle, reach_at(by, step))
	var hit: GridEntity = aim["hit"]
	var way := Vector2.from_angle(angle if is_nan(aimed) else aimed)
	by._world_set_facing(Vector2i(roundi(way.x), roundi(way.y)))
	by._world_shot(aim["end"], aim["struck"])
	noise(by.tile, NOISE_BOW, &"bow", by)
	if hit == null:
		# A miss lands with a thud where it stops (397 amended (2); Jeff's
		# hunting: "you want to have distance"): game near it bolts, the shot
		# heard where it fell, not only at the bow.
		noise(aim["cell"], Senses.NOISE_THUD_LIGHT, &"thud", by)
	if hit == null or not can_target(by, hit) or spares(by, hit) or not hit.is_breakable():
		_log("shot: %s at %.2f rad, step %d, %s" % [by.name, angle, step, "nothing hit (%s at %s)" % [aim["struck"], aim["end"]] if hit == null else "stopped by %s" % hit.name])
		return null
	var amount := maxi(1, roundi(by.attack_damage * float(verb["damage"]) * Items.damage_for(verb, step, distance(by.tile, hit.tile))))
	var met: Variant = _meet_guard(hit, by, amount, 0.0, true)
	if met != null:
		amount = met[0]
	amount = armour_turns(hit, amount, "deflect_shot")
	_log("shot: %s hits %s at %s for %d, step %d" % [by.name, hit.name, hit.tile, amount, step])
	if amount > 0 and not is_sheltered(hit):  # (Arriving, 661: no harm, no credit.)
		var creature := hit.is_creature()
		var ammo := Items.ammo_of(by.slots[bundle_slot(by)]) if bundle_slot(by) >= 0 else {}
		damage(hit, amount, by, &"shot")
		if creature:
			_credit(by, drawn_slot(by), "felled" if not _alive(hit) else "shot")
			if not _alive(hit):
				_felled_with(by, drawn_slot(by), hit)
		if not str(ammo.get("effect", "")).is_empty() and _alive(hit):
			afflict(hit, ammo["effect"], int(ammo["ticks"]), int(ammo["every"]), int(ammo["amount"]))  # Flame, barbed.
	return hit


## The guard [param target] meets a blow from [param source]'s side with
## (decision 340): a raised shield's (raised "block": the block verb in
## its left hand) when the blow comes within its arc of where the target
## faces (arc: 45 degree steps either side; a shield's 1, the facing cell
## and the two beside it); else, raising nothing and its next blow ready
## (not mid-swing), a sword's in its right hand (arc 0, straight ahead).
## {} for none, and when stunned.
func guarding(target: GridEntity, source: GridEntity) -> Dictionary:
	if not holds_in_hands(target) or is_stunned(target) or not is_instance_valid(source) or source.tile == target.tile:
		return {}
	var held := ""
	if target.raised == "block":
		if tick >= target.bash_moment_until:  # Down for a bash's moment (decision 379).
			held = target.slots[Items.LEFT_HAND]
	elif target.raised.is_empty() and tick >= target.next_attack_tick and target.wind_up.is_empty():
		held = target.slots[Items.RIGHT_HAND]  # Not mid-lead (338 amended): the sword is swinging.
	var verb := Items.verb_of(held) if not held.is_empty() else {}
	if verb.get("kind") != "block" or target.facing == Vector2i.ZERO:
		return {}
	var off := absf((body_centre(source) - body_centre(target)).angle_to(Vector2(target.facing)))  # Centres (699).
	return verb if off <= float(verb["arc"]) * PI / 4.0 + 0.01 else {}


## A blow of [param amount] damage and [param force] (its push before
## knockback_min_force; 0 for a shot) from [param source] on
## [param target], met by its guard (guarding; decision 340): null when
## there is none, else [damage, force] what is left. A blow weighs its
## damage plus its force: the guard pays the verb's stamina times that (at
## least 1) and takes absorb of both (a shield all, a sword half, the
## damage taken off rounded up). A blow weighing breaks_at or more (a
## brute's, a hammer's; never a [param shot]), or too little stamina,
## breaks it: the blow lands whole, the shield is lowered, its holder
## stunned GUARD_BREAK_STUN and unable to raise one again for
## GUARD_BROKEN_TICKS. A [param crushing] blow (a wound-up one, decision
## 392) breaks it whatever it weighs.
func _meet_guard(target: GridEntity, source: GridEntity, amount: int, force: float, shot := false,
		crushing := false) -> Variant:
	var verb := guarding(target, source)
	if verb.is_empty() or is_sheltered(target):
		return null  # (Arriving, decision 661: nothing reaches its guard.)
	var weight := amount + force
	var slot := Items.LEFT_HAND if target.raised == "block" else Items.RIGHT_HAND  # As guarding found it.
	var steady := float(Items.strength_value(slot_strength(target, slot), "guard_stamina", 1.0))
	var cost := maxi(1, ceili(float(verb["stamina"]) * weight * steady))
	target._world_note_exertion(tick)
	if (weight >= float(verb["breaks_at"]) or crushing) and not shot or target.max_stamina > 0 and target.stamina < cost:
		if target.max_stamina > 0:
			target.stamina = maxi(0, target.stamina - cost)
		target.raised = ""
		target.guard_broken_until = tick + GUARD_BROKEN_TICKS
		_stun_for(target, GUARD_BREAK_STUN)
		_log("guard: %s's guard broken by %s (a blow of %d, force %.2f)" % [target.name, source.name, amount, force])
		target._world_guarded(true)
		guard_met.emit(target, source, true)
		return [amount, force]
	if target.max_stamina > 0:
		target.stamina -= cost
	var absorb := clampf(float(verb["absorb"]), 0.0, 1.0)
	_log("guard: %s takes %s's blow (%d, force %.2f) for %d stamina" % [target.name, source.name, amount, force, cost])
	target._world_guarded(false)
	guard_met.emit(target, source, false)
	_credit(target, slot, "guarded")
	return [maxi(0, amount - ceili(amount * absorb - 0.001)), force * (1.0 - absorb)]


## Whether [param by]'s arrow spares [param body] (decision 456; Jeff:
## "arrows dont harm friendlies, but it might hit and stick out for a
## little while"): a player's or a companion's shot ends at a resident, a
## companion or a player on the line, no harm, no stagger, no ailment (the
## views stick the arrow in them a while). A monster's is never stopped.
static func spares(by: GridEntity, body: GridEntity) -> bool:
	return (by is Player or by is Companion) and (body is Resident or body is Companion or body is Player)


## Where [param by]'s shot at [param angle] would go with the bow in its
## hands, reaching [param cells] (its longest step's when under 0; decision
## 583): {end: the point it stops at (cell units, a cell's centre at
## Vector2(cell)), cell: the last cell it crosses (its own if none), hit:
## the first body on the way, or null, struck: what stopped it, &"body"
## or shot_ray's}; {} with no bow. The server's shoot, a client's aim while
## drawing (Main) and an archer's clear shot (Monster) read the same ray.
func shot_aim(by: GridEntity, angle: float, cells := -1) -> Dictionary:
	var verb := Items.verb_of(drawn_with(by))
	if verb.is_empty() or not is_finite(angle):
		return {}
	var start := shot_origin(by)
	var ray := shot_ray(by.tile, angle, int(verb["cells"]) if cells < 0 else cells, start)
	var out := {"end": ray["end"], "cell": by.tile, "hit": null, "struck": ray["struck"]}
	var way := Vector2.from_angle(angle)
	for cell: Vector2i in ray["cells"]:
		out["cell"] = cell
		var body: GridEntity = _occupancy.get(cell)
		if body != null and body != by:
			out["hit"] = body
			out["struck"] = &"body"
			out["end"] = start + way * maxf(0.0, way.dot(Vector2(cell) - start))  # Abreast of its centre.
			break
	return out


## The ray of a shot from [param from]'s centre at [param angle] (radians
## on the grid; decision 583), at most [param cells] away as
## World.distance counts (Chebyshev: as far along a diagonal as straight):
## {cells: every cell it crosses, in order, not its own; where it passes
## exactly through a corner, both cells beside it too (a supercover: no
## slipping between two bodies), end: the point it stops at, struck: what
## stopped it, &"wood" (a closed door), &"stone" (a wall, higher ground,
## the map's end) or &"ground" (its range spent: it comes down past end);
## &"body" is shot_aim's, a body on the way}.
## A wall edge or a closed door is crossed as sight is
## (_sight_crosses_edge); over relief (decision 525) the arrow flies from
## the eye toward the aim height over the range's end, and ground above
## that stops it. [param origin]: where in [param from] it starts, a free
## body's centre (688, combat's side; shot_origin); the cell's centre if not
## given.
func shot_ray(from: Vector2i, angle: float, cells: int, origin := Vector2(NAN, NAN)) -> Dictionary:
	var out: Array[Vector2i] = []
	var start := origin if origin.is_finite() else Vector2(from)
	var result := {"cells": out, "end": start, "struck": &"ground"}
	if cells <= 0 or not is_finite(angle):
		return result
	var way := Vector2.from_angle(angle)
	way = Vector2(0.0 if absf(way.x) < 1e-9 else way.x, 0.0 if absf(way.y) < 1e-9 else way.y)
	var reach := float(cells) / maxf(absf(way.x), absf(way.y))
	var s := Vector2i(1 if way.x > 0.0 else -1, 1 if way.y > 0.0 else -1)
	var delta := Vector2(INF if way.x == 0.0 else 1.0 / absf(way.x), INF if way.y == 0.0 else 1.0 / absf(way.y))
	# The ray's length to the first cell side across, each axis (half a cell from the centre).
	var next := Vector2(INF if way.x == 0.0 else (float(from.x) + 0.5 * s.x - start.x) / way.x,
		INF if way.y == 0.0 else (float(from.y) + 0.5 * s.y - start.y) / way.y)
	var top := height_at(from)
	var eye := elevation_at(from) + Relief.EYE_M
	var aim_at: Vector2i = Vector2i((start + way * reach).round())
	var drop_per_cell := (eye - elevation_at(aim_at) - Relief.AIM_M) / reach
	var at := from
	while true:
		var t := minf(next.x, next.y)
		if t > reach + 1e-6:
			result["end"] = start + way * reach
			return result
		var step := Vector2i(s.x if next.x - t < 1e-6 else 0, s.y if next.y - t < 1e-6 else 0)
		var point := start + way * t
		if step.x != 0 and step.y != 0:
			for side: Vector2i in [Vector2i(step.x, 0), Vector2i(0, step.y)]:
				if not edge_blocks_sight(at, side) and _shot_open(from, at + side, eye, drop_per_cell, top):
					out.append(at + side)
		if _sight_crosses_edge(at, step):
			result["end"] = point
			result["struck"] = _edge_struck(at, step)
			return result
		if not _shot_open(from, at + step, eye, drop_per_cell, top):
			result["end"] = point
			result["struck"] = &"stone"
			return result
		at += step
		out.append(at)
		next += Vector2(delta.x if step.x != 0 else 0.0, delta.y if step.y != 0 else 0.0)
	return result


## Whether a shot from [param from] flies through [param cell]: ground or
## water, and not above the arrow (shot_ray's line, or without relief no
## higher than the shooter's cell).
func _shot_open(from: Vector2i, cell: Vector2i, eye: float, drop_per_cell: float, top: float) -> bool:
	if not (is_walkable(cell) or is_water(cell)):
		return false
	if _relief_given:
		return elevation_at(cell) <= eye - drop_per_cell * Vector2(from).distance_to(Vector2(cell))
	return height_at(cell) <= top


## What a shot crossing from [param at] by [param step] meets on the edge
## that stops it: &"wood" for a closed door on any edge of the way, else
## &"stone".
func _edge_struck(at: Vector2i, step: Vector2i) -> StringName:
	var edges: Array = [[at, step]]
	if step.x != 0 and step.y != 0:
		var via_x := Vector2i(step.x, 0)
		var via_y := Vector2i(0, step.y)
		edges = [[at, via_x], [at + via_x, via_y], [at, via_y], [at + via_y, via_x]]
	for edge: Array in edges:
		var door := door_across(edge[0], edge[1])
		if door != null and not door.open:
			return &"wood"
	return &"stone"


## Whether [param entity] carries the key to [param lock] (a thing whose
## catalog "opens" is it), in its pack or a hand: World.key_check's own.
func holds_key(entity: GridEntity, lock: String) -> bool:
	if lock.is_empty() or not is_instance_valid(entity):
		return false
	for id in entity.slots:
		if not id.is_empty() and Items.opens_of(id) == lock:
			return true
	return false


## [param by] uses what is in its slot [param slot], by the thing's catalog
## use: a bandaging kit ("bandage") bandages [param by] (try_bandage). A
## thing with effects (food, a draught, a
## charm) is consumed, whatever its use is called ("eat", "drink"...): its
## buffs go on [param by] (add_buff) and it is gone. A key is used by
## carrying it (holds_key). False, and nothing happens, if it cannot.
func try_use(by: GridEntity, slot: int) -> bool:
	if not Net.is_authority() or not _can_handle(by) or is_stunned(by):
		return false
	if slot < 0 or slot >= by.slots.size() or by.slots[slot].is_empty():
		return false
	var id := by.slots[slot]
	var effects: Array = Items.def(id).get("effects", [])
	if not effects.is_empty():
		var uid := take_item(by, by, slot)
		if uid == 0:
			return false
		items.end(uid, "consumed", "by %s" % _label_of(by), zone.name, by.tile)
		for effect: Dictionary in effects:
			add_buff(by, effect["kind"], effect["amount"], effect["ticks"])
		_log("use: %s consumed %s" % [by.name, id])
		return true
	match str(Items.def(id).get("use", "")):
		"bandage":
			return try_bandage(by, by)
	return false


## Puts a buff on [param entity]: [param kind] (Items.BUFF_KINDS) raised by
## [param amount] for [param ticks]. Buffs of a kind do not add up: one on
## already keeps the larger amount and the later end (a second meal tops
## the first up, it does not double it). Mass shows at once (_weigh).
func add_buff(entity: GridEntity, kind: String, amount: float, ticks: int) -> void:
	if not Net.is_authority() or kind not in Items.BUFF_KINDS or amount <= 0.0 or ticks <= 0:
		return
	var now: Dictionary = entity.buffs.duplicate(true)
	var had: Array = now.get(kind, [])
	now[kind] = [maxf(amount, float(had[0])) if not had.is_empty() else amount,
		maxi(tick + ticks, int(had[1])) if not had.is_empty() else tick + ticks]
	if kind == "heal":
		now[kind].append(tick)  # Its start: the drink's own tick heals nothing (682), whichever runs first.
	entity.buffs = now
	_buffed[entity] = true
	if kind == "mass":
		_weigh(entity)
	buff_changed.emit(entity, kind, &"started" if had.is_empty() else &"renewed")


## How much [param kind] is raised on [param entity] now (0 for none): for
## whatever reads aura or wits; mass is already in its mass.
func buff(entity: GridEntity, kind: String) -> float:
	var on: Array = entity.buffs.get(kind, [])
	return float(on[0]) if not on.is_empty() else 0.0


## Buffs whose time is up wear off (this zone's buffed only).
func _fade_buffs() -> void:
	if _buffed.is_empty():
		return
	# One freed some other way never goes into a typed variable, nor is
	# looked up or erased by (a typed dictionary refuses a freed key):
	# the live ones are kept (decision 572 amended).
	if _buffed.keys().any(func(held: Variant) -> bool: return not is_instance_valid(held)):
		var live: Dictionary[GridEntity, bool] = {}
		for held: Variant in _buffed.keys():
			if is_instance_valid(held):
				live[held] = true
		_buffed = live
	for entity: GridEntity in _buffed.keys():
		if entity.zone != zone.name:
			continue
		_heal_tick(entity)
		var now: Dictionary = entity.buffs.duplicate(true)
		var faded: Array[String] = []
		for kind: String in entity.buffs:
			if int(entity.buffs[kind][1]) <= tick:
				now.erase(kind)
				faded.append(kind)
		if faded.is_empty():
			continue
		entity.buffs = now
		if now.is_empty():
			_buffed.erase(entity)
		if "mass" in faded:
			_weigh(entity)
		for kind in faded:
			_log("buff: %s's %s wore off" % [entity.name, kind])
			buff_changed.emit(entity, kind, &"faded")


## A heal buff on [param entity] (decision 682; physics' rules) gives its
## amount in hp a second, whole hp at TICK_RATE (_carried: 1 a second is 20
## over 200 ticks: the ticks after its start, on[2], to its end, so a drink
## heals its amount x ticks whether it came before this pass or after),
## never past max_hp (heal) nor to a downed body; a hit does not stop it
## and a bleed or a burn runs beside it. At death it ends (this pass fades it).
func _heal_tick(entity: GridEntity) -> void:
	var on: Array = entity.buffs.get("heal", [])
	if on.is_empty() or int(on[1]) < tick or (on.size() > 2 and tick <= int(on[2])):  # Its last tick heals too, then this pass fades it.
		return
	if entity.hp <= 0:
		var now: Dictionary = entity.buffs.duplicate(true)
		now["heal"] = [on[0], tick]
		entity.buffs = now
		return
	if not is_downed(entity):
		heal(entity, _carried(float(on[0]) / TICK_RATE, tick))


## How many cells [param by] can throw [param id]: its strength over the
## thing's weight (square root: a sack goes a cell or two, a kit across a
## room), 1 to THROW_MAX.
func throw_reach(by: GridEntity, id: String) -> int:
	return clampi(floori(THROW_PER_STRENGTH * by.strength / sqrt(maxf(Items.weight_of(id), 0.5))), 1, THROW_MAX)


## [param cell] if it has room for one more thing, else the nearest that
## does, within GROUND_SPILL (dry floor); NO_CELL if none.
func _ground_room(cell: Vector2i, uid := 0) -> Vector2i:
	for radius in GROUND_SPILL + 1:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var each := cell + Vector2i(dx, dy)
				# Nothing put down on a level link's cell (decision 571).
				if is_walkable(each) and not is_water(each) and not is_link_cell(each) \
						and _ground_takes(zone.ground.get(each, PackedInt32Array()), uid):
					return each
	return NO_CELL


## Whether a cell holding [param there] has room for [param uid] (0: for
## anything): fewer than GROUND_PER_CELL heaps, a stackable kind's units
## a heap up to its stack (decision 619), or a heap of its kind with room.
func _ground_takes(there: PackedInt32Array, uid := 0) -> bool:
	var of_kind := {}
	for each in there:
		var id := items.id_of(each)
		of_kind[id] = int(of_kind.get(id, 0)) + 1
	var heaps := 0
	for id: String in of_kind:
		heaps += ceili(float(of_kind[id]) / Items.stack_of(id))
	if heaps < GROUND_PER_CELL:
		return true
	var mine := items.id_of(uid) if uid != 0 else ""
	return not mine.is_empty() and int(of_kind.get(mine, 0)) % Items.stack_of(mine) != 0


## [param by] (a player or a companion, alive, not stunned, carrying a
## bandaging kit: a thing whose catalog use is "bandage") starts
## bandaging [param patient]: itself, or a player or a companion beside it,
## hurt, not already being bandaged or mending, both out of combat (no
## hostile within BANDAGE_SAFE, neither hurt for BANDAGE_CALM_TICKS). It
## takes BANDAGE_TICKS; moving, attacking or shoving, either of them hurt
## or a hostile coming near breaks it off (_tend_wounds). Done, the patient
## mends (mending 2): BANDAGE_HEAL hp, one every BANDAGE_REGEN_TICKS, while
## the bandager may walk away; a hurt stops it. The kit is gear: it is not
## used up. False, and nothing starts, if it cannot.
func try_bandage(by: GridEntity, patient: GridEntity) -> bool:
	if not Net.is_authority() or not _can_handle(by) or is_stunned(by) or not has_hands(by):
		return false
	if not is_instance_valid(patient) or not patient.spawned or patient.hp <= 0 or not has_hands(patient):
		return false
	if not bandage_within(by, patient):
		return false
	if patient.hp >= patient.max_hp or patient.mending != 0 or by.mending == 1 or _bandaging.has(by):
		return false
	if bandage_kit(by) < 0 or not calm(by) or not calm(patient):
		return false
	_bandaging[by] = {"patient": patient, "until": tick + BANDAGE_TICKS, "from": tick, "tile": by.tile,
		"exerted": by.last_exertion_tick()}
	patient.mending = 1
	by.tending = String(patient.name)  # The views' kneel and ruffle.
	if free_body(by):
		halt(by, tick)  # Its banked free steps dropped (713): one after this would break it before a view saw it.
	cure(patient, "bleed")  # A bandage stops bleeding at once (decision 375).
	_log("bandage: %s starts on %s" % [by.name, patient.name])
	bandage_changed.emit(by, patient, &"started")
	return true


## How far a bandager reaches its patient (decision 713; Jeff: "Player has
## no way to apply bandages to their companion"): a step beside, or within
## BANDAGE_REACH cells with a clear line (has_line_of_sight), in one zone.
const BANDAGE_REACH := 2


## Whether [param by] reaches [param patient] to bandage it (itself always).
func bandage_within(by: GridEntity, patient: GridEntity) -> bool:
	if patient == by:
		return true
	if patient.zone != by.zone:
		return false
	return can_melee(by.tile, patient.tile) \
			or distance(by.tile, patient.tile) <= BANDAGE_REACH and has_line_of_sight(by.tile, patient.tile)


## Why [param by] could not begin bandaging [param patient] now
## (try_bandage's checks, in its order), "" if they could: "gone",
## "not_beside", "no_wound", "mending", "busy", "no_kit", "hurt_now" (either
## hurt within BANDAGE_CALM_TICKS), "not_safe" (a monster within
## BANDAGE_SAFE of either). Said by companions in her words and to a player
## as a line (decision 625).
func bandage_refusal(by: GridEntity, patient: GridEntity) -> String:
	if not is_instance_valid(by) or not is_instance_valid(patient) or not patient.spawned or patient.hp <= 0 or not has_hands(patient):
		return "gone"
	if not bandage_within(by, patient):
		return "not_beside"
	if patient.hp >= patient.max_hp:
		return "no_wound"
	if patient.mending != 0:
		return "mending"
	if by.mending == 1 or _bandaging.has(by) or is_stunned(by) or not has_hands(by):
		return "busy"
	if bandage_kit(by) < 0:
		return "no_kit"
	if tick - by.hurt_tick < BANDAGE_CALM_TICKS or tick - patient.hurt_tick < BANDAGE_CALM_TICKS:
		return "hurt_now"
	if not calm(by) or not calm(patient):
		return "not_safe"
	return ""


## Why the last bandaging broken off (bandage_changed "interrupted") was:
## "patient_moved", "moved", "hurt", "not_safe", "gone" (decision 625).
var bandage_broke_why := ""


## The slot of [param entity]'s bandaging kit (a thing used to "bandage"), -1 if none.
func bandage_kit(entity: GridEntity) -> int:
	for slot in entity.slots.size():
		if not entity.slots[slot].is_empty() and Items.def(entity.slots[slot]).get("use") == "bandage":
			return slot
	return -1


## Out of combat: not hurt for BANDAGE_CALM_TICKS and no hostile within
## BANDAGE_SAFE cells (the cells round it looked at, not every monster).
func calm(entity: GridEntity) -> bool:
	if tick - entity.hurt_tick < BANDAGE_CALM_TICKS:
		return false
	for dy in range(-BANDAGE_SAFE, BANDAGE_SAFE + 1):
		for dx in range(-BANDAGE_SAFE, BANDAGE_SAFE + 1):
			var other: GridEntity = _occupancy.get(entity.tile + Vector2i(dx, dy))
			if other != null and other is Monster and other.hp > 0:
				return false
	return true


## Each tick: bandaging under way goes on, ends (the patient mends from
## now) or is broken off; and the mending mend.
func _tend_wounds() -> void:
	for by: GridEntity in _bandaging.keys():
		var job: Dictionary = _bandaging[by]
		var patient: GridEntity = job["patient"]
		if _alive(by) and by.zone != zone.name:
			continue  # Another zone's: its own step tends it.
		var broken := not _alive(by) or not _alive(patient)
		if not broken:
			broken = by.tile != job["tile"] or by.last_exertion_tick() != job["exerted"] \
					or by.hurt_tick >= job["from"] or patient.hurt_tick >= job["from"] \
					or not calm(by) or not calm(patient)
		if not broken and not bandage_within(by, patient):
			broken = true  # The patient gone out of reach (713; 625's "if target moves it interrupts", now past the reach).
		if broken:
			_bandaging.erase(by)
			if is_instance_valid(by):
				by.tending = ""
			if _alive(patient):
				patient.mending = 0
			bandage_broke_why = "gone" if not _alive(by) or not _alive(patient) else "patient_moved" if not bandage_within(by, patient) \
				else "moved" if by.tile != job["tile"] or by.last_exertion_tick() != job["exerted"] \
				else "hurt" if by.hurt_tick >= job["from"] or patient.hurt_tick >= job["from"] else "not_safe"
			_log("bandage: %s's bandaging of %s broken off" % [by.name, patient.name])
			bandage_changed.emit(by, patient, &"interrupted")
		elif tick >= int(job["until"]):
			_bandaging.erase(by)
			by.tending = ""
			patient.mending = 2
			_mending[patient] = {"left": BANDAGE_HEAL, "next": tick, "from": tick}  # The first hp as it is done (713).
			_log("bandage: %s bandaged %s" % [by.name, patient.name])
			bandage_changed.emit(by, patient, &"done")
	for patient: GridEntity in _mending.keys():
		if is_instance_valid(patient) and patient.zone != zone.name:
			continue
		var mend: Dictionary = _mending[patient]
		var stop := not _alive(patient) or patient.hurt_tick >= int(mend["from"])
		if not stop and tick >= int(mend["next"]):
			heal(patient, 1)
			mend["left"] = int(mend["left"]) - 1
			mend["next"] = tick + BANDAGE_REGEN_TICKS
			stop = int(mend["left"]) <= 0 or patient.hp >= patient.max_hp
		if stop:
			_mending.erase(patient)
			if is_instance_valid(patient):
				patient.mending = 0
			bandage_changed.emit(null, patient, &"mended")


## Puts saved contents back into [param entity]'s slots (unknown items
## dropped, cut or padded to its size), each with its saved instance from
## [param uids] where the book still has it, a new one ("migrated": a save
## from before instances, or one it lost) where not. Server only.
func set_slots(entity: GridEntity, contents: Variant, uids: Variant = []) -> void:
	if not Net.is_authority():
		return
	contents = _purses_migrated(entity, contents, uids)
	var tidy := Items.tidy(contents, entity.slots.size())
	var kept := PackedInt32Array()
	kept.resize(tidy.size())
	var carrier := _carrier_of(entity)
	for slot in tidy.size():
		if tidy[slot].is_empty():
			continue
		var uid := 0
		if (uids is Array or uids is PackedInt32Array) and slot < uids.size() and (uids[slot] is int or uids[slot] is float):
			uid = int(uids[slot])
		if uid in kept or items.id_of(uid) != tidy[slot]:
			uid = items.mint(tidy[slot], "migrated", _label_of(entity), entity.zone, entity.tile)
		items.place(uid, holder_key(entity), carrier[0], carrier[1])
		kept[slot] = uid
	if tidy != entity.slots or kept != entity.slot_items:
		entity.slots = tidy
		entity.slot_items = kept
		_slots_changed(entity)


## [param contents] (set_slots') with any old coin purse in them taken out
## (601 amended: gold is never a thing): its gold (purse_gold) into a
## player's record gold, else dropped where [param entity] stands; the
## purse ended. As they were when none.
func _purses_migrated(entity: GridEntity, contents: Variant, uids: Variant) -> Variant:
	if not (contents is Array or contents is PackedStringArray) or not OLD_PURSE in Array(contents):
		return contents
	var out: Array = Array(contents)
	for slot in out.size():
		if str(out[slot]) != OLD_PURSE:
			continue
		var uid := int(uids[slot]) if (uids is Array or uids is PackedInt32Array) and slot < uids.size() \
				and (uids[slot] is int or uids[slot] is float) else 0
		var gold := purse_gold(uid) if items.id_of(uid) == OLD_PURSE else OLD_PURSE_GOLD  # A purse with no instance: the old yield.
		out[slot] = ""
		if items.has(uid):
			items.end(uid, "migrated", "into gold (601 amended)", entity.zone, entity.tile)
		var player_id: Variant = entity.get("player_id")
		if player_id is String and not str(player_id).is_empty() and economy != null:
			add_gold(player_id, gold, "a coin purse")
		else:
			drop_gold(entity.zone if not entity.zone.is_empty() else zone.name, entity.tile, gold)
		print("[state] %s's coin purse: %d gold (601 amended)" % [entity.name, gold])
	return out


func spawn(entity: GridEntity, at: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if entity.spawned or entity.holds_cell and not is_free(at):
		push_warning("World.spawn: cannot place %s at %s" % [entity.name, at])
		return false
	if entity.holds_cell:
		_occupancy[at] = entity  # One holding no cell (a Locker, 722) stands where it is put.
	_entities.append(entity)
	_roster_changed()
	if entity is Cargo or entity is Monster and not entity.slots.is_empty():
		_weigh(entity)  # What its spawn spec put in it (loot, its hands) weighs from the start.
	zone.comings += 1
	entity.zone = zone.name
	entity._world_place(_next_id, at)
	if entity is Player:
		free_drop(entity as Player)  # What a body sent before it was placed is not walked (688 amended).
	_next_id += 1
	if entity is Monster and not (entity as Monster).named_id.is_empty():
		_named_arrived(entity as Monster)
	return true


## [param entity] out of the world and freed, from its own zone (657): one in
## another zone than World is in is taken out there (World enters it and
## comes back), never left in its zone's entities and occupancy, freed.
func despawn(entity: GridEntity) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	if entity.zone != zone.name and zones.has(entity.zone):
		var was := enter(zones[entity.zone])
		despawn(entity)
		enter(was)
		return
	if entity is Monster and not (entity as Monster).named_id.is_empty():
		_keep_named_weapon(entity as Monster)  # Gone away (702): it comes back with it.
	if entity is Player:
		for each: GridEntity in _entities.duplicate():
			if each is Locker and (each as Locker).player_id == (entity as Player).player_id:
				despawn(each)  # Its chest goes with it (722); the record keeps what is in it.
	_let_go_things(entity)
	_forget_jobs(entity)
	if _occupancy.get(entity.tile) == entity:
		_occupancy.erase(entity.tile)  # Not one that holds no cell (vacate): another may stand there.
	_entities.erase(entity)
	_roster_changed()
	zone.comings += 1
	entity._world_remove()
	entity_despawned.emit(entity)
	entity.queue_free()


## [param entity] leaving the world, before it is freed (decision 572
## amended): no job of the world's keeps it, as key or as patient or body.
## A bandaging or a channel it was in ends as broken off (told, as ever); its
## buff, mending, wind-up and downed lapse with it. A freed node read by
## these each tick crashed the release template (572).
func _forget_jobs(entity: GridEntity) -> void:
	_boss_moves.erase(entity)
	_axes.erase(entity)
	for id: int in _telegraphs.keys():
		if _telegraphs[id]["source"] == entity:
			end_telegraph(id, false)  # Its source gone: never lands (decision 602).
	_buffed.erase(entity)
	_mending.erase(entity)
	_winders.erase(entity)
	_rushers.erase(entity)
	_downed.erase(entity)
	# Untyped till checked, by keys and values side by side (a typed
	# dictionary refuses a freed key even to look up or erase): a job holding
	# one freed some other way goes quietly, one naming [param entity] as
	# broken off.
	var keys := _bandaging.keys()
	var jobs := _bandaging.values()
	var kept: Dictionary[GridEntity, Dictionary] = {}
	var broken: Array = []
	for i in keys.size():
		var patient: Variant = jobs[i]["patient"]
		if not is_instance_valid(keys[i]) or not is_instance_valid(patient):
			if is_instance_valid(keys[i]):
				keys[i].tending = ""
			continue
		if keys[i] == entity or patient == entity:
			broken.append([keys[i], patient])
		else:
			kept[keys[i]] = jobs[i]
	_bandaging = kept
	for pair: Array in broken:
		pair[0].tending = ""
		if pair[1] != entity and _alive(pair[1]):
			pair[1].mending = 0
		bandage_changed.emit(pair[0], pair[1], &"interrupted")
	keys = _channels.keys()
	jobs = _channels.values()
	var channels: Dictionary[GridEntity, Dictionary] = {}
	var ending: Array = []
	for i in keys.size():
		if not is_instance_valid(keys[i]) or not is_instance_valid(jobs[i]["body"]):
			continue
		channels[keys[i]] = jobs[i]
		if keys[i] == entity or jobs[i]["body"] == entity:
			ending.append(keys[i])
	_channels = channels
	for by: GridEntity in ending:
		_end_channel(by, &"broken")


## Spawn grace: for [param ticks], or until it moves or attacks, monsters do
## not target [param entity].
func protect(entity: GridEntity, ticks: int) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	entity.protected = true
	entity.protected_until_tick = tick + ticks
	entity.sheltered = false
	entity.shelter_lead = null


## Arrival shelter (decision 661; a zone's view takes seconds to build, the
## sim does not wait): spawn grace for [param ticks] that also keeps every
## harm off [param entity] (damage of any cause but bleeding, a push, a stun,
## a knock-down), from monsters and players alike. It ends as the grace does
## (time, a step, an attack) or by unshelter (the client's view built). A
## companion's, with [param lead] her player, lasts while his does, and her
## own steps do not end it.
func shelter(entity: GridEntity, ticks: int, lead: GridEntity = null) -> void:
	protect(entity, ticks)
	if entity.protected:
		entity.sheltered = true
		entity.shelter_lead = lead


## Whether [param entity] is sheltered now (decision 661): its grace on and
## not ended, and a companion's player sheltered too.
func is_sheltered(entity: GridEntity) -> bool:
	if not entity.sheltered or not entity.protected:
		return false
	if entity.shelter_lead != null:
		return is_instance_valid(entity.shelter_lead) and is_sheltered(entity.shelter_lead)
	return true


## [param entity]'s shelter over, its view built (decision 661): harm can
## land again at once, and plain spawn grace runs [param grace] ticks from
## now. Nothing when it is not sheltered.
func unshelter(entity: GridEntity, grace: int) -> void:
	if not Net.is_authority() or not is_sheltered(entity):
		return
	entity.sheltered = false
	entity.shelter_lead = null
	entity.protected_until_tick = tick + grace


## Puts back state read from a snapshot, right after spawn. Values are clamped
## to what the entity allows; a facing that is not a direction is ignored.
func restore(entity: GridEntity, hp: int, stamina: int, facing: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	if entity.max_hp > 0:
		entity.hp = clampi(hp, 1, entity.max_hp)
	if entity.max_stamina > 0:
		entity.stamina = clampi(stamina, 0, entity.max_stamina)
	if facing in DIRECTIONS:
		entity._world_set_facing(facing)


## Gives [param entity] back [param amount] hp, up to its max (a
## companion resting out of combat). Server only.
func heal(entity: GridEntity, amount: int) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or amount <= 0 or entity.max_hp <= 0:
		return
	entity.hp = mini(entity.hp + amount, entity.max_hp)


## Moves [param entity] one tile in [param direction] (one of [constant DIRECTIONS]),
## pushing any chain of pushable entities whose total mass does not exceed the
## mover's. Resolves immediately. Diagonals may not cut a wall corner.
func try_move(entity: GridEntity, direction: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if not entity.spawned or direction not in DIRECTIONS:
		return false
	if tick < entity.next_move_tick or is_stunned(entity):
		return false
	if entity.raised == "draw":
		return false  # A drawn bow stands firm (583 amended; Jeff): no step till it is loosed or let down.
	if _meets_brace(entity, entity.tile + direction, direction):
		return false
	# A level link's cell is a player's way out alone (decision 571): no
	# other body steps onto one.
	if not entity is Player and is_link_cell(entity.tile + direction):
		return false
	var duration := step_ticks(entity, direction)
	# A walk in progress keeps its own clock: a step due at 12.5 and taken
	# on tick 13 starts at 12.5, so the next is due at 15, not 15.5.
	var start := float(tick)
	if tick - entity.next_move_tick < 1.0:
		start = entity.next_move_tick
	if not _swap_with_own(entity, direction, duration, start) and not _shift(entity, entity, direction, entity.mass, duration, start):
		_step_refused(entity, direction)
		return false
	entity.next_move_tick = start + duration
	entity.step_velocity = Vector2(direction) / duration  # Its momentum (body_velocity).
	entity.step_until = entity.next_move_tick
	entity.last_step_tick = tick  # (A braced spear stands still: braced.)
	entity._world_set_facing(direction)
	_stepped_off(entity, entity.tile - direction, duration)
	return true


## What a step of [param entity]'s in [param direction] that did not go
## tells (try_move's refusal; a free body pressing an edge it cannot cross,
## _free_pressed, 688 amended (4)): a creature ahead bumped, the map's edge
## walked off, a link's cell someone stands on taken all the same, a burial
## niche's edge pressed.
func _step_refused(entity: GridEntity, direction: Vector2i) -> void:
	var ahead: GridEntity = _occupancy.get(entity.tile + direction)
	if ahead != null and ahead.is_creature() \
			and not _terrain_blocks_step(entity.tile, direction, true):
		entity_bumped.emit(entity, ahead, direction)
	elif not is_walkable(entity.tile + direction):
		walked_off.emit(entity, direction)
	# Someone on a link's cell does not shut the way: a player who
	# steps at it takes the link all the same (decision 571). A shut door
	# they may not open (locked, no key: the hidden niche's slab, 608
	# amended (2)) does shut it.
	var shut := _closed_door_across(entity.tile, direction)
	if entity is Player and is_link_cell(entity.tile + direction) \
			and not _terrain_blocks_step(entity.tile, direction, true) and (shut == null or may_open(entity, shut)):
		link_bumped.emit(entity, entity.tile + direction)
	# A step into a burial niche's edge that stops it presses on the
	# niche (608): the hidden door's slab gives to a press, nothing else.
	if (direction.x == 0 or direction.y == 0) and niche_edges.has(Terrain.edge_key(entity.tile, direction)) \
			and edge_blocks(entity.tile, direction):
		niche_pressed.emit(entity, Terrain.edge_key(entity.tile, direction))


## What a step does as [param entity] leaves [param left] for its tile
## over [param duration] ticks (try_move; a free body's claim, 688): the
## grass it left trampled, spawn grace ended, its footstep and its armour's
## clank heard.
func _stepped_off(entity: GridEntity, left: Vector2i, duration: float) -> void:
	_trample(entity, left)
	if entity.shelter_lead == null or not is_sheltered(entity):
		entity.protected = false  # Moving ends spawn grace (a companion's shelter: her player's act does, 661).
	if entity is Player or entity is Companion:
		noise(entity.tile, Senses.step_radius(entity), &"step", entity)
		var worn := entity.slots[Items.ARMOUR] if entity.slots.size() > Items.ARMOUR else ""
		noise(entity.tile, int(armour_noise(worn, CLANK_WALK_TICKS / maxf(duration, 0.001))["radius"]), &"clank", entity)  # 676 1b: none at 0.


## The noise a worn [param worn_id] makes a step at [param pace] (a walk's
## speed 1; decision 676 step 1b): {radius, kind}, its material's clank a kg
## (clank_plate, clank_mail; leather and robes none) times its kg times the
## pace, rounded, under CLANK_MAX; kind "plate", "mail", or "none" at 0. The
## server's &"clank" noise and a client's sound read the same.
func armour_noise(worn_id: String, pace := 1.0) -> Dictionary:
	var look := str(Items.armour_of(worn_id).get("look", ""))
	var per_kg := {"plate": clank_plate, "mail": clank_mail}.get(look, 0.0) as float
	var radius := mini(roundi(per_kg * Items.weight_of(worn_id) * clampf(pace, 0.0, 2.0)), CLANK_MAX) if per_kg > 0.0 else 0
	return {"radius": radius, "kind": look if radius > 0 else "none"}


## Whether [param at] is one of this zone's level links' cells (Fields
## link_cells, decision 571).
func is_link_cell(at: Vector2i) -> bool:
	return fields.link_cells.has(at)


## This zone's ways out (decision 702): a dungeon's (level.json "depth")
## level links' cells but those hidden, closed or sealed, which a routed
## band runs for; none elsewhere.
func ways_out() -> Array[Vector2i]:
	return fields.way_out_cells


## Each body but a player that finds itself on a level link's cell (spawned
## or saved there, pushed on) steps off it, the first free way (decision
## 571), when its step's timer lets it; a link's cell is a player's way out.
func _clear_links() -> void:
	for at: Vector2i in fields.link_cells:
		var on: GridEntity = _occupancy.get(at)
		if on == null or on is Player or not on.spawned or tick < on.next_move_tick:
			continue
		for direction: Vector2i in DIRECTIONS:
			if try_move(on, direction):
				break


## A swing at nothing: the attack's cooldown, facing and lunge, with no
## target. Refused like an attack while cooling down, mid-step or stunned.
func try_swing(entity: GridEntity, direction: Vector2i, paid := false) -> bool:
	if not Net.is_authority():
		return false
	if not entity.spawned or direction not in DIRECTIONS or is_stunned(entity):
		return false
	if tick < entity.next_attack_tick or tick < entity.next_move_tick:
		return false
	entity.next_attack_tick = tick + attack_ticks_of(entity)
	_halt_for_blow(entity, entity.next_attack_tick)
	entity._world_set_facing(direction)
	entity.protected = false
	if not paid:
		_pay_swing(entity, true)  # A whiff (decision 597).
		entity._world_note_exertion(tick)
	entity._world_swung(direction)
	entity_swung.emit(entity, direction)
	noise(entity.tile, Senses.NOISE_FIGHT, &"fight", entity)
	return true


## Turns a creature that is standing still to face [param direction]
## (the cursor, in WASD). Refused while it is mid-step.
func face(entity: GridEntity, direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or direction not in DIRECTIONS or tick < entity.next_move_tick:
		return
	entity._world_set_facing(direction)


## Melee: attack_damage (or [param hit_damage], when given) plus a push of
## half the shove force, at no stamina cost. Queued; resolved after every
## entity has acted this tick.
func try_attack(attacker: GridEntity, target: GridEntity, hit_damage := -1) -> bool:
	if not Net.is_authority():
		return false
	return _try_hit(attacker, target, attacker.attack_damage if hit_damage < 0 else hit_damage, false)


## Shove: no direct damage, only a push at full force, paid for in stamina
## whether or not anything moves. Queued like an attack.
##
## [param direction] aims it: Vector2i.ZERO pushes the target straight away
## from the attacker; one of [constant DIRECTIONS] tosses it that way instead.
## Tossed straight back at the attacker it goes over the attacker's head and
## lands on the tile behind, which must be free.
func try_shove(attacker: GridEntity, target: GridEntity,
		direction := Vector2i.ZERO) -> bool:
	if not Net.is_authority():
		return false
	if attacker.strength <= 0:
		return false
	return _try_hit(attacker, target, 0, true, direction)


## The ticks [param entity]'s weapon winds a blow up before striking it
## (decision 392: its verb's windup, the giant axe's 8; else its lead, the
## sword's 2, 338 amended); 0, it strikes at once.
func windup_ticks(entity: GridEntity) -> int:
	if not is_instance_valid(entity):
		return 0
	var verb := blow_verb(entity)
	var heavy := int(verb.get("windup", 0))
	return heavy if heavy > 0 else int(verb.get("lead", 0))


## The blow [param entity] is winding up (try_wind_up): {target, lands,
## direction, from}; {} for none.
func winding(entity: GridEntity) -> Dictionary:
	return entity.wind_up if is_instance_valid(entity) else {}


## [param by] winds up its heavy weapon's blow at [param target] (decision
## 392; the player's attack with such a weapon, Player._pursue_action, and
## any monster's AI): windup_ticks from now it is struck (_tend_wind_ups),
## breaking any guard it meets at full weight, if the target is still in
## reach; else it whiffs. Until then a walk away (a free body's intent off
## its way, _free_give_up_wind_up), a stun, a knockdown or being moved off its cell gives it up
## (cancel_wind_up); after, nothing does. The views wind up with it
## (GridEntity.winding). False, nothing begun, if it cannot strike now.
func try_wind_up(by: GridEntity, target: GridEntity) -> bool:
	if not Net.is_authority() or not is_instance_valid(by) or not is_instance_valid(target):
		return false
	var ticks := windup_ticks(by)
	if ticks <= 0 or not by.wind_up.is_empty() or not by.spawned or not target.spawned or by == target:
		return false
	if not can_target(by, target) or is_stunned(by) or is_down(by):
		return false
	if tick < by.next_attack_tick or tick < by.next_move_tick or not in_reach(by, target):
		return false
	var direction := melee_way(by, target)
	# A lead (338 amended) is no heavy blow: never crushing, and its
	# ticks come out of the weapon's own cycle, hit to hit attack_ticks_of.
	var lead := int(blow_verb(by).get("windup", 0)) <= 0
	by.wind_up = {"target": target, "lands": tick + ticks, "direction": direction, "from": by.tile, "began": tick, "lead": lead}
	_halt_for_blow(by, tick + ticks)
	_pay_swing(by, false)  # Paid as it begins; given up, not refunded (decision 597).
	_winders[by] = true
	by._world_set_facing(direction)
	by._world_note_exertion(tick)
	by.protected = false
	by._world_winding(direction, ticks)
	_log("windup: %s winds up at %s, %d ticks" % [by.name, target.name, ticks])
	return true


## [param entity]'s wind-up given up (decision 392): nothing is struck, and
## the views are told (GridEntity.winding, 0 ticks).
func cancel_wind_up(entity: GridEntity) -> void:
	if not is_instance_valid(entity) or entity.wind_up.is_empty():
		return
	var direction: Vector2i = entity.wind_up["direction"]
	entity.wind_up = {}
	_winders.erase(entity)
	entity._world_winding(direction, 0)
	_log("windup: %s gives up its wind-up" % entity.name)


## Each wind-up (try_wind_up) on: given up if its winder was moved off its
## cell, stunned or knocked down; struck when due, before the tick's hits
## resolve: a crushing blow (Hit.crushing) at its target if still in
## reach, else a swing at the air.
func _tend_wind_ups() -> void:
	for entity: GridEntity in _winders.keys():
		if not _alive(entity) or entity.wind_up.is_empty():
			_winders.erase(entity)
			continue
		if entity.zone != zone.name:
			continue  # Another zone's: its own step tends it, on its own tick.
		if entity.tile != entity.wind_up["from"] or is_stunned(entity) or is_down(entity):
			cancel_wind_up(entity)
			continue
		if tick < int(entity.wind_up["lands"]):
			continue
		# Untyped till checked: a target freed since cannot be a GridEntity.
		var aimed: Variant = entity.wind_up["target"]
		var direction: Vector2i = entity.wind_up["direction"]
		var lead: bool = entity.wind_up.get("lead", false)
		var began: int = entity.wind_up.get("began", tick)
		entity.wind_up = {}
		_winders.erase(entity)
		var first := _hits.size()
		if is_instance_valid(aimed) and (aimed as GridEntity).spawned and _wind_up_reaches(entity, aimed as GridEntity, lead) \
				and _try_hit(entity, aimed as GridEntity, entity.attack_damage, false, Vector2i.ZERO, true, lead):
			for i in range(first, _hits.size()):
				_hits[i].crushing = not lead
			_log("windup: %s at %s strikes %s at %s" % [entity.name, entity.tile, (aimed as GridEntity).name, (aimed as GridEntity).tile])
		else:
			try_swing(entity, direction, true)
			_log("windup: %s at %s strikes the air" % [entity.name, entity.tile])
		if lead:
			# Its next blow attack_ticks_of after this one began, not after it landed.
			entity.next_attack_tick = mini(entity.next_attack_tick, began + attack_ticks_of(entity))
			entity.free_halt_until = mini(entity.free_halt_until, entity.next_attack_tick)


## Whether a wound-up blow by [param entity] reaches [param aimed] as it
## lands: in reach, or for a [param lead] (338 amended) up to
## lead_slack past it with nothing between, where a body is free.
func _wind_up_reaches(entity: GridEntity, aimed: GridEntity, lead: bool) -> bool:
	if in_reach(entity, aimed):
		return true
	if not lead or not (free_body(entity) or free_body(aimed)):
		return false
	return _body_reach(body_centre(entity), body_centre(aimed), entity, aimed, blow_verb(entity), lead_slack)


## The shield in [param entity]'s left hand, if it can bash (decision 379):
## its block verb, with bash_force over 0; {} for none.
func bash_verb(entity: GridEntity) -> Dictionary:
	if not is_instance_valid(entity) or not holds_in_hands(entity):
		return {}
	var verb := Items.verb_of(entity.slots[Items.LEFT_HAND])
	return verb if verb.get("kind") == "block" and float(verb.get("bash_force", 0.0)) > 0.0 else {}


## Whether [param entity] could bash now (decision 379): a shield that bashes,
## not stunned, its bash_ticks since the last one passed, and the stamina for
## it. For the monsters' AI as well as the player's.
func bash_ready(entity: GridEntity) -> bool:
	var verb := bash_verb(entity)
	if verb.is_empty() or is_stunned(entity) or tick < entity.next_bash_tick or entity.winded:
		return false  # Winded: no bash (decision 597).
	return entity.max_stamina <= 0 or entity.stamina >= int(verb["bash_stamina"])


## A shield bash by [param by] on [param target], the body beside it
## (decision 379; the player's left button with the shield raised, Player's
## _pursue_action, and any monster's AI): a shove through _push, its force a
## blow's push (ATTACK_FORCE_FACTOR) times the shield's bash_force, pushing
## only from knockback_min_force; no damage; always a stagger of
## bash_stagger ticks; a guard up against it (guarding) is opened: lowered,
## not raised again for GUARD_BROKEN_TICKS, without 340's long stun. Costs
## bash_stamina, then bash_ticks till the next. The bearer's own raised shield
## is down for the bash's moment (bash_stagger ticks). Queued like an attack;
## no guard meets it. False, nothing spent, if it cannot.
func try_bash(by: GridEntity, target: GridEntity) -> bool:
	if not Net.is_authority() or not is_instance_valid(by) or not is_instance_valid(target):
		return false
	if not by.spawned or not target.spawned or by == target or not can_target(by, target) or not bash_ready(by):
		return false
	if not in_reach(by, target, true) or tick < by.next_move_tick:
		return false
	var verb := bash_verb(by)
	var aim := target.tile - by.tile
	var line := melee_way(by, target)  # The cells' way, or the centres' where a free body is in it (699).
	var way := Vector2(line).normalized() * push_force(by, target) * ATTACK_FORCE_FACTOR * float(verb["bash_force"]) \
			+ momentum_push(by, target, Vector2(line))  # Lunging into it (decision 592).
	var force := way.length()
	var raw_force := force
	if force < knockback_min_force:
		force = 0.0  # Too light to move it: the stagger alone.
	if by.max_stamina > 0:
		by.stamina -= int(verb["bash_stamina"])
	by.next_bash_tick = tick + int(verb["bash_ticks"])
	by.bash_moment_until = tick + int(verb["bash_stagger"])
	_halt_for_blow(by, by.bash_moment_until)  # A free body stands for its bash (688).
	by._world_set_facing(line)
	by._world_swung(line)
	entity_swung.emit(by, line)
	by._world_note_exertion(tick)
	by.protected = false
	noise(by.tile, Senses.NOISE_FIGHT, &"fight", by)
	_queue_hit(by, target, aim, line, 0, force, raw_force, true, 0)
	_hits[-1].push_way = way
	_hits[-1].bash = int(verb["bash_stagger"])
	return true


## A bash's hit landing (try_bash, decision 379): the guard up against it
## opened, the target staggered, the shield credited "guarded" (365).
func _bash_lands(hit: Hit) -> void:
	var opened := not guarding(hit.target, hit.source).is_empty()
	if opened:
		hit.target.raised = ""
		hit.target.guard_broken_until = tick + GUARD_BROKEN_TICKS
		hit.target._world_guarded(true)
	_stun_for(hit.target, hit.bash)
	_log("bash: %s bashes %s%s, force %.2f" % [hit.source_name, hit.target_name, ", its guard opened" if opened else "", hit.force])
	if hit.target.is_creature():
		_credit(hit.source, Items.LEFT_HAND, "guarded")
	shield_bashed.emit(hit.source, hit.target, opened)


## [param cause] is &"attack", &"shot", &"impact" or &"fire". Only FLESH and WOOD with
## max_hp > 0 can be hurt; at 0 hp the entity is removed and its tile is empty.
func damage(target: GridEntity, amount: int, source: GridEntity = null,
		cause: StringName = &"attack") -> void:
	if not Net.is_authority():
		return
	if not target.spawned or amount <= 0 or not target.is_breakable():
		return
	if not target.holds_cell:
		return  # Gone (573 amended (4), the draugr at rest): nothing there to hurt.
	if is_downed(target) and cause != &"bled":
		return  # Downed (decision 544): no blow lands on the fallen.
	if is_sheltered(target) and cause != &"bled":
		return  # Arriving, its view not built (decision 661): nothing lands.
	var lost := mini(amount, target.hp)
	target.hp -= lost
	target.hurt_tick = tick
	if target.hp == 0 and target is Monster and (target as Monster).never_dies:
		target.hp = 1  # The practice dummy (decision 673): held at 1, full again when let be.
	if cause != &"fire":
		var loud := float(Senses.NOISE_FIGHT)
		if cause == &"attack" and is_instance_valid(source):
			loud *= float(Items.strength_value(slot_strength(source, Items.RIGHT_HAND), "noise", 1.0))  # A quiet blade's.
		noise(target.tile, roundi(loud), &"fight", source)
	target._world_damaged(amount, cause)
	entity_damaged.emit(target, amount, source, cause)
	if is_instance_valid(source):
		_take_grudges(target, source, lost)  # Decisions 417, 473.
		_named_fight(target, source)
		if target is Monster and cause in [&"attack", &"shot"]:
			(target as Monster).note_struck(source)  # It answers who struck it.
	if target.hp == 0 and spared.is_valid():
		var by := str(spared.call(target, source, cause))
		if by != "":
			target.hp = 1
			entity_taken.emit(target, by)
			return
	if target.hp == 0 and downed.is_valid() and cause != &"bled":
		var ticks := int(downed.call(target, source, cause))
		if ticks > 0:
			lay_downed(target, ticks)
			entity_downed.emit(target, source, ticks)
			return
	if target.hp == 0:
		if not target.is_creature():
			noise(target.tile, Senses.NOISE_BREAK, &"break", source)  # A crate or a barrel smashed.
		if target is Monster and not (target as Monster).named_id.is_empty():
			_named_fell(target as Monster, source)
		entity_died.emit(target, cause)
		var spilt: Array[int] = []
		if target is Cargo:
			spilt = empty_container(target)
		elif target is Monster:
			spilt = empty_container(target)  # What it carried (loot, decision 330).
			spilt.append_array((target as Monster).remains())  # An animal's meat and hide (decision 318).
		var gold := (target as Monster).purse_gold() if target is Monster else 0  # 601 amended: a count, never a thing.
		var at := target.tile
		despawn(target)
		for uid in spilt:
			put_on_ground(uid, at)
		if gold > 0:
			drop_gold(zone.name, at, gold)


## Player intent: swing toward [param direction] where it stands (decision
## 593's stand-and-swing; the WASD scheme's click), at the next free tick:
## whatever stands in its way then (stand_target) takes the blow, else it is
## a swing at the air. It never steps.
func order_swing(entity: GridEntity, direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or direction not in DIRECTIONS:
		return
	entity.action_order = GridEntity.Order.SWING
	entity.action_target = null
	entity.action_direction = direction


## Player intent (decision 593: Ctrl and a click): [param entity]'s
## signature move (signature_of) at [param target], from where it stands:
## refused out of reach, never walked to.
func order_signature(entity: GridEntity, target: GridEntity) -> void:
	if not Net.is_authority() or signature_of(entity).is_empty():
		return
	_order_action(entity, GridEntity.Order.SIGNATURE, target, Vector2i.ZERO)


## [param entity]'s signature move (decision 593): "bash" with a shield that
## bashes in its left hand (bash_verb, 379), else what the weapon in its
## right hand names as its "signature" (the bow's heavy shot, the spear's
## charge, later); "" for none.
func signature_of(entity: GridEntity) -> String:
	if not bash_verb(entity).is_empty():
		return "bash"
	if not is_instance_valid(entity) or not holds_in_hands(entity):
		return ""
	return str(Items.verb_of(entity.slots[Items.RIGHT_HAND]).get("signature", ""))


## Who a swing by [param entity] toward [param direction] from where it
## stands would strike (decision 593): the first body that way it may attack
## and can reach (in_reach: the cell beside, a spear's further along), never
## its keeper's own companion; null for none.
func stand_target(entity: GridEntity, direction: Vector2i) -> GridEntity:
	if direction not in DIRECTIONS:
		return null
	var cells := 1
	var verb := blow_verb(entity)
	if verb.get("kind") == "reach":
		cells = int(verb["cells"])
	for i in range(1, cells + 1):
		var other: GridEntity = _occupancy.get(entity.tile + direction * i)
		if other == null or other == entity:
			continue
		if not other.spawned or not can_target(entity, other) or not in_reach(entity, other):
			return null
		if other.keeper_peer != 0 and other.keeper_peer == entity.owner_peer:
			return null
		return other
	return null


## Player intent: attack [param target] on the entity's next free tick.
func order_attack(entity: GridEntity, target: GridEntity) -> void:
	if not Net.is_authority():
		return
	_order_action(entity, GridEntity.Order.ATTACK, target, Vector2i.ZERO)


## Player intent: shove [param target] on the entity's next free tick.
## With a [param direction] it is a toss: the target goes that way instead of
## straight away from the entity.
func order_shove(entity: GridEntity, target: GridEntity, direction := Vector2i.ZERO) -> void:
	if not Net.is_authority():
		return
	if direction != Vector2i.ZERO and direction not in DIRECTIONS:
		return
	_order_action(entity, GridEntity.Order.SHOVE, target, direction)


## A strike's order set: a free body's client closes in (697); a body on the
## grid walks up to it (Player._pursue_action).
func _order_action(entity: GridEntity, order: GridEntity.Order, target: GridEntity,
		direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or not target.spawned or entity == target:
		return
	if not can_target(entity, target):
		return
	entity.action_order = order
	entity.action_target = target
	entity.action_direction = direction
	entity.action_tick = tick


# --- Input from any peer ------------------------------------------------------
# Input code calls command_*. On the server that is the gated order_* directly;
# on a client it is an RPC to the server, which checks that the sender owns the
# entity before calling the same order_*. Clients never call try_*.

func command_attack(entity: GridEntity, target: GridEntity) -> void:
	if Net.is_authority():
		order_attack(entity, target)
	else:
		_note_strike_sent(entity)
		_to_server(&"request_attack", [entity.get_path(), target.get_path()])


func command_shove(entity: GridEntity, target: GridEntity, direction := Vector2i.ZERO) -> void:
	if Net.is_authority():
		order_shove(entity, target, direction)
	else:
		_predict_shove(entity, target, direction)
		_note_strike_sent(entity)
		_to_server(&"request_shove", [entity.get_path(), target.get_path(), direction])


## Client: a plain shove the server will take at once (the shover standing,
## for longer than the server is behind the screen, next to the target, off
## cooldown as far as this client knows) is shown
## now: the target is slid to where predict_push_end says the push leaves
## it, and the server's word confirms or corrects it (GridEntity.guess_knock).
func _predict_shove(entity: GridEntity, target: GridEntity, direction: Vector2i) -> void:
	var aim := target.tile - entity.tile
	if direction != Vector2i.ZERO and direction != aim:
		return  # A toss: not guessed.
	var now := tick + tick_alpha
	if not can_melee(entity.tile, target.tile) \
			or now < entity._reel_until or tick < entity._guessed_ready_tick:
		return
	entity._guessed_ready_tick = tick + entity.attack_ticks
	var end := predict_push_end(entity, target, aim)
	if end != target.tile:
		target.guess_knock(end, push_slide_ticks(distance(target.tile, end)))


## Client: a blow was sent, which the server may only take once a step is
## over and a round trip has passed; until it has cooled down from that, no
## shove is guessed (it would wait on the server, and the guess be taken back).
func _note_strike_sent(entity: GridEntity) -> void:
	var later := float(entity.attack_ticks) + Net.rtt_ticks()
	entity._guessed_ready_tick = maxi(entity._guessed_ready_tick, tick + ceili(later))


## Where a plain shove by [param mover] leaves [param body], pushed
## [param direction], by the same reckoning as _push for the first body
## (force, stamina, mass, terrain, whoever is in the way), changing
## nothing. A client's guess: the server's _push is what happens.
func predict_push_end(mover: GridEntity, body: GridEntity, direction: Vector2i) -> Vector2i:
	var force := push_force(mover, body)
	var cost := shove_cost(force, body)
	if mover.max_stamina > 0 and cost > 0 and mover.stamina < cost:
		force *= float(mover.stamina) / cost
	var max_tiles: int = mini(floori(force * slide_per_speed + 0.001), max_travel)  # The mover standing (decision 592).
	var at := body.tile
	var tiles := 0
	while tiles < max_tiles:
		var next := at + direction
		if is_water(next) and not edge_blocks(at, direction):
			break
		if _terrain_blocks_step(at, direction, false, false) or height_step(at, direction) < 0 \
				or _occupancy.has(next):
			break
		var drop := height_step(at, direction)
		at = next
		tiles += 1
		if drop > 0 or (is_burning(next) and body.is_creature()):
			break
	return at


## Sends [param method] to the server, after Net.test_lag seconds when that
## test hook is set (to stand in for a long way to the server).
func _to_server(method: StringName, args: Array) -> void:
	if Net.test_lag > 0.0:
		await get_tree().create_timer(Net.test_lag).timeout
	callv("rpc_id", [1, method] + args)


## A free body's input commands from its client (decision 689;
## FreeNet.pack_commands): the newest few, each seq taken once (take_free).
## Unreliable: the next send repeats what one lost. A sender that does not
## own the body, or a packet of the wrong shape, is dropped (logged once a
## peer).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_free(entity_path: NodePath, packed: PackedByteArray) -> void:
	if Net.is_authority():
		free_from(multiplayer.get_remote_sender_id(), entity_path, packed)


## request_free's work, by [param sender] (free_net_test's way in): false
## for one refused.
func free_from(sender: int, entity_path: NodePath, packed: PackedByteArray) -> bool:
	var entity := _entity_at_path(entity_path) if Net.is_peer_authenticated(sender) else null
	if not entity is Player or entity.owner_peer != sender:
		_free_refused(sender, "not its body: %s" % entity_path)
		return false
	var commands := FreeNet.unpack_commands(packed)
	if commands.is_empty():
		_free_refused(sender, "a packet of %d bytes" % packed.size())
		return false
	if commands.any(func(command: Dictionary) -> bool: return (command["intent"] as Vector2).length() > 0.01):
		# 724: a free body's first move is its order, for --test-hold (it
		# waited its 20 s for grid orders that never come: physics' "server
		# froze for one 20.4 s frame").
		Net.test_note_order(sender, tick)
	var was := enter_named(entity.zone)
	take_free(entity as Player, commands)
	enter(was)
	return true


## The most input commands a second a free body takes from its client
## (decision 689): about 30 come; the rest are dropped.
const FREE_COMMANDS_PER_SECOND := 40.0
## Free commands refused, by peer and reason (a body's path among them),
## counted; logged the first time each, then at 100 and 1000 (689; 697:
## once a body, not once a peer, so one after a travel shows).
var _free_refused_peers: Dictionary[String, int] = {}


func _free_refused(peer: int, why: String) -> void:
	var key := "%d %s" % [peer, why]
	var count: int = _free_refused_peers.get(key, 0) + 1
	_free_refused_peers[key] = count
	if count in [1, 100, 1000]:
		_log("refused free commands from peer %d (%s)%s" % [peer, why, "" if count == 1 else ", %d times" % count])


## [param commands] from [param player]'s client (decision 689), or a
## host's own: each one newer than the last taken goes to free_input, at
## most FREE_COMMANDS_PER_SECOND a second (by the clock, not the tick).
## The speed is the bank's (688): no command moves it faster.
func take_free(player: Player, commands: Array[Dictionary]) -> void:
	if not free_body(player):
		return
	var now := Time.get_ticks_msec()
	player.free_allowance = minf(player.free_allowance + (now - player.free_allowance_at) / 1000.0 * FREE_COMMANDS_PER_SECOND,
			FREE_COMMANDS_PER_SECOND)
	player.free_allowance_at = now
	for command in commands:
		var seq: int = command["seq"]
		if player.free_seen >= 0 and not FreeNet.seq_after(seq, player.free_seen):
			continue  # Taken already (each send repeats the last few).
		if player.free_allowance < 1.0:
			return
		player.free_allowance -= 1.0
		player.free_seen = seq
		var intent: Vector2 = command["intent"]
		free_input(player, intent.limit_length(1.0), float(command["ticks"]) / TICK_RATE, seq)


@rpc("any_peer", "call_remote", "reliable")
func request_attack(entity_path: NodePath, target_path: NodePath) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	var target := _entity_at_path(target_path)
	if entity != null and target != null and target.zone == entity.zone:
		var was := enter_named(entity.zone)
		order_attack(entity, target)
		enter(was)


@rpc("any_peer", "call_remote", "reliable")
func request_shove(entity_path: NodePath, target_path: NodePath, direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	var target := _entity_at_path(target_path)
	if entity != null and target != null and target.zone == entity.zone:
		var was := enter_named(entity.zone)
		order_shove(entity, target, direction)
		enter(was)


## Any other player command, from input code on any peer. On the server it
## is handed straight to command_received; on a client it goes by RPC.
func command(entity: GridEntity, command_name: String, args: Dictionary) -> void:
	if Net.is_authority():
		command_received.emit(entity, command_name, args)
	else:
		request_command.rpc_id(1, entity.get_path(), command_name, args)


@rpc("any_peer", "call_remote", "reliable")
func request_command(entity_path: NodePath, command_name: String, args: Dictionary) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	if entity != null:
		var was := enter_named(entity.zone)
		command_received.emit(entity, command_name, args)
		enter(was)


func _entity_at_path(path: NodePath) -> GridEntity:
	var entity := get_node_or_null(path) as GridEntity
	if entity == null or not entity.spawned:
		return null
	return entity


## The entity at [param path], but only if the peer that sent the current RPC
## owns it. Anything else is rejected and logged.
func _entity_owned_by_sender(path: NodePath) -> GridEntity:
	var sender := multiplayer.get_remote_sender_id()
	if not Net.is_peer_authenticated(sender):
		_log("ignored order from unauthenticated peer %d" % sender)
		return null
	var entity := _entity_at_path(path)
	if entity == null or entity.owner_peer != sender:
		_log("rejected order from peer %d for %s" % [sender, path])
		return null
	return entity


# --- Client mirror (non-server only) -------------------------------------------
# Nothing derived is replicated. A client gets entity tiles and rebuilds the
# occupancy map from them; terrain comes from the same level data the server
# loaded.

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_tick(server_tick: int) -> void:
	if Net.is_authority():
		return
	tick = server_tick
	var error := server_tick - _clock
	if absf(error) > CLOCK_SNAP_TICKS:
		_clock = server_tick
		_clock_drift = 0.0
	else:
		_clock_drift = error * CLOCK_PULL
	tick_alpha = _clock - tick
	DayNight.update()
	fields.update_weather(DayNight.now())
	ticked.emit(tick)


## The server is half way through [param server_tick] (Net.tick_send_hz 20).
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_half_tick(server_tick: int) -> void:
	if Net.is_authority() or server_tick < tick:
		return
	var error := server_tick + 0.5 - _clock
	if absf(error) <= CLOCK_SNAP_TICKS:
		_clock_drift = error * CLOCK_PULL


func mirror_reset() -> void:
	if Net.is_authority():
		return
	_entities.clear()
	_roster_changed()
	_occupancy.clear()
	_grid_rect = Rect2i()
	_grid_steps = PackedByteArray()
	_floor.clear()
	_fire.clear()
	_edges.clear()
	_height.clear()
	_stairs.clear()
	_relief = PackedFloat32Array()
	_relief_size = Vector2i.ZERO
	_relief_given = false
	_water.clear()
	_fords.clear()
	_solid.clear()
	tick = 0
	tick_alpha = 0.0
	_clock = 0.0
	_clock_drift = 0.0
	_accumulator = 0.0


## [param terrain] is what Terrain.parse returns; a client reads the same
## map the server does.
func mirror_terrain(terrain: Dictionary) -> void:
	if Net.is_authority():
		return
	_set_terrain(terrain)


func mirror_add(entity: GridEntity) -> void:
	if Net.is_authority():
		return
	if entity not in _entities:
		_entities.append(entity)
		_roster_changed()
	entity._mirror_attach()
	mirror_changed()


func mirror_remove(entity: GridEntity) -> void:
	if Net.is_authority():
		return
	_entities.erase(entity)
	_roster_changed()
	mirror_changed()


## Rebuilds occupancy from the entities' replicated tiles.
func mirror_changed() -> void:
	if Net.is_authority():
		return
	_occupancy.clear()
	for entity in _entities:
		if entity.holds_cell:
			_occupancy[entity.tile] = entity


func _try_hit(attacker: GridEntity, target: GridEntity, hit_damage: int, is_shove: bool,
		push_direction := Vector2i.ZERO, paid := false, lead := false) -> bool:
	if not Net.is_authority():
		return false
	if not attacker.spawned or not target.spawned or attacker == target:
		return false
	if not can_target(attacker, target) or is_stunned(attacker):
		return false
	if tick < attacker.next_attack_tick or not (in_reach(attacker, target, is_shove) or lead and _wind_up_reaches(attacker, target, true)):
		return false
	# No hitting mid-step: the attacker's tile changes when a step starts, but
	# on screen it is still crossing over, so the blow would land from afar.
	if tick < attacker.next_move_tick:
		return false
	var aim: Vector2i = target.tile - attacker.tile
	var way := melee_way(attacker, target)  # The cells' way, or the centres' where a free body is in it (699).
	if push_direction == Vector2i.ZERO:
		push_direction = way  # A spear's reach: pushed one cell's way.
	elif push_direction not in DIRECTIONS:
		return false
	elif push_direction == -way and not _can_land_behind(attacker, push_direction):
		# Overhead toss with nowhere to come down: refused, costs nothing.
		return false
	# The weapon in the blow (decision 338): its speed, and below its
	# damage (twice from behind with a dagger) and its force.
	var verb := {} if is_shove else blow_verb(attacker)
	attacker.next_attack_tick = tick + attack_ticks_of(attacker) if not is_shove else tick + attacker.attack_ticks
	_halt_for_blow(attacker, attacker.next_attack_tick)
	attacker._world_set_facing(way)
	if not is_shove:
		attacker._world_swung(way)
		entity_swung.emit(attacker, way)
	attacker._world_note_exertion(tick)
	attacker.protected = false  # So does attacking or shoving.
	var force := push_force(attacker, target)
	if not is_shove and not paid:
		_pay_swing(attacker, false)  # Decision 597, after its push is weighed; a wound-up blow paid as it began.
	if is_shove:
		# Paid now, whatever the shove goes on to do. Short on stamina: the
		# force shrinks in proportion and everything left is spent.
		var cost := shove_cost(force, target)
		if attacker.max_stamina > 0 and cost > 0:
			if attacker.stamina < cost:
				force *= float(attacker.stamina) / cost
				attacker.stamina = 0
			else:
				attacker.stamina -= cost
	if not is_shove:
		force *= ATTACK_FORCE_FACTOR * float(verb.get("force", 1.0))
	# Moving into it adds the attacker's momentum (decision 592), and
	# moving across it angles the push; a toss is aimed, and takes none.
	var push_way := Vector2(push_direction)
	if push_direction == way:
		push_way = push_way.normalized() * force + momentum_push(attacker, target, push_way)
		force = push_way.length()
	var raw_force := force
	if not is_shove and force < knockback_min_force:
		force = 0.0  # A blow too light to knock back: damage only.
	if not is_shove and hit_damage > 0 and not verb.is_empty():
		var scale := float(verb["damage"])
		if verb.get("kind") == "backstab" and is_behind(attacker, target):
			scale *= float(verb["behind"])
		hit_damage = maxi(1, roundi(hit_damage * scale))
	if not is_shove and hit_damage > 0 and attacker.winded:
		hit_damage = maxi(1, roundi(hit_damage * winded_blow_scale))  # Decision 597.
	var down := int(verb["down_ticks"]) if verb.get("kind") == "knockdown" else 0
	if down > 0:
		down += int(Items.strength_value(slot_strength(attacker, Items.RIGHT_HAND), "down_ticks", 0))  # A heavy axe's.
	var deed := ""
	if not is_shove:
		deed = "downed" if down > 0 else "behind" if verb.get("kind") == "backstab" and is_behind(attacker, target) else "struck"
	_queue_hit(attacker, target, aim, push_direction, hit_damage, force, raw_force, is_shove, down)
	_hits[-1].push_way = push_way
	_hits[-1].deed = deed
	_hits[-1].pierce = verb.get("kind") in ["backstab", "reach"]
	if down > 0 and way in DIRECTIONS:
		# A giant axe's arc (decision 343): the cells either side of the
		# one struck, a step of 45 degrees each, take the same blow.
		for turn in range(1, int(verb["arc"]) + 1):
			for side in [-1, 1]:
				var side_way := Vector2(way).rotated(side * turn * PI / 4.0)
				var cell := attacker.tile + Vector2i(clampi(roundi(side_way.x), -1, 1), clampi(roundi(side_way.y), -1, 1))
				var other: GridEntity = _occupancy.get(cell)
				if other != null and other != target and other != attacker and other.spawned \
						and can_target(attacker, other) and can_melee(attacker.tile, cell):
					_queue_hit(attacker, other, cell - attacker.tile, cell - attacker.tile, hit_damage, force, raw_force, false, down)
					_hits[-1].deed = deed
	return true


## A Hit of [param attacker] on [param target] queued for _resolve_hits.
func _queue_hit(attacker: GridEntity, target: GridEntity, aim: Vector2i, push_direction: Vector2i, hit_damage: int,
		force: float, raw_force: float, is_shove: bool, down_ticks: int) -> void:
	var hit := Hit.new()
	hit.source = attacker
	hit.target = target
	hit.source_id = attacker.id
	hit.source_name = attacker.name
	hit.target_name = target.name
	hit.direction = aim
	hit.push_direction = push_direction
	hit.damage = hit_damage
	hit.force = force
	hit.shove = is_shove
	hit.raw_force = raw_force
	hit.down_ticks = down_ticks
	_hits.append(hit)


## Ascending source id. A hit whose target is no longer where it was aimed
## (an earlier hit or a move displaced something) is dropped, never re-aimed.
func _resolve_hits() -> void:
	if _hits.is_empty():
		return
	var hits := _hits
	_hits = []
	hits.sort_custom(func(a: Hit, b: Hit) -> bool: return a.source_id < b.source_id)
	for hit in hits:
		if not _alive(hit.source) or not _alive(hit.target) \
				or hit.target.tile != hit.source.tile + hit.direction:
			if is_instance_valid(hit.source) and _logs_for(hit.source):
				_log("hit dropped: %s -> %s (no longer lined up)" % [hit.source_name, hit.target_name])
			continue
		if hit.bash > 0:
			_bash_lands(hit)
		if not hit.shove:
			var met: Variant = _meet_guard(hit.target, hit.source, hit.damage, hit.raw_force, false, hit.crushing)
			if met != null:
				hit.damage = met[0]
				hit.force = met[1] if met[1] >= knockback_min_force else 0.0
		if hit.pierce:
			hit.damage = armour_turns(hit.target, hit.damage, "deflect_pierce")
		if hit.damage > 0 and not is_sheltered(hit.target):  # (Arriving, 661: no harm, wear or credit.)
			var creature := hit.target.is_creature()
			damage(hit.target, hit.damage, hit.source, &"attack")
			if hit.down_ticks > 0 and _alive(hit.target) and hit.target.is_creature():
				knock_down(hit.target, hit.source, hit.down_ticks)
			if bool(Items.def(wielded(hit.source)).get("blunt", false)):
				_wear_bundle(hit.target)
			if creature and not hit.deed.is_empty():
				_credit(hit.source, Items.RIGHT_HAND, "felled" if not _alive(hit.target) else hit.deed)
			if creature and not _alive(hit.target):
				_felled_with(hit.source, Items.RIGHT_HAND, hit.target)
			elif creature and holder_grudge(hit.source, kind_of(hit.target)):
				_stun_for(hit.target, int(Items.growth()["grudge_stagger"]))  # A grudge's blow (decision 417).
		var way := hit.push_way if hit.push_way != Vector2.ZERO else Vector2(hit.push_direction)
		if hit.force > 0.0 and _alive(hit.target):
			_push(hit.source, hit.target, way, hit.force, hit.push_direction != hit.direction)
		if _alive(hit.target) and not is_sheltered(hit.target):
			_rush_struck(hit.target, way.normalized() * hit.raw_force)  # A rush slowed or stopped (604).


## Force push (decision 592). [param force] is the speed the push gives
## [param first]; it slides slide_per_speed cells a unit of it (at most
## max_travel) along [param way], a line at any angle traced a cell at a
## time, losing speed as it goes. Stopped by a wall, a closed door or a
## step up, the speed left (u) hurts it, impact_per_energy x 1/2 m u^2;
## by a body, the two collide: the one met goes on at
## (1 + restitution) m1 u / (m1 + m2) (and may knock on another), the
## energy lost is shared as impact. Off a drop it falls, and the fall is
## what hurts. Nothing here knows what kind of entity it is pushing. A free
## body (688 amended (2)) slides from its centre, not a cell at a time
## (_free_slide): the same reach, at any angle, sliding along a wall it
## meets at a slant, and its slide is shown over the ticks after.
## [param toss]: the first body was tossed (aimed another way than straight
## on), for the views; what it knocks on is pushed. [param stagger]: the
## ticks a body that slid stays stunned past its slide (combat's; -1,
## knockback_stun_ticks). What happened to each body set moving, in order:
## {body, from, to, cells, stopped_by, impact}.
func _push(mover: GridEntity, first: GridEntity, way: Vector2, force: float, toss := false,
		stagger := -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if way == Vector2.ZERO:
		return out
	# One cell a step along the line: the longer axis a whole cell each.
	var line := way / maxf(absf(way.x), absf(way.y))
	var body: GridEntity = first
	var u: float = force
	while body != null and u > 0.0:
		if is_sheltered(body):
			# Arriving (decision 661): it does not give, and the push ends.
			if _logs_for(mover):
				_log("push: %s -> %s blocked: sheltered on arrival" % [mover.name, body.name])
			return out
		# An exhausted or downed body counts as less mass (pushed_mass).
		var body_mass := pushed_mass(body)
		# Less than a tile's worth of speed moves nothing and hurts nothing.
		# The ground it can cross: open cells' worth, each cell costing its
		# ground_drag (607), so a ford or grass or a slope up shortens it.
		var reach := u * slide_per_speed + 0.001
		var spent := 0.0
		var max_tiles: int = mini(floori(reach), max_travel)
		if max_tiles == 0:
			if _logs_for(mover):
				_log("push: %s -> %s blocked: too heavy (mass %s, speed %.2f)" % [mover.name, body.name, body_mass, u])
			return out
		var start: Vector2i = body.tile
		var tiles := 0
		var stopped := false
		var collided := false
		var stopped_by := "nothing (force spent)"
		var blocker: GridEntity = null
		var direction := Vector2i(roundi(line.x), roundi(line.y))
		# An overhead toss: the first body is lifted over the mover's own tile
		# and comes down behind it. That is two tiles of travel in one go.
		var lofted := body == first and body.tile + direction == mover.tile
		if lofted:
			if max_tiles < 2:
				stopped_by = "nothing (too heavy to lift overhead)"
				max_tiles = 0
			elif not _can_land_behind(mover, direction):
				stopped_by = "nothing (no room to land)"
				max_tiles = 0
			else:
				var landing: Vector2i = mover.tile + direction
				body._world_note_moved(tick)
				_relocate(body, landing)
				tiles = 2
				spent = 2.0  # Through the air.
				if is_burning(landing) and body.is_creature():
					stopped = true
					stopped_by = "fire"
					max_tiles = 0
		var door_hit: Door = null
		var fall := 0
		var glance := 0.0
		var traced := false
		if free_body(body) and not lofted:
			var slid := _free_slide(body, line.normalized(), u)
			traced = true
			tiles = slid["cells"]
			stopped = slid["stopped"]
			collided = slid["collided"]
			stopped_by = slid["stopped_by"]
			blocker = slid["blocker"]
			door_hit = slid["door"]
			fall = slid["fall"]
			glance = slid["glance"]
			spent = (u - float(slid["speed"])) * slide_per_speed  # So what is left below is the speed it stopped at.
			var going: Vector2 = slid["way"]
			line = going / maxf(absf(going.x), absf(going.y))  # Whom it meets goes on its way now.
			direction = Vector2i(roundi(line.x), roundi(line.y))
			body.free_kick_path = slid["path"]
			body.free_kick_at = tick
			body.free_kick_ticks = push_slide_ticks(maxi(tiles, 1))
			_free_kicked[body] = true
			body.free_way = Vector2.ZERO
			if body is Player:
				free_drop(body as Player)  # What it sent is not walked: the slide overrides it.
		while not traced and tiles < max_tiles:
			var next: Vector2i = start + Vector2i((line * (tiles + 1)).round())
			direction = next - body.tile
			var cost := ground_drag(body.tile, direction)
			if spent + cost > reach:
				break  # Its speed spent on the ground before this cell.
			if is_water(next) and not edge_blocks(body.tile, direction):
				# The water's edge: it stops there, unhurt.
				stopped = true
				stopped_by = "water"
				break
			if _terrain_blocks_step(body.tile, direction, false, false):
				stopped = true
				collided = true
				door_hit = _closed_door_across(body.tile, direction)
				stopped_by = "wall" if door_hit == null else door_hit.name
				break
			var drop := height_step(body.tile, direction)
			if drop < 0:
				# Nothing is pushed up a step.
				stopped = true
				collided = true
				stopped_by = "a ledge"
				break
			blocker = _occupancy.get(next)
			if blocker != null:
				stopped = true
				collided = true
				stopped_by = blocker.name
				break
			_relocate(body, next)
			tiles += 1
			spent += cost
			if drop > 0:
				# Off a ledge: it falls, and the fall is what hurts.
				fall = drop
				stopped = true
				stopped_by = "a fall of %d" % drop
				break
			if is_burning(next) and body.is_creature():
				stopped = true
				stopped_by = "fire"
				break
		if tiles > 0:
			body.step_velocity = Vector2.ZERO  # Thrown off its feet: no step's momentum left.
			if _rushers.has(body) and body != mover:
				_end_rush(body, "knocked")  # Off its line (decision 604).

		# Speed spent on travel; what is left is what hits.
		var remaining := 0.0
		if stopped and fall == 0:
			remaining = maxf(u - spent / slide_per_speed, 0.0)
		var impact := 0
		var passed := 0.0
		var blocker_impact := 0
		var wall_body := blocker != null and is_sheltered(blocker)
		if wall_body:
			# Arriving (decision 661): it does not give, so it is met as a
			# wall is, and nothing goes on.
			stopped_by = "%s (sheltered)" % blocker.name
			impact = roundi(impact_per_energy * 0.5 * body_mass * remaining * remaining)
		elif blocker != null:
			# A collision along the line: the one met takes up the speed.
			var blocker_mass := pushed_mass(blocker)
			passed = (1.0 + restitution) * body_mass * remaining / (body_mass + blocker_mass)
			var lost := 0.5 * body_mass * remaining * remaining - 0.5 * blocker_mass * passed * passed
			impact = roundi(impact_per_energy * maxf(lost, 0.0) * 0.5)
			blocker_impact = impact
		else:
			impact = roundi(impact_per_energy * 0.5 * body_mass * remaining * remaining)
		# A free body's slant into a wall it slid along: the speed it lost into it.
		impact += roundi(impact_per_energy * 0.5 * body_mass * glance * glance)

		if tiles > 0:
			body._world_slide_from(start, tick, push_slide_ticks(tiles))
		body._world_pushed(tiles, lofted and tiles > 0, toss and body == first, start, tick,
				push_slide_ticks(tiles), mover.owner_peer)
		var note := ""
		var next_body: GridEntity = null
		if impact > 0:
			# What it hit, for the views: a wall's stone, a door's wood, a body.
			var against := &""
			if blocker != null:
				against = &"body"
			elif door_hit != null:
				against = &"wood" if door_hit.body_material == GridEntity.BodyMaterial.WOOD else &"stone"
			elif collided or glance > 0.0:
				against = &"stone"
			_impact(body, impact, mover, against)
			if door_hit != null:
				_hit_door(door_hit, impact, mover)
		if fall > 0 and _alive(body):
			impact = FALL_IMPACT_PER_LEVEL * fall
			_stun(body, 0.0)
			_impact(body, impact, mover, &"stone")
		# Running into something stuns, even with no force left to hurt.
		if collided:
			_stun(body, remaining)
		if tiles > 0 and fall == 0:
			_stun_for(body, push_slide_ticks(tiles) + (knockback_stun_ticks if stagger < 0 else stagger))
		if blocker != null and not wall_body:
			_stun(blocker, remaining)
			note = " (%s takes %d, goes on at %.2f)" % [blocker.name, blocker_impact, passed]
			if blocker_impact > 0:
				_impact(blocker, blocker_impact, mover, &"body")
			if _alive(blocker):
				next_body = blocker
		_log("push: %s -> %s dir=%s force=%.2f tiles=%d impact=%d stopped_by=%s%s" % [
			mover.name, body.name, direction, u, tiles, impact, stopped_by, note])
		entity_pushed.emit(body, mover, direction, tiles, impact, stopped_by)
		out.append({"body": body, "from": start, "to": body.tile if is_instance_valid(body) else start,
			"cells": tiles, "stopped_by": stopped_by, "impact": impact})

		body = next_body  # It goes on from where it was met, the same way.
		u = passed
	return out


## A blow's push (decision 592), for combat: [param target] struck by
## [param source] with [param blow]'s impulse (kg x speed; blow_impulse
## gives the default), along its direction (a Vector2 at any angle; ZERO,
## source to target), the source's momentum added, held to
## knockback_min_force (not with no_floor true: the draugr's spin, which
## throws whoever it strikes, 603 amended (4)), then slid; its stagger the
## ticks stunned past the slide (-1, knockback_stun_ticks). Damage is the caller's. Server only;
## at once, not queued. {moved, distance (cells), cells (each body's end),
## stopped_by, impact_damage (the target's), struck (bodies knocked on),
## knocked_down, speed}; emitted as blow_resolved.
func apply_blow(source: GridEntity, target: GridEntity, blow: Dictionary) -> Dictionary:
	var result := _slide_result()
	if not Net.is_authority() or not _alive(source) or not _alive(target) or source == target:
		return result
	var direction: Vector2 = blow.get("direction", Vector2.ZERO)
	if direction == Vector2.ZERO:
		direction = body_centre(target) - body_centre(source)  # Centres (699).
	if direction == Vector2.ZERO:
		return result
	var way := direction.normalized() * float(blow.get("impulse", 0.0)) / maxf(pushed_mass(target), 0.001) \
			+ momentum_push(source, target, direction)
	result["speed"] = way.length()
	if way.length() >= knockback_min_force or bool(blow.get("no_floor", false)) and way.length() > 0.0:
		_fill_slide(result, target, _push(source, target, way, way.length(), false, int(blow.get("stagger", -1))))
	if not is_sheltered(target):
		_rush_struck(target, way)  # A rush slowed or stopped (604).
	result["knocked_down"] = is_down(target)
	blow_resolved.emit(source, target, result)
	return result


## A body launched (decision 598): [param body] thrown by [param by] along
## [param toward] (any angle) at [param impulse] over its pushed mass, through
## 592's _push: it slides, meets walls, bodies and drops as any push does, and
## is not held to knockback_min_force (a throw, not a blow). Aimed back past
## [param by] from beside it, it goes over its head and lands behind, as a
## toss does. For the staff's grab and throw (combat weighs its cost by
## mass_of) and the heavy shot. [param stagger] as apply_blow's. Server only,
## at once. The same result as apply_blow's; emitted as launched.
func launch(by: GridEntity, body: GridEntity, toward: Vector2, impulse: float, stagger := -1) -> Dictionary:
	var result := _slide_result()
	if not Net.is_authority() or not _alive(by) or not _alive(body) or by == body or toward == Vector2.ZERO \
			or impulse <= 0.0:
		return result
	var speed := impulse / maxf(pushed_mass(body), 0.001)
	result["speed"] = speed
	var away := Vector2(body.tile - by.tile)
	_fill_slide(result, body, _push(by, body, toward, speed, toward.normalized().dot(away.normalized()) < 0.99, stagger))
	_rush_struck(body, toward.normalized() * speed)  # A rush slowed or stopped (604).
	result["knocked_down"] = is_down(body)
	_log("launch: %s throws %s toward %s at %.2f: %d cells, stopped by %s" % [by.name, body.name, toward, speed,
			result["distance"], result["stopped_by"]])
	launched.emit(by, body, result)
	return result


## An empty result of a slide (apply_blow's, launch's).
func _slide_result() -> Dictionary:
	return {"moved": false, "distance": 0, "cells": [], "stopped_by": "", "impact_damage": 0,
		"struck": [], "knocked_down": false, "speed": 0.0}


## [param result] filled from _push's [param pushed], [param target] the
## body set moving first.
func _fill_slide(result: Dictionary, target: GridEntity, pushed: Array[Dictionary]) -> void:
	for each: Dictionary in pushed:
		result["cells"].append(each["to"])
		if each["body"] == target:
			result["moved"] = each["cells"] > 0
			result["distance"] = each["cells"]
			result["stopped_by"] = each["stopped_by"]
			result["impact_damage"] = each["impact"]
		else:
			result["struck"].append(each["body"])


## A body moving itself down a line (decision 596): [param entity] lunges
## up to [param cells] along [param toward] (any angle, traced a cell at a
## time as a push is), each cell a step of lunge_ticks_per_cell times the
## cell's ground_drag (607 amended; its drive is not spent), so its
## velocity and momentum are real (body_velocity). Walls, closed doors,
## ledges, water, fire and a link's cell stop it as they stop a walk; a
## braced spear meets it as it meets a charge. [param opts]: blow ({impulse,
## stagger}, as apply_blow's), through (bool). Without through (a shield
## bash) it stops at the first body met and the blow lands there through
## apply_blow, its momentum added. With through (a charge down a line) each
## body met is a collision of the whole charger at its speed: the one met
## is pushed at (1 + restitution) m1 u / (m1 + m2) plus the blow's impulse
## over its mass, the charger goes on at (m1 - restitution m2) u / (m1 + m2)
## if that is lunge_min_speed or more and the cell came free, else it stops
## there; the energy lost is shared between them as impact. Server only, at
## once. {cells (moved), stopped_by, struck: [{body, cells, impact}],
## impact_damage (the lunger's)}; emitted as lunge_resolved.
func lunge(entity: GridEntity, toward: Vector2, cells: int, opts := {}) -> Dictionary:
	var state := _lunge_begin(entity, toward, cells, opts)
	if state.is_empty():
		return {"cells": 0, "stopped_by": "", "struck": [], "impact_damage": 0}
	while str(state["reason"]).is_empty():
		_lunge_cell(state, false)
	var moved: int = state["moved"]
	if moved > 0:
		entity._world_slide_from(state["start"], tick, float(state["spent_ticks"]))
		entity.next_move_tick = maxf(entity.next_move_tick, tick + float(state["spent_ticks"]))
	var result := _lunge_finish(state)
	_log("lunge: %s from %s %d cells toward %s, stopped by %s" % [entity.name, state["start"], moved, toward, result["stopped_by"]])
	lunge_resolved.emit(entity, result)
	return result


## A charge spread over time (decision 604): 596's lunge, a cell each
## lunge_ticks_per_cell / its speed x the cell's ground_drag, from the next tick on (_tend_rushes),
## so it can be met and struck on the way. [param opts] as lunge's, and
## "to": the cell it runs for (arrived there), else it runs its cells. Its
## speed u starts at 1 and is changed by what it meets: every hit on it
## (any blow or shove, even one under knockback_min_force) adds the hit's
## speed along the rush (impulse over its mass; the part behind it adds
## nothing), and it ends when u is rush_stop_speed or less ("blow"). A push
## that moves it ends it ("knocked"); so do a braced spear ("brace"), a body
## it cannot go on through ("body"), the terrain ("wall") and a stun
## ("stunned"); reaching its cell or running its cells is "arrived". Each
## end emits rush_ended(entity, reason, at, result). True if it started.
## Server only. A rushing body does not walk or strike on its own.
func rush(entity: GridEntity, toward: Vector2, cells: int, opts := {}) -> bool:
	if _rushers.has(entity):
		return false
	var state := _lunge_begin(entity, toward, cells, opts)
	if state.is_empty():
		return false
	state["due"] = float(tick) + 1.0
	_rushers[entity] = state
	entity.next_move_tick = maxf(entity.next_move_tick, state["due"])
	_log("rush: %s from %s toward %s, %d cells%s" % [entity.name, entity.tile, toward, cells,
			"" if state["to"] == NO_CELL else " to %s" % state["to"]])
	return true


## Whether [param entity] is rushing (rush).
func rushing(entity: GridEntity) -> bool:
	return _rushers.has(entity)


## Each rush's cell when due, in id order (the zone's step, before the act
## phase): only this zone's rushers (604 amended), since each zone keeps its
## own tick, terrain and occupancy.
func _tend_rushes() -> void:
	if _rushers.is_empty():
		return
	var each: Array[GridEntity] = []
	each.assign(_rushers.keys())
	each.sort_custom(func(a: GridEntity, b: GridEntity) -> bool: return a.id < b.id)
	for entity in each:
		var state: Dictionary = _rushers.get(entity, {})
		if state.is_empty():
			continue
		if not _alive(entity):
			_rushers.erase(entity)
			continue
		if entity.zone != zone.name:
			continue  # Another zone's, on its own clock and ground (604 amended).
		if is_stunned(entity):
			_end_rush(entity, "stunned")
			continue
		if float(tick) < float(state["due"]):
			continue
		_lunge_cell(state, true)
		if not str(state["reason"]).is_empty():
			_end_rush(entity, state["reason"])
		else:
			state["due"] = float(tick) + float(state["cell_ticks"])
			entity.next_move_tick = maxf(entity.next_move_tick, state["due"])


## A hit on [param body] (a blow's, shove's or launch's [param way], its
## speed vector before the threshold): a rushing body's speed changes by its
## part along the rush (decision 604), ending the rush once spent.
func _rush_struck(body: GridEntity, way: Vector2) -> void:
	var state: Dictionary = _rushers.get(body, {})
	if state.is_empty() or way == Vector2.ZERO:
		return
	var along := way.dot(Vector2(state["line"]).normalized())
	if along >= 0.0:
		return  # From behind: it adds nothing, and never stops it.
	state["u"] = float(state["u"]) + along
	_log("rush: %s struck, %.2f, its speed now %.2f" % [body.name, along, state["u"]])
	if float(state["u"]) <= rush_stop_speed:
		_end_rush(body, "blow")
	else:
		state["ticks"] = maxf(lunge_ticks_per_cell, 0.1) / float(state["u"])
		body.step_velocity = Vector2(state["line"]) / (float(state["ticks"]) * float(state["drag"]))


## [param entity]'s rush ends for [param reason]: rush_ended.
func _end_rush(entity: GridEntity, reason: String) -> void:
	var state: Dictionary = _rushers.get(entity, {})
	if state.is_empty():
		return
	_rushers.erase(entity)
	if str(state["reason"]).is_empty():
		state["reason"] = reason
		state["stopped_by"] = reason
	var result := _lunge_finish(state)
	result["reason"] = reason
	_log("rush: %s ends at %s after %d cells: %s" % [entity.name, entity.tile if _alive(entity) else state["start"], state["moved"], reason])
	rush_ended.emit(entity, reason, entity.tile if _alive(entity) else NO_CELL, result)


## A lunge's or a rush's state, or {} if [param entity] cannot.
func _lunge_begin(entity: GridEntity, toward: Vector2, cells: int, opts: Dictionary) -> Dictionary:
	if not Net.is_authority() or not _alive(entity) or is_stunned(entity) or toward == Vector2.ZERO or cells <= 0:
		return {}
	var line := toward / maxf(absf(toward.x), absf(toward.y))
	var ticks := maxf(lunge_ticks_per_cell, 0.1)
	# Its own speed from the start (a cell a lunge step), for the momentum it
	# carries and for a braced spear to read.
	entity.step_velocity = line / ticks
	entity.step_until = tick + cells * ticks
	entity._world_set_facing(Vector2i(roundi(line.x), roundi(line.y)))
	entity._world_note_exertion(tick)
	entity.protected = false
	return {"entity": entity, "start": entity.tile, "line": line, "cells": cells, "ticks": ticks,
		"u": line.length() / ticks, "blow": opts.get("blow", {}), "through": bool(opts.get("through", false)),
		"to": opts.get("to", NO_CELL), "moved": 0, "drag": 1.0, "cell_ticks": ticks, "spent_ticks": 0.0, "reason": "", "stopped_by": "", "struck": [], "impact": 0}


## One cell of a lunge or a rush ([param timed]: a rush's, drawn as it is
## taken). Sets state's reason and stopped_by when it ends.
func _lunge_cell(state: Dictionary, timed: bool) -> void:
	var entity: GridEntity = state["entity"]
	var line: Vector2 = state["line"]
	var moved: int = state["moved"]
	if moved >= int(state["cells"]) or entity.tile == state["to"]:
		state["reason"] = "arrived"
		state["stopped_by"] = "nothing (the lunge's length)"
		return
	var next: Vector2i = state["start"] + Vector2i((line * (moved + 1)).round())
	var direction := next - entity.tile
	if _terrain_blocks_step(entity.tile, direction, true) or not is_walkable(next) \
			or entity.is_creature() and is_burning(next) or not entity is Player and is_link_cell(next):
		state["reason"] = "wall"
		state["stopped_by"] = "wall" if _closed_door_across(entity.tile, direction) == null else "a door"
		return
	# The ground (607 amended): this cell takes ground_drag times its time, and
	# the body is at that cell's speed in it (what a spear or a body met
	# feels); its drive, u, is not spent, so it picks up on open ground.
	var drag := ground_drag(entity.tile, direction)
	state["drag"] = drag
	var cell_ticks := float(state["ticks"]) * drag
	entity.step_velocity = line / cell_ticks
	if _meets_brace(entity, next, direction, true):
		state["reason"] = "brace"
		state["stopped_by"] = "a braced spear"
		return
	var blow: Dictionary = state["blow"]
	var body: GridEntity = null
	for each in bodies_struck_at(next):  # Its holder first, as the hurl's (688 amended (5)).
		if each != entity:
			body = each
			break
	if body == null and _occupancy.has(next) and _occupancy[next] != entity:
		# A free body's held cell its circle has left (its claim waiting on
		# its own companion's): the cell stops the charge, nobody is struck.
		state["reason"] = "body"
		state["stopped_by"] = "a cell held (%s)" % (_occupancy[next] as GridEntity).name
		return
	if body != null:
		if not state["through"]:
			state["reason"] = "body"
			state["stopped_by"] = body.name
			if not blow.is_empty():
				var landed := apply_blow(entity, body, {"impulse": float(blow.get("impulse", 0.0)),
						"direction": line, "stagger": int(blow.get("stagger", -1))})
				state["struck"].append({"body": body, "cells": landed["distance"], "impact": landed["impact_damage"]})
			return
		var u: float = float(state["u"]) / drag  # Its speed in this cell.
		var m1 := pushed_mass(entity)
		var m2 := pushed_mass(body)
		var given := (1.0 + restitution) * m1 * u / (m1 + m2)
		var kept := (m1 - restitution * m2) * u / (m1 + m2)
		var lost := 0.5 * m1 * u * u - 0.5 * m1 * maxf(kept, 0.0) * maxf(kept, 0.0) - 0.5 * m2 * given * given
		var impact := roundi(impact_per_energy * maxf(lost, 0.0) * 0.5)
		var speed := given + float(blow.get("impulse", 0.0)) / maxf(m2, 0.001)
		var pushed := _push(entity, body, line, speed, false, int(blow.get("stagger", -1)))
		var went := 0
		for each: Dictionary in pushed:
			if each["body"] == body:
				went = each["cells"]
		if impact > 0:
			_impact(body, impact, entity, &"body")
			_impact(entity, impact, entity, &"body")
			state["impact"] = int(state["impact"]) + impact
		state["struck"].append({"body": body, "cells": went, "impact": impact})
		_log("lunge: %s meets %s at %.2f: it goes %d, the charge goes on at %.2f" % [entity.name, body.name, u, went, kept])
		kept *= drag  # Back to its drive.
		state["u"] = kept
		if kept > 0.0:
			state["ticks"] = maxf(lunge_ticks_per_cell, 0.1) / kept
			cell_ticks = float(state["ticks"]) * drag
		if not _alive(entity) or kept < lunge_min_speed or _occupancy.has(next):
			state["reason"] = "body"
			state["stopped_by"] = body.name
			return
	var from := entity.tile
	_relocate(entity, next)
	state["moved"] = moved + 1
	_trample(entity, from)
	state["cell_ticks"] = cell_ticks
	state["spent_ticks"] = float(state["spent_ticks"]) + cell_ticks
	entity.step_velocity = line / cell_ticks
	entity.step_until = tick + cell_ticks
	entity.last_step_tick = tick
	if timed:
		entity._world_slide_from(from, tick, cell_ticks)
	if entity.tile == state["to"]:
		state["reason"] = "arrived"
		state["stopped_by"] = "nothing (it arrived)"


## A lunge's or a rush's result from its state.
func _lunge_finish(state: Dictionary) -> Dictionary:
	var entity: GridEntity = state["entity"]
	if _alive(entity) and entity.is_creature():
		noise(entity.tile, Senses.NOISE_FIGHT, &"fight", entity)
	return {"cells": state["moved"], "stopped_by": state["stopped_by"], "struck": state["struck"],
		"impact_damage": state["impact"]}


## A sweep through a cone (decision 605): every body within [param cells]
## of [param source] whose angle off [param toward] is within half of
## [param arc_degrees], and that a swing could reach (no wall or closed door
## on the cells between: _sweep_reaches), takes apply_blow along its own
## line from the source, so the push fans out. [param blow] as apply_blow's
## (impulse, stagger; swing_impulse gives a weapon's). The bodies are taken
## as they stand when it starts and struck from one edge of the cone to the
## other; one already knocked out of it on the way is passed over. Server
## only, at once. Each struck body's {body, result}; emitted as swept.
func sweep(source: GridEntity, toward: Vector2, arc_degrees: float, cells: int, blow: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Net.is_authority() or not _alive(source) or toward == Vector2.ZERO or cells <= 0:
		return out
	var half := deg_to_rad(arc_degrees) / 2.0 + 0.01
	var found: Array[Array] = []
	for dy in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			var off := Vector2i(dx, dy)
			if off == Vector2i.ZERO:
				continue
			var body: GridEntity = _occupancy.get(source.tile + off)
			if body == null or body == source or not _alive(body):
				continue
			var angle := toward.angle_to(Vector2(off))
			if absf(angle) <= half and _sweep_reaches(source.tile, source.tile + off):
				found.append([angle, body])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for each: Array in found:
		var body: GridEntity = each[1]
		if not _alive(body):
			continue
		var off := body.tile - source.tile
		if maxi(absi(off.x), absi(off.y)) > cells or absf(toward.angle_to(Vector2(off))) > half:
			continue  # Knocked out of the cone by one struck before it.
		out.append({"body": body, "result": apply_blow(source, body, {"impulse": float(blow.get("impulse", 0.0)),
				"direction": Vector2(off), "stagger": int(blow.get("stagger", -1))})})
	_log("sweep: %s toward %s, %.0f degrees, %d cells: %d struck" % [source.name, toward, arc_degrees, cells, out.size()])
	swept.emit(source, out)
	return out


## Whether a swing from [param from] reaches [param to]: every step of the
## straight line between them open (can_melee), bodies aside.
func _sweep_reaches(from: Vector2i, to: Vector2i) -> bool:
	var off := to - from
	var steps := maxi(absi(off.x), absi(off.y))
	var at := from
	for k in range(1, steps + 1):
		var next := from + Vector2i((Vector2(off) * float(k) / steps).round())
		if not can_melee(at, next):
			return false
		at = next
	return true


## A weapon's swing's impulse (decision 605): [param wielder]'s blow with
## [param item] (blow_impulse at its verb) and the thing's own weight swung,
## weight x swing_speed. For the draugr's 7 kg battle axe, 178: an 80 kg
## player knocked 3 cells.
func swing_impulse(wielder: GridEntity, item: String) -> float:
	return blow_impulse(wielder, Items.verb_of(item)) + Items.weight_of(item) * swing_speed


## A thing thrown down a line (decision 606; 606 amended, its options):
## what [param by] holds in
## [param slot] leaves its hand and flies along [param toward] (any angle,
## traced a cell at a time), at most [param cells]; a wall, a closed door or
## higher ground stops it before. The first body on the line is launched
## (598) along it at the thing's weight x [param speed] and takes impact by
## 592's rule; the thing lands at that body's feet (the cell it was struck
## on), else where its flight ended, on dry ground (put_on_ground, spilling
## if the cell is full), for anyone to pick up. Its flight is told to the
## views (GridEntity.hurled). The damage of the hit is the caller's (combat).
## A body struck and not moved still staggers by the hit's speed (_stun).
## [param opts]: lands ("feet", the default; "before": the cell before the
## body, the thrower's own if it stood beside it, as the pack's throw has
## it), hurts (the body takes impact_per_energy x 1/2 x the thing's weight
## x [param speed]^2, its energy: the pack's throw, at a real speed; a
## caller dealing the hit's damage itself, as combat's axe does, leaves it
## off). Server only, at once. {thrown, landed (a cell, NO_CELL if it found
## no ground), hit (the body, or null), hit_result (launch's, {} for none),
## impact}; emitted as hurled.
func hurl(by: GridEntity, slot: int, toward: Vector2, cells: int, speed: float, opts := {}) -> Dictionary:
	var out := {"thrown": false, "landed": NO_CELL, "hit": null, "hit_result": {}, "impact": 0}
	if not Net.is_authority() or not _alive(by) or is_stunned(by) or not holds_in_hands(by) \
			or slot not in [Items.RIGHT_HAND, Items.LEFT_HAND] or by.slots[slot].is_empty() or toward == Vector2.ZERO or cells <= 0:
		return out
	var id := by.slots[slot]
	var line := toward / maxf(absf(toward.x), absf(toward.y))
	var at := by.tile
	var dry := by.tile
	var hit: GridEntity = null
	for k in range(1, cells + 1):
		var next: Vector2i = by.tile + Vector2i((line * k).round())
		var step := next - at
		if _terrain_blocks_step(at, step, false, false) and not is_water(next) or edge_blocks(at, step):
			break
		for body in bodies_struck_at(next):  # A free body by struck_cell (enemy-ai's free-walk audit).
			if body != by:
				hit = body
				break
		if hit != null:
			at = next
			break
		at = next
		if not is_water(at):
			dry = at
	var uid := _take_out(by, slot)  # A wielding monster's hand too (the draugr's axe).
	if uid == 0:
		return out
	_put_down_by[uid] = _label_of(by)
	var feet := at if hit != null and str(opts.get("lands", "feet")) == "feet" else dry
	out["thrown"] = true
	if hit != null:
		items.note(uid, "thrown", "at %s by %s" % [_label_of(hit), _label_of(by)], zone.name, hit.tile)
		out["hit"] = hit
		var weight := Items.weight_of(id)
		out["hit_result"] = launch(by, hit, line, weight * speed)
		if _alive(hit) and not out["hit_result"].get("moved", false):
			_stun(hit, float(out["hit_result"].get("speed", 0.0)))  # Struck where it stands: it staggers.
		if bool(opts.get("hurts", false)) and _alive(hit):
			out["impact"] = roundi(impact_per_energy * 0.5 * weight * speed * speed)
			if out["impact"] > 0:
				_impact(hit, out["impact"], by, &"body")
	var landed := put_on_ground(uid, feet, by.tile)
	out["landed"] = landed
	_thud(landed, id, by)
	by._world_hurled(id, landed if landed != NO_CELL else at)
	_log("hurl: %s threw %s from %s toward %s, landing at %s%s" % [by.name, id, by.tile, toward, landed,
			"" if hit == null else ", hitting %s" % hit.name])
	hurled.emit(by, id, landed, hit)
	return out


## The impulse of [param attacker]'s blow with [param verb] (blow_verb's),
## standing (decision 592's draft, today's feel): strength x its mass x
## shove_scale x ATTACK_FORCE_FACTOR x the verb's force x its stamina
## fraction. A body of mass m is pushed at this over m.
func blow_impulse(attacker: GridEntity, verb: Dictionary) -> float:
	if attacker.strength <= 0:
		return 0.0
	return attacker.strength * attacker.mass * shove_scale * ATTACK_FORCE_FACTOR * float(verb.get("force", 1.0)) \
			* attacker.stamina_fraction()


## True if a body tossed over [param mover] in [param direction] has a free
## tile to come down on directly behind it, with no wall in the way.
func _can_land_behind(mover: GridEntity, direction: Vector2i) -> bool:
	var from: Vector2i = mover.tile - direction
	return not _terrain_blocks_step(from, direction) \
			and not _terrain_blocks_step(mover.tile, direction) \
			and not _occupancy.has(mover.tile + direction)


## Ticks a push of [param tiles] is drawn sliding.
static func push_slide_ticks(tiles: int) -> int:
	return clampi(tiles * PUSH_SLIDE_TICKS_PER_TILE, 1, MAX_PUSH_SLIDE_TICKS)


## Creatures only. A longer stun replaces a shorter one; they do not add up.
func _stun(entity: GridEntity, remaining_force: float) -> void:
	_stun_for(entity, stun_ticks_base + roundi(remaining_force * stun_ticks_per_force))


## Stuns [param entity] for [param ticks] from now, if that is longer.
func _stun_for(entity: GridEntity, ticks: int) -> void:
	if not _alive(entity) or not entity.is_creature() or is_sheltered(entity):
		return
	if tick + ticks > entity.stunned_until_tick:
		entity._world_stunned(tick + ticks, ticks)


## [param against] is what it hit: &"stone", &"wood", &"body", or &"" (it
## was stopped by fire, not by anything).
func _impact(entity: GridEntity, amount: int, source: GridEntity, against: StringName) -> void:
	entity._world_impacted(amount, against)
	damage(entity, amount, source, &"impact")
	_wear_bundle(entity)


## Resting and walking regain stamina. Attacking, shoving, or being moved more
## than one tile in a tick stops it for that tick and stamina_regen_delay more.
func _regen_stamina() -> void:
	for entity in _entities:
		# Winded (decision 597): from 0 until back at recover_at, for those
		# who pay for their swings.
		if entity.max_stamina > 0 and entity.pays_swings and not entity.winded and entity.stamina <= 0:
			entity.winded = true
		elif entity.winded and (entity.stamina >= mini(recover_at, entity.max_stamina) or not entity.pays_swings):
			entity.winded = false
		var delay := winded_regen_delay if entity.winded else stamina_regen_delay
		var every := maxi(1, entity.stamina_regen_every)
		if entity.max_stamina > 0 and entity.stamina < entity.max_stamina \
				and tick - entity.last_exertion_tick() > delay and tick % every == 0:
			var breath := entity.stamina_regen_amount if entity.stamina_regen_amount > 0 else stamina_regen
			var rate := breath * load_breath(entity)
			if rate < breath:
				# The fraction carried by the breath's count: plate's 1.6 a
				# breath gives 1, 2, 2, 1, 2..., with no state kept.
				var n := tick / every
				breath = floori(rate * (n + 1)) - floori(rate * n)
			entity.stamina = mini(entity.stamina + breath, entity.max_stamina)


func _apply_hazards() -> void:
	if not fields.has_heat():
		return
	if _carried_heat():
		for entity in _entities.duplicate():
			if _alive(entity) and entity.is_creature() and is_burning(entity.tile):
				damage(entity, FIRE_DAMAGE, null, &"fire")
		return
	# Nobody carries heat (as now, always): only who stands where the map's
	# own heat burns, in id order as above, not every entity.
	var burning: Array[GridEntity] = []
	for cell in fields.hot_cells(self, HEAT_BURN):
		var entity: GridEntity = _occupancy.get(cell)
		if entity != null and _alive(entity) and entity.is_creature():
			burning.append(entity)
	burning.sort_custom(func(a: GridEntity, b: GridEntity) -> bool: return a.id < b.id)
	for entity in burning:
		damage(entity, FIRE_DAMAGE, null, &"fire")


## One walking step for [param entity], shoving the pushable chain ahead of
## it, drawn from [param start] (a tick, maybe fractional) for
## [param duration] ticks.
func _shift(mover: GridEntity, entity: GridEntity, direction: Vector2i, push_budget: float,
		duration: float, start: float) -> bool:
	var from: Vector2i = entity.tile
	var to: Vector2i = from + direction
	if _terrain_blocks_step(from, direction, entity.is_creature()):
		return false
	var door := _closed_door_across(from, direction)
	if door != null and not may_open(entity, door):
		return false
	var blocker: GridEntity = _occupancy.get(to)
	if blocker != null:
		if not blocker.pushable or blocker.mass > push_budget:
			return false
		if not _shift(mover, blocker, direction, push_budget - blocker.mass, duration, start):
			return false
	if door != null:
		_set_door(door, true, entity)  # A creature that may; anything else was blocked above.
	_relocate(entity, to)
	entity._world_slide_from(from, start, duration)
	if entity != mover:
		entity._world_pushed(1, false, false, from, start, duration, mover.owner_peer)
		_log("push: %s -> %s dir=%s tiles=1 impact=0 stopped_by=nothing (walked into)" % [
			mover.name, entity.name, direction])
		entity_pushed.emit(entity, mover, direction, 1, 0, "nothing (walked into)")
	return true


## A player's step into their own companion's cell (the swap rule; ui's
## trace: held-key corrections beside her were steps the server took late,
## waiting on her make_way or bump): they change places on this tick, the
## step on its own clock from [param start]. Only their own companion,
## alive, not downed, lying or stunned; dodging or fighting she swaps
## all the same (679 amended: her intent is the server's alone, and a
## refusal the client cannot foresee snaps his own body back; a wind-up she
## began is given up, moved off its cell, and a blow lands from where she
## now stands or misses); never across a wall, a closed door or a corner
## (swap_places). False, nothing done, otherwise (decision 679).
func _swap_with_own(entity: GridEntity, direction: Vector2i, duration: float, start: float) -> bool:
	if not entity is Player:
		return false
	var pet := _occupancy.get(entity.tile + direction) as Companion
	if pet == null or pet.keeper != entity or not _alive(pet) or is_downed(pet) or is_down(pet) or is_stunned(pet):
		return false
	return swap_places(entity, pet, duration, start)


## [param a] and [param b], side by side, change places at once, each
## sliding over [param duration] ticks as a step from [param start] (this
## tick when not given): a companion making way for her player where there
## is no room to step aside (Companion.bumped), a player's step into her
## (_swap_with_own). Both must be creatures, next to each other, with
## nothing between.
func swap_places(a: GridEntity, b: GridEntity, duration: float, start := -1.0) -> bool:
	if not Net.is_authority() or not a.is_creature() or not b.is_creature() or not are_adjacent(a.tile, b.tile):
		return false
	if free_body(a) or free_body(b):
		return false  # A free body passes through his own companion instead (688).
	var direction: Vector2i = b.tile - a.tile
	if _terrain_blocks_step(a.tile, direction, true) or _terrain_blocks_step(b.tile, -direction, true) \
			or _closed_door_across(a.tile, direction) != null:
		return false
	var at: Vector2i = a.tile
	var bt: Vector2i = b.tile
	var from := float(tick) if start < 0.0 else start
	_occupancy[at] = b
	_occupancy[bt] = a
	for each: Array in [[a, at, bt], [b, bt, at]]:
		var entity: GridEntity = each[0]
		entity._world_set_tile(each[2])
		entity._world_note_moved(tick)
		entity._world_slide_from(each[1], from, duration)
		entity.next_move_tick = from + duration
	_log("swap: %s %s <-> %s %s" % [a.name, at, b.name, bt])
	entity_moved.emit(a, at, bt)
	entity_moved.emit(b, bt, at)
	return true


## A free body (688, combat's side; ui: "an attack or swing stops the body
## for its windup") stands where it is from its blow, swing, shove, door's
## bash or wind-up until [param until_tick] (halt), where a body on the grid
## is refused mid-step. Nothing for a body on the grid.
func _halt_for_blow(entity: GridEntity, until_tick: int) -> void:
	if free_body(entity):
		halt(entity, until_tick)


## Where [param entity]'s shots and lobs start (688, combat's side): a free
## body's own centre (free_pos), else its cell's. On a client free_pos is
## not kept (a replicated tile leaves it where the body was placed), so
## its own body's centre is where its view draws it (689's FreeNet.Own),
## and any other's its cell's (677 amended: aimed from the join cell, the
## lob's circle fell on walls and roofs and showed red).
func shot_origin(entity: GridEntity) -> Vector2:
	if not free_body(entity):
		return Vector2(entity.tile)
	if Net.is_authority():
		return entity.free_pos
	var view: Variant = entity.get("free_view")
	if view is FreeNet.Own and (view as FreeNet.Own).base != Vector2.INF:
		return (view as FreeNet.Own).shown(entity)
	return Vector2(entity.tile)


## Whether [param entity] moves as a free body (decision 688): a player,
## always since 703.
func free_body(entity: GridEntity) -> bool:
	if not Net.is_authority():
		# A client's rules follow each body (decision 693): free while the
		# server sends its free state, whatever a client starts with.
		return entity is Player and not (entity as Player).free_state.is_empty()
	return entity is Player


## Queues one input command for [param entity]'s free body (688): its
## [param intent], a way of length up to 1 (shorter walks slower), held for
## [param seconds], numbered [param seq] by its client (688 amended: the
## server's ack, Player.free_acked). Applied in order in its act
## (tend_free_body). Server only.
func free_input(entity: GridEntity, intent: Vector2, seconds: float, seq := -1) -> void:
	if not Net.is_authority() or not free_body(entity) or not is_finite(intent.x) or not is_finite(intent.y):
		return
	var player := entity as Player
	_free_give_up_wind_up(player, intent)
	if player.free_inputs.size() >= FREE_INPUTS_MAX:
		_free_acked(player, player.free_inputs.pop_front())
	player.free_inputs.append({"intent": intent.limit_length(1.0), "ticks": clampf(seconds * TICK_RATE, 0.0, FREE_BANK_TICKS),
		"used": 0.0, "seq": seq})


## A free body's wind-up given up by walking off it (392 amended, the
## coordinator's; ui and items: under free walk the halt dropped every
## command and the grid's cancel, a step off its cell, never came, so every
## heavy wind-up landed): an [param intent] of at least
## WIND_UP_LEAVE_INTENT not strictly within WIND_UP_KEEP_ANGLE of the way to its target ends
## it (cancel_wind_up, paid and not refunded as ever) and lifts its halt, so
## the command walks. Pressing on at the foe, as a chase's late commands
## do, keeps it.
func _free_give_up_wind_up(player: Player, intent: Vector2) -> void:
	if player.wind_up.is_empty() or player.wind_up.get("lead", false) or intent.length() < WIND_UP_LEAVE_INTENT:
		return  # A lead is the swing itself, never walked off (338 amended).
	var target: Variant = player.wind_up.get("target")
	var way := Vector2(player.wind_up["direction"])
	if is_instance_valid(target):
		way = body_centre(target) - body_centre(player)
	if way.length() > 0.001 and intent.normalized().dot(way.normalized()) > cos(deg_to_rad(WIND_UP_KEEP_ANGLE)):
		return
	cancel_wind_up(player)
	player.free_halt_until = tick


## [param command] is done with, whether applied or dropped (688 amended):
## its seq acknowledged, so the client replays it no more.
func _free_acked(player: Player, command: Dictionary) -> void:
	if int(command.get("seq", -1)) >= 0:
		player.free_acked = maxi(player.free_acked, int(command["seq"]))
	player.free_used = 0.0


## Every command waiting on [param player]'s free body dropped, each
## acknowledged (688 amended: a halt, a spawn).
func free_drop(player: Player) -> void:
	for command: Dictionary in player.free_inputs:
		_free_acked(player, command)
	player.free_inputs.clear()
	player.free_used = 0.0


## [param entity]'s free body stops where it is and takes no intent before
## [param until_tick] (688; combat's attacks and wind-ups, stand_firm): its
## velocity and its waiting commands are dropped.
func halt(entity: GridEntity, until_tick: int) -> void:
	entity.free_halt_until = maxi(entity.free_halt_until, until_tick)
	entity.free_way = Vector2.ZERO
	if entity is Player:
		free_drop(entity as Player)


## Whether [param entity]'s free body ignores its intent now (688): halted,
## a bow drawn (it stands firm, 583 amended), stunned, lying or downed, or
## a push's slide being shown (688 amended (2)).
func free_held(entity: GridEntity) -> bool:
	return tick < entity.free_halt_until or entity.raised == "draw" or is_stunned(entity) \
			or is_down(entity) or is_downed(entity) or not entity.free_kick_path.is_empty()


## A free body's turn (688, from Player._sim_tick): a tick's more real time
## banked, its commands applied in order while the bank lasts, each moving
## the body (_free_glide, its effects on); a held body's command spends its
## time standing. Each command used up is acknowledged (free_acked), and
## free_used is what the head one has had. A body that moved has stepped
## (last_step_tick: a spear braced only standing still) and carries its
## velocity as a step's momentum (step_velocity, step_until).
func tend_free_body(player: Player) -> void:
	if not Net.is_authority() or not player.spawned:
		return
	player.free_bank = minf(player.free_bank + 1.0, FREE_BANK_TICKS)
	if not player.free_kick_path.is_empty():
		# A push's slide being shown (688 amended (2), _tend_free_kicks): what
		# it sends meanwhile is dropped, acknowledged, as a halt's is.
		free_drop(player)
		return
	var was := player.free_pos
	var way := Vector2.ZERO
	var pressing := Vector2.ZERO
	while not player.free_inputs.is_empty() and player.free_bank > 0.001:
		var command: Dictionary = player.free_inputs[0]
		var ticks := minf(float(command["ticks"]), player.free_bank)
		way = _free_glide(player, player.free_pos, command["intent"], ticks, true)[1]
		if not free_held(player):
			pressing = command["intent"]
		player.free_bank -= ticks
		command["ticks"] = float(command["ticks"]) - ticks
		command["used"] = float(command["used"]) + ticks
		player.free_used = float(command["used"])
		if float(command["ticks"]) <= 0.001:
			_free_acked(player, player.free_inputs.pop_front())
	player.free_way = way
	_free_pressed(player, pressing)
	if player.free_pos.distance_to(was) > 0.01:
		player.last_step_tick = tick
		player.step_velocity = way
		player.step_until = tick + 1.0


## [param player]'s free body pressing [param intent] (this tick's, ZERO for
## none) into the edges of its cell (688 amended (4); Jeff: the barrow's
## hidden niche no longer opened): each straight way the intent leans at
## least FREE_PRESS_LEAN into, whose edge the body cannot cross and its
## circle is against, counted a tick at a time; at FREE_PRESS_TICKS it is a
## step refused there (_step_refused: the niche pressed, the map's edge
## walked off), and counts again from none, as a grid walk's refused steps
## come again while it is held. Brushing past along a wall leans too little
## into it to press.
func _free_pressed(player: Player, intent: Vector2) -> void:
	if player.free_press_tile != player.tile:
		player.free_press.clear()
		player.free_press_tile = player.tile
	for axis: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var against := intent.dot(Vector2(axis)) >= FREE_PRESS_LEAN \
				and (player.free_pos - Vector2(player.tile)).dot(Vector2(axis)) >= 0.5 - FREE_RADIUS - 0.01 \
				and _terrain_blocks_step(player.tile, axis)
		if not against:
			player.free_press.erase(axis)
			continue
		player.free_press[axis] = int(player.free_press.get(axis, 0)) + 1
		if int(player.free_press[axis]) >= FREE_PRESS_TICKS:
			player.free_press.erase(axis)
			_step_refused(player, axis)


## Where [param entity]'s free body would go from [param from] by
## [param intent] for [param ticks] (688 amended), touching nothing: no
## door opened, no crate shifted, no cell held, nothing told, whoever asks
## (a client's or a host's replay of its own commands, ui's 689). Its cell
## is [param held] (the cell it holds at [param from]; its tile if not
## given): a replay of several commands passes each the last one's, as the
## server's body holds its cell from one to the next (688 amended (3)).
## [centre, velocity in cells a tick, the cell it would hold].
func free_glide(entity: GridEntity, from: Vector2, intent: Vector2, ticks: float, held := NO_CELL) -> Array:
	return _free_glide(entity, from, intent, ticks, false, held)


## A free body's move (688): at its walk's speed (1 / step_ticks the way it
## mostly goes, from its cell: load, winded, the speed buff and the ground
## count, and a diagonal costs what a straight does), a substep at a time,
## each pushed out of what is solid (_free_resolve). A substep kept under a
## quarter of its move (head on into a corner) is tried along the way the
## intent mostly points alone, then the other (688 amended: it slides off
## rather than stall; x first on a tie). With [param effects] (the server's
## own turn) it also faces its way, writes its free_pos, opens and shifts
## what it presses and holds the cell its centre is in (_free_claim), a
## substep at a time. [centre, velocity, cell held].
func _free_glide(entity: GridEntity, from: Vector2, intent: Vector2, ticks: float, effects: bool, held := NO_CELL) -> Array:
	if held == NO_CELL or effects:
		held = entity.tile
	if free_held(entity) or intent.length() < 0.001 or ticks <= 0.0:
		return [from, Vector2.ZERO, held]
	var axis := _free_axis(intent)
	if effects:
		var facing := Vector2i(signi(roundi(intent.x * 1.3)), signi(roundi(intent.y * 1.3)))
		entity._world_set_facing(facing if facing != Vector2i.ZERO else axis)
	var p := from
	# The speed is read from the cell held, a substep at a time (688 amended
	# (3)), so a command split across the server's bank goes as its client's
	# replay of it whole does, however many cells it crosses.
	var speed := 1.0
	var velocity := Vector2.ZERO
	var left := ticks
	var guard := 0
	while left > 0.0001 and guard < 128:
		speed = 1.0 / maxf(step_ticks(entity, axis, held), 0.001)
		velocity = intent * speed
		var dt := minf(left, FREE_SUBSTEP / velocity.length())
		var move := velocity * dt
		# Cut short where the cell held would change, so the speed changes
		# there and not at whichever substep's end follows, which a split
		# command's substeps would place elsewhere.
		var cut := _free_cell_exit(p - Vector2(held), move)
		if cut < 1.0:
			dt *= cut
			move *= cut
		var to := _free_resolve(entity, p + move, intent, effects)
		if to.distance_to(p) < 0.25 * move.length():
			var other := Vector2i(axis.y, axis.x).abs()
			for along: Vector2 in [Vector2(axis).abs(), Vector2(other)]:
				var part := move * along
				if part.length() < 0.0001:
					continue
				var tried := _free_resolve(entity, p + part, intent, effects)
				if tried.distance_to(p) > to.distance_to(p) + 0.0001:
					to = tried
				if to.distance_to(p) >= 0.25 * move.length():
					break
		p = to
		if effects:
			entity.free_pos = p
			_free_claim(entity, 1.0 / speed)
			held = entity.tile
		else:
			held = _free_cell_from(held, p)
		left -= dt
		guard += 1
	return [p, velocity, held]


## The part of [param move] from [param off] (from the held cell's centre)
## at which the centre just passes FREE_HYSTERESIS beyond that cell's edge
## (688 amended (3)), 1 if it does not; never so little it barely moves.
static func _free_cell_exit(off: Vector2, move: Vector2) -> float:
	var limit := 0.5 + FREE_HYSTERESIS + 0.0005
	var cut := 1.0
	for i in 2:
		if absf(move[i]) < 0.000001:
			continue
		var t := (signf(move[i]) * limit - off[i]) / move[i]
		if t > 0.0 and t < cut:
			cut = t
	return cut if cut * move.length() > 0.0005 else 1.0


## The straight way [param intent] mostly points (688), x on a tie.
static func _free_axis(intent: Vector2) -> Vector2i:
	if absf(intent.x) >= absf(intent.y):
		return Vector2i(signi(roundi(signf(intent.x))), 0)
	return Vector2i(0, signi(roundi(signf(intent.y))))


## The cell [param entity]'s free body would hold with its centre at
## [param at] (688 amended), touching nothing: its tile, until the centre is
## FREE_HYSTERESIS past that cell's edge on either axis, then the cell the
## centre is in. Others there are _free_claim's to wait on.
func free_cell(entity: GridEntity, at: Vector2) -> Vector2i:
	return _free_cell_from(entity.tile, at)


## free_cell's rule from [param held], whatever is held.
static func _free_cell_from(held: Vector2i, at: Vector2) -> Vector2i:
	var off := at - Vector2(held)
	if absf(off.x) <= 0.5 + FREE_HYSTERESIS and absf(off.y) <= 0.5 + FREE_HYSTERESIS:
		return held
	return Vector2i(roundi(at.x), roundi(at.y))


## [param at] for [param entity]'s free body, pushed out of what is solid
## to it (688): the edges a step from the side its centre is on could not
## cross (_terrain_blocks_step: a wall, a closed door, a step up, the edge
## of the walkable), and the cells others hold (a monster, another player,
## a crate; never its own companion, whom it passes through). With
## [param effects], pressing [param intent] into a closed door it may open
## opens it; into a crate it shifts it a cell, at its walk's pace. A circle
## of FREE_RADIUS slides along what it meets and never cuts a corner.
## Without [param pass_own] (a push's slide, 688 amended (2)) its own
## companion is met as anyone is.
func _free_resolve(entity: GridEntity, at: Vector2, intent: Vector2, effects := true, pass_own := true) -> Vector2:
	var p := at
	for _pass in 3:
		var c := Vector2i(roundi(p.x), roundi(p.y))
		var moved := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var cell: Vector2i = c + Vector2i(dx, dy)
				for direction: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var out := _free_off_edge(entity, p, cell, direction, intent, effects)
					if out != p:
						p = out
						moved = true
				var square := _free_off_cell(entity, p, cell, intent, effects, pass_own)
				if square != p:
					p = square
					moved = true
		if not moved:
			break
	return p


## [param p] pushed off the edge between [param cell] and the cell
## [param direction] (east or south) of it, if that edge is solid from the
## side [param p] is on and the circle reaches it (688). A closed door
## pressed into opens only with [param effects].
func _free_off_edge(entity: GridEntity, p: Vector2, cell: Vector2i, direction: Vector2i, intent: Vector2, effects := true) -> Vector2:
	var across := direction.x  # 1: the edge is vertical, at x = cell.x + 0.5.
	var line := (cell.x if across == 1 else cell.y) + 0.5
	var along := p.y if across == 1 else p.x
	var middle := float(cell.y if across == 1 else cell.x)
	var offset := (p.x if across == 1 else p.y) - line
	var nearest := clampf(along, middle - 0.5, middle + 0.5)
	var gap := Vector2(offset, along - nearest) if across == 1 else Vector2(along - nearest, offset)
	if gap.length() >= FREE_RADIUS:
		return p
	var side := cell if offset < 0.0 else cell + direction
	var way := direction if offset < 0.0 else -direction
	if not _terrain_blocks_step(side, way):
		return p
	var door := _closed_door_across(side, way) if effects else null
	if door != null and intent.dot(Vector2(way)) > 0.0 and may_open(entity, door):
		_set_door(door, true, entity)
		if not _terrain_blocks_step(side, way):
			return p
	if gap.length() < 0.00001:
		return p - Vector2(way) * FREE_RADIUS
	return p + gap.normalized() * (FREE_RADIUS - gap.length())


## [param p] pushed out of [param cell], if another holds it that
## [param entity]'s free body may not pass (688): its own companion it
## passes through. With [param effects], pressing [param intent] into a
## pushable one beside its own cell shifts it a cell when its walk allows,
## and one on a link's cell is bumped as a refused step was.
## Whether [param other] is [param entity]'s own companion, on any peer
## (689): her keeper is the server's alone; a client knows her by her
## keeper's peer, so its replay passes through her as the server does.
static func _own_companion_of(other: GridEntity, entity: GridEntity) -> bool:
	if not other is Companion:
		return false
	var her := other as Companion
	return her.keeper == entity or her.keeper_peer != 0 and her.keeper_peer == entity.owner_peer


func _free_off_cell(entity: GridEntity, p: Vector2, cell: Vector2i, intent: Vector2, effects := true, pass_own := true) -> Vector2:
	if cell == entity.tile:
		return p
	var other: GridEntity = _occupancy.get(cell)
	if other == null or other == entity or pass_own and _own_companion_of(other, entity):
		return p
	var low := Vector2(cell) - Vector2(0.5, 0.5)
	var nearest := p.clamp(low, low + Vector2.ONE)
	var gap := p - nearest
	if gap.length() >= FREE_RADIUS:
		return p
	var axis := _free_axis(intent)
	if effects and entity is Player and is_link_cell(cell) and tick - (entity as Player).free_bumped_tick >= FREE_BUMP_TICKS:
		(entity as Player).free_bumped_tick = tick
		link_bumped.emit(entity, cell)  # A body on a link's cell never shuts the way (571).
	if effects and other.pushable and cell == entity.tile + axis and tick >= entity.next_move_tick:
		var duration := step_ticks(entity, axis)
		if _shift(entity, other, axis, entity.mass, duration, float(tick)):
			entity.next_move_tick = tick + duration
			return p
	if gap.length() > 0.00001:
		return p + gap.normalized() * (FREE_RADIUS - gap.length())
	# Its centre inside the cell (it took the cell under the body): out by
	# the nearest face.
	var into := p - Vector2(cell)
	if absf(into.x) >= absf(into.y):
		return Vector2(cell.x + signf(into.x) * (0.5 + FREE_RADIUS), p.y)
	return Vector2(p.x, cell.y + signf(into.y) * (0.5 + FREE_RADIUS))


## [param entity]'s free body holds the cell its centre is in (free_cell),
## as a step there would (688): the cell claimed (_relocate: entity_moved,
## interest, links), slid for the views over [param duration], and the
## step's grass, grace, noise and clank (_stepped_off). Its own companion's
## cell it waits on, bumping her (entity_bumped, every FREE_BUMP_TICKS) so
## she yields.
func _free_claim(entity: GridEntity, duration: float) -> void:
	var held := entity.tile
	var cell := free_cell(entity, entity.free_pos)
	if cell == held or not is_walkable(cell):
		return
	var other: GridEntity = _occupancy.get(cell)
	if other != null and other != entity:
		if other is Companion and entity is Player and tick - (entity as Player).free_bumped_tick >= FREE_BUMP_TICKS:
			(entity as Player).free_bumped_tick = tick
			entity_bumped.emit(entity, other, (cell - held).clamp(Vector2i(-1, -1), Vector2i(1, 1)))
		return
	entity._free_claiming = true
	_relocate(entity, cell)
	entity._free_claiming = false
	entity._world_slide_from(held, float(tick), duration)
	_stepped_off(entity, held, duration)


## A free body's slide from a push (688 amended (2)), decided at once as
## _push's cells are: [param body]'s centre traced from its free_pos along
## [param way] at speed [param u], a substep at a time through the free
## collision (_free_resolve, its own companion met as anyone), each cell
## crossed costing its ground_drag a cell's length, as far as
## u x slide_per_speed cells (at most max_travel). The cells its centre
## comes to hold are taken on the way (_free_cell_from). Met head on (within
## FREE_GLANCE_COS of the wall's normal), a wall, a closed door or a step up
## stops it; at a slant it goes on along it, its speed into it lost (the
## glance, which hurts). A body met stops it (_push hands the speed on);
## water at the edge stops it unhurt; a drop it goes off and falls; fire
## stops a creature in it. {path (the centres, from its free_pos), cells,
## speed (left at the end), stopped, collided, stopped_by, blocker, door,
## fall, glance (the most speed it lost into a wall it slid along), way
## (the way it was going at the end)}.
func _free_slide(body: GridEntity, way: Vector2, u: float) -> Dictionary:
	var dir := way.normalized()
	var out := {"path": PackedVector2Array([body.free_pos]), "cells": 0, "speed": 0.0, "stopped": false,
		"collided": false, "stopped_by": "nothing (force spent)", "blocker": null, "door": null, "fall": 0,
		"glance": 0.0, "way": dir}
	var speed := u
	var p := body.free_pos
	var travelled := 0.0
	var guard := 0
	while speed > 0.0001 and travelled < max_travel - 0.0001 and guard < 256:
		guard += 1
		var held := body.tile
		var drag := ground_drag(held, _free_axis(dir))
		var move := dir * minf(minf(FREE_SUBSTEP, speed * slide_per_speed / drag), max_travel - travelled)
		move *= _free_cell_exit(p - Vector2(held), move)
		var want := p + move
		var to := _free_resolve(body, want, dir, false, false)
		var gone := to.distance_to(p)
		travelled += gone
		speed = maxf(speed - gone * drag / slide_per_speed, 0.0)
		p = to
		out["path"].append(p)
		var cell := _free_cell_from(body.tile, p)
		if cell != body.tile and is_walkable(cell) and not _occupancy.has(cell):
			body._free_claiming = true
			_relocate(body, cell)
			body._free_claiming = false
			out["cells"] += 1
			if is_burning(cell) and body.is_creature():
				out["stopped"] = true
				out["stopped_by"] = "fire"
				break
		if to.distance_to(want) < 0.001:
			continue
		# Something stopped it: what lies the way it was pressed.
		var into := (want - to).normalized()
		var met := _free_met(body, to, into)
		if met != null:
			out["stopped"] = true
			out["collided"] = true
			out["blocker"] = met
			out["stopped_by"] = met.name
			break
		held = body.tile
		var axis := _free_axis(into)
		var next := held + axis
		if is_water(next) and not edge_blocks(held, axis):
			out["stopped"] = true
			out["stopped_by"] = "water"
			break
		var drop := height_step(held, axis) if is_walkable(next) else 0
		if drop > 0 and not edge_blocks(held, axis) and not _occupancy.has(next):
			# Off a ledge: it falls, and the fall is what hurts.
			body._free_claiming = true
			_relocate(body, next)
			body._free_claiming = false
			out["path"].append(Vector2(next))
			out["cells"] += 1
			out["fall"] = drop
			out["stopped"] = true
			out["stopped_by"] = "a fall of %d" % drop
			break
		var door := _closed_door_across(held, axis)
		var cosine := dir.dot(into)
		var along := dir - into * cosine
		if cosine >= FREE_GLANCE_COS or along.length() < 0.001:
			out["stopped"] = true
			out["collided"] = true
			out["door"] = door
			out["stopped_by"] = "a ledge" if drop < 0 else "wall" if door == null else door.name
			break
		out["glance"] = maxf(out["glance"], speed * cosine)
		speed *= along.length()
		dir = along.normalized()
	out["speed"] = speed if out["stopped"] else 0.0
	out["way"] = dir
	return out


## The body whose cell [param body]'s free circle at [param p] touches the
## way [param into] points (688 amended (2)), its own companion too; null
## for none.
func _free_met(body: GridEntity, p: Vector2, into: Vector2) -> GridEntity:
	var c := Vector2i(roundi(p.x), roundi(p.y))
	var best: GridEntity = null
	var best_dot := 0.0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cell: Vector2i = c + Vector2i(dx, dy)
			var other: GridEntity = _occupancy.get(cell)
			if other == null or other == body or cell == body.tile:
				continue
			var low := Vector2(cell) - Vector2(0.5, 0.5)
			if p.distance_to(p.clamp(low, low + Vector2.ONE)) > FREE_RADIUS + 0.01:
				continue
			var ahead := (Vector2(cell) - p).normalized().dot(into)
			if ahead > best_dot:
				best_dot = ahead
				best = other
	return best


## Each pushed free body's slide in this zone shown a tick further (688
## amended (2)), before anyone acts, whether it may act or not (a stunned
## body skips its turn): what it sent meanwhile dropped and acknowledged,
## its state packed for its client.
func _tend_free_kicks() -> void:
	for body: GridEntity in _free_kicked.keys():
		if not _alive(body) or body.free_kick_path.is_empty():
			_free_kicked.erase(body)
			continue
		if body.zone != zone.name:
			continue  # Its own zone's clock shows it (604 amended's lesson).
		var player := body as Player
		free_drop(player)
		_free_kick_show(player)
		player.pack_free()


## The slide decided for [param player]'s free body (688 amended (2)) shown
## a tick further: its centre along the path, slowing to a stop over
## free_kick_ticks; done, the path cleared.
func _free_kick_show(player: Player) -> void:
	var path := player.free_kick_path
	var t := clampf(float(tick - player.free_kick_at) / maxf(player.free_kick_ticks, 1), 0.0, 1.0)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	var left := length * (1.0 - (1.0 - t) * (1.0 - t))
	var at := path[path.size() - 1]
	for i in range(1, path.size()):
		var piece := path[i].distance_to(path[i - 1])
		if left <= piece:
			at = path[i - 1].lerp(path[i], left / piece if piece > 0.0 else 1.0)
			break
		left -= piece
	player.free_way = at - player.free_pos
	player.free_pos = at
	if t >= 1.0:
		player.free_kick_path = PackedVector2Array()
		player.free_way = Vector2.ZERO


func _relocate(entity: GridEntity, to: Vector2i) -> void:
	var from: Vector2i = entity.tile
	if _occupancy.get(from) == entity:
		_occupancy.erase(from)
	_occupancy[to] = entity
	entity._world_set_tile(to)
	entity._world_note_moved(tick)
	entity_moved.emit(entity, from, to)


# --- Queries (safe anywhere) --------------------------------------------------

func is_walkable(at: Vector2i) -> bool:
	return _floor.has(at)


## Every walkable cell of the zone's terrain, in no set order (a copy).
func floor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_floor.keys())
	return out


## A cell's height in whole levels (0..6 from height.png; relief.png's
## elevation rounded to levels, decision 525).
func height_at(at: Vector2i) -> int:
	return _height.get(at, 0)


## A cell's elevation in metres (decision 525), 0 off the map.
func elevation_at(at: Vector2i) -> float:
	return Relief.at(_relief, _relief_size, at)


## Whether this zone's level gave its ground in relief.png (decision 525).
func has_relief() -> bool:
	return _relief_given


## The terrain's elevation field (Level's "relief"), or one derived from
## its whole levels for a terrain that has none (Terrain.parse's, a test's).
func _load_relief(terrain: Dictionary) -> void:
	_relief_given = bool(terrain.get("relief_given", false))
	if terrain.has("relief"):
		# As walked: the bridges' decks over the water (505 amended).
		_relief = Level.walk_relief(terrain)
		_relief_size = terrain["relief_size"]
		return
	var high := Vector2i.ZERO
	for cell: Vector2i in _floor:
		high = high.max(cell + Vector2i.ONE)
	for cell: Vector2i in _height:
		high = high.max(cell + Vector2i.ONE)
	_relief_size = high
	_relief = Relief.derived(_height, high)


## The way the stair on [param at] climbs, or ZERO for none.
func stair_at(at: Vector2i) -> Vector2i:
	return _stairs.get(at, Vector2i.ZERO)


func is_water(at: Vector2i) -> bool:
	return _water.has(at)


## The cover of [param at] (decision 508), 0..1: how well it hides who
## stands in it from a look at a distance (Senses decides what it does).
## TALL_GRASS_COVER on standing tall grass, 0 trampled, open or off the map.
## A lookup: no allocation.
func cover_at(at: Vector2i) -> float:
	if not _cover_rect.has_point(at):
		return 0.0
	var cover := _cover[(at.y - _cover_rect.position.y) * _cover_rect.size.x + at.x - _cover_rect.position.x]
	return 0.0 if cover > 0.0 and _trampled_here.has(at) else cover


## Whether [param at] is tall grass, standing or trampled (decision 508).
func is_tall_grass(at: Vector2i) -> bool:
	return _cover_rect.has_point(at) and _cover[(at.y - _cover_rect.position.y) * _cover_rect.size.x + at.x - _cover_rect.position.x] > 0.0


## Whether [param at] is tall grass trampled flat now.
func is_trampled(at: Vector2i) -> bool:
	return _trampled_here.has(at)


## The cover array over the bounds of the terrain's tall grass.
func _load_cover(terrain: Dictionary) -> void:
	_cover = PackedFloat32Array()
	_cover_rect = Rect2i()
	var grass: Array = terrain.get("tall_grass", [])
	if grass.is_empty():
		return
	_cover_rect = Rect2i(grass[0], Vector2i.ONE)
	for cell: Vector2i in grass:
		_cover_rect = _cover_rect.expand(cell)
	_cover_rect.size += Vector2i.ONE
	_cover.resize(_cover_rect.size.x * _cover_rect.size.y)
	for cell: Vector2i in grass:
		_cover[(cell.y - _cover_rect.position.y) * _cover_rect.size.x + cell.x - _cover_rect.position.x] = TALL_GRASS_COVER
	_trampled_here = _trampled_of(fields.level)


## [param level]'s trampled cells, made if it has none (the dictionary
## itself: _trampled_here is the same one).
func _trampled_of(level: String) -> Dictionary:
	if not trampled.has(level):
		trampled[level] = {}
	return trampled[level]


## [param entity] stepped off [param at]: standing tall grass left by a
## body of TRAMPLE_MASS or more is flattened for TRAMPLE_DAYS, a trail
## behind it, while the cell it stands in keeps hiding it (508 amended).
func _trample(entity: GridEntity, at: Vector2i) -> void:
	if entity.mass < TRAMPLE_MASS or not is_tall_grass(at):
		return
	var flat := not _trampled_here.has(at)
	_trampled_here[at] = steps + int(TRAMPLE_DAYS * DayNight.day_steps)
	if flat and Net.is_authority():
		grass_changed.emit(fields.level, PackedInt32Array([at.x, at.y]), PackedInt32Array())


## The world tick's: trampled grass whose time has come stands again, in
## every level.
func _regrow() -> void:
	for level: String in trampled:
		var cells: Dictionary = trampled[level]
		var stood := PackedInt32Array()
		for cell: Vector2i in cells.keys():
			if int(cells[cell]) <= steps:
				cells.erase(cell)
				stood.append_array([cell.x, cell.y])
		if not stood.is_empty():
			grass_changed.emit(level, PackedInt32Array(), stood)


## [param level]'s trampled cells, flat [x, y, ...] (the "grass" message).
func trampled_cells(level: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for cell: Vector2i in trampled.get(level, {}):
		out.append_array([cell.x, cell.y])
	return out


## The snapshot's: level -> [x, y, the step it stands again, ...].
func trampled_to_dict() -> Dictionary:
	var out := {}
	for level: String in trampled:
		var flat: Array = []
		for cell: Vector2i in trampled[level]:
			flat.append_array([cell.x, cell.y, int(trampled[level][cell])])
		if not flat.is_empty():
			out[level] = flat
	return out


func trampled_from_dict(data: Dictionary) -> void:
	for level: String in trampled:
		trampled[level].clear()
	for level: Variant in data:
		var flat: Variant = data[level]
		if not flat is Array:
			continue
		var cells := _trampled_of(str(level))
		for i in range(0, (flat as Array).size() - 2, 3):
			cells[Vector2i(int(flat[i]), int(flat[i + 1]))] = int(flat[i + 2])
	_trampled_here = _trampled_of(fields.level)


## A client's: the "grass" message for [param level] ({level, full: its
## whole trampled set in flat, or flat newly trampled and stood standing
## again}); grass_changed for the view.
func grass_told(level: String, data: Dictionary) -> void:
	var cells := _trampled_of(level)
	var flat: Variant = data.get("flat", PackedInt32Array())
	var stood: Variant = data.get("stood", PackedInt32Array())
	if bool(data.get("full", false)):
		cells.clear()
	for i in range(0, (flat as PackedInt32Array).size() - 1 if flat is PackedInt32Array else 0, 2):
		cells[Vector2i(flat[i], flat[i + 1])] = 0
	for i in range(0, (stood as PackedInt32Array).size() - 1 if stood is PackedInt32Array else 0, 2):
		cells.erase(Vector2i(stood[i], stood[i + 1]))
	grass_changed.emit(level, flat if flat is PackedInt32Array and not bool(data.get("full", false)) else PackedInt32Array(),
		stood if stood is PackedInt32Array else PackedInt32Array())


## Whether [param at] is a ford (decision 505): floor, walked into at
## FORD_TICK_SCALE; not water (is_water is deep water only).
func is_ford(at: Vector2i) -> bool:
	return _fords.has(at)


func is_torch(at: Vector2i) -> bool:
	return _torches.has(at)


## How a step from [param from] in [param direction] meets the ground: 0 on
## the level or by a stair (the lower cell's stair climbing that way, one
## level), n > 0 a drop of n levels off a ledge, n < 0 a ledge n levels up.
## A diagonal across any change of height is a ledge (stairs are
## orthogonal), up or down as the destination is.
func height_step(from: Vector2i, direction: Vector2i) -> int:
	return Relief.step(_relief, _relief_size, _stairs, from, direction)


## What is on the edge leaving [param from] in orthogonal [param direction];
## OPEN for a diagonal, which crosses a corner, not an edge.
func edge_kind(from: Vector2i, direction: Vector2i) -> int:
	if direction.x != 0 and direction.y != 0:
		return Terrain.Edge.OPEN
	return _edges.get(Terrain.edge_key(from, direction), Terrain.Edge.OPEN)


## The door node on that edge, or null.
func door_across(from: Vector2i, direction: Vector2i) -> Door:
	if direction.x != 0 and direction.y != 0:
		return null
	return _doors.get(Terrain.edge_key(from, direction))


func _closed_door_across(from: Vector2i, direction: Vector2i) -> Door:
	var door := door_across(from, direction)
	return door if door != null and not door.is_open() else null


## True if the edge leaving [param from] in orthogonal [param direction]
## cannot be crossed: a wall, or a closed door unless the crosser
## [param opens_doors] (creatures do, by walking through). A door edge whose
## node has not arrived yet counts as closed.
func edge_blocks(from: Vector2i, direction: Vector2i, opens_doors := false) -> bool:
	match edge_kind(from, direction):
		Terrain.Edge.WALL:
			return true
		Terrain.Edge.DOOR:
			var door := door_across(from, direction)
			if door != null and door.is_open():
				return false
			return not opens_doors
	return false


## A closed door or a wall: what stops sight, unless the eye of the sight
## being walked is above both cells it stands between (higher cells see
## over lower walls), or the wall is a field's fence (Fields.fences).
func edge_blocks_sight(from: Vector2i, direction: Vector2i) -> bool:
	if _eye >= 0.0 and _eye - maxf(elevation_at(from), elevation_at(from + direction)) > Relief.WALK_RISE:
		return false
	match edge_kind(from, direction):
		Terrain.Edge.WALL:
			return not fields.fences.has(Terrain.edge_key(from, direction))
		Terrain.Edge.DOOR:
			var door := door_across(from, direction)
			return door == null or not door.is_open()
	return false


func is_free(at: Vector2i) -> bool:
	return is_walkable(at) and not _occupancy.has(at)


func is_fire(at: Vector2i) -> bool:
	return _fire.has(at)


func get_entity_at(at: Vector2i) -> GridEntity:
	return _occupancy.get(at)


func get_entities() -> Array[GridEntity]:
	return _entities.duplicate()


## Every entity in the zone. Not a copy: read it, do not change it, and do
## not spawn or despawn while going through it (get_entities for that).
func entities() -> Array[GridEntity]:
	return _entities


## The players and companions in the zone, in id order: what a monster
## looks for, without going through every crate and monster. Not a copy:
## read it, do not change it.
func sought() -> Array[GridEntity]:
	_take_roster()
	return _sought


## The monsters in the zone, in id order. Not a copy, as sought().
func monsters() -> Array[GridEntity]:
	_take_roster()
	return _monsters


## The zone's residents' bodies (Resident, decision 333), in id order. Not a
## copy, as sought(). Not sought: they wake no monster's tier.
func townsfolk() -> Array[GridEntity]:
	_take_roster()
	return _townsfolk


func _roster_changed() -> void:
	_roster_current = false


func _take_roster() -> void:
	if _roster_current:
		return
	# New arrays, not cleared ones: one handed out before stays as it was.
	_sought = []
	_hearers = []
	_monsters = []
	_townsfolk = []
	_actors = []
	for entity in _entities:
		if entity.acts:
			_actors.append(entity)
		if entity is Player or entity is Companion:
			_sought.append(entity)
			if entity is Companion:
				_hearers.append(entity)
		elif entity is Monster:
			_monsters.append(entity)
		elif entity is Resident:
			_townsfolk.append(entity)
			_hearers.append(entity)
	_roster_current = true


## True if occupancy and the entity list describe the same thing: every entity
## is the occupant of its own walkable tile, and nothing else is occupied.
func is_occupancy_consistent() -> bool:
	if _occupancy.size() != _entities.size():
		return false
	for entity in _entities:
		if not is_instance_valid(entity) or not is_walkable(entity.tile) \
				or _occupancy.get(entity.tile) != entity:
			return false
	return true


## Distance in steps (a diagonal is one step). Used for reach and sight range.
func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Ticks one walking step in [param direction] takes for [param entity];
## may be fractional. The step is from [param from], the entity's tile if
## not given: a walk planned ahead (a client's prediction, an offscreen
## walk) or a step already taken (a slide drawn after the tile moved) passes
## the step's own start, or its slope, ford and grass are another cell's and
## the client's pace drifts from the server's (perf, 2026-10-19, looking
## into rubber banding by the wilds town's chests, on grass and slopes).
func step_ticks(entity: GridEntity, direction: Vector2i, from := NO_CELL) -> float:
	var ticks := entity.move_ticks * (DIAGONAL_TICK_SCALE if direction.x != 0 and direction.y != 0 else 1.0)
	if from == NO_CELL:
		from = entity.tile
	if entity.winded:
		ticks *= winded_move_scale  # Decision 597; winded replicates, so a client's prediction agrees.
	ticks /= 1.0 + buff(entity, "speed")  # A stamina potion (decision 562); buffs replicate, so a client's prediction agrees.
	ticks *= walk_load(entity)  # Its body's load (676); replicated, so a client's prediction agrees.
	return ticks * ground_drag(from, direction)  # The ground (607), as a slide meets it.


## How hard the ground is to cross from [param from] the way
## [param direction] points (decision 607), one multiple for a walk's step
## time (step_ticks) and a slide's speed spent a cell (_push): uphill
## (Relief.pace, decision 525; a stair is not), times a ford's
## FORD_TICK_SCALE (wading), else tall grass standing TALL_GRASS_TICK_SCALE;
## 1 on open level ground. Downhill is no easier yet. A lunge's and a rush's
## cells read it too (607 amended).
func ground_drag(from: Vector2i, direction: Vector2i) -> float:
	var to := from + direction
	var drag := Relief.pace(elevation_at(to) - elevation_at(from), direction.x != 0 and direction.y != 0)
	if _fords.has(to):
		return drag * FORD_TICK_SCALE
	return drag * TALL_GRASS_TICK_SCALE if cover_at(to) > 0.0 else drag


func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return distance(a, b) == 1


## No friendly fire: an entity controlled by a peer may not attack or shove
## another peer-controlled entity. This is decided when a hit is accepted; the
## push code itself still treats every body alike, so a player can be caught
## by a crate or monster that someone else sent flying.
func can_target(attacker: GridEntity, target: GridEntity) -> bool:
	return target.holds_cell and (attacker.owner_peer == 0 or target.owner_peer == 0)


## [param entity] out of everyone's way (573 amended (4): the draugr gone at
## rest): kept in the zone's entities, its tile [param at] (where it is
## saved), but it holds no cell, so another may stand there, and nothing
## strikes it (can_target). hold_cell takes one again. Server only.
func vacate(entity: GridEntity, at: Vector2i) -> void:
	if not Net.is_authority():
		return
	if _occupancy.get(entity.tile) == entity:
		_occupancy.erase(entity.tile)
	entity.holds_cell = false
	if entity.tile != at:
		var from := entity.tile
		entity._world_set_tile(at)
		entity_moved.emit(entity, from, at)


## [param entity], vacated, holding a cell again: [param at] if free, else
## the first free one beside it (a step, no wall edge between); false, and
## still vacated, with none (it waits). Server only.
func hold_cell(entity: GridEntity, at: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if entity.holds_cell:
		return true
	var cell := at
	if not is_free(at):
		cell = NO_CELL
		for way in Relief.FOUR:
			if is_free(at + way) and not _terrain_blocks_step(at, way):
				cell = at + way
				break
		if cell == NO_CELL:
			return false
	_occupancy[cell] = entity
	entity.holds_cell = true
	if entity.tile != cell:
		var from := entity.tile
		entity._world_set_tile(cell)
		entity_moved.emit(entity, from, cell)
	return true


## Adjacent, with no wall or closed door between: nothing hits through a wall
## or diagonally past its corner.
func can_melee(from: Vector2i, to: Vector2i) -> bool:
	return are_adjacent(from, to) and not _terrain_blocks_step(from, to - from)


## Stunned entities cannot move, attack or shove, and skip their turn.
func is_stunned(entity: GridEntity) -> bool:
	return tick < entity.stunned_until_tick


## Mass used when [param entity] is on the receiving end of a push: halved
## while it is exhausted.
func pushed_mass(entity: GridEntity) -> float:
	var mass := entity.mass * EXHAUSTED_MASS_FACTOR if entity.is_exhausted() else entity.mass
	return mass * DOWN_MASS_FACTOR if is_down(entity) else mass


## Whether [param attacker] can strike [param target] where they stand:
## beside it (can_melee), or, with a spear's reach verb and not a
## [param shove], as far as its cells in a straight line (also diagonal)
## with every cell between empty and every step open (decision 344).
func in_reach(attacker: GridEntity, target: GridEntity, shove := false) -> bool:
	var verb := {} if shove else blow_verb(attacker)
	if free_body(attacker) or free_body(target):
		return _body_reach(body_centre(attacker), body_centre(target), attacker, target, verb)
	return _cell_reach(attacker.tile, target.tile, verb)


## The grid's reach (in_reach), from [param from] to [param to]: adjacent
## with no wall between, or a reach verb's straight line, no body on it.
func _cell_reach(from: Vector2i, to: Vector2i, verb: Dictionary) -> bool:
	if can_melee(from, to):
		return true
	if verb.get("kind") != "reach":
		return false
	var offset := to - from
	var cells := distance(from, to)
	if cells > int(verb["cells"]) or cells < 2:
		return false
	var step := offset / cells
	if step * cells != offset:
		return false  # Not on a straight line.
	var at := from
	for i in cells:
		if not can_melee(at, at + step) or i < cells - 1 and _occupancy.has(at + step):
			return false
		at += step
	return true


## Reach by bodies (decision 699), where a free body is in it: [param target]
## at [param to] struck from [param from] (centres, or a cell it might
## stand on) while they are at most the verb's reach plus both radii apart
## and nothing that would stop a step lies between; a reach verb past a
## plain blow's, no body on the cells between either.
func _body_reach(from: Vector2, to: Vector2, attacker: GridEntity, target: GridEntity, verb: Dictionary, slack := 0.0) -> bool:
	var apart := from.distance_to(to)
	var reach := melee_reach + slack
	if verb.get("kind") == "reach":
		reach = maxf(reach, float(verb["cells"]) - 0.1)
	if apart > reach + 2.0 * FREE_RADIUS or apart < 0.001:
		return false
	var cells := _cells_between(from, to)
	if cells.is_empty():
		return false  # A wall, a closed door or a step up between.
	if apart > melee_reach + 2.0 * FREE_RADIUS:
		for cell in cells.slice(1, cells.size() - 1):
			var other: GridEntity = _occupancy.get(cell)
			if other != null and other != attacker and other != target:
				return false
	return true


## The cells the segment [param from] to [param to] crosses, in order, or
## [] when an edge between two of them would stop a step (decision 699:
## melee's clear line, terrain only).
func _cells_between(from: Vector2, to: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i(from.round())]
	var samples := maxi(1, ceili(from.distance_to(to) / 0.05))
	for i in range(1, samples + 1):
		var cell := Vector2i(from.lerp(to, float(i) / samples).round())
		if cell == out[-1]:
			continue
		if _terrain_blocks_step(out[-1], cell - out[-1]):
			return []
		out.append(cell)
	return out


## How far apart two centres may be for [param attacker]'s blow to land
## where a free body is in it (decision 699): its reach plus both radii.
func reach_limit(attacker: GridEntity) -> float:
	var verb := blow_verb(attacker)
	var reach := melee_reach
	if verb.get("kind") == "reach":
		reach = maxf(reach, float(verb["cells"]) - 0.1)
	return reach + 2.0 * FREE_RADIUS


## Where [param entity]'s body is, in cells (decision 699): a free body's
## centre (as its shots start, shot_origin), else its cell's.
func body_centre(entity: GridEntity) -> Vector2:
	return shot_origin(entity)


## The way [param attacker] strikes [param target], one of DIRECTIONS
## (decision 699): on the grid the cells' (clamped); where a free body is
## in it, the line between the centres to the nearest 45 degrees.
func melee_way(attacker: GridEntity, target: GridEntity) -> Vector2i:
	if not free_body(attacker) and not free_body(target):
		return (target.tile - attacker.tile).clamp(Vector2i(-1, -1), Vector2i(1, 1))
	var v := body_centre(target) - body_centre(attacker)
	if v.length() < 0.001:
		return Vector2i.ZERO
	var angle := snappedf(v.angle(), PI / 4.0)
	return Vector2i(roundi(cos(angle)), roundi(sin(angle)))


## The cells [param attacker] could stand on to strike [param target] where
## it is now (decision 699; enemy-ai's approach), nearest [param attacker]
## first: strike_cells_at its centre.
func strike_cells(attacker: GridEntity, target: GridEntity) -> Array[Vector2i]:
	return strike_cells_at(attacker, body_centre(target), target)


## The cells [param attacker] could stand on to strike [param target] were
## its centre at [param centre] (a lead on a moving target; enemy-ai's):
## walkable, nobody else's, in its reach by in_reach's rule from there,
## nearest [param attacker] first. A body on the grid at its own cell: the
## neighbours with no wall between (and a reach verb's line), as ever.
func strike_cells_at(attacker: GridEntity, centre: Vector2, target: GridEntity) -> Array[Vector2i]:
	var verb := blow_verb(attacker)
	var reach := melee_reach
	if verb.get("kind") == "reach":
		reach = maxf(reach, float(verb["cells"]) - 0.1)
	var span := ceili(reach + 2.0 * FREE_RADIUS)
	var at := Vector2i(centre.round())
	var by_cells := not free_body(attacker) and not free_body(target)
	var out: Array[Vector2i] = []
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var cell := at + Vector2i(dx, dy)
			if cell == at or cell == target.tile or not is_walkable(cell):
				continue
			var other: GridEntity = _occupancy.get(cell)
			if other != null and other != attacker and other != target:
				continue
			if _cell_reach(cell, at, verb) if by_cells else _body_reach(Vector2(cell), centre, attacker, target, verb):
				out.append(cell)
	var from := attacker.tile
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - from).length_squared() < Vector2(b - from).length_squared())
	return out


## Whether [param entity]'s spear is braced (decision 344): a reach
## verb with brace in its hand, BRACE_TICKS without a step, not stunned.
func braced(entity: GridEntity) -> bool:
	var verb := blow_verb(entity)
	return verb.get("kind") == "reach" and bool(verb.get("brace", false)) and not is_stunned(entity) \
			and tick - entity.last_step_tick >= int(Items.strength_value(slot_strength(entity, Items.RIGHT_HAND), "brace_ticks", BRACE_TICKS))


## A charging [param mover] stepping onto [param cell] meets a braced
## spear whose reach, along where its holder faces, covers the cell
## (decision 344): the step is refused, and the holder's blow is
## queued on it: its blow times the spear's damage times
## BRACE_DAMAGE_FACTOR, pushed back the way it came with BRACE_FORCE_PER_KG
## times its mass. True when it was stopped.
## [param rushing]: it is lunging (decision 596), whatever kind it is.
func _meets_brace(mover: GridEntity, cell: Vector2i, direction: Vector2i, rushing := false) -> bool:
	if not rushing and (not mover is Monster or not (mover as Monster).charging()):
		return false
	for facing: Vector2i in DIRECTIONS:
		for k in [1, 2]:
			var holder: GridEntity = _occupancy.get(cell - facing * k)
			if holder == null or holder == mover or holder.facing != facing or not braced(holder) \
					or k > int(blow_verb(holder)["cells"]) or not can_target(holder, mover):
				continue
			if k == 2 and (_occupancy.has(cell - facing) and _occupancy.get(cell - facing) != mover or not can_melee(holder.tile, cell - facing)):
				continue
			var amount := maxi(1, roundi(holder.attack_damage * float(blow_verb(holder)["damage"]) * BRACE_DAMAGE_FACTOR))
			# Pushed back by the spear's blow and its own momentum, turned
			# (decision 592): a collision, not held to knockback_min_force.
			var force := push_force(holder, mover) * ATTACK_FORCE_FACTOR * float(blow_verb(holder)["force"]) \
					+ (1.0 + brace_restitution) * body_velocity(mover).length()  # All of it: a body run onto a stop.
			_log("brace: %s's spear stops %s's charge (%d, force %.2f)" % [holder.name, mover.name, amount, force])
			_queue_hit(holder, mover, mover.tile - holder.tile, -direction, amount, force, force, false, 0)
			_hits[-1].deed = "braced"
			holder._world_swung(cell - holder.tile)
			braced_against.emit(holder, mover)
			return true
	return false


## Whether [param entity] lies downed (decision 544): at 1 hp, not acting,
## no blow landing, no foe minding it, till downed_until.
func is_downed(entity: GridEntity) -> bool:
	return is_instance_valid(entity) and tick < entity.downed_until


## Lays [param target] downed for [param ticks] (decision 544): 1 hp, lying
## (down_until, as knocked down) and stunned as long, whatever it was doing
## dropped. Server only.
func lay_downed(target: GridEntity, ticks: int) -> void:
	if not Net.is_authority() or ticks <= 0 or not _alive(target):
		return
	target.hp = maxi(target.hp, 1)
	target.downed_until = tick + ticks
	target.down_until = maxi(target.down_until, target.downed_until)
	target.raised = ""
	_stun_for(target, ticks)
	if _bandaging.has(target):
		# Broken off as _tend_wounds would: the patient free to be bandaged again.
		var patient: GridEntity = _bandaging[target]["patient"]
		_bandaging.erase(target)
		if _alive(patient):
			patient.mending = 0
		bandage_broke_why = "hurt"
		_log("bandage: %s's bandaging of %s broken off (downed)" % [target.name, patient.name])
		bandage_changed.emit(target, patient, &"interrupted")
	target.tending = ""
	if _channels.has(target):
		_end_channel(target, &"broken")
	_downed[target] = true
	_log("downed: %s lies downed for %d ticks" % [target.name, ticks])


## [param body]'s downed window, and its lying and stun with it, longer by
## [param ticks] (a slowed heart, Mortally Wounded). Server only.
func extend_downed(body: GridEntity, ticks: int) -> void:
	if not Net.is_authority() or ticks <= 0 or not is_downed(body):
		return
	body.downed_until += ticks
	body.down_until = maxi(body.down_until, body.downed_until)
	_stun_for(body, body.downed_until - tick)


## [param body], downed, gets up at [param hp] (a channel done, decision
## 544). Server only.
func raise_downed(body: GridEntity, hp: int) -> void:
	if not Net.is_authority() or not _alive(body) or not is_downed(body):
		return
	body.downed_until = 0
	body.down_until = tick
	body.stunned_until_tick = tick
	_downed.erase(body)
	heal(body, clampi(hp, 1, body.max_hp) - body.hp)
	_log("downed: %s gets up at %d hp" % [body.name, body.hp])


## [param by] begins to bring back the downed [param body] (decision 544):
## beside it, holding still, for [param ticks]; done unless meanwhile
## [param by] moves, exerts itself or is hit, or [param body] gets up or
## dies (_tend_downed). Who may is Main's (the blessing, the half, the
## count). False if it cannot start.
func try_channel(by: GridEntity, body: GridEntity, ticks: int) -> bool:
	if not Net.is_authority() or ticks <= 0 or not _alive(by) or not _alive(body) or by == body:
		return false
	if is_downed(by) or is_stunned(by) or not is_downed(body) or body.zone != by.zone or not can_melee(by.tile, body.tile):
		return false
	if _channels.has(by) or _channels.values().any(func(job: Dictionary) -> bool: return job["body"] == body):
		return false
	_channels[by] = {"body": body, "until": tick + ticks, "from": tick, "tile": by.tile, "exerted": by.last_exertion_tick()}
	by.channel_of = String(body.name)
	by.channel_until = tick + ticks
	_log("channel: %s begins to bring back %s" % [by.name, body.name])
	channel_changed.emit(by, body, &"started")
	return true


## Who [param body] is being brought back by (decision 544); null if nobody.
func channeler_of(body: GridEntity) -> GridEntity:
	for by: GridEntity in _channels:
		if _channels[by]["body"] == body:
			return by
	return null


func _end_channel(by: GridEntity, state: StringName) -> void:
	var job: Dictionary = _channels.get(by, {})
	_channels.erase(by)
	if is_instance_valid(by):
		by.channel_of = ""
		by.channel_until = 0
	if not job.is_empty():
		_log("channel: %s's return of %s %s" % [by.name if is_instance_valid(by) else "?", job["body"].name if is_instance_valid(job["body"]) else "?", state])
		channel_changed.emit(by, job["body"], state)


## Each tick (decision 544): channels go on, are broken off or are done;
## a downed body whose time ran out dies as ever (cause &"bled").
func _tend_downed() -> void:
	for by: GridEntity in _channels.keys():
		var job: Dictionary = _channels[by]
		var body: GridEntity = job["body"]
		if _alive(by) and by.zone != zone.name:
			continue  # Another zone's: its own step tends it.
		var broken := not _alive(by) or not _alive(body) or not is_downed(body) or is_downed(by)
		if not broken:
			broken = by.tile != job["tile"] or by.last_exertion_tick() != job["exerted"] \
					or by.hurt_tick >= int(job["from"]) or not can_melee(by.tile, body.tile)
		if broken:
			_end_channel(by, &"broken")
		elif tick >= int(job["until"]):
			_end_channel(by, &"done")
	for body: GridEntity in _downed.keys():
		if not _alive(body):
			_downed.erase(body)
		elif body.zone == zone.name and not is_downed(body) and body.downed_until > 0:
			_downed.erase(body)
			body.downed_until = 0
			if channeler_of(body) != null:
				_end_channel(channeler_of(body), &"broken")
			_log("downed: %s's time ran out" % body.name)
			damage(body, body.hp, null, &"bled")


## Whether [param entity] lies knocked down (knock_down; decision 343).
func is_down(entity: GridEntity) -> bool:
	return tick < entity.down_until


## Knocks [param target] down for [param ticks] (a giant axe's blow;
## decision 343): it lies (down_until, replicated, for the views), cannot
## act (a stun as long), lowers what it raised, and is pushed as if
## DOWN_MASS_FACTOR of its mass.
func knock_down(target: GridEntity, source: GridEntity, ticks: int) -> void:
	if not Net.is_authority() or ticks <= 0 or is_sheltered(target):
		return  # (Arriving, decision 661: not knocked down.)
	if target is Monster and (target as Monster).never_lies:
		# Never on the floor (573 amended (4), the draugr; approved by the
		# coordinator, combat's file): a stagger, the stun alone. No
		# knocked_down, so the party log tells no knockdown (Main._narrate_down).
		target.raised = ""
		_wear_bundle(target)
		_stun_for(target, ticks)
		_log("staggered: %s by %s for %d ticks (never lies)" % [target.name, source.name if is_instance_valid(source) else "?", ticks])
		return
	target.down_until = maxi(target.down_until, tick + ticks)
	target.raised = ""
	_wear_bundle(target)
	_stun_for(target, ticks)
	_log("down: %s knocked down by %s for %d ticks" % [target.name, source.name if is_instance_valid(source) else "?", ticks])
	knocked_down.emit(target, source)


## Force of a shove by [param attacker] on [param target], the speed it
## gives it (decision 592): its impulse, strength x the attacker's mass x
## shove_scale, over the target's pushed mass, scaled by how much stamina
## the attacker has left. So pushes fade as the attacker tires, down to
## nothing at 0. A melee attack carries half.
func push_force(attacker: GridEntity, target: GridEntity) -> float:
	if attacker.strength <= 0:
		return 0.0
	return attacker.strength * attacker.mass * shove_scale / maxf(pushed_mass(target), 0.001) \
			* attacker.stamina_fraction()


## [param entity]'s velocity in cells a tick (decision 592): its step's,
## while it steps and momentum_ticks after; ZERO standing. Server only.
func body_velocity(entity: GridEntity) -> Vector2:
	if not is_instance_valid(entity) or tick > entity.step_until + momentum_ticks:
		return Vector2.ZERO
	return entity.step_velocity


## The mass [param entity] is pushed as (pushed_mass), for combat's costs.
func mass_of(entity: GridEntity) -> float:
	return pushed_mass(entity)


## What [param attacker]'s motion adds to a push of [param target] along
## [param way] (decision 592): its momentum over the target's mass, the
## part backward along the way dropped; ZERO standing.
func momentum_push(attacker: GridEntity, target: GridEntity, way: Vector2) -> Vector2:
	var velocity := body_velocity(attacker)
	if velocity == Vector2.ZERO or way == Vector2.ZERO:
		return Vector2.ZERO
	var push := velocity * attacker.mass * momentum_scale / maxf(pushed_mass(target), 0.001)
	var along := push.dot(way.normalized())
	return push - way.normalized() * along if along < 0.0 else push


## Stamina a shove of [param force] on [param target] costs.
func shove_cost(force: float, target: GridEntity) -> int:
	return roundi(shove_cost_base + force * pushed_mass(target) * shove_cost_scale)


func blocks_sight(at: Vector2i) -> bool:
	if _through_bodies:
		return false
	var occupant: GridEntity = _occupancy.get(at)
	return occupant != null and occupant.blocks_sight


## Bresenham walk between two tiles. Sight is stopped by a wall edge or a
## closed door crossed on the way, and by an entity that blocks sight on a
## tile between; the endpoints themselves never block. A diagonal step of
## the walk needs one of its two orthogonal routes open.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	_eye = elevation_at(from)
	var seen := _line_of_sight(from, to)
	_eye = -1.0
	return seen


## A line of sight that bodies do not stop: how light and heat travel.
func has_clear_line(from: Vector2i, to: Vector2i) -> bool:
	_through_bodies = true
	var seen := has_line_of_sight(from, to)
	_through_bodies = false
	return seen


## What a clear line (has_clear_line) from [param from] to [param to]
## owes to doors: null if the terrain alone stops it, else the keys of the
## doors it crosses, each of which must be open for it to be clear ([] for
## none); LINE_ASK when it passes a door on a diagonal step, where it
## depends on more than one door being open. Walls, heights and where the
## doors are stay put, so this is worked out once (Fields).
const LINE_ASK := -1
func line_doors(from: Vector2i, to: Vector2i) -> Variant:
	var eye := height_at(from)
	var top := maxi(eye, height_at(to))
	var doors: Array[Vector3i] = []
	var d: Vector2i = (to - from).abs()
	var s := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var err: int = d.x - d.y
	var at: Vector2i = from
	while at != to:
		var e2: int = 2 * err
		var step := Vector2i.ZERO
		if e2 > -d.y:
			err -= d.y
			step.x = s.x
		if e2 < d.x:
			err += d.x
			step.y = s.y
		if step.x == 0 or step.y == 0:
			var crossing: Variant = _sight_edge(at, step, eye)
			if crossing == null:
				return null
			if crossing is Vector3i:
				doors.append(crossing)
		else:
			var via_x := Vector2i(step.x, 0)
			var via_y := Vector2i(0, step.y)
			var routes := [[_sight_edge(at, via_x, eye), _sight_edge(at + via_x, via_y, eye)],
				[_sight_edge(at, via_y, eye), _sight_edge(at + via_y, via_x, eye)]]
			var open_route := false
			var door_route := false
			for route: Array in routes:
				if route.has(null):
					continue
				if route[0] is Vector3i or route[1] is Vector3i:
					door_route = true
				else:
					open_route = true
			if not open_route:
				if not door_route:
					return null
				return LINE_ASK
		at += step
		if at != to and (height_at(at) > top or _solid.has(at)):
			return null
	return doors


## An edge as sight (edge_blocks_sight, from an eye at [param eye]) meets
## it, whatever its door is doing: null for a wall, the key for a door,
## true for open.
func _sight_edge(from: Vector2i, direction: Vector2i, eye: int) -> Variant:
	if eye >= 0 and eye > maxi(height_at(from), height_at(from + direction)):
		return true
	match edge_kind(from, direction):
		Terrain.Edge.WALL:
			return true if fields.fences.has(Terrain.edge_key(from, direction)) else null
		Terrain.Edge.DOOR:
			return Terrain.edge_key(from, direction)
	return true


## The walk itself. Ground higher than both ends stops it too, and for
## sight (not light and heat: has_clear_line) ground higher than the eye
## does (decision 513): from under a cliff its lip is seen, nothing behind
## it; from on top, everything below.
func _line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if _relief_given and not _through_bodies:
		return _line_in_metres(from, to)
	var top := maxi(height_at(from), height_at(to))
	if not _through_bodies:
		top = height_at(from)
	var d: Vector2i = (to - from).abs()
	var s := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var err: int = d.x - d.y
	var at: Vector2i = from
	while at != to:
		var e2: int = 2 * err
		var step := Vector2i.ZERO
		if e2 > -d.y:
			err -= d.y
			step.x = s.x
		if e2 < d.x:
			err += d.x
			step.y = s.y
		if _sight_crosses_edge(at, step):
			return false
		at += step
		if at != to and (blocks_sight(at) or _solid.has(at) or height_at(at) > top):
			return false
	return true


## Sight over a level's relief (decision 525): a line from Relief.EYE_M
## over the viewer's ground to Relief.AIM_M over the seen cell's, stopped
## by ground above it on the way (a ridge hides the valley behind it; from
## under a cliff its lip is seen, not what stands back from it), and by
## walls, doors and bodies as the walk above.
func _line_in_metres(from: Vector2i, to: Vector2i) -> bool:
	var eye := elevation_at(from) + Relief.EYE_M
	var aim := elevation_at(to) + Relief.AIM_M
	var length := Vector2(from).distance_to(Vector2(to))
	var d: Vector2i = (to - from).abs()
	var s := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var err: int = d.x - d.y
	var at: Vector2i = from
	while at != to:
		var e2: int = 2 * err
		var step := Vector2i.ZERO
		if e2 > -d.y:
			err -= d.y
			step.x = s.x
		if e2 < d.x:
			err += d.x
			step.y = s.y
		if _sight_crosses_edge(at, step):
			return false
		at += step
		if at != to and (blocks_sight(at) or _solid.has(at) or elevation_at(at) > lerpf(eye, aim, Vector2(from).distance_to(Vector2(at)) / length)):
			return false
	return true


func _sight_crosses_edge(from: Vector2i, step: Vector2i) -> bool:
	if step.x == 0 or step.y == 0:
		return edge_blocks_sight(from, step)
	var via_x := Vector2i(step.x, 0)
	var via_y := Vector2i(0, step.y)
	var route_x := edge_blocks_sight(from, via_x) or edge_blocks_sight(from + via_x, via_y)
	var route_y := edge_blocks_sight(from, via_y) or edge_blocks_sight(from + via_y, via_x)
	return route_x and route_y


## A* over the cells, 8-connected, costed in ticks (see
## [constant DIAGONAL_TICK_SCALE]).
## Returns the tiles to step through, excluding [param from] and including
## [param to]; empty if unreachable. Walls are edges; diagonals never cut a
## wall corner. Closed doors are walked through (every pathfinder is a
## creature, and creatures open doors) at the cost of an extra step. Fire is
## walkable but avoided when a short detour exists.
## With [param ignore_goal_occupant] the goal may be occupied (walk up to a
## monster, push a crate), but occupied tiles along the way still block.
## [param ignore] is an entity whose own tile does not count as occupied
## (a client predicting for itself, whose replicated tile lags behind).
## [param max_tiles] > 0 gives up (empty) after looking at that many tiles:
## a monster's way to a tile beside its target is short or not worth it.
## With [param nearest], giving up (or no way there) gives the way to the
## tile it looked at that is nearest [param to] instead (the earliest of
## equals; empty if that is [param from]): as far as a walk can get.
## [param walls]: cells it never steps into ({cell: anything}; another
## faction's held ground), the goal among them.
## Without [param opens_doors] a closed door is shut to it (a monster that
## cannot open doors, or will not now: Monster.opens_doors_now); the memo of
## steps (_path_step) is shared and says a door is passable, so that is
## asked here, on door steps only.
## [param fire_extra]: what a burning cell costs beyond a step
## (PATH_FIRE_EXTRA, a short detour; PATH_FIRE_AVOID, decision 707, for
## those that keep off fire).
func find_path(from: Vector2i, to: Vector2i, ignore_goal_occupant := false,
		ignore: GridEntity = null, max_tiles := 0, nearest := false, walls := {}, opens_doors := true,
		fire_extra := PATH_FIRE_EXTRA) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if from == to or not is_walkable(to):
		return path
	if _occupancy.has(to) and not ignore_goal_occupant and _occupancy[to] != ignore:
		return path
	_ensure_grid()
	var origin := _grid_rect.position
	var width := _grid_rect.size.x
	if not _grid_rect.has_point(from):
		return path  # Off the map and its edge: nothing walkable beside it.
	# Search number _search: a cell's entries count only if stamped with it.
	_search += 1
	var stamp := _search
	# Packed arrays are copied when written through a second name: the
	# members are written directly.
	var from_at := (from.y - origin.y) * width + from.x - origin.x
	var to_at := (to.y - origin.y) * width + to.x - origin.x
	_search_opened[from_at] = stamp
	_search_order[from_at] = 0
	_search_cost[from_at] = 0
	var opened_count := 1
	var closed_count := 0
	var best := from_at
	var best_left := _path_heuristic(from, to)
	var heat_carried := _carried_heat()
	var hot: Dictionary = {} if heat_carried else fields.hot_set(self, HEAT_BURN)
	var hot_any := not hot.is_empty()
	# The open cells (indices) in a binary heap keyed by (f, the order each
	# was first opened in): the cheapest, the earliest of equals, comes out
	# first, as a scan of a list in that order would pick it, without the
	# scan. A cell made cheaper is pushed again; its older entry is stale and
	# skipped when it comes up. The cells' state is in flat arrays by index
	# (_search_*), stamped with the search's number, not dictionaries made
	# for each search: a third of the time.
	var heap_keys := PackedInt64Array()
	var heap_cells := PackedInt32Array()
	var walled := not walls.is_empty()
	heap_keys.append(best_left << PATH_ORDER_BITS)
	heap_cells.append(from_at)
	var offsets := PackedInt32Array()
	for direction in DIRECTIONS:
		offsets.append(direction.y * width + direction.x)
	# In grid coordinates (from the grid's corner) from here: the heuristic
	# (_path_heuristic) worked out inline, and a cell off the grid's rim
	# only checked for on the rim.
	var to_x := to.x - origin.x
	var to_y := to.y - origin.y
	var last_x := width - 1
	var last_y := _grid_rect.size.y - 1

	while not heap_keys.is_empty():
		# The heap's top taken off and its last sifted down from the top,
		# inline (a call per cell looked at was a good part of the search).
		var key := heap_keys[0]
		var at: int = heap_cells[0]
		var heap_last := heap_keys.size() - 1
		var sift_key := heap_keys[heap_last]
		var sift_cell: int = heap_cells[heap_last]
		heap_keys.resize(heap_last)
		heap_cells.resize(heap_last)
		if heap_last > 0:
			var hole := 0
			while true:
				var child := hole * 2 + 1
				if child >= heap_last:
					break
				if child + 1 < heap_last and heap_keys[child + 1] < heap_keys[child]:
					child += 1
				if heap_keys[child] >= sift_key:
					break
				heap_keys[hole] = heap_keys[child]
				heap_cells[hole] = heap_cells[child]
				hole = child
			heap_keys[hole] = sift_key
			heap_cells[hole] = sift_cell
		var x := at % width
		var y := at / width
		var dx := absi(x - to_x)
		var dy := absi(y - to_y)
		var diagonals := mini(dx, dy)
		var left := diagonals * PATH_DIAGONAL_COST + (maxi(dx, dy) - diagonals) * PATH_STEP_COST
		var cost: int = _search_cost[at]
		if _search_closed[at] == stamp or key >> PATH_ORDER_BITS != cost + left:
			continue  # Stale: closed already, or pushed again since, cheaper.
		if max_tiles > 0 and closed_count >= max_tiles:
			break
		if at == to_at:
			while at != from_at:
				path.append(Vector2i(origin.x + at % width, origin.y + at / width))
				at = _search_from[at]
			path.reverse()
			return path
		_search_closed[at] = stamp
		closed_count += 1
		if nearest and left < best_left:
			best = at
			best_left = left
		var current := Vector2i(origin.x + x, origin.y + y)
		var rim := x == 0 or y == 0 or x == last_x or y == last_y
		var steps_at := at * 8
		for way in 8:
			var direction: Vector2i = DIRECTIONS[way]
			if rim and (x + direction.x < 0 or y + direction.y < 0 or x + direction.x > last_x or y + direction.y > last_y):
				continue  # Off the grid: not floor, so blocked.
			var next_at := at + offsets[way]
			if _search_closed[next_at] == stamp:
				continue
			var step: int = _grid_steps[steps_at + way] - 1
			if step == -1:
				step = _path_step(current, way)
			if step == PATH_STEP_BLOCKED or step == PATH_STEP_ASK and _terrain_blocks_step(current, direction, opens_doors):
				continue
			var shut := step == PATH_STEP_DOOR and _closed_door_across(current, direction) != null
			if shut and not opens_doors:
				continue
			var next := current + direction
			if next_at != to_at and _occupancy.has(next) and _occupancy[next] != ignore:
				continue
			if walled and walls.has(next):
				continue
			var next_cost := cost
			if way >= 4:
				next_cost += PATH_DIAGONAL_COST + PATH_DIAGONAL_EXTRA
			else:
				next_cost += PATH_STEP_COST
				if shut:
					next_cost += PATH_DOOR_EXTRA
			if is_burning(next) if heat_carried else hot_any and hot.has(next):
				next_cost += fire_extra
			var seen := _search_opened[next_at] == stamp
			if not seen or next_cost < _search_cost[next_at]:
				_search_cost[next_at] = next_cost
				_search_from[next_at] = at
				if not seen:
					_search_opened[next_at] = stamp
					_search_order[next_at] = opened_count
					opened_count += 1
				dx = absi(x + direction.x - to_x)
				dy = absi(y + direction.y - to_y)
				diagonals = mini(dx, dy)
				# Onto the heap, sifted up, inline.
				var push_key := ((next_cost + diagonals * PATH_DIAGONAL_COST
						+ (maxi(dx, dy) - diagonals) * PATH_STEP_COST) << PATH_ORDER_BITS) | _search_order[next_at]
				var hole := heap_keys.size()
				heap_keys.append(push_key)
				heap_cells.append(next_at)
				while hole > 0:
					var parent := (hole - 1) >> 1
					if heap_keys[parent] <= push_key:
						break
					heap_keys[hole] = heap_keys[parent]
					heap_cells[hole] = heap_cells[parent]
					hole = parent
				heap_keys[hole] = push_key
				heap_cells[hole] = next_at
	if nearest:
		var at := best
		while at != from_at:
			path.append(Vector2i(origin.x + at % width, origin.y + at / width))
			at = _search_from[at]
		path.reverse()
	return path


## A player's own way from [param from] to [param to] (decision 678;
## Jeff: "walking still wants to be on a diagonal and it doesn't fit with
## the new camera"): find_path's way with the string pulled, each run of it
## that a straight line can take replaced by that line (line_cells), so a
## clearing is crossed straight, not as a staircase of diagonals then
## straights. A run grows while the line from its start to the next point
## of the way is all steps the way could take (_line_clear: no wall or
## corner refusal, nobody but [param ignore] or the goal's occupant, no
## fire); never longer, as a line of n cells is n steps and the same
## diagonals. Players' own routes only (the prediction's plan and
## Player's re-path); monsters keep find_path.
func walk_path(from: Vector2i, to: Vector2i, ignore: GridEntity = null, fire_extra := PATH_FIRE_EXTRA) -> Array[Vector2i]:
	var path := find_path(from, to, true, ignore, 0, false, {}, true, fire_extra)
	if path.size() < 3:
		return path
	var pulled: Array[Vector2i] = []
	var anchor := from
	var i := 0
	while i < path.size():
		var j := i
		while j + 1 < path.size() and _line_clear(anchor, path[j + 1], to, ignore):
			j += 1
		pulled.append_array(line_cells(anchor, path[j]))
		anchor = path[j]
		i = j + 1
	return pulled


## The cells of the straight line from [param a] to [param b] (decision
## 678), b's included and a's not: one a step, each a king's move, the
## nearest cell to the true line at each of the max(|dx|, |dy|) steps.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var delta := b - a
	var n := maxi(absi(delta.x), absi(delta.y))
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		cells.append(a + Vector2i(roundi(delta.x * t), roundi(delta.y * t)))
	return cells


## Whether every step of the line from [param a] to [param b] could be
## walked as find_path walks (decision 678): the terrain lets it (walls,
## corners, heights; doors open), nobody stands in it but [param ignore]
## or whoever holds [param goal], and it is not on fire.
func _line_clear(a: Vector2i, b: Vector2i, goal: Vector2i, ignore: GridEntity) -> bool:
	var at := a
	for next in line_cells(a, b):
		if _terrain_blocks_step(at, next - at, true):
			return false
		if next != goal and _occupancy.has(next) and _occupancy[next] != ignore:
			return false
		if is_burning(next):
			return false
		at = next
	return true


## What the terrain lets a walker who opens doors do stepping from
## [param from] the way DIRECTIONS[[param way]] points (PATH_STEP_*),
## worked out once a zone's terrain and remembered: walls, heights and
## stairs stay put, and a door edge never blocks one who opens doors going
## straight through; only a diagonal past one depends on the door
## (PATH_STEP_ASK). A cell's eight are worked out together the first time
## one is asked (_fill_path_steps).
func _path_step(from: Vector2i, way: int) -> int:
	_ensure_grid()
	var base := ((from.y - _grid_rect.position.y) * _grid_rect.size.x + from.x - _grid_rect.position.x) * 8
	if _grid_steps[base + way] == 0:
		_fill_path_steps(from, base)
	return _grid_steps[base + way] - 1


## _path_step's eight answers for [param from], into _grid_steps from
## [param base]: what _terrain_blocks_step(from, direction, true) and the
## edges say, each cell, edge and height around it looked up once, not
## once a step (perf: a step at a time was most of a search on ground not
## searched before, 7.6 us a step). A step is BLOCKED onto a cell that is
## not floor, up or down a ledge (a straight step by a stair excepted),
## across a wall, or on a diagonal past a cell that is not floor or a
## height that differs; a diagonal past a door edge is ASK, a straight one
## through a door DOOR.
func _fill_path_steps(from: Vector2i, base: int) -> void:
	var x := from.x
	var y := from.y
	var level := elevation_at(from)
	# The four edges round the cell, by way (DIRECTIONS 0..3: east, south,
	# west, north), and whether each straight neighbour is floor at its height.
	var sides := PackedInt32Array([
		_edges.get(Vector3i(x, y, Terrain.EAST), Terrain.Edge.OPEN),
		_edges.get(Vector3i(x, y, Terrain.SOUTH), Terrain.Edge.OPEN),
		_edges.get(Vector3i(x - 1, y, Terrain.EAST), Terrain.Edge.OPEN),
		_edges.get(Vector3i(x, y - 1, Terrain.SOUTH), Terrain.Edge.OPEN)])
	var level_with := PackedByteArray([0, 0, 0, 0])
	for way in 4:
		var direction: Vector2i = DIRECTIONS[way]
		var to := from + direction
		var step := PATH_STEP_BLOCKED
		if _floor.has(to):
			if not Relief.cliff_between(level, elevation_at(to)):
				level_with[way] = 1
			if sides[way] != Terrain.Edge.WALL and height_step(from, direction) == 0:
				step = PATH_STEP_DOOR if sides[way] == Terrain.Edge.DOOR else PATH_STEP_OPEN
		_grid_steps[base + way] = step + 1
	for way in range(4, 8):
		var direction: Vector2i = DIRECTIONS[way]
		# Its two straight halves' ways: x first, then y.
		var way_x := 0 if direction.x > 0 else 2
		var way_y := 1 if direction.y > 0 else 3
		# The edges past the corner: from the x neighbour going y, from the
		# y neighbour going x.
		var beyond_x: int = _edges.get(Vector3i(x + direction.x, y if direction.y > 0 else y - 1, Terrain.SOUTH), Terrain.Edge.OPEN)
		var beyond_y: int = _edges.get(Vector3i(x if direction.x > 0 else x - 1, y + direction.y, Terrain.EAST), Terrain.Edge.OPEN)
		var step := PATH_STEP_OPEN
		if sides[way_x] == Terrain.Edge.DOOR or sides[way_y] == Terrain.Edge.DOOR \
				or beyond_x == Terrain.Edge.DOOR or beyond_y == Terrain.Edge.DOOR:
			step = PATH_STEP_ASK
		elif not _floor.has(from + direction) or level_with[way_x] == 0 or level_with[way_y] == 0 \
				or height_step(from, direction) != 0 \
				or sides[way_x] == Terrain.Edge.WALL or sides[way_y] == Terrain.Edge.WALL \
				or beyond_x == Terrain.Edge.WALL or beyond_y == Terrain.Edge.WALL:
			step = PATH_STEP_BLOCKED
		_grid_steps[base + way] = step + 1


## _grid_rect and _grid_steps worked out, if not yet, and find_path's own
## arrays as big as this zone's grid.
func _ensure_grid() -> void:
	if _grid_rect.size != Vector2i.ZERO:
		return
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	var first := true
	for cell: Vector2i in _floor:
		low = cell if first else low.min(cell)
		high = cell if first else high.max(cell)
		first = false
	_grid_rect = Rect2i(low - Vector2i.ONE, high - low + Vector2i(3, 3))
	var cells := _grid_rect.size.x * _grid_rect.size.y
	_grid_steps = PackedByteArray()
	_grid_steps.resize(cells * 8)
	if _search_opened.size() < cells:
		_search_opened.resize(cells)
		_search_closed.resize(cells)
		_search_cost.resize(cells)
		_search_from.resize(cells)
		_search_order.resize(cells)


## Cheapest possible cost between two tiles on an empty grid.
func _path_heuristic(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	var diagonals := mini(dx, dy)
	return diagonals * PATH_DIAGONAL_COST + (maxi(dx, dy) - diagonals) * PATH_STEP_COST


## True if terrain alone forbids stepping from [param from] in [param direction]:
## the destination is not floor, the edge between is a wall (or a closed door
## and the stepper does not open doors), or, for a diagonal, either
## orthogonal neighbour is not floor or any of the four edges around that
## corner is shut: no cutting a wall corner. With [param heights] (walking),
## a ledge up or down too: only a stair joins two heights. Entities
## standing there do not count.
func _terrain_blocks_step(from: Vector2i, direction: Vector2i, opens_doors := false, heights := true) -> bool:
	var to := from + direction
	if not is_walkable(to):
		return true
	if heights and height_step(from, direction) != 0:
		return true
	if direction.x == 0 or direction.y == 0:
		return edge_blocks(from, direction, opens_doors)
	var via_x := Vector2i(direction.x, 0)
	var via_y := Vector2i(0, direction.y)
	if not is_walkable(from + via_x) or not is_walkable(from + via_y):
		return true
	return edge_blocks(from, via_x) or edge_blocks(from + via_x, via_y) \
			or edge_blocks(from, via_y) or edge_blocks(from + via_y, via_x)


func _alive(entity: Variant) -> bool:
	return is_instance_valid(entity) and entity.spawned


## Whether a door, a dropped hit or a push that moved nothing is logged
## when [param by] does it: a player's or a companion's, yes; a monster's,
## no (a crowd's blows on a player too heavy to shift, its doors, were
## lines a tick on a busy server, slow to write and of no use). A push that
## moves something is logged whoever does it.
func _logs_for(by: GridEntity) -> bool:
	return by is Player or by is Companion


## How many lines _log has written (tests check a fight among monsters
## writes none).
var logged := 0


func _log(message: String) -> void:
	logged += 1
	print("[tick %d] %s" % [tick, message])
