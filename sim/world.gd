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
signal entity_despawned(entity: GridEntity)
## Reduced to 0 hp by [param cause] (&"attack", &"shot", &"impact", &"fire"), just
## before it is removed.
signal entity_died(entity: GridEntity, cause: StringName)
## Beaten down and spared (spared): left at 1 hp, taken by [param by] (a
## raid group's id), not killed. Whoever keeps it (Main, a companion's
## record) takes it off the map.
signal entity_taken(entity: GridEntity, by: String)
## [param each] fell asleep: nobody is in it now (World.step).
signal zone_slept(each: Zone)
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
signal loosed(by: GridEntity, at: Vector2i, strength: float)
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
## WASD steps queued on the server for one player at most; more are
## dropped (the client never sends more than one ahead).
const MAX_QUEUED_STEPS := 3
## A move order's via tiles (the walk the client shows) kept at most; the
## rest of the way the server plans itself.
const MAX_VIA_STEPS := 64
## How many steps shorter a way found now must be than the rest of a walk
## being shown (or walked from the client's via tiles) to replace it: a
## detour round a passage that has since cleared, not the step or two that
## monsters moving about gain or lose every tick.
const DETOUR_STEPS := 3
## report_move_refused's epoch for a refusal that dropped the order (a
## strike closing in that cannot): the client stops predicting it.
const ORDER_DROPPED := -1
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
## root of the weight, 1 to THROW_MAX cells; a body hit takes force weight x
## THROW_FORCE_PER_KG (impact_damage at the thing's mass over its).
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
const THROW_FORCE_PER_KG := 0.3
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
## with BRACE_FORCE_PER_KG times its own mass: its own charge, turned.
const BRACE_TICKS := 5
## The least status of lore's name forms that names things (decision 365;
## Lore.name_forms): "agreed" in play; tests and clips use "draft".
var name_least := "agreed"
## How a thing kept from its namer is marked where it is shown (decision
## 370; the pack panel tints a slot that says it).
const KEPT_MARK := "ill-starred"
const BRACE_DAMAGE_FACTOR := 2.0
const BRACE_FORCE_PER_KG := 0.03
## Mass multiplier for being pushed while at 0 stamina.
const EXHAUSTED_MASS_FACTOR := 0.5

# Exported vars, not consts: GDScript cannot export constants.
## Impact damage per unit of force left over when a pushed entity is stopped.
@export var impact_per_force := 2
## FORCE_SCALE: force = strength x mover_mass / target_mass x this.
@export var force_scale := 0.1
## MAX_FORCE: upper clamp on that force.
@export var max_force := 4.0
## SHOVE_COST_BASE and SHOVE_COST_SCALE: a shove costs
## base + force x target_mass x scale stamina.
@export var shove_cost_base := 5.0
@export var shove_cost_scale := 0.15
## STAMINA_REGEN: stamina regained on a tick spent resting or walking.
@export var stamina_regen := 2
## A creature that is thrown into a wall or another entity, or is the one run
## into, is stunned for base + round(remaining force x per_force) ticks.
@export var stun_ticks_base := 4
@export var stun_ticks_per_force := 3.0
## A creature knocked back (it moved) is stunned at least this many ticks
## past the end of its slide, wall or no wall: a beat to double over before
## it can act again.
@export var knockback_stun_ticks := 7
## An attack's blow (after ATTACK_FORCE_FACTOR) pushes only from this force
## up; a lighter one only hurts. Shoves, tosses, throws and falls are not
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

## Server: every loaded zone by name, and the one World is working on.
var zones: Dictionary[String, Zone] = {}
## The damaged roofs (decision 383): "<level>/<x>,<y>" (the roof's rect's
## top-left, so an edit to the level's list moves none) -> true. Saved in
## the snapshot; the server's (environment's storms damage, economy's
## repairs mend: damage_roof, repair_roof).
var roofs_damaged: Dictionary[String, bool] = {}
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
## Server: whoever has a buff on (GridEntity.buffs), so only they are
## looked at for fading.
var _buffed: Dictionary[GridEntity, bool] = {}
var _mending: Dictionary[GridEntity, Dictionary] = {}
## The longest a thing's story line runs in its slot's note (story_line).
const STORY_LONGEST := 80
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
	var target: GridEntity
	var source_id := 0
	var source_name := ""
	var target_name := ""
	## Where the target stood relative to the source when the hit was accepted.
	var direction := Vector2i.ZERO
	## Which way the target is pushed. The same as direction unless tossed.
	var push_direction := Vector2i.ZERO
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
	# 1. Act, in ascending id: those that have a turn (a crate has none). The
	# roster is made anew when the entities change, so one despawned
	# mid-tick leaves this one as it was.
	var near := _tier_origins()
	_take_roster()
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
	if near.is_empty() or monster.target != null:
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
	monster.tier = Tier.NEAR if nearest <= NEAR_TILES else Tier.MID if nearest <= MID_TILES else Tier.FAR
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
	from.cover = _cover
	from.cover_rect = _cover_rect
	from.torches = _torches
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
	_cover = to.cover
	_cover_rect = to.cover_rect
	_torches = to.torches
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
			entity._world_remove()
	_entities.clear()
	_roster_changed()
	zone.comings += 1
	_occupancy.clear()
	_hits.clear()
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
	_cover = PackedFloat32Array()
	_cover_rect = Rect2i()
	_next_id = 1
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


## [param terrain] is what Terrain.parse returns.
func load_terrain(terrain: Dictionary) -> void:
	if not Net.is_authority():
		return
	_set_terrain(terrain)


func _set_terrain(terrain: Dictionary) -> void:
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
	_torches.clear()
	for cell: Vector2i in terrain.get("torches", []):
		_torches[cell] = true
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
	entity._world_set_facing(direction)
	entity._world_swung(direction)
	_hit_door(door, amount, entity)
	return true


func _set_door(door: Door, open: bool, by: GridEntity) -> void:
	if door.open == open:
		return
	door.open = open
	if _logs_for(by):
		_log("door: %s %s %s" % [by.name, "opened" if open else "closed", door.name])
	noise(by.tile, Senses.NOISE_DOOR, &"door", by)
	door_changed.emit(door, by)


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
func try_transfer(by: GridEntity, from: GridEntity, from_slot: int, to: GridEntity, to_slot: int) -> bool:
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
	if to is Chest and (to as Chest).temple:
		return _hand_to_priest(by, from, from_slot, to)
	if to is Chest and (to as Chest).depot:
		return _bank(by, from, from_slot, to)
	if to is Chest and (to as Chest).shop:
		return _sell(by, from, from_slot, to)
	var uid := slot_uid(from, from_slot)
	var other_uid := slot_uid(to, to_slot)
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
			return false
		from.slots = taken
		from.slot_items = taken_uids
	else:
		var given := to.slots.duplicate()
		var given_uids := to.slot_items.duplicate()
		given[to_slot] = item
		given_uids[to_slot] = uid
		if not hands_allow(from, taken) or not hands_allow(to, given):
			return false
		from.slots = taken
		from.slot_items = taken_uids
		to.slots = given
		to.slot_items = given_uids
		_moved_item(uid, from, to)
		if to is Resident and by is Player and from != to:
			handed.emit(by, to, item, uid)  # A gift to one of the town's people (decision 443).
		if other_uid != 0:
			_moved_item(other_uid, to, from)
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
	var uid := slot_uid(from, slot)
	var taken := from.slots.duplicate()
	var taken_uids := from.slot_items.duplicate()
	_log("slots: %s took %s out of %s %d" % [by.name, taken[slot], from.name, slot])
	taken[slot] = ""
	taken_uids[slot] = 0
	from.slots = taken
	from.slot_items = taken_uids
	items.place(uid, "")
	_slots_changed(from)
	return uid


## [param by] puts the instance [param uid] (from the stockpile...) into
## [param to]'s empty slot [param slot]. False, and nothing moves, if it
## cannot (try_transfer's rules; an unknown uid; a full slot).
func put_item(by: GridEntity, to: GridEntity, slot: int, uid: int) -> bool:
	if not Net.is_authority() or not _can_handle(by) or not reaches(by, to):
		return false
	var id := items.id_of(uid)
	if id.is_empty() or not Items.exists(id) or slot < 0 or slot >= to.slots.size() or not to.slots[slot].is_empty():
		return false
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
## then empty. Anything else (a chest) has no hands.
func hands_allow(entity: GridEntity, slots: PackedStringArray) -> bool:
	if not has_hands(entity) or slots.size() < Items.CARRIED:
		return true
	var right := slots[Items.RIGHT_HAND]
	var left := slots[Items.LEFT_HAND]
	for held in [right, left]:
		if not held.is_empty() and int(Items.def(held).get("hands", 0)) == 0:
			return false
	if not left.is_empty() and int(Items.def(left)["hands"]) == 2:
		return false
	return right.is_empty() or int(Items.def(right)["hands"]) < 2 or left.is_empty()


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
## free hand for, by its index there; -1 for none.
func _weapon_index(monster: GridEntity, cell: Vector2i) -> int:
	var ids := ground_at(cell)
	for i in ids.size():
		if not Items.verb_of(ids[i]).is_empty() and _free_hand(monster, ids[i]) >= 0:
			return i
	return -1


## The hand [param entity] could hold [param id] in (Items.RIGHT_HAND,
## LEFT_HAND), -1 for none: a two-handed thing only with both hands empty,
## in the right; a monster with no hands yet has both free.
func _free_hand(entity: GridEntity, id: String) -> int:
	var hands := int(Items.def(id).get("hands", 0))
	if hands == 0:
		return -1
	var right := entity.slots[Items.RIGHT_HAND] if entity.slots.size() == Items.CARRIED else ""
	var left := entity.slots[Items.LEFT_HAND] if entity.slots.size() == Items.CARRIED else ""
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


## A player or a companion: something with hands (Items.CARRIED slots).
func has_hands(entity: GridEntity) -> bool:
	return (entity is Player or entity.keeper_peer != 0) and entity.slots.size() == Items.CARRIED


## Whether [param entity] fights with what is in its hands: one with hands
## (has_hands), or a monster given them (its kind's or its entry's
## "wields", Level; decision 338). Only for fighting: a monster's hands are
## not a carrier's (nobody hands it things or bandages it).
func holds_in_hands(entity: GridEntity) -> bool:
	return has_hands(entity) or entity is Monster and entity.slots.size() == Items.CARRIED


## The verb [param attacker]'s blow is struck with (decision 338): its
## wielded weapon's (Items.verb_of), but for a bow, which is no club (its
## numbers are the shot's); {} for bare hands.
func blow_verb(attacker: GridEntity) -> Dictionary:
	var verb := Items.verb_of(wielded(attacker))
	return {} if verb.get("kind") == "ranged" else verb


## [param attacker]'s time between blows: its attack_ticks times its
## weapon's speed (blow_verb; a dagger quicker, a giant axe slower).
func attack_ticks_of(attacker: GridEntity) -> int:
	return maxi(1, roundi(attacker.attack_ticks * float(blow_verb(attacker).get("speed", 1.0))))


## Whether [param attacker] stands behind [param target]: on the side
## away from where it faces (as a flanker's backstab reads it).
func is_behind(attacker: GridEntity, target: GridEntity) -> bool:
	return Vector2(attacker.tile - target.tile).dot(Vector2(target.facing)) < 0.0


## [param entity]'s slots changed: its mass follows what it carries (its
## base_mass and the things' weights), a stance whose thing left the hand
## ends, and slots_changed is emitted.
func _slots_changed(entity: GridEntity) -> void:
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
		for id in entity.slots:
			if not id.is_empty():
				carried += Items.weight_of(id)
	entity.mass = entity.base_mass + carried + buff(entity, "mass")


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
			items.place(uid, "")
			uids.append(uid)
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


## Every slot's instance (slot_uid), made where missing: what a save keeps.
func slot_uids(entity: GridEntity) -> PackedInt32Array:
	for slot in entity.slots.size():
		slot_uid(entity, slot)
	return entity.slot_items.duplicate()


## A new [param id] bound for life to [param owner] (a holder_key; decision
## 544), minted for [param entity] (who it is made for, the companion's
## token's bearer or the player) at [param at_zone] [param tile]. Its uid,
## not yet in any slot: put_item places it.
func mint_bound(id: String, owner: String, entity: GridEntity, at_zone := "", tile := Vector2i(-1, -1)) -> int:
	var uid := items.mint(id, "bound", _label_of(entity) if is_instance_valid(entity) else "", at_zone, tile)
	items.bind(uid, owner, at_zone, tile)
	return uid


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
	return "%s/%s" % [entity.zone, entity.name]


## Whether [param entity] is a named holder, who can name what it carries
## (decision 365): a player or a companion. A monster is known by its kind.
func _names_things(entity: GridEntity) -> bool:
	var who := _carrier_of(entity)[0]
	return who.begins_with("player:") or who.begins_with("companion:")


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
			# The tally (decision 415) and the story (decision 421), each on a
			# line of its own under the thing's name, found by its first word.
			for line in [kills_line(entity.slot_items[slot]), story_line(entity.slot_items[slot])]:
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
	if not items.bane_of(uid).is_empty():
		more.append("%s-bane" % items.bane_of(uid))  # Decision 417.
	if not items.grudge_of(uid).is_empty():
		more.append("vengeance on %s" % _plural(str(items.grudge_of(uid)["kind"])))
	if not items.blessed_for(uid).is_empty():
		more.append("blessed")  # Decision 424.
	if not more.is_empty():
		note = "%s, %s" % [note if not note.is_empty() else Items.name_of(items.id_of(uid)), ", ".join(more)]
	return note


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
			elif origin.is_empty() and event["kind"] == "hunted":
				origin = "from %s's hunt" % event["what"] if not str(event["what"]).is_empty() else "from a hunt"
		if not origin.is_empty():
			parts.append(origin)
	if not items.style_of(uid).is_empty():
		parts.append("%s work" % items.style_of(uid))  # Decision 474.
	if items.short_of(uid) < 1.0:
		parts.append("short measure")  # Decision 493.
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
	var taken := from.slots.duplicate()
	var taken_uids := from.slot_items.duplicate()
	taken[from_slot] = ""
	taken_uids[from_slot] = 0
	from.slots = taken
	from.slot_items = taken_uids
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
## [param why]: a coin purse opened ("purse"), a sale... Their gold now; 0
## with no economy (a client). The one way players' gold changes.
func add_gold(player_id: String, amount: int, why := "") -> int:
	if economy == null or player_id.is_empty():
		return 0
	var now_gold := economy.add_gold(player_id, amount, why)
	gold_changed.emit(player_id, now_gold)
	return now_gold


## Player [param player_id]'s gold (0 on a client).
func gold_of(player_id: String) -> int:
	return economy.gold(player_id) if economy != null else 0


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
	var uid := slot_uid(from, from_slot)
	var taken := from.slots.duplicate()
	var taken_uids := from.slot_items.duplicate()
	taken[from_slot] = ""
	taken_uids[from_slot] = 0
	from.slots = taken
	from.slot_items = taken_uids
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
	var deal := economy.sell(who, place, item)
	if not deal["ok"]:
		_log("shop: %s refused %s at %s: %s" % [by.name, item, place, deal["why"]])
		traded.emit(by, shop, str(deal["why"]))
		return false
	var uid := slot_uid(from, from_slot)
	var taken := from.slots.duplicate()
	var taken_uids := from.slot_items.duplicate()
	taken[from_slot] = ""
	taken_uids[from_slot] = 0
	from.slots = taken
	from.slot_items = taken_uids
	if Items.yield_of(item).is_empty():
		items.place(uid, "")
		items.note(uid, "sold", "to %s by %s for %d gold" % [place, who, deal["paid"]])
		stockpile.stock_shop(place, uid, "sold:%s" % who)
	else:
		_bank_thing(place, uid, "sold:%s" % who, _label_of(from), shop.zone, shop.tile)
	_log("shop: %s sold %s at %s for %d gold" % [by.name, item, place, deal["paid"]])
	_slots_changed(from)
	gold_changed.emit(who, economy.gold(who))
	traded.emit(by, shop, "")
	return true


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
	var deal := economy.buy(who, place, uid)
	if not deal["ok"]:
		traded.emit(by, shop, str(deal["why"]))
		return false
	put_item(by, by, slot, uid)
	_log("shop: %s bought %s at %s for %d gold" % [by.name, id, place, deal["price"]])
	gold_changed.emit(who, economy.gold(who))
	traded.emit(by, shop, "")
	return true


## Who last put each thing on the ground (a drop or a throw), by uid, for
## the stockpile's ledger; gone when it is taken off again.
var _put_down_by: Dictionary[int, String] = {}


func _ready() -> void:
	key_check = holds_key
	ground_changed.connect(_on_ground_for_stockpile)
	entity_moved.connect(_on_moved_for_stockpile)
	entity_pushed.connect(_on_pushed_for_stockpile)
	entity_despawned.connect(func(entity: GridEntity) -> void: _pushed_by.erase(entity))


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
## own cell if null; one it reaches). A full cell (GROUND_PER_CELL) spills
## to the nearest with room. False, and nothing moves, if it cannot.
func try_drop(by: GridEntity, slot: int, at: Variant = null) -> bool:
	if not Net.is_authority() or not _can_handle(by):
		return false
	var cell: Vector2i = by.tile if at == null else at
	if not reaches_cell(by, cell) or slot < 0 or slot >= by.slots.size() or by.slots[slot].is_empty():
		return false
	if _ground_room(cell) == NO_CELL:
		return false
	var id := by.slots[slot]
	var uid := take_item(by, by, slot)
	if uid == 0:
		return false
	_put_down_by[uid] = _label_of(by)
	var landed := put_on_ground(uid, cell)
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
		index = there.size() - 1
	if index >= there.size():
		return false
	var uid := there[index]
	if _swap_bundle(by, cell, index):
		return true
	var slot := free_slot_for(by, items.id_of(uid))
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
	for slot in mini(entity.slots.size(), Items.PACK if has_hands(entity) else entity.slots.size()):
		if entity.slots[slot].is_empty():
			return slot
	return -1


## Puts the instance [param uid] on [param cell], or the nearest cell with
## room (on the floor, dry, fewer than GROUND_PER_CELL there) within
## GROUND_SPILL: where it went, NO_CELL if nowhere (it stays where it was).
## For whatever lays things down: a drop, a throw, later loot.
func put_on_ground(uid: int, cell: Vector2i, thrown_from := NO_CELL) -> Vector2i:
	var landed := _ground_room(cell)
	if landed == NO_CELL or not items.has(uid):
		return NO_CELL
	var there: PackedInt32Array = zone.ground.get(landed, PackedInt32Array()).duplicate()
	there.append(uid)
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


## [param by] throws what is in one of its hands ([param slot]) toward
## [param target]: it flies a cell at a time (a step toward the target
## each, so diagonals first) as far as throw_reach, over water and
## ledges, until a wall or a closed door stops it or it hits a body; the
## body takes an impact from its weight (impact_damage, through _impact,
## as a push's collision does) and is stunned. It lands on the last cell
## it reached (off water). False, and nothing moves, if it cannot.
func try_throw(by: GridEntity, slot: int, target: Vector2i) -> bool:
	if not Net.is_authority() or not _can_handle(by) or is_stunned(by):
		return false
	if not has_hands(by) or slot not in [Items.RIGHT_HAND, Items.LEFT_HAND] or by.slots[slot].is_empty() or target == by.tile:
		return false
	var id := by.slots[slot]
	var reach := throw_reach(by, id)
	var cell := by.tile
	var dry := by.tile
	var hit: GridEntity = null
	for i in reach:
		if cell == target:
			break
		var step := Vector2i(signi(target.x - cell.x), signi(target.y - cell.y))
		if _terrain_blocks_step(cell, step, false, false) and not is_water(cell + step):
			break
		if edge_blocks(cell, step):
			break
		var body: GridEntity = _occupancy.get(cell + step)
		if body != null and body != by:
			hit = body
			break
		cell += step
		if not is_water(cell):
			dry = cell
	var uid := take_item(by, by, slot)
	if uid == 0:
		return false
	_put_down_by[uid] = _label_of(by)
	var landed := put_on_ground(uid, dry, by.tile)
	_thud(landed, id, by)
	_log("throw: %s threw %s from %s to %s%s" % [by.name, id, by.tile, landed, "" if hit == null else ", hitting %s" % hit.name])
	if hit != null:
		var force := Items.weight_of(id) * THROW_FORCE_PER_KG
		var impact := impact_damage(force, mass_ratio(Items.weight_of(id), pushed_mass(hit)))
		items.note(uid, "thrown", "at %s by %s" % [_label_of(hit), _label_of(by)], zone.name, hit.tile)
		_stun(hit, force)
		if impact > 0:
			_impact(hit, impact, by, &"body")
	return true


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
	if not Net.is_authority() or not _alive(entity) or ticks <= 0 or amount <= 0:
		return
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
## reads it. False if it holds nothing for it.
func try_stance(by: GridEntity, kind: String) -> bool:
	if not Net.is_authority() or not is_instance_valid(by):
		return false
	if kind.is_empty():
		by.raised = ""
		return true
	if kind != off_hand(by) or kind == "draw" and not quiver_check.call(by):
		return false
	if kind == "block" and tick < by.guard_broken_until or is_stunned(by):
		return false  # A broken guard comes back up only after a while; nothing is raised reeling or lying.
	if by.raised != kind:
		by.raised = kind
		by.raised_tick = tick
	return true


## How far [param entity]'s bow is drawn, 0 to 1: nothing until its verb's
## draw_min ticks, full at draw_full; 0 when not drawing.
func draw_of(entity: GridEntity) -> float:
	if not is_instance_valid(entity) or entity.raised != "draw":
		return 0.0
	var verb := Items.verb_of(drawn_with(entity))
	if verb.is_empty():
		return 0.0
	var drawn := tick - entity.raised_tick
	# A quick bow (decision 365) draws in less time.
	var quick := float(Items.strength_value(slot_strength(entity, drawn_slot(entity)), "draw", 1.0))
	if drawn < roundi(int(verb["draw_min"]) * quick):
		return 0.0
	return clampf(float(drawn) / maxf(1.0, float(verb["draw_full"]) * quick), 0.0, 1.0)


## [param by] lets its drawn bow go at [param at] (the right button
## released): loosed is emitted with the draw (draw_of), and it shoots
## (shoot); drawn too little, nothing. The stance ends either way.
func try_loose(by: GridEntity, at: Vector2i) -> bool:
	if not Net.is_authority() or not is_instance_valid(by) or by.raised != "draw":
		return false
	var strength := draw_of(by)
	by.raised = ""
	if strength <= 0.0:
		return false
	_log("loose: %s at %s, drawn %.2f" % [by.name, at, strength])
	loosed.emit(by, at, strength)
	shoot(by, at, strength)
	return true


## [param by]'s shot toward [param at], its bow drawn [param strength] (0
## to 1; decision 335). Along the line from its cell through
## [param at] and on (shot_line), as far as its bow's cells, it hits the
## first body there; a wall, a closed door, higher ground or the map's end
## stops it first. A body it may not attack (can_target) or a friend it spares (spares) stops it unharmed.
## Damage is its blow (attack_damage) times the bow's damage times the
## draw, at least 1, cause &"shot"; no push. It faces the shot, is heard
## NOISE_BOW about it, and the views draw the arrow's flight
## (GridEntity.shot). The body struck, or null.
func shoot(by: GridEntity, at: Vector2i, strength: float) -> GridEntity:
	if not Net.is_authority() or not is_instance_valid(by) or at == by.tile or strength <= 0.0:
		return null
	var aim := shot_aim(by, at)
	if aim.is_empty():
		return null
	var verb := Items.verb_of(drawn_with(by))
	var hit: GridEntity = aim["hit"]
	var end: Vector2i = aim["end"]
	by._world_set_facing(Vector2i(signi(at.x - by.tile.x), signi(at.y - by.tile.y)))
	by._world_shot(end)
	noise(by.tile, NOISE_BOW, &"bow", by)
	if hit == null or not can_target(by, hit) or spares(by, hit) or not hit.is_breakable():
		_log("shot: %s at %s, drawn %.2f, %s" % [by.name, end, strength, "nothing hit" if hit == null else "stopped by %s" % hit.name])
		return null
	var amount := maxi(1, roundi(by.attack_damage * float(verb["damage"]) * strength))
	var met: Variant = _meet_guard(hit, by, amount, 0.0, true)
	if met != null:
		amount = met[0]
	_log("shot: %s hits %s at %s for %d, drawn %.2f" % [by.name, hit.name, hit.tile, amount, strength])
	if amount > 0:
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
	elif target.raised.is_empty() and tick >= target.next_attack_tick:
		held = target.slots[Items.RIGHT_HAND]
	var verb := Items.verb_of(held) if not held.is_empty() else {}
	if verb.get("kind") != "block" or target.facing == Vector2i.ZERO:
		return {}
	var off := absf(Vector2(source.tile - target.tile).angle_to(Vector2(target.facing)))
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
	if verb.is_empty():
		return null
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


## Where [param by]'s shot toward [param at] would go with the bow in its
## hands: {end: the last cell it crosses (its own if none), hit: the first
## body on the way, or null}; {} with no bow. The server's shoot and the
## client's aim while drawing (Main) read the same line.
func shot_aim(by: GridEntity, at: Vector2i) -> Dictionary:
	var verb := Items.verb_of(drawn_with(by))
	if verb.is_empty() or at == by.tile:
		return {}
	var hit: GridEntity = null
	var end := by.tile
	for cell in shot_line(by.tile, at, int(verb["cells"])):
		end = cell
		var body: GridEntity = _occupancy.get(cell)
		if body != null and body != by:
			hit = body
			break
	return {"end": end, "hit": hit}


## The cells a shot from [param from] toward [param toward] crosses, in
## order, at most [param cells] away: a Bresenham line through
## [param toward] and on. It ends before a wall edge or a closed door
## (crossed as sight is: _sight_crosses_edge), a cell higher than the
## shooter's, or one with no ground and no water (the map's end).
func shot_line(from: Vector2i, toward: Vector2i, cells: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := toward - from
	var longest := maxi(absi(d.x), absi(d.y))
	if longest == 0 or cells <= 0:
		return out
	var to := from + d * maxi(1, ceili(float(cells) / longest))
	var top := height_at(from)
	# Over relief (decision 525) the arrow flies from the eye toward the
	# aim over [param toward], and ground above that line stops it.
	var eye := elevation_at(from) + Relief.EYE_M
	var drop_per_cell := (eye - elevation_at(toward) - Relief.AIM_M) / Vector2(from).distance_to(Vector2(toward))
	var span: Vector2i = (to - from).abs()
	var s := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var err: int = span.x - span.y
	var at: Vector2i = from
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
			break
		at += step
		var above := elevation_at(at) > eye - drop_per_cell * Vector2(from).distance_to(Vector2(at)) if _relief_given \
				else height_at(at) > top
		if distance(from, at) > cells or above or not (is_walkable(at) or is_water(at)):
			break
		out.append(at)
	return out

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
## use: a bandaging kit ("bandage") bandages [param by] (try_bandage); a
## coin purse ("purse", a player's) is opened into their gold, its yield's
## gold (add_gold), and is gone. A thing with effects (food, a draught, a
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
		"purse":
			var player_id: Variant = by.get("player_id")
			var gold := int(Items.def(id)["yield"].get("gold", 0))
			if player_id is not String or str(player_id).is_empty() or gold <= 0:
				return false
			var uid := take_item(by, by, slot)
			if uid == 0:
				return false
			items.end(uid, "opened", "by %s" % _label_of(by), zone.name, by.tile)
			add_gold(player_id, gold, "purse")
			_log("use: %s opened %s: %d gold" % [by.name, id, gold])
			return true
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
	for entity: GridEntity in _buffed.keys():
		if not is_instance_valid(entity):
			_buffed.erase(entity)
			continue
		if entity.zone != zone.name:
			continue
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


## How many cells [param by] can throw [param id]: its strength over the
## thing's weight (square root: a sack goes a cell or two, a kit across a
## room), 1 to THROW_MAX.
func throw_reach(by: GridEntity, id: String) -> int:
	return clampi(floori(THROW_PER_STRENGTH * by.strength / sqrt(maxf(Items.weight_of(id), 0.5))), 1, THROW_MAX)


## [param cell] if it has room for one more thing, else the nearest that
## does, within GROUND_SPILL (dry floor); NO_CELL if none.
func _ground_room(cell: Vector2i) -> Vector2i:
	for radius in GROUND_SPILL + 1:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var each := cell + Vector2i(dx, dy)
				if is_walkable(each) and not is_water(each) and zone.ground.get(each, PackedInt32Array()).size() < GROUND_PER_CELL:
					return each
	return NO_CELL


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
	if patient != by and (patient.zone != by.zone or not can_melee(by.tile, patient.tile)):
		return false
	if patient.hp >= patient.max_hp or patient.mending != 0 or by.mending == 1 or _bandaging.has(by):
		return false
	if bandage_kit(by) < 0 or not calm(by) or not calm(patient):
		return false
	_bandaging[by] = {"patient": patient, "until": tick + BANDAGE_TICKS, "from": tick, "tile": by.tile,
		"exerted": by.last_exertion_tick()}
	patient.mending = 1
	cure(patient, "bleed")  # A bandage stops bleeding at once (decision 375).
	_log("bandage: %s starts on %s" % [by.name, patient.name])
	bandage_changed.emit(by, patient, &"started")
	return true


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
					or patient != by and not can_melee(by.tile, patient.tile) or not calm(by) or not calm(patient)
		if broken:
			_bandaging.erase(by)
			if _alive(patient):
				patient.mending = 0
			_log("bandage: %s's bandaging of %s broken off" % [by.name, patient.name])
			bandage_changed.emit(by, patient, &"interrupted")
		elif tick >= int(job["until"]):
			_bandaging.erase(by)
			patient.mending = 2
			_mending[patient] = {"left": BANDAGE_HEAL, "next": tick + BANDAGE_REGEN_TICKS, "from": tick}
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


func spawn(entity: GridEntity, at: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if entity.spawned or not is_free(at):
		push_warning("World.spawn: cannot place %s at %s" % [entity.name, at])
		return false
	_occupancy[at] = entity
	_entities.append(entity)
	_roster_changed()
	if entity is Cargo or entity is Monster and not entity.slots.is_empty():
		_weigh(entity)  # What its spawn spec put in it (loot, its hands) weighs from the start.
	zone.comings += 1
	entity.zone = zone.name
	entity._world_place(_next_id, at)
	_next_id += 1
	return true


func despawn(entity: GridEntity) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	_let_go_things(entity)
	_occupancy.erase(entity.tile)
	_entities.erase(entity)
	_roster_changed()
	zone.comings += 1
	entity._world_remove()
	entity_despawned.emit(entity)
	entity.queue_free()


## Spawn grace: for [param ticks], or until it moves or attacks, monsters do
## not target [param entity].
func protect(entity: GridEntity, ticks: int) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	entity.protected = true
	entity.protected_until_tick = tick + ticks


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
	if _meets_brace(entity, entity.tile + direction, direction):
		return false
	var duration := step_ticks(entity, direction)
	# A walk in progress keeps its own clock: a step due at 12.5 and taken
	# on tick 13 starts at 12.5, so the next is due at 15, not 15.5.
	var start := float(tick)
	if tick - entity.next_move_tick < 1.0:
		start = entity.next_move_tick
	if not _shift(entity, entity, direction, entity.mass, duration, start):
		var ahead: GridEntity = _occupancy.get(entity.tile + direction)
		if ahead != null and ahead.is_creature() \
				and not _terrain_blocks_step(entity.tile, direction, true):
			entity_bumped.emit(entity, ahead, direction)
		elif not is_walkable(entity.tile + direction):
			walked_off.emit(entity, direction)
		return false
	entity.next_move_tick = start + duration
	entity.last_step_tick = tick  # (A braced spear stands still: braced.)
	_trample(entity, entity.tile - direction)
	if entity.raised == "draw":
		entity.raised_tick = tick  # A step spoils the draw: it starts again.
	entity._world_set_facing(direction)
	entity.protected = false  # Moving ends spawn grace.
	if entity is Player or entity is Companion:
		noise(entity.tile, Senses.step_radius(entity), &"step", entity)
	return true


## A swing at nothing: the attack's cooldown, facing and lunge, with no
## target. Refused like an attack while cooling down, mid-step or stunned.
func try_swing(entity: GridEntity, direction: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if not entity.spawned or direction not in DIRECTIONS or is_stunned(entity):
		return false
	if tick < entity.next_attack_tick or tick < entity.next_move_tick:
		return false
	entity.next_attack_tick = tick + attack_ticks_of(entity)
	entity._world_set_facing(direction)
	entity.protected = false
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
## (decision 392: its verb's windup; the giant axe's 8); 0, it strikes at once.
func windup_ticks(entity: GridEntity) -> int:
	return int(blow_verb(entity).get("windup", 0)) if is_instance_valid(entity) else 0


## The blow [param entity] is winding up (try_wind_up): {target, lands,
## direction, from}; {} for none.
func winding(entity: GridEntity) -> Dictionary:
	return entity.wind_up if is_instance_valid(entity) else {}


## [param by] winds up its heavy weapon's blow at [param target] (decision
## 392; the player's attack with such a weapon, Player._pursue_action, and
## any monster's AI): windup_ticks from now it is struck (_tend_wind_ups),
## breaking any guard it meets at full weight, if the target is still in
## reach; else it whiffs. Until then a move order or a step (order_move,
## order_step), a stun, a knockdown or being moved off its cell gives it up
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
	var direction := (target.tile - by.tile).clamp(Vector2i(-1, -1), Vector2i(1, 1))
	by.wind_up = {"target": target, "lands": tick + ticks, "direction": direction, "from": by.tile}
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
		if entity.tile != entity.wind_up["from"] or is_stunned(entity) or is_down(entity):
			cancel_wind_up(entity)
			continue
		if tick < int(entity.wind_up["lands"]):
			continue
		# Untyped till checked: a target freed since cannot be a GridEntity.
		var aimed: Variant = entity.wind_up["target"]
		var direction: Vector2i = entity.wind_up["direction"]
		entity.wind_up = {}
		_winders.erase(entity)
		var first := _hits.size()
		if is_instance_valid(aimed) and (aimed as GridEntity).spawned and in_reach(entity, aimed as GridEntity) \
				and _try_hit(entity, aimed as GridEntity, entity.attack_damage, false):
			for i in range(first, _hits.size()):
				_hits[i].crushing = true
			_log("windup: %s strikes %s" % [entity.name, (aimed as GridEntity).name])
		else:
			try_swing(entity, direction)
			_log("windup: %s strikes the air" % entity.name)


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
	if verb.is_empty() or is_stunned(entity) or tick < entity.next_bash_tick:
		return false
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
	if not can_melee(by.tile, target.tile) or tick < by.next_move_tick:
		return false
	var verb := bash_verb(by)
	var aim := target.tile - by.tile
	var force := push_force(by, target) * ATTACK_FORCE_FACTOR * float(verb["bash_force"])
	var raw_force := force
	if force < knockback_min_force:
		force = 0.0  # Too light to move it: the stagger alone.
	if by.max_stamina > 0:
		by.stamina -= int(verb["bash_stamina"])
	by.next_bash_tick = tick + int(verb["bash_ticks"])
	by.bash_moment_until = tick + int(verb["bash_stagger"])
	by._world_set_facing(aim)
	by._world_swung(aim)
	entity_swung.emit(by, aim)
	by._world_note_exertion(tick)
	by.protected = false
	noise(by.tile, Senses.NOISE_FIGHT, &"fight", by)
	_queue_hit(by, target, aim, aim.clamp(Vector2i(-1, -1), Vector2i(1, 1)), 0, force, raw_force, true, 0)
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
	var lost := mini(amount, target.hp)
	target.hp -= lost
	target.hurt_tick = tick
	if cause != &"fire":
		var loud := float(Senses.NOISE_FIGHT)
		if cause == &"attack" and is_instance_valid(source):
			loud *= float(Items.strength_value(slot_strength(source, Items.RIGHT_HAND), "noise", 1.0))  # A quiet blade's.
		noise(target.tile, roundi(loud), &"fight", source)
	target._world_damaged(amount, cause)
	entity_damaged.emit(target, amount, source, cause)
	if is_instance_valid(source):
		_take_grudges(target, source, lost)  # Decisions 417, 473.
	if target.hp == 0 and spared.is_valid():
		var by := str(spared.call(target, source, cause))
		if by != "":
			target.hp = 1
			entity_taken.emit(target, by)
			return
	if target.hp == 0:
		if not target.is_creature():
			noise(target.tile, Senses.NOISE_BREAK, &"break", source)  # A crate or a barrel smashed.
		entity_died.emit(target, cause)
		var spilt: Array[int] = []
		if target is Cargo:
			spilt = empty_container(target)
		elif target is Monster:
			spilt = empty_container(target)  # What it carried (loot, decision 330).
			spilt.append_array((target as Monster).remains())  # An animal's meat and hide (decision 318).
		var at := target.tile
		despawn(target)
		for uid in spilt:
			put_on_ground(uid, at)


## Player intent: walk to [param target], by way of [param via] first
## (the steps the ordering client is already showing). Server only; input
## code on any peer goes through command_move().
func order_move(entity: GridEntity, target: Vector2i, via: Array[Vector2i] = []) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	cancel_wind_up(entity)  # A move order gives a wind-up up (decision 392).
	entity.move_order = target
	entity.has_move_order = true
	entity.move_via = via.slice(0, MAX_VIA_STEPS)
	if entity is Player:
		(entity as Player).queued_steps.clear()
	entity.action_order = GridEntity.Order.NONE
	entity.action_target = null


## Player intent (WASD): one step in [param direction], taken when the
## movement timer allows, after any already queued. [param epoch] is the
## client's count of refusals seen: a step sent before the client heard of
## the latest refusal is stale and dropped (see Player.step_epoch). A
## [param predicted] step is one the client is showing; only those are
## reported back when refused.
func order_step(entity: GridEntity, direction: Vector2i, epoch: int, predicted: bool) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or direction not in DIRECTIONS or not entity is Player:
		return
	var player := entity as Player
	if epoch != player.refusals or player.queued_steps.size() >= MAX_QUEUED_STEPS:
		return
	cancel_wind_up(player)  # A step gives a wind-up up (decision 392).
	player.has_move_order = false
	player.move_via.clear()
	player.action_order = GridEntity.Order.NONE
	player.action_target = null
	player.queued_steps.append({"direction": direction, "predicted": predicted})


## Player intent: swing toward [param direction] at the next free tick (an
## attack with nothing there).
func order_swing(entity: GridEntity, direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or direction not in DIRECTIONS:
		return
	entity.action_order = GridEntity.Order.SWING
	entity.action_target = null
	entity.action_direction = direction
	entity.has_move_order = false


## Player intent: attack [param target] on the entity's next free tick.
func order_attack(entity: GridEntity, target: GridEntity, via: Array[Vector2i] = []) -> void:
	if not Net.is_authority():
		return
	_order_action(entity, GridEntity.Order.ATTACK, target, Vector2i.ZERO, via)


## Player intent: shove [param target] on the entity's next free tick.
## With a [param direction] it is a toss: the target goes that way instead of
## straight away from the entity.
func order_shove(entity: GridEntity, target: GridEntity, direction := Vector2i.ZERO,
		via: Array[Vector2i] = []) -> void:
	if not Net.is_authority():
		return
	if direction != Vector2i.ZERO and direction not in DIRECTIONS:
		return
	_order_action(entity, GridEntity.Order.SHOVE, target, direction, via)


## [param via]: the steps the client was already showing when it sent the
## order (a walk under way); they are walked first, as for a move order
## (Player._sim_tick), or the client would be pulled back off a step it
## showed while the server struck from where it stood.
func _order_action(entity: GridEntity, order: GridEntity.Order, target: GridEntity,
		direction: Vector2i, via: Array[Vector2i] = []) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or not target.spawned or entity == target:
		return
	if not can_target(entity, target):
		return
	entity.action_order = order
	entity.action_target = target
	entity.action_direction = direction
	entity.has_move_order = false
	entity.move_via = via.slice(0, MAX_QUEUED_STEPS)


# --- Input from any peer ------------------------------------------------------
# Input code calls command_*. On the server that is the gated order_* directly;
# on a client it is an RPC to the server, which checks that the sender owns the
# entity before calling the same order_*. Clients never call try_*.

func command_move(entity: GridEntity, target: Vector2i) -> void:
	if Net.is_authority():
		order_move(entity, target)
	else:
		# Shown at once on this client; the server still decides what happens.
		# The steps already on screen go with it: the server walks those first
		# (see Player.move_via), or a new order arriving before the server
		# has taken a step the client shows would set off from the tile
		# before it and go another way.
		var via := entity.predict_move(target)
		_to_server(&"request_move", [entity.get_path(), target, via])


## Client: the walk its prediction re-planned after a correction, sent
## again as the order, so the server goes that way too and not round the
## monsters a way of its own (see MovePrediction.order).
func resend_move(entity: GridEntity, target: Vector2i, via: Array[Vector2i]) -> void:
	if not Net.is_authority():
		_to_server(&"request_move", [entity.get_path(), target, via])


func command_attack(entity: GridEntity, target: GridEntity) -> void:
	if Net.is_authority():
		order_attack(entity, target)
	else:
		var via := entity.predict_approach(target.tile, target)
		_note_strike_sent(entity)
		_to_server(&"request_attack", [entity.get_path(), target.get_path(), via])


func command_shove(entity: GridEntity, target: GridEntity, direction := Vector2i.ZERO) -> void:
	if Net.is_authority():
		order_shove(entity, target, direction)
	else:
		var via := entity.predict_approach(target.tile, target)
		_predict_shove(entity, target, direction)
		_note_strike_sent(entity)
		_to_server(&"request_shove", [entity.get_path(), target.get_path(), direction, via])


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
	if not can_melee(entity.tile, target.tile) or entity.predicting() \
			or now - entity._walk_shown_at < Net.rtt_ticks() + 1.0 \
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
	var later := float(entity.attack_ticks) + Net.rtt_ticks() + (entity.move_ticks if entity.predicting() else 0.0)
	entity._guessed_ready_tick = maxi(entity._guessed_ready_tick, tick + ceili(later))


## Where a plain shove by [param mover] leaves [param body], pushed
## [param direction], by the same reckoning as _push for the first body
## (force, stamina, mass, terrain, whoever is in the way), changing
## nothing. A client's guess: the server's _push is what happens.
func predict_push_end(mover: GridEntity, body: GridEntity, direction: Vector2i) -> Vector2i:
	var body_mass := pushed_mass(body)
	if body_mass > mover.mass:
		return body.tile
	var force := push_force(mover, body)
	var cost := shove_cost(force, body)
	if mover.max_stamina > 0 and cost > 0 and mover.stamina < cost:
		force *= float(mover.stamina) / cost
	var max_tiles: int = floori(force * mass_ratio(mover.mass, body_mass) + 0.001)
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


## WASD: one step in [param direction]. On a client it is predicted when
## nothing in the replicated world refuses it, and sent either way, so a
## step into someone who will not move still reaches the server (a bump).
func command_step(entity: GridEntity, direction: Vector2i) -> void:
	if Net.is_authority():
		order_step(entity, direction, (entity as Player).refusals, false)
	else:
		var predicted := entity.predict_step(direction)
		_to_server(&"request_step", [entity.get_path(), direction, entity.step_epoch(), predicted])


## Sends [param method] to the server, after Net.test_lag seconds when that
## test hook is set (to stand in for a long way to the server).
func _to_server(method: StringName, args: Array) -> void:
	if Net.test_lag > 0.0:
		await get_tree().create_timer(Net.test_lag).timeout
	callv("rpc_id", [1, method] + args)


@rpc("any_peer", "call_remote", "reliable")
func request_move(entity_path: NodePath, target: Vector2i, via: Array) -> void:
	if not Net.is_authority():
		return
	Net.test_note_order(multiplayer.get_remote_sender_id(), tick)
	var entity := _entity_owned_by_sender(entity_path)
	if entity == null:
		return
	var tiles: Array[Vector2i] = []
	for at: Variant in via:
		if at is Vector2i:
			tiles.append(at)
	var was := enter_named(entity.zone)
	order_move(entity, target, tiles)
	enter(was)


@rpc("any_peer", "call_remote", "reliable")
func request_step(entity_path: NodePath, direction: Vector2i, epoch: int, predicted: bool) -> void:
	if not Net.is_authority():
		return
	Net.test_note_order(multiplayer.get_remote_sender_id(), tick)
	var entity := _entity_owned_by_sender(entity_path)
	if entity != null:
		var was := enter_named(entity.zone)
		order_step(entity, direction, epoch, predicted)
		enter(was)


@rpc("any_peer", "call_remote", "reliable")
func request_attack(entity_path: NodePath, target_path: NodePath, via: Array) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	var target := _entity_at_path(target_path)
	if entity != null and target != null and target.zone == entity.zone:
		var was := enter_named(entity.zone)
		order_attack(entity, target, _tiles(via))
		enter(was)


@rpc("any_peer", "call_remote", "reliable")
func request_shove(entity_path: NodePath, target_path: NodePath, direction: Vector2i, via: Array) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	var target := _entity_at_path(target_path)
	if entity != null and target != null and target.zone == entity.zone:
		var was := enter_named(entity.zone)
		order_shove(entity, target, direction, _tiles(via))
		enter(was)


## The tiles of an order's via list as sent (anything else in it dropped).
static func _tiles(via: Array) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for at: Variant in via:
		if at is Vector2i:
			tiles.append(at)
	return tiles


## Server: a player's step into [param tile] was refused this tick (someone
## else got there first). Its client re-plans at once instead of waiting
## for a position that is not going to change. [param epoch] is the
## player's refusal count after this one (see order_step).
func report_move_refused(entity: GridEntity, tile: Vector2i, epoch := 0) -> void:
	if not Net.is_authority():
		return
	if entity.owner_peer != 0 and entity.owner_peer != Net.local_id \
			and entity.owner_peer in Net.sendable_peers():
		move_refused.rpc_id(entity.owner_peer, entity.get_path(), tile, epoch)


@rpc("authority", "call_remote", "reliable")
func move_refused(entity_path: NodePath, tile: Vector2i, epoch: int) -> void:
	var entity := get_node_or_null(entity_path) as GridEntity
	if entity != null:
		entity._on_move_refused(tile, epoch)


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
		_occupancy[entity.tile] = entity


func _try_hit(attacker: GridEntity, target: GridEntity, hit_damage: int, is_shove: bool,
		push_direction := Vector2i.ZERO) -> bool:
	if not Net.is_authority():
		return false
	if not attacker.spawned or not target.spawned or attacker == target:
		return false
	if not can_target(attacker, target) or is_stunned(attacker):
		return false
	if tick < attacker.next_attack_tick or not in_reach(attacker, target, is_shove):
		return false
	# No hitting mid-step: the attacker's tile changes when a step starts, but
	# on screen it is still crossing over, so the blow would land from afar.
	if tick < attacker.next_move_tick:
		return false
	var aim: Vector2i = target.tile - attacker.tile
	if push_direction == Vector2i.ZERO:
		push_direction = aim.clamp(Vector2i(-1, -1), Vector2i(1, 1))  # A spear's reach: pushed one cell's way.
	elif push_direction not in DIRECTIONS:
		return false
	elif push_direction == -aim and not _can_land_behind(attacker, push_direction):
		# Overhead toss with nowhere to come down: refused, costs nothing.
		return false
	# The weapon in the blow (decision 338): its speed, and below its
	# damage (twice from behind with a dagger) and its force.
	var verb := {} if is_shove else blow_verb(attacker)
	attacker.next_attack_tick = tick + attack_ticks_of(attacker) if not is_shove else tick + attacker.attack_ticks
	attacker._world_set_facing(target.tile - attacker.tile)
	if not is_shove:
		attacker._world_swung(aim)
		entity_swung.emit(attacker, aim)
	attacker._world_note_exertion(tick)
	attacker.protected = false  # So does attacking or shoving.
	var force := push_force(attacker, target)
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
	var raw_force := force
	if not is_shove:
		force *= ATTACK_FORCE_FACTOR * float(verb.get("force", 1.0))
		raw_force = force
		if force < knockback_min_force:
			force = 0.0  # A blow too light to knock back: damage only.
		if hit_damage > 0 and not verb.is_empty():
			var scale := float(verb["damage"])
			if verb.get("kind") == "backstab" and is_behind(attacker, target):
				scale *= float(verb["behind"])
			hit_damage = maxi(1, roundi(hit_damage * scale))
	var down := int(verb["down_ticks"]) if verb.get("kind") == "knockdown" else 0
	if down > 0:
		down += int(Items.strength_value(slot_strength(attacker, Items.RIGHT_HAND), "down_ticks", 0))  # A heavy axe's.
	var deed := ""
	if not is_shove:
		deed = "downed" if down > 0 else "behind" if verb.get("kind") == "backstab" and is_behind(attacker, target) else "struck"
	_queue_hit(attacker, target, aim, push_direction, hit_damage, force, raw_force, is_shove, down)
	_hits[-1].deed = deed
	if down > 0 and aim in DIRECTIONS:
		# A giant axe's arc (decision 343): the cells either side of the
		# one struck, a step of 45 degrees each, take the same blow.
		for turn in range(1, int(verb["arc"]) + 1):
			for side in [-1, 1]:
				var way := Vector2(aim).rotated(side * turn * PI / 4.0)
				var cell := attacker.tile + Vector2i(clampi(roundi(way.x), -1, 1), clampi(roundi(way.y), -1, 1))
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
		if hit.damage > 0:
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
		if hit.force > 0.0 and _alive(hit.target):
			_push(hit.source, hit.target, hit.push_direction, hit.force, hit.push_direction != hit.direction)


## Force push. The mover's mass is a budget: each body set in motion spends its
## own mass from it, and a body heavier than what is left does not move. A body
## travels up to floor(force * ratio) tiles; whatever force is left when
## something stops it becomes impact. Nothing here knows what kind of entity
## it is pushing.
## [param toss]: the first body was tossed (aimed another way than straight
## on), for the views; what it knocks on is pushed.
func _push(mover: GridEntity, first: GridEntity, direction: Vector2i, force: float, toss := false) -> void:
	var mover_mass: float = mover.mass
	var budget: float = mover_mass
	var body: GridEntity = first
	var f: float = force
	while body != null and f > 0.0:
		# An exhausted body counts as half its mass for everything below.
		var body_mass := pushed_mass(body)
		if body_mass > budget:
			if _logs_for(mover):
				_log("push: %s -> %s blocked: too heavy (mass %s, %s left)" % [
					mover.name, body.name, body_mass, budget])
			return
		budget -= body_mass

		var ratio := mass_ratio(mover_mass, body_mass)
		# Less than a tile's worth of force moves nothing and hurts nothing.
		var max_tiles: int = floori(f * ratio + 0.001)
		var start: Vector2i = body.tile
		var tiles := 0
		var stopped := false
		var collided := false
		var stopped_by := "nothing (force spent)"
		var blocker: GridEntity = null
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
				if is_burning(landing) and body.is_creature():
					stopped = true
					stopped_by = "fire"
					max_tiles = 0
		var door_hit: Door = null
		var fall := 0
		while tiles < max_tiles:
			var next: Vector2i = body.tile + direction
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

		# Force spent on travel, rounded up; the rest is what hits.
		var remaining := 0.0
		if stopped and fall == 0:
			remaining = maxf(f - ceili(tiles / ratio - 0.001), 0.0)
		var impact := impact_damage(remaining, ratio)

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
			elif collided:
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
			_stun_for(body, push_slide_ticks(tiles) + knockback_stun_ticks)
		if blocker != null:
			_stun(blocker, remaining)
			var blocker_impact := impact_damage(
					remaining, mass_ratio(mover_mass, pushed_mass(blocker)))
			note = " (%s takes %d)" % [blocker.name, blocker_impact]
			if blocker_impact > 0:
				_impact(blocker, blocker_impact, mover, &"body")
			if _alive(blocker):
				next_body = blocker
		_log("push: %s -> %s dir=%s force=%.2f tiles=%d impact=%d stopped_by=%s%s" % [
			mover.name, body.name, direction, f, tiles, impact, stopped_by, note])
		entity_pushed.emit(body, mover, direction, tiles, impact, stopped_by)

		body = next_body
		f = remaining - 1.0


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
	if not _alive(entity) or not entity.is_creature():
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
		if entity.max_stamina > 0 and entity.stamina < entity.max_stamina \
				and tick - entity.last_exertion_tick() > stamina_regen_delay:
			entity.stamina = mini(entity.stamina + stamina_regen, entity.max_stamina)


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


## [param a] and [param b], side by side, change places at once, each
## sliding over [param duration] ticks as a step: a companion making way
## for her player where there is no room to step aside (Companion.bumped).
## Both must be creatures, next to each other, with nothing between.
func swap_places(a: GridEntity, b: GridEntity, duration: float) -> bool:
	if not Net.is_authority() or not a.is_creature() or not b.is_creature() or not are_adjacent(a.tile, b.tile):
		return false
	var direction: Vector2i = b.tile - a.tile
	if _terrain_blocks_step(a.tile, direction, true) or _terrain_blocks_step(b.tile, -direction, true) \
			or _closed_door_across(a.tile, direction) != null:
		return false
	var at: Vector2i = a.tile
	var bt: Vector2i = b.tile
	_occupancy[at] = b
	_occupancy[bt] = a
	for each: Array in [[a, at, bt], [b, bt, at]]:
		var entity: GridEntity = each[0]
		entity._world_set_tile(each[2])
		entity._world_note_moved(tick)
		entity._world_slide_from(each[1], float(tick), duration)
		entity.next_move_tick = tick + duration
	_log("swap: %s %s <-> %s %s" % [a.name, at, b.name, bt])
	entity_moved.emit(a, at, bt)
	entity_moved.emit(b, bt, at)
	return true


func _relocate(entity: GridEntity, to: Vector2i) -> void:
	var from: Vector2i = entity.tile
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
		_relief = terrain["relief"]
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
	var to := from + direction
	# Uphill is slower (Relief.pace, decision 525); a stair is not.
	ticks *= Relief.pace(elevation_at(to) - elevation_at(from), direction.x != 0 and direction.y != 0)
	if _fords.has(to):
		return ticks * FORD_TICK_SCALE
	return ticks * TALL_GRASS_TICK_SCALE if cover_at(to) > 0.0 else ticks


func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return distance(a, b) == 1


## No friendly fire: an entity controlled by a peer may not attack or shove
## another peer-controlled entity. This is decided when a hit is accepted; the
## push code itself still treats every body alike, so a player can be caught
## by a crate or monster that someone else sent flying.
func can_target(attacker: GridEntity, target: GridEntity) -> bool:
	return attacker.owner_peer == 0 or target.owner_peer == 0


## Adjacent, with no wall or closed door between: nothing hits through a wall
## or diagonally past its corner.
func can_melee(from: Vector2i, to: Vector2i) -> bool:
	return are_adjacent(from, to) and not _terrain_blocks_step(from, to - from)


func mass_ratio(mover_mass: float, target_mass: float) -> float:
	return clampf(mover_mass / maxf(target_mass, 0.001), MASS_RATIO_MIN, MASS_RATIO_MAX)


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
	if can_melee(attacker.tile, target.tile):
		return true
	var verb := {} if shove else blow_verb(attacker)
	if verb.get("kind") != "reach":
		return false
	var offset := target.tile - attacker.tile
	var cells := distance(attacker.tile, target.tile)
	if cells > int(verb["cells"]) or cells < 2:
		return false
	var step := offset / cells
	if step * cells != offset:
		return false  # Not on a straight line.
	var at := attacker.tile
	for i in cells:
		if not can_melee(at, at + step) or i < cells - 1 and _occupancy.has(at + step):
			return false
		at += step
	return true


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
func _meets_brace(mover: GridEntity, cell: Vector2i, direction: Vector2i) -> bool:
	if not mover is Monster or not (mover as Monster).charging():
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
			var force := BRACE_FORCE_PER_KG * mover.mass
			_log("brace: %s's spear stops %s's charge (%d, force %.2f)" % [holder.name, mover.name, amount, force])
			_queue_hit(holder, mover, mover.tile - holder.tile, -direction, amount,
					force if force >= knockback_min_force else 0.0, force, false, 0)
			_hits[-1].deed = "braced"
			holder._world_swung(cell - holder.tile)
			braced_against.emit(holder, mover)
			return true
	return false


## Whether [param entity] lies knocked down (knock_down; decision 343).
func is_down(entity: GridEntity) -> bool:
	return tick < entity.down_until


## Knocks [param target] down for [param ticks] (a giant axe's blow;
## decision 343): it lies (down_until, replicated, for the views), cannot
## act (a stun as long), lowers what it raised, and is pushed as if
## DOWN_MASS_FACTOR of its mass.
func knock_down(target: GridEntity, source: GridEntity, ticks: int) -> void:
	if not Net.is_authority() or ticks <= 0:
		return
	target.down_until = maxi(target.down_until, tick + ticks)
	target.raised = ""
	_wear_bundle(target)
	_stun_for(target, ticks)
	_log("down: %s knocked down by %s for %d ticks" % [target.name, source.name if is_instance_valid(source) else "?", ticks])
	knocked_down.emit(target, source)


## Force of a shove by [param attacker] on [param target]:
## strength x mover_mass / target_mass x force_scale, clamped to max_force,
## then scaled by how much stamina the attacker has left. So pushes fade as
## the attacker tires, down to nothing at 0. A melee attack carries half.
func push_force(attacker: GridEntity, target: GridEntity) -> float:
	if attacker.strength <= 0:
		return 0.0
	var raw := attacker.strength * attacker.mass / maxf(pushed_mass(target), 0.001) * force_scale
	return clampf(raw, 0.0, max_force) * attacker.stamina_fraction()


func shove_cost(force: float, target: GridEntity) -> int:
	return roundi(shove_cost_base + force * pushed_mass(target) * shove_cost_scale)


func impact_damage(remaining_force: float, ratio: float) -> int:
	return roundi(remaining_force * impact_per_force * ratio)


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
		if at != to and height_at(at) > top:
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
		if at != to and (blocks_sight(at) or height_at(at) > top):
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
		if at != to and (blocks_sight(at) or elevation_at(at) > lerpf(eye, aim, Vector2(from).distance_to(Vector2(at)) / length)):
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
func find_path(from: Vector2i, to: Vector2i, ignore_goal_occupant := false,
		ignore: GridEntity = null, max_tiles := 0, nearest := false, walls := {}, opens_doors := true) -> Array[Vector2i]:
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
				next_cost += PATH_FIRE_EXTRA
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
