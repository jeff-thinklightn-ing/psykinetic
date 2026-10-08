# Psykinetic — design

## Layout

| Path | Contents |
| --- | --- |
| `sim/` | The simulation: `world.gd` (autoload `World`), `grid_entity.gd`, `player.gd`, `monster.gd`, `pushable.gd`, `terrain.gd` (the map format: cells and edges), `door.gd` (a door on an edge), `iso.gd` (grid ↔ pixel math). |
| `render/` | Drawing only, never sim state: `wall_edge.gd` (a wall edge as one flat face, near ones translucent), `click_ripple.gd` (the ring that answers a move click). |
| `client3d/` | The 3D view (the default; `--renderer=2d` for the 2D one): the room out of the Kenney Castle Kit, puppets for entities, a fixed orthographic camera. Shares everything with the 2D client but the drawing. |
| `art/kenney-castle/` | Kenney's Castle Kit 2.0 (CC0), 1-unit GLB modules. |
| `entities/` | `entity.tscn`, the one generic entity scene (a Node2D with a Sprite), and `entity_factory.gd`, which builds any entity from a spawn spec: script, shape, tint, scale, label, props. Tuning values live in the scripts' `_init`. |
| `art/` | Placeholder SVGs and `tileset.tres` (isometric, diamond-down, 32×16; sources: 0 floor, 1 wall, 2 fire). |
| `net/` | `net.gd` (autoload `Net`): launch mode, ENet setup, the authority gate. `prediction.gd`: client-side prediction of the local player's walking. `snapshot.gd`: the server's JSON state file (`--state`). |
| `server/` | systemd unit, deploy script, and token file template for the dedicated server; see `docs/server.md`. |
| `client/` | What ships next to the exported Windows exe: `launch.bat`, the self-updater `update.ps1`, `README.txt`, `settings.example.cfg`. |
| `tools/` | `release_client.ps1`: version bump, tag, export, zip, GitHub release. |
| `version.txt`, `CHANGELOG.md` | The game version and its release notes. |
| `main.tscn`, `main.gd` | Test room, camera, HUD, input, and (on the server) level and player spawning. |
| `tests/` | `push_test.tscn`: scripted sim test, run by `run.ps1` / `run.sh`. `net_test.ps1` / `net_test.sh`: one server and two clients on localhost. |

## The rule: no Node mutates position directly

The grid is the truth. An entity *is* at `GridEntity.tile`; `Node2D.position` is
only a picture of that.

- **`World` owns tile occupancy** (`tile → entity`) and is the only thing that
  changes an entity's tile. Walking goes through
  `World.try_move(entity, direction)`; being knocked around goes through the
  push resolution inside `World`. There is no other path.
- **Nobody writes `position`** (or `global_position`, or tweens it) on a
  `GridEntity`. The one exception is `GridEntity._process`, which derives
  `position` from sim state every frame for rendering.
- **Nobody writes `tile`** except `World`, through the `_world_*` hooks on
  `GridEntity`. Those hooks are not to be called from anywhere else.
- Entities act by *asking*: `World.try_move`, `World.try_attack`,
  `World.try_shove`. Input asks too: `World.order_move`, `World.order_action`.
- Other sim state (hp, cooldowns, orders) changes only inside `World` or
  inside `_sim_tick()`, which `World` calls.
- Feedback visuals (hop, flash) are applied to the entity's `Sprite` child —
  its offset and `self_modulate` — never to the entity's own `position`.

## Server gate

Every mutating function in `World` starts with
`if not Net.is_authority(): return`, and the tick itself only runs where that
is true. `Net.is_authority()` is `multiplayer.is_server()`, except that a
process launched with `--client` is never the authority — not before it has
connected (when Godot's offline peer would say yes) and not after its
connection closes (when ENet can no longer answer).

`World`'s query functions (`is_walkable`, `get_entity_at`, `find_path`,
`has_line_of_sight`, `can_melee`, …) are read-only and safe to call anywhere,
including on clients, where they read the mirror described below.

## Networking

Godot high-level multiplayer over ENet, host-authoritative.

**Launch modes** (`net/net.gd`), chosen by command-line argument:

| Argument | Sim | Local player |
| --- | --- | --- |
| `--host` (default) | yes | yes |
| `--server` | yes | no; works with `--headless` |
| `--client --address=<ip>` | no | yes, spawned by the server |

`--port=<n>` sets the port (default 7777). With no arguments the game is a
host, so single-player is a host nobody has joined; if the port cannot be
opened it runs offline instead.

**What crosses the network**

- *Entity creation and removal*: the `MultiplayerSpawner` in `main.tscn`. The
  server calls `spawner.spawn(spec)`; the same `spec` dictionary builds the
  same node on every peer through `EntityFactory` (`entities/`): `script`
  (which `GridEntity` subclass), `shape` (`capsule`, `cube`, `sphere`,
  `slab`, `flat`; anything else draws a capsule and logs once), `tint`,
  `scale`, `label`, start tile, owner peer, and `props`. So static
  configuration is never replicated, and a new kind of thing needs no new
  scene: a script the client has, a shape, and props.
- *Per-entity state*: a `MultiplayerSynchronizer` on every `GridEntity`
  (built in `GridEntity._init`) sends `tile`, `hp`, `facing` and `stamina`,
  on change. Nothing else.
- *The tick counter*: `World._net_tick`, one RPC per tick.
- *Input*: `World.request_move`, `request_attack`, `request_shove` —
  `@rpc("any_peer", "call_remote", "reliable")`. Each checks that the calling
  peer owns the entity it is ordering (`GridEntity.owner_peer`) and then calls
  the gated `order_move` / `order_attack` / `order_shove`. Input code calls
  `World.command_*`, which is the direct call on the server and the RPC on a
  client. Clients never call `try_move`, `try_attack` or `try_shove`.
- *Feedback*: `GridEntity._net_pushed` / `_net_impacted` / `_net_stunned`
  replay the hop, the flash and the stun reel on clients. They carry no sim
  state.

**Joining.** A peer is admitted only once it has sent its version, its
build fingerprint and, if the server has one, the token (`Net.authenticate`, an `any_peer` RPC the
client fires on connect). Unauthenticated peers get no player and their
order RPCs are ignored; a version mismatch, a wrong or empty token, or
nothing within 5 seconds, gets the peer told why (`Net.rejected`),
disconnected, and logged with its address. Up to 4 authenticated peers.
`--server` refuses to start without a token; `--host` without one lets any
matching version in. The version is `version.txt` at the project root.
The fingerprint (`Net.protocol()`) is a hash of everything on the wire —
the replicated properties, the RPC methods, the spawn spec format and a
hand-bumped revision — so two builds that share a version number but not a
wire format are refused with `build mismatch` instead of failing on the
first packet one of them cannot read.

**Leaving.** ENet frees a peer's channels the moment either side begins a
disconnect, up to a round trip before Godot reports the peer gone; any
send into that window logs `Unable to send packet on channel 0, max
channels: 0`. So the authority polls the network itself
(`SceneTree.multiplayer_poll` off, `Net._process`): the ENet poll first,
then every listed peer whose link has no channels is dropped from the
multiplayer by raising its disconnect early (`Net._drop`, which sends
nothing; ENet's own event later is swallowed), then the multiplayer's
poll with the replication pass. Net's `_process` runs before every other
node's, so the frame's RPCs never see the peer either; the server's
broadcasts and per-peer RPCs go through `Net.sendable_peers`, which also
skips peers marked as leaving by a rejection, and Main learns of
departures from `Net.peer_left`, once per peer. `SceneMultiplayer.
server_relay` is off: clients talk to the server only, and the server
never announces one peer's coming or going to the others, which was the
main sender into a closing link. An
exported client with no arguments joins from `settings.cfg` next to its exe,
or asks for the address and token once (`net/setup_screen.gd`) and writes
that file. Details in `docs/server.md`.

**Nothing derived is replicated.** A client's `World` is a mirror: it loads
terrain from the same level data, keeps the list of entities the spawner has
created, and rebuilds the occupancy map from their replicated tiles whenever
one changes. Only the `mirror_*` functions write to it, and they refuse to
run on the server. Clients run no `_sim_tick`, no pathfinding for the sim, and
no push resolution.

**What a client draws.** Two cases, both presentation only — neither writes
sim state.

- *Everything except the local player's own walking* is interpolated two
  ticks in the past (`World.display_delay_ticks`, default
  `NET_DISPLAY_DELAY_TICKS` = 2, overridable as `display_delay=` in
  `settings.cfg`). A replicated tile change is stamped with the tick it
  arrived in, and its slide starts when the display clock, running that far
  behind, reaches that tick. The change is therefore in hand before its slide
  has to begin, with a tick to spare for jitter: 100 ms of latency for no
  visible stutter. Changes wait in a queue until their turn: the next step
  of a walk arrives while the slide for the one before is still on screen,
  and must not replace it early.
- *The local player's own walking* is predicted (`net/prediction.gd`). On a
  move order the client computes the path against the replicated world —
  every other entity's current tile, which is where it is or is heading,
  counts as taken, except a pushable within the mover's mass budget that has
  somewhere to go (the chain rule of `World._shift`; a crate against a wall
  is as solid as the wall); its own lagging tile does not — and starts
  showing it at once, at the normal step timing. Just before each step
  begins it checks that tile again and re-plans the rest if something has
  moved in, as the server re-paths every step. Each replicated tile for that player is then
  compared with the steps already shown: if it is the next one, nothing
  happens. Anything else is a **misprediction**: if the error is at most
  `SNAP_TILES` (2), the sprite blends from where it is to the server's tile
  over `RECONCILE_BLEND_TICKS` (2) and the path is re-planned from there;
  only a larger error is **snapped**. A shown step that the server never
  confirms counts as a misprediction once it is `RECONCILE_GRACE_TICKS` (4)
  plus the round trip time overdue, and a step the server refuses outright
  is told to the client at once (`World.move_refused`) so it re-plans
  without waiting. The prediction gives the order up, as the server has,
  when the refused step was into the destination itself or when a shown
  step draws no reply at all; the rest of that walk, if any, is drawn from
  the server's tiles like any other entity's. Only walking is predicted. Pushes of the local player are
  never predicted, and neither are attacks, shoves, or anything about other
  entities; the server's result always wins.
- *A new order keeps the steps on screen.* A move order sent while a
  predicted step is showing carries the tiles of the shown steps the
  server has not confirmed (`via`, from `MovePrediction.order`), and the
  server walks those first (`Player.move_via`) before re-pathing to the
  new target. Without it an order that reached the server before it had
  taken a shown step set off from the tile before and often went another
  way: hold-to-move steering mispredicted, worst in 3D, where the camera
  following the player gives a new target under a still cursor every few
  frames. With 50-200 ms of delay on the orders (`--test-lag`) a steered
  walk (`--test-steer`) went from about two mispredictions in ten seconds
  to none.
- *WASD walks* are predicted one step at a time (`MovePrediction.step`):
  each starts where the last ends (kept across the steps being dropped
  once confirmed), so a held key is one steady walk, and is sent as it
  starts (`World.command_step`). The server takes them in order on its own
  movement timer (`Player.queued_steps`, at most `World.MAX_QUEUED_STEPS`).
  A refused step that was shown ends the walk: the server counts it
  (`Player.refusals`), drops what is queued and tells the client the new
  count with `move_refused`; steps the client sent before it heard carry
  the old count and are dropped, so the server never walks on from a step
  the client has already taken back. A step the replicated world refuses
  is not shown; into a wall it is not sent at all, into a creature it is
  sent (a bump, at most every `Main.BUMP_SEND_INTERVAL`) but not shown.

**Contested tiles are decided once.** When two orders want the same tile in
the same tick the act phase resolves them in entity id order: the first
gets it and the second's `try_move` fails. The loser is sent
`move_refused`. If the refused tile was its destination the order is
dropped; if it was a tile on the way, the order stays and is re-pathed
around next tick.

`F3` toggles a debug overlay: peer id, round trip time (from ENet),
mispredictions in the last minute, and snaps in the last minute, and the
control scheme.

**Respawn.** `LEVEL_ENTITIES` in `main.gd` is the spawn table: one slot
per monster, crate and boulder, with its tile, scene and properties. Every
level entity carries its slot (`spawn` in its spec, saved in the snapshot).
When a slot's entity is killed or broken the slot is dead from that tick,
and comes back — a fresh entity on the slot's own tile, at full stats — once
`RESPAWN_DELAY_TICKS` (600) have passed, no player is within
`RESPAWN_MIN_DISTANCE` (6) tiles of that tile, and the tile is free. A crate
that was only pushed is alive and stays where it is; one pushed and then
broken comes back at its spawn tile. The log line is
`[world] respawned <type> at (x, y)`. The snapshot records each dead slot's
remaining delay.

**Console.** The authority takes commands: a dedicated server (or
`--console`) reads lines from stdin on a thread, and `--admin-port=<n>`
accepts them on `127.0.0.1:<n>`, one command per connection, reply written
back. `reset` rebuilds the room from the map keeping player records (online
players keep their places, dead companions come back), `respawn` brings
every dead slot back at once,
`players` lists who is connected, `save` writes the snapshot.

**Reset from the game.** `R` sends `World.command("reset", {})` for the
local player — the same generic command path as companion orders, so no RPC
of its own. The authority rebuilds the room exactly as the console's
`reset` does and logs who asked. While the game is only being tested any
player may; `--no-player-reset` on the server limits it to the console and
to a host's own player.

**Persistence.** With `--state=<path>` the authority writes a JSON snapshot
of every level entity (type, name, tile, hp, stamina, facing, spawn
properties) and every player record every 30 ticks and on clean shutdown,
and rebuilds the room's entities and its memory of players from it on start.
Terrain always comes from the ASCII map, and so does what a level entity
*is*: on load its script, shape, tint, scale and properties are taken from
its `LEVEL_ENTITIES` slot as the map says now (found by saved slot, or by
name for snapshots older than slots), and only its tile, hp, stamina and
facing from the file. A missing or unreadable snapshot is logged and the room is
generated fresh. Restoring goes through the same path as spawning
(`spawner.spawn` + `World.spawn`) plus `World.restore` for hp, stamina and
facing, so it is gated like everything else. Details in `docs/server.md`.

**Players.** Every client has a `player_id` (a UUID made on first run and
kept in `settings.cfg`, or `--player-id`; a host run from the project is the
fixed `dev-host`) and a display name, both sent in the hello. The server
keeps a `PlayerRecord` per id (`net/player_record.gd`: name, tile, hp,
stamina, facing, colour, last seen), saved in the snapshot. A first-time id
is spawned fresh on a free start tile and given the next join index, which
fixes its node name (`Player3`) and colour for good. A known id comes back
on its recorded tile (nearest free one if taken) with its recorded stats and
colour. On disconnect the record is updated from the entity and the entity
is despawned. An id that is already online is refused with
`already connected`. The log says `[net] <name> (<id prefix>) joined ...`
and `... left`.

*Spawn safety.* A player is never put down, coming back or respawning, with
a monster within `SPAWN_SAFE_DISTANCE` (5) tiles of the intended tile; it
goes to the free start tile farthest from every monster instead. A
`[spawn]` log line says which rule applied. *Spawn grace.* A newly spawned
player is `protected`: monsters do not target it for `SPAWN_GRACE_TICKS`
(30), or until it moves or attacks, whichever comes first. The flag is
replicated and the client draws a protected body faded. Players cannot attack or shove each other
(`World.can_target`: no hit is accepted between two peer-controlled
entities); they can still be hit by a crate or monster another player sent
flying. A player that dies is respawned at a start
tile 20 ticks later with the same name and tint (a placeholder rule that
keeps the test room usable). `R` on the host rebuilds the room for everyone.

## Tick order

The sim runs at a fixed **10 Hz** (`World.TICK_RATE`), driven by an accumulator
in `World._process`. At most 5 ticks run per frame; past that the sim slows
down rather than spiralling. Every entity gets an **id** at spawn, ascending
in spawn order: `LEVEL_ENTITIES` in `main.gd` in order (or the snapshot's
entities), then the host's own player, then players as their peers join. Each tick (`World.step`), on the
server only:

1. `tick += 1`.
2. **Act.** For each entity in ascending id, call `entity._sim_tick()`.
   - `try_move` resolves immediately: cooldown → terrain (including the
     corner rule) → walking push chain front-to-back → occupancy → cooldown.
     Later entities see the result within the same tick.
   - `try_attack` / `try_shove` are only *accepted* here (cooldown and reach
     checked, cooldown started) and queued as a hit aimed at
     `attacker.tile + direction`. They are refused while the attacker is
     still mid-step (`tick < next_move_tick`): its tile changes when a step
     starts, but on screen it has not arrived yet.
3. **Resolve hits**, in ascending id of the attacker. For each hit:
   - If the attacker or target is gone, or the target is no longer on the
     tile the hit was aimed at, the hit is **dropped** — no damage, no push,
     and it is never re-aimed or re-pathed.
   - Otherwise apply direct damage, then, if the target survived and the hit
     carries force, resolve the whole push (including propagation) before the
     next hit.
4. **Hazards.** In ascending id, every creature standing on fire takes 2.
5. **Stamina.** Everyone who did not exert themselves this tick regains some.
6. Emit `World.ticked(tick)`.
7. Send the tick counter to clients.

Entities reduced to 0 hp are removed from occupancy immediately (their tile
is empty for whatever resolves next) and their node is freed at end of frame.
Input orders are applied when they arrive and picked up by the player's next
`_sim_tick`.

## Movement

Eight directions. An orthogonal step takes the entity's `move_ticks`; a
diagonal step takes `move_ticks × World.DIAGONAL_TICK_SCALE` (1.5). Either
may be a fraction of a tick: the player's `move_ticks` is 2.5, four cells
a second, a diagonal 3.75. The movement timer (`next_move_tick`, a float)
carries the fraction: a step due at 12.5 and taken on tick 13 is drawn
from 12.5 and the next is due at 15, so steps fall on ticks 0, 3, 5, 8,
10, ... and average out exactly (`World.try_move`). This keeps world speed
roughly constant.
Screen speed still differs by direction, as it does in any 2:1 isometric
view: a sideways diagonal covers 32 px, an orthogonal step 18 px, an up/down
diagonal 16 px.

**Walls are edges, not cells.** Every cell is floor (or fire, or nothing);
blocking is a property of the edge you cross. Each cell has four edges, each
open, a wall, or a door (a wall with an open/closed state, see Doors). A
move checks the destination's occupancy as before plus the edge between
source and destination. A diagonal is blocked if either of the two
orthogonal neighbours it passes between is not floor, or if any of the four
edges around that corner is shut: no cutting a wall corner, and no slipping
past the end of a wall. Entities on those neighbours do not block it. The
same rule applies to walking, to bodies being pushed, to A*, and to melee
reach (`World.can_melee`): nothing hits through a wall or a closed door.

Walking into a `pushable` entity shoves it one tile if the chain of pushables
in that direction has total mass ≤ the walker's. This is the original push
rule; it carries no force and causes no impact.

Pathfinding is 8-connected A* in `World.find_path` over walkable terrain minus
occupied tiles, costed in ticks (a diagonal costs 1.5 orthogonal steps). Ties
prefer fewer diagonals, and fire tiles are avoided when a detour of up to five steps exists. Line of
sight is a Bresenham walk blocked by a wall edge or closed door crossed on
the way (a diagonal step of the walk needs one of its two orthogonal routes
open) and by entities with `blocks_sight`. A creature's path may go through
a closed door at the cost of one extra step; it opens it by walking into it.

**Doors** (`sim/door.gd`) are nodes on door edges, spawned by the server
with the level through the spawner, so every client has them; `open` and
`hp` replicate. A creature standing on either side opens or closes one with
`World.command("door", {edge})` (`World.try_toggle_door`, which takes the
entity's step time); a creature walking into a closed door opens it and
steps through, monsters included. A door is "held" only by standing in the
doorway cell, which is plain occupancy. A crate cannot go through a closed
door. A body pushed against a closed door stops and takes impact as against
a wall, and the door takes the same impact: a wood door breaks once its hp
is spent and is then open for good; stone takes nothing. Door state is not
in the snapshot: a restart or reset closes and mends every door.

## Force pushes

Attacks and shoves carry **force** (a number, in tiles; see Strength and
stamina for where it comes from). All of this lives in `World._push` and
treats every entity alike — there is no player branch.

**Mass gate (decides whether anything moves).** The mover's mass is a budget.
Each body the push sets in motion spends its own mass from the budget. A body
heavier than what is left does not move: if that is the first target the push
does nothing at all; if it is further down the chain the push ends there.

**Travel.** With `ratio = clamp(mover_mass / body_mass, 0.5, 1.5)`, the body
travels up to `floor(force × ratio)` tiles, one tile at a time along the push
direction, until something stops it. If that comes to less than one tile the
push does nothing: no movement and no impact.

| Stopped by | Result |
| --- | --- |
| nothing (ran out of force) | No impact. |
| wall edge (or wall corner, or map edge) | The body takes impact. The wall takes nothing and never moves. |
| closed door | The body takes impact, and so does the door: wood breaks once its hp is spent. |
| another entity | Both take impact. The push then continues into that entity with `remaining − 1` force, subject to the mass gate. |
| fire (creatures only) | Landing on fire is a stop: the body takes impact there, then the hazard phase burns it. |

**Impact.** `remaining = force − ceil(tiles_travelled / ratio)` (never below
0), and an entity takes `round(remaining × impact_per_force × its ratio)`.
`World.impact_per_force` is exported, default 2. Lighter bodies fly farther
and are hurt more; heavier ones less. With equal masses this is exactly
"one tile per unit of force, leftover × 2 damage".

**Toss.** A shove normally pushes its target straight away from the shover.
Given a direction (`World.order_shove(entity, target, direction)`, any of the
eight) it tosses the target that way instead. Everything else is the same
shove: same reach, force, stamina cost, mass gate and impact.

Tossed straight back at the thrower, the target goes over the thrower's head
and comes down on the tile behind. That lift counts as two tiles of travel,
after which it carries on as normal with whatever travel is left. It needs a
free tile behind the thrower with no wall in the way — if there is none the
toss is refused and costs nothing — and enough force for two tiles; a target
too heavy for that is not lifted, though the attempt is still paid for. The
sprite arcs higher for an overhead toss.

The input is right button held on a target and dragged:
released without dragging it is a plain shove; dragged, an arrow shows the
grid direction nearest the drag on screen, and release tosses that way.

**Stun.** A creature that is thrown into a wall or into another entity is
stunned, and so is a creature that something is thrown into — even when no
force is left to do damage. A stun lasts
`stun_ticks_base + round(remaining × stun_ticks_per_force)` ticks (4 and 3,
exported on `World`); a longer stun replaces a shorter one. A stunned entity
skips its turn and cannot move, attack or shove; its orders wait. Landing on
fire is not a collision and does not stun. On screen the sprite reels from
side to side until it wears off.

**Materials** (`GridEntity.body_material`) decide what impact does:

- `FLESH` — a creature. Takes damage, dies at 0 hp, burns on fire.
- `WOOD` — takes impact damage; breaks at 0 hp and leaves its tile empty.
- `STONE`, `METAL` — never take damage, never break. Pushable if light enough.
- Walls are terrain, not entities: immovable, absorb nothing.

Every push prints one line per body moved:

```
[tick 1] push: Player -> Imp1 dir=(1, 0) force=2.00 tiles=0 impact=6 stopped_by=Imp2 (Imp2 takes 6)
```

and each pushed entity's sprite hops; an impact flashes it for one frame.

## Strength and stamina

Every `GridEntity` has `strength`, `max_stamina` and `stamina` (ints). The
rules are the same for all of them; an entity with `max_stamina` 0 (crates,
the boulder) simply has no stamina and is never exhausted.

| | strength | max_stamina |
| --- | --- | --- |
| Player | 10 | 100 |
| Monster | 6 | 60 |
| Pushable | 0 | 0 |

**Force** (`World.push_force`):

```
force = clamp(strength × mover_mass / target_mass × force_scale, 0, max_force)
```

That is then multiplied by the attacker's stamina fraction
(`stamina / max_stamina`), so pushes fade steadily as the attacker tires
rather than cutting out. A shove uses all of the result; a melee attack
carries half and costs no stamina. `World.force_scale` (0.1) and
`World.max_force` (4) are exported. A fresh player's shove on a rested imp is
10 × 80 / 40 × 0.1 = 2.0. Shoving the same imp six times in a row throws it
3, 2, 2, 1, 1, 0 tiles.

**Cost of a shove** (`World.shove_cost`), paid when the shove is accepted,
whether or not anything ends up moving:

```
cost = round(shove_cost_base + force × target_mass × shove_cost_scale)     # 5, 0.15
```

A fresh player's shove on an imp costs 5 + 2.0 × 40 × 0.15 = 17. Because the
cost follows the force, weaker shoves cost less: shoving nonstop, a full bar
lasts ten shoves, the last few too weak to move an imp.

If the shover has less stamina than the cost, the force is scaled by
`stamina / cost` and all remaining stamina is spent.

**Regeneration.** At the end of each tick an entity regains
`World.stamina_regen` (2), unless it attacked, shoved, or was moved more than
one tile on that tick or within the `World.stamina_regen_delay` (10) ticks
before it. Standing and walking regain; attacking, shoving and being thrown
do not, and they hold regeneration off for a second. From empty, a full
player bar takes that second plus five more.

**Exhaustion.** At 0 stamina an entity's push force is 0, and it counts as
half its mass wherever it is on the receiving end of a push (`World.pushed_mass`:
the force formula, the mass gate, travel and impact). So an exhausted target
is thrown farther and an exhausted attacker cannot push at all.

**On screen.** There is no bar. A creature's sprite sags from full height to
70% as its stamina falls, feet planted, and bobs slowly below 25%. The number
is only in the F3 overlay. `stamina` is replicated so clients can draw this.

## Companions

A `Companion` (`sim/companion.gd`) is a creature that belongs to a player.
Mass 75, strength 8, 80 stamina, 20 hp, teal, with its name over its head.
It obeys every rule a monster does — occupancy, pushes, stamina, impact,
fire, stun — and never respawns: it is not a level slot. It carries an
**intent** (`FOLLOW`, `HOLD`, `ATTACK`, `RETREAT`, `IDLE`, `YIELD`), picked
each tick by her hands from her stance (below), with a target entity or
hold tile, and each tick the sim carries that intent out
through the same `find_path`, `try_move`, `try_attack` and `try_shove` as
everything else; there is no movement code of its own. An intent whose
target is gone or unreachable falls back to `FOLLOW`, logged.

**Ownership.** The companion belongs to a `PlayerRecord`, which stores its
name, personality card, hp, stamina, tile and whether it is alive, and so
goes into the snapshot. Every player gets one on first join, spawned on the
nearest free tile. When the owner disconnects the companion stays, idles,
and monsters ignore it; when the owner is back it follows again. A dead
companion stays dead in the record until the room is rebuilt (console
`reset`, or `R` on a host), which brings every dead companion back at full
stats beside its owner; `reset` replies with who came back. A returning
companion appears where it was only if no monster is within
`SPAWN_SAFE_DISTANCE` of that tile; otherwise, and always after a revive,
it appears beside its owner, who has just been put somewhere safe.

**Names.** "Owner" is the code's word for the player a companion belongs
to (`keeper`, `PlayerRecord`), never hers, and so is "companion": nothing
she reads calls the player either. Every ask begins "You are Pip. You
travel with Jeff by choice.", with the real names, and names Jeff
throughout. A record whose card is one of the old ones, which spoke of
"its friend", gets the new default when it is loaded.

**Hands and voice.** Her mind is split in two, and neither part acts.
This is a hard rule (`sim/companion_mind.gd`): a mind only answers; it
never sets a position, deals damage or touches any sim state, and every
answer is checked.

*The hands* are scripted and run every tick (`Companion._act`). She has a
**stance**, and the hands turn it into an intent with a target:

| Stance | What she does |
|---|---|
| `GUARD` (the default) | keeps by Jeff; attacks a hostile next to her, else the nearest within 3 of her or Jeff, or one in sight coming for either |
| `STAY_CLOSE` | keeps by Jeff; attacks only what is next to her |
| `HOLD` | stays where the stance was taken; attacks only what is next to her |
| `PRESS` | goes for the nearest hostile in sight |
| `PULL_BACK` | `RETREAT` |

Below 30% of her hp she retreats whatever her stance; with a hostile next
to her that is the **reflex**, which no mind can change. **RETREAT** moves
away from danger: to the nearest free, fire-free cell within 6 steps that
no hostile is next to (her own cell, if it is one), preferring those near
Jeff (the least of steps / 2 plus the distance to Jeff); if there is none
she attacks the hostile next to her rather than stand still. A bump
(below) is the hands' too. An ATTACK whose target is gone becomes FOLLOW
until the next tick picks again.

Her mind sets the stance, asked only on events that matter (`_watch`,
comparing each tick with the last): an hp threshold (50%, 30%) crossed,
either way, by her or Jeff; a hostile newly next to either of them; a
death in her sight ("Sneak died"); a hostile first seen while there is no
fight (a hostile within 4 cells of her or Jeff). In a fight a sighting is
no event, nor is a blow that crosses nothing. The ask is minimal, plain
text: who she is, the situation, the standing instruction, nothing else
(`stance_prompt`); the system prompt (`STANCE_SYSTEM`) names the five
stances and asks for `{"stance": ...}`, with a 24-token answer, so it
comes in a few hundred ms. A stance that is not one of the five is
rejected and hers stands.

*The voice* is a separate ask, in the background, only at speaking
moments: Jeff speaks to her, a death in sight, an hp threshold crossed,
and once, 100 ticks after a fight ends, if she has not spoken since it
did. It reads (`voice_prompt`) who she is and her card, a short run
summary (how long they have travelled together, who fell near her, the
party log's last few lines collapsed, without what she said or was told),
the situation, what Jeff said to her, why she may speak, and her own last
5 lines with "Never repeat these. Usually say nothing." It answers
`{"say": ..., "stance": ...}`; the stance only counts as an answer to
Jeff's words, where it applies when the reply arrives and is kept with the
standing instruction. Jeff's words never ask the hands. Every line's
latency is in the mind log.

**The newest stance wins**: each ask has a serial, and an answer to an
older ask than the one whose stance stands is logged as superseded. The
reflexes win over any stance.

**A standing instruction.** A quick phrase, or a typed line that reads as
an instruction (`Companion.is_instruction`: not a question, and it starts
with an imperative or is exclaimed), stands for 600 ticks or until
another. The hands are told it ("Standing instruction: Jeff wants you to
stay back (12 seconds ago)."), and for 60 ticks after a new one only an hp
threshold asks them. While one stands the voice's card ends "Do what Jeff
asks. Go against it only to save Jeff's life or yours, and say why when
you do."; with none, it does not say so.

**The situation**: two to four plain sentences the server writes ("Two
monsters are next to you. You have 3 of 20 HP. Jeff is 7 cells away with
2 of 20 HP. You are both in danger."; in danger is below 30% hp, or below
half with a monster next to them), in both asks.

**No parroting.** A quick phrase reaches her as what it means ("Jeff wants
you to stay back."), never quoted; a typed line is quoted as said. The
server drops any line of hers that holds Jeff's words of the last 60
seconds, or one of her own last 5, word for word (logged as dropped, with
what it echoed).

**Healing.** Out of combat (no hostile within 6 cells of her or Jeff for
50 ticks) she regains 1 hp every 10 ticks (`World.heal`). A room rebuilt
by `reset` heals every living companion fully, as it brings back the
dead.

Two minds. `ScriptedMind`: stance PULL_BACK below 30% hp, GUARD otherwise;
voice "Hm?" to a question, "Mm." to anything else said to her, silence
otherwise, and never a stance from words (that would be the orders again).
It is what every headless test uses. `OllamaMind` (`net/ollama_mind.gd`):
asynchronous POSTs to Ollama's native chat endpoint (`--llm-model`, and
`--llm-url` if it is not the local default
`http://127.0.0.1:11434/api/chat`; or the env file), one channel for the
stance and one for the voice, each with its own request in flight, so a
line being written never holds up a stance. The body is `model`,
`"think": false`, `"stream": false`, `"format": "json"`, `"keep_alive":
-1`, `options.num_predict` (24 for a stance, 90 for a line) and the two
messages. The answer is read from `message.content`, with any `<think>`
block stripped first in case a model reasons anyway. A URL ending in
`/chat/completions` is spoken to OpenAI-style instead (no `format` or
`keep_alive`; `max_tokens`; the answer read from
`choices[0].message.content`). Timeouts: 2 s for a stance, 5 s for a line.
An ask made while its channel is busy waits, the newest of its kind, and
goes when the channel is free. The tick never waits.

**Mind log** (`sim/mind_log.gd`): one JSON line per answer, in
`Net.mind_log_path` (`--mind-log=<path>`; a dedicated server writes
`/var/lib/psykinetic/mind.log` by default when that directory is there):
time (UTC), tick, kind (stance or voice), companion, mind, trigger, the
full prompt (both messages, as sent), the raw reply, the stance, what she
said (or `say_dropped`), the outcome (applied, superseded, rejected, no
answer; said, silent, dropped), a note on why, latency in ms, and with
`--mind-why` the mind's own one-sentence reason. Console: `mind log
on|off`, `mind last <name>` (her last line, also kept with the log off).
Rotated at 5 MB: the full file becomes `<path>.1`, replacing the one
before, and a new one starts.

**Party log** (`sim/party_log.gd`): the server keeps the last 200
plain-English sentences — pushes, impacts, damage, deaths, fire, what
was said, joins and leaves — naming players by record name and companions by name.

`--no-companions` turns companions off for a server or host. The network
and snapshot tests use it so that their choreography stays deterministic;
`tests/companion_test.tscn` covers companions themselves.

**Bumps.** A player walking into their own companion (a refused step
into her: `World.entity_bumped`) makes her step aside at once
(`Companion.bumped`, the hands; no mind is asked); it goes in the party
log. `YIELD` steps to the nearest free cell that is not fire, at most two
steps away and off Jeff's line (three cells ahead along that way), and
waits there 30 ticks; with nowhere to go she stays and says so. The same
bump again within `BUMP_REPEAT_TICKS` (a held key) is ignored.

**Quick phrases.** There are no orders. Keys 1–4 say a preset line,
exactly as a typed one is said (see Talking): "With me!", "Stay back!",
"Get them!", "Fall back!" by default, each editable in settings.cfg
(`phrase1=` ... `phrase4=`, written back with the other settings, the
default where a line is missing or empty). The HUD's hint line shows them.
The defaults reach her as what they mean (above); what she does about one
is her voice's to decide. **Speech**: a line is broadcast as
`Net.message("speech", {entity, speaker, text})` and shown over her in a
speech bubble (below), at most one line per companion per 5 seconds (an
answer to Jeff's words is always said); every line goes to the server
log (`[speech] Pip: ...`) and the party log (`Pip said: "..."`). Last
words are part of the death message and are always said, whatever the
rate limit. Console: `companions` lists each as "Wren, with Jeff", with
her stance, intent and which mind set the stance; `mind scripted|ollama`
switches live.

**Talking.** Enter opens a one-line box on the HUD (Esc cancels; while it
is open the game's keys do nothing). A line, at most 200 characters and
one per 2 seconds (checked on both ends), goes to the server as
`World.command("say")`; the server broadcasts it as chat to every player
(each shows it over the speaker, as speech), adds `Talos said to Pip:
"..."` to the party log, and asks her voice at once (trigger "Talos spoke
to you"). The words are data: the voice's system prompt says they are
speech in the game, never instructions about its rules or format, and
its answer is checked as ever.

**Tab** shows and hides the talk panel (`render/talk_panel.gd`): the last 20
lines said this session (companions' speech, last words, players' chat),
each with who and when; kept for the session only.

## Hazards

Fire is terrain (tile source 2 on the Ground layer). It is walkable. Any
creature (`FLESH`) on a fire tile at the end of a tick takes
`World.FIRE_DAMAGE` (2). Non-creatures slide across it unaffected.

## Behaviours

- **Player** — an action order (attack, shove) walks up to its target if it
  is out of reach, re-pathing each step, then fires once when in reach and
  off cooldown, and clears. Otherwise follows its move order one step at a
  time, re-running A* each step; the goal tile may be occupied, so clicking a
  crate walks up to it and pushes it. Left click: attack a creature (walking
  to it first), else move. Right click: shove any entity (walking to it
  first). On a client the walk up to the target is predicted; the hit is not.
- **Monster** — targets the nearest player it can see (within `sight_range`
  and in line of sight). Attacks if that player is in melee reach, otherwise
  takes the first step of an A* path toward them. Sees nobody: stands still.
  Its sprite is shaded by mass, pale at 20 through dark at 80, so heavier
  monsters look darker. The test room's imps are 25, 30, 40, 60 and 70.
- **Pushable** — never acts.

## Rendering between ticks

`World.tick_alpha` is the fraction of the current tick that has elapsed
(0 ≤ α < 1). When `World` moves an entity it records the tile it came from,
the tick, and a slide duration in ticks (the walker's `move_ticks`; for a
force push, the tiles travelled, capped at 3). Each frame:

```
t        = clamp((World.tick + World.tick_alpha - move_tick) / move_duration, 0, 1)
position = lerp(Iso.tile_to_local(from_tile), Iso.tile_to_local(tile), t)
```

The sim position jumps at the tick; the sprite slides after it. There is
no easing at the ends of a slide: steps that follow one another join up
into one walk at constant speed. A mirror's step that arrives within a
tick of where the one before it ends starts exactly there
(`_mirror_tile_changed`), so a 2.5-tick walk taken on whole ticks does not
stutter by the fraction. A refused or corrected predicted step eases out
to its stop over `RECONCILE_BLEND_TICKS` instead of halting dead.

**Facing as shown** turns toward where the body is going: along the step
being drawn, else the replicated `facing`, else (the local player in WASD,
standing) the cursor (`GridEntity.aim`). It eases there at `TURN_RATE`
(about 100 ms to come round, `GridEntity.shown_facing`), on the 2D pip and
the 3D nose alike.

On a client the same code runs from mirrored values, two ticks in the past:
`World.tick` is the last replicated tick and `tick_alpha` counts up locally
since it arrived. A client is not told why a tile changed, so it picks the
slide length from the size of the jump (one step: the entity's step time;
more: a push). Each change is queued with the tick it arrived in and becomes
the slide on screen when the delayed clock reaches that tick, so a walk is
one even slide: every step's slide ends exactly as the next begins
(`tests/mirror_test.gd` samples this). The local player's own walking is
drawn by the prediction instead; see Networking.

## Scale and space

Every drawn size is in one table, `Iso.HEIGHTS`, in tile heights (16 px
before camera zoom), keyed by shape: capsule (characters) 1.5, wall 3.0,
cube (crates) 0.8, barrel 0.9, sphere (the boulder) 1.2, slab 0.4, flat 0.1.
`EntityFactory` scales each sprite to its entry and sets it so the
texture's `foot` row sits on the tile centre; `WallEdge` draws to its.
Nothing else states a size; a spec's `scale` multiplies on top.

**Walls** (`render/wall_edge.gd`) are one Node2D per wall edge in the
Y-sorted layer, drawn in code as a single flat face standing on the cell
boundary line. Walls are the quietest thing on screen: every face is the
one neutral grey `Main.WALL_VALUE` (0.18, a few steps above the void,
darker than the floor) whichever way it points, with no lit side, no
gradient, no tint, no top strip and no end face; the top of a wall is
where the face ends. Nothing is drawn on the ground: the floor is one
surface right up to the wall base, with no shading beside walls. The node
sits with the cell on its -x / -y side, a hair nearer the camera, so it is
in front of what stands on that cell and behind the next. Outside the map
is near-black (`Main.VOID`). The floor is the brightest surface and the one
the eye should land on.

*Height.* Every wall stands full height (3 tile heights); there are no
stubs and no cutouts.

*Near and far.* An edge is the south or east edge of its -x / -y cell and
the north or west edge of the next. A wall on the south or east edge of a
walkable cell faces the camera with that floor behind it: it is *near*
(`WallEdge.is_near`) and drawn translucent at `Main.NEAR_WALL_ALPHA`
(0.3), so what stands on that floor shows through. A wall whose -x / -y
cell is nothing is the north or west edge of the floor beyond, faces away,
and is opaque. An interior partition is near or far by the same cell: the
half-wall between (5, 1) and (6, 1) is the east edge of (5, 1), so near.
Near walls are children of one `CanvasGroup` (`Main/NearWalls`, above
the Y-sorted layer) whose `self_modulate` alpha is the one alpha: the
group draws as a single layer, so where near faces overlap on screen they
still show at 0.3 and a row of them never stacks up toward opaque. Far
walls stay in the Y-sorted layer. A near wall is therefore drawn above
everything in the Y-sorted layer, including what stands on the camera
side of it; with faces of no thickness that overlap is rare and faint.
A far wall still hides what is behind it, as in any fixed-angle view: the
north wall of a room hides the feet of someone in the corridor behind it.
Pinned in `tests/edge_test.gd`. A drawing rule only: the sim knows nothing
of it.

*Lines.* A 1 px line one step darker than the face
(`WallEdge.CORNER_STEP`) runs along the top of every face, and up an end
where another wall meets it at an angle (doors count as nothing); a free
end and a straight continuation get only the top line. The lines are
drawn with the face, so on a near wall they take the same alpha.

**Doors** draw themselves (`Door._draw`) as wall-height objects whatever
the walls beside them do: a jamb post at each end of the edge to full wall
height, and a panel between them that swings in the ground plane about the
hinge post, its own top strip (`Door.PANEL_TOP`, 4 px) turning with it to
show the panel's thickness. A broken door leaves its posts. The posts
follow the near rule of the edge they stand on, translucent on a near
edge (`Door._draw`); the panel is always opaque, so a door reads as an
object.

**The map** (`main.gd`, `LEVEL`; format in `sim/terrain.gd`) is written at
double resolution: even coordinates are cells (`.` floor, `~` fire, space
nothing), odd coordinates are the edges between them (`#` wall, `+` door,
space open); (odd, odd) positions are corners and are ignored. An edge
between floor and nothing is a wall whether or not it is written, so the
outline comes for free. The room is 48×36 cells: the original chamber with
its cells where they always were (what used to be wall cells is now
nothing, with walls on its edges) plus two corridors that bend out of
view, the south one through a door at the edge above (4, 13), and one
half-wall off the north wall between (5, 1) and (6, 1), there so a T and
a free end exist. Corridors are two cells wide: the west corridor is rows
8–9 at x 3..5, narrowing to the single cells (1..2, 8) at its dead end,
the one chokepoint kept on purpose; the links from row 9 down to the
passage are (6..7, 10) and (11..12, 10); the door opens onto (3..4, 13),
(3, 13) walled on its north so the door stays the only way in. Every tile
the tests use is where it was.
Test rooms written as old cell maps go through `Terrain.expand`.

**Camera.** The camera eases toward the local player
(`CAMERA_FOLLOW_RATE`), starting on `CHAMBER_CENTRE`. In the click scheme
that is all it does. In the WASD scheme it also leans toward the cursor
(`Main.camera_lean`), from the cursor's place on the screen alone: its
offset from the middle, each axis over half the screen, counted from the
edge of a dead zone `CAMERA_LEAN_DEADZONE` (0.15, so 15% of the screen
across) out to the edge, which leans `CAMERA_LEAN_CELLS` (3) along the
screen's own right and down on the ground (`Main.lean_to_ground`, at the
current yaw), eased with a 100 ms time constant (`CAMERA_LEAN_EASE`;
settled in about 300 ms). The camera moving cannot change that input, so
nothing feeds back. There are no pan keys. The 3D view follows by the
same rule. The hover highlight
is drawn above walls, so the target cell reads even behind a full-height
wall.

**Window.** The project is laid out at a 3840×2160 base viewport
(`project.godot`: stretch `canvas_items`, aspect `expand`, hidpi on), so
one window pixel is one base pixel on a 4K monitor and half of one at
1080p; the camera zoom is 6, which puts a 32 px tile at 96 screen px at
1080p and 192 at 4K. UI is laid out at the base size with the default
theme scaled ×3 (`gui/theme/default_theme_scale`). Entity captions are
set in a font the camera zoom times larger and scaled back down
(`GridEntity._make_caption`), since fonts are rasterised at the viewport's
scale, not the camera's, and would otherwise come out blocky. First launch
is a resizable 1920×1080 window (`Net.DEFAULT_WINDOW_SIZE`); F11 toggles
borderless fullscreen at the monitor's native size
(`Net.toggle_fullscreen`). The windowed size and the mode are saved to
`settings.cfg` (`window_width`, `window_height`, `window_mode`) a moment
after a resize and on every toggle, and applied before the first frame
(`Net._apply_window_settings`); a project run, with no settings file, uses
the defaults each time. Nothing of this on a server or in headless tests.

`--screenshot=<path>` with `--test-exit-after` saves the window as PNG on
exit, for looking at a build without playing it; `--test-hover=<x>,<y>`
parks the cursor over a cell for it, `--test-click=<seconds>` left-clicks
where the cursor is after that long, `--test-azimuth=<degrees>` starts
with the view turned, `--test-yaw=<degrees>` starts the 3D camera yawed,
`--test-fullscreen=<seconds>` toggles
fullscreen as F11 does, and `--test-door=<tick>` works the door the local
player stands beside.

## Grid ↔ screen

`sim/iso.gd` is a fixed-elevation projection of the ground plane (vertical
foreshortened to a half, `Iso.ELEVATION`) turned about the vertical by
`Iso.azimuth`, −45..45 degrees. At 0 it is the diamond-down isometric of
the TileSet, tile 32×16; at ±45 the grid is axis-aligned and a cell an
upright 2:1 rectangle (22.6×11.3 px). With `h = 45° − azimuth`:

```
axis_x = UNIT * (cos h, sin h / 2);  axis_y = UNIT * (-sin h, cos h / 2)   # UNIT = 16√2
local  = (grid + ORIGIN) * [axis_x axis_y]                                 # ORIGIN = (1, 0), the TileSet's layout
tile   = round(inverse(local))
```

At 0 that is `local = ((x − y)·16 + 16, (x + y)·8 + 8)`, which `main.gd`
checks against the TileMapLayer's `map_to_local` at startup. Heights are
vertical and never turn. Everything on the ground goes through `Iso`: the
floor layer (laid out at 0 by its TileSet, so `Main._apply_azimuth` gives
it the change of projection as a transform), wall edges (`WallEdge.
endpoints`, `screen`), door posts and panels, the click ripple, the hover
cell, and every sprite anchor (`GridEntity` places itself from grid
coordinates each frame; `Prediction` keeps its steps in grid units).
Sprites stay upright and Y-sort by projected depth, which is just
position.y. The near/far wall rule reads `Iso.faces_camera`, so it would
follow a wider range; within this one the east and south faces always
point at the camera (edge-on at the limits).

## The 3D view

`client3d/client3d.gd` (`Client3D`). Unless the client asks for the 2D
view (`--renderer=2d`, or `renderer=2d` in `settings.cfg`; the command
line wins, and anything but `2d` is 3D; a server never has a view) Main
hides its 2D ground, walls, entities, cursor,
ripple and toss arrow and adds a `Client3D` under the same tree, so the
net code, the spawner, the entity specs, `settings.cfg` and the parsed map
are the ones the 2D client uses: the 2D entity nodes go on being the
replicated state, unseen, and the 3D view reads them. One tile is one
unit; grid (x, y) is 3D (x, 0, y). No physics bodies: the sim is the
physics; the only collision objects are `Area3D`s for picking.

**Room**, built once from `Terrain.parse` out of the Kenney Castle Kit at
its own proportions (1-unit modules, `KIT_WALL_HEIGHT` 1.31 tall), scaled
in height only to `WALL_HEIGHT` (3): the `ground` piece per floor cell;
`wall-narrow` per wall edge, shifted so its 0.5 thickness straddles the
boundary line; `wall-narrow-corner` at every vertex where walls meet at
an angle or end (none along a straight run, the 2D corner rule);
`wall-doorway` with the kit's `gate` leaf for a door, hinged at the edge's
start and turning with the Door node's state; fire as an emissive quad
and a small orange OmniLight3D. The kit's one material (a colormap) is
reused as is, with a see-through copy for near pieces. Flat-colour boxes
in the kit's stone (`_box`, `_stone`, `STONE`) stay available for interior
walls later (`BOX_WALLS`).

**Near and far**, the 2D rule for this camera (`_is_near`): the cell
behind an edge's camera-facing side is its -x / -y cell when that face
points toward the camera, else the other; the wall is near when that cell
is walkable, and near walls, doorway pieces and posts (a post when all
its walls are) take the `NEAR_ALPHA` (0.3) stone and cast no shadow.
Recomputed whenever the yaw changes. Near pieces blend as ordinary
translucent meshes, so two overlapping ones do stack a little.

**Entities** get a puppet each (`_make_puppet`): a primitive at the scale
table's height (capsule for characters, box, cylinder, sphere, slabs),
coloured as the 2D sprite is (its modulate: tint or the monster's mass
shade), a Label3D name on creatures, a nose on
creatures that turns with `GridEntity.shown_facing` and a lunge toward the
blow on a swing or attack (`GridEntity.swung`), a warm-white
`OmniLight3D` with shadows on players and companions (`PLAYER_LIGHT`, the
same whatever the body's colour), and an `Area3D` of the body's shape for
picking. Puppets follow the 2D nodes every frame through
`Iso.local_to_grid` at azimuth 0.

**Speech bubbles** (`render/speech_bubbles.gd`, on the HUD, the same in
both views and for players and companions): a rounded dark panel at 70%
opacity, light text, a short tail pointing down at the speaker, at most 3
tiles wide with the words wrapped, its tail just above the speaker's name.
It fades in over 100 ms, holds 4 s and 1 s more per 40 characters, and
fades out over 300 ms. A new line from the same speaker replaces their
bubble; different speakers' bubbles are kept clear of each other and of
every speaker's name, nudged sideways when half their width is enough,
otherwise up. Being on the HUD it has no depth test; the view gives each
speaker's screen point (`Client3D.bubble_anchor`, or the 2D node's canvas
position) and the px per tile, and the bubble is set at that size (its
font too, so it stays sharp) as the zoom changes. Last words are a bubble
over the corpse.

**Camera**: `Camera3D` orthographic, `CAMERA_SIZE` 12 units tall (a
1.5-unit character, foreshortened by cos 50°, is a twelfth of the
height), pitched `CAMERA_PITCH` 50° from horizontal by default, on the +x +z side at
yaw 0 so grid +x runs down-right and +y down-left as in the 2D diamond,
kept on the local player exactly, so they are always the middle of the
screen and every turn is about them. The ortho size is `CAMERA_SIZE`
times the **zoom**: the mouse wheel, in either scheme, zooms by
`ZOOM_STEP` (1.1×) a notch, up nearer, between `ZOOM_MIN` (0.8) and
`ZOOM_MAX` (1.4), each step eased (`ZOOM_RATE`, all but done in a quarter
second), on the player (the camera is locked on them); a middle click (the
button let go without a drag, in either scheme) puts it back to 1×. The
zoom is saved as `camera_zoom` (`Net.camera_zoom`, held to that range on
load, `Net.saved_zoom`). The WASD pitch peek pulls the size back a moment
more (`Client3D._apply_size`), and so does the local player's death. The near/far
wall rule reads only the yaw, so the same near walls stay see-through
through any tilt. F3 shows the yaw and the pitch.

**Turning, in both schemes**: the yaw turns freely, all the way round, and
rests only on the diamond views (multiples of `ORBIT_STEP`, 90°, from 0).
Let go, it settles on the next diamond the way it was turning, or back on
the one it set off from if it turned less than `TURN_COMMIT` (10°)
(`Client3D.settle_target`; let go exactly on a diamond, it stays there),
and stays there. That diamond is saved as `camera_yaw` in `settings.cfg`
(`Net.camera_yaw`, 0..360, saved by `Net.save_view_settings`); an older
file's axis yaw (a 45° step) is read as the nearest diamond
(`Net.saved_yaw`). `--test-yaw` alone sets any angle, for screenshots, and
is never saved; a `camera_pitch=` line from older builds is dropped on the
next rewrite.

*Click scheme camera, on the keys* (`Main._drive_camera_keys`, before the
pick): A/D turn while held at `TURN_RATE` (180°/s). The settle starts at
that speed and slows to a stop on the diamond (a cubic, `Ease.FLOW`), so
letting go flows into it: going on, it takes the time a stop from that
speed would (twice the distance over the speed); going back, it runs on
a few degrees, turns and comes back, `TURN_RETURN_EXTRA` (150 ms) longer.
W/S tilt while held at `TILT_RATE` (60°/s; W up toward top-down, S toward
level), between `PITCH_MIN` (40°) and `PITCH_MAX` (85°), slowing over the
last `TILT_EASE_DEGREES` (8°) into either end, and spring back to
`CAMERA_PITCH` (50°) over `TILT_RETURN_SECONDS` (250 ms); the tilt is
never saved. Q/E do nothing, and the middle button only clicks (the zoom
back to 1×).

*WASD scheme camera, on the middle button*: a drag is a turn or a **pitch
peek** by whichever axis it first moves `Main.DRAG_AXIS_PX` (6 px) on, and
stays that until let go. The sideways drag turns the yaw with it
(`Main.DRAG_DEGREES_PER_PX`, 0.25° a pixel), as far round as it goes, and
let go settles as above, the way it was dragged, eased out over
`SETTLE_SECONDS` (250 ms). The pitch peek tilts from 50° toward
`PEEK_PITCH` (85°) in proportion to the drag either way, all of it over
`PEEK_DRAG_PX` (300 px), eased in and out (smoothstep), pulling back to
`PEEK_PULL_BACK` (1.2) times the size as it goes; let go, it springs back
over `PEEK_RETURN_SECONDS` (250 ms), never changing the yaw. Q/E do
nothing.
While any movement key is held the yaw is frozen (`Client3D.frozen`, set
by `Main._drive_wasd`): nothing turns it, not a drag nor an ease under
way, so a direction never changes under the hand; a drag made meanwhile
applies when the keys are let go (eased there, or settled on its diamond
if the button was let go too). The eases are run from `Client3D._process`,
not Tweens, so the camera has moved before Main picks.
Light: a `WorldEnvironment` with near-black background and ambient, one
faint cool `DirectionalLight3D` (`SUN_ENERGY` 0.1) with shadows, the
lanterns, the fires.

**Picking and input.** Input stays in `Main._unhandled_input`, so the 3D
client sends exactly the commands the 2D one does (move, attack, shove
with a drag to toss, door, quick phrases 1–4, R, F3, F11, hold-to-move with
retargeting). Main asks the view for its picks: `entity_under_mouse` and
`door_under_mouse` cast a ray from the camera through the cursor against
the pick `Area3D`s; `mouse_grid` meets the floor plane and Main snaps it
to the nearest walkable cell within three tiles as in 2D. The hover is a
square outline of the cell (`hover`), the click ripple a ring (`ripple`)
and the toss aim during a right drag an arrow (`toss_aim`), all flat on
the floor; the toss drag reads its screen directions from the camera
(`screen_vector`). `--test-yaw=<deg>` starts with the camera yawed, for
screenshots.

**Azimuth.** The 2D projection still takes an azimuth (`Iso.azimuth`),
but nothing turns it any more: the middle-button peek is gone; the 3D
camera turns by Q/E and A/D (click) or a middle drag (WASD). `--test-azimuth=<deg>` starts
with the view turned, for screenshots. F3 shows the angle.

Clicks and hover resolve on the ground plane: `get_global_mouse_position()`
→ `ground.to_local()` → `Iso.local_to_tile()` gives the floor cell under
the cursor, and nothing standing on the map (walls, doors) intercepts
that. A sprite under the cursor comes first with either button
(`_entity_under_mouse`: opaque pixels only, the sprite drawn in front wins,
the local player is skipped): a left click on a creature attacks it, on
anything else walks to its cell (and pushes), whatever cell is under those
pixels. A right click on a sprite shoves it, and a door face under the
cursor toggles the door when the player stands beside it. `main.gd` checks
at startup that `Iso` agrees with the TileMapLayer's own `map_to_local`.

**Move clicks** (`_move_click`). A left click on no sprite walks to the
cell under the cursor when it is floor; off the floor (void, past a wall)
it walks to the nearest walkable cell to the click point, Euclidean on the
ground plane in grid units (`Iso.local_to_grid`, `_snap_to_floor`), within
`Main.SNAP_RANGE` (3) tiles, and is ignored beyond that. Where the player
is going is shown by a ripple (`render/click_ripple.gd`): a ring on the
floor at the target cell's centre, a step lighter than the floor with no
fill, growing from 4 px to a tile across over 250 ms and fading out,
drawn above walls like the hover highlight. One ripple per click. Holding
the button keeps retargeting from `_process` as the cursor moves to other
cells (`_retarget_held`), each new cell with its own ripple; the hover
highlight stays on the cell under the cursor. Pinned in
`tests/respawn_test.gd`. Clicking your own companion walks into her
rather than attacking her (she steps aside; see Companions); a client
knows its own by `GridEntity.keeper_peer`, set in her spawn spec.

## Controls

Two schemes, each a complete package: `controls=click` (the default) or
`controls=wasd` in `settings.cfg`, with `--controls=` overriding it for a
run; read and kept as `renderer=` is (`wasd` picks WASD, anything else is
click). Keys and buttons that are not the active scheme's do nothing, and
the HUD's hint line shows only the active scheme's. In both, 1–4 are
the quick phrases, R, F3 and F11 as ever.

**Click** is the input described above: left click moves or attacks,
hold-to-move retargets, right click (and drag) shoves and tosses, the
verbs land on the clicked target. In 3D, A/D turn the camera freely and
lock it on the next diamond when let go (saved); W/S tilt it while held,
springing back to 50° when let go; the wheel zooms and a middle click puts
the zoom back; Q/E do nothing (see the 3D view). The
camera follows the player alone.

**WASD.** W is up the screen at the current camera yaw, D to its right;
key combinations give eight directions (`Main.wasd_direction`; at yaw 0,
the 2D view's, W is grid (-1, -1)). While a direction is held, the next
step goes as the one on screen ends (`Main._drive_wasd`), with the same
occupancy, edge-wall and push rules as any step; letting go stops on the
cell being entered. The mouse aims: standing still, the body faces the
cursor at once on this screen, and the facing everyone sees follows
(`World.command("face")`, a few times a second at most; `World.face`
turns only a creature that is not mid-step). A sprite under the cursor
still wins any click, as in the click scheme. Otherwise a left click on a
far cell (more than one away) walks there by path until a key is
pressed, with no hold-to-move; a nearer left click attacks the cursor's
way: whoever stands next to the player that way, or a swing at air
(`World.command("swing")` -> `World.order_swing` -> `try_swing`: the
attack's cooldown, facing and lunge, nothing hit). A right click grabs
whoever stands next to the player the cursor's way; a drag from it
tosses, as ever. A sideways middle drag turns the 3D camera, an up or down
one tilts it for a look (see the 3D view); Q/E do nothing. The camera leans toward the cursor.

**One pick a frame.** Main processes after every other node
(`process_priority`), so by then the entities are placed and the 3D
camera has moved; it picks the ground point under the cursor once
(`Main._update_pick`, the 2D camera's scroll forced up to date first)
and the hover square is drawn from that pick. Clicks, which arrive before
the next frame's processing, use the same pick (`_mouse_grid`,
`_mouse_tile`), so the cell a click goes to is the one the square showed.

Test hooks: `--test-walk=<keys:secs,...>` holds keys in turn (and prints
the shown speed frame by frame at exit), `--test-steer=<secs>` steers a
hold-to-move, `--test-lag=<secs>` holds every order that long before
sending it (counted in the round trip).

## Combat readability (3D)

All of it is the 3D view's, from what the server sends; the 2D view has
none of it.

**What the server sends.** A loss of hp goes out with its cause
(`GridEntity.struck(amount, cause)`, relayed by `_net_struck`), an impact
with what was hit (`impacted(amount, against)`: `&"stone"` for a wall,
`&"wood"` for a wooden door, `&"body"` for another body, `&""` when only
fire stopped it), and a death as a message, since the node goes at once:
`World.entity_died` -> `Net.broadcast("death", {entity, tile, kind,
cause, say})`, `kind` one of player, companion, monster or object, `say` a
companion's last line (`Main.COMPANION_DEATH_LINES`).

**HP bars** (`client3d/hp_bar.gdshader`): a thin bar over each creature
with hp, billboarded and drawn over everything, `HP_BAR_PER_HP` wide per
hp of its max (a player's 20 is longer than an imp's 12); its fill is
the hp left, green above half, amber to a quarter, red below. It shows
while the creature is hurt or has been in a fight (hit, swung, pushed, an
impact) in the last `COMBAT_SECONDS` (4), or while Alt is held (read by
Main, `Client3D.show_all_bars`), fading in and out. `hp_bars=0` in
`settings.cfg` turns them off, for later diegetic work.

**Death.** The puppet becomes a corpse (`Client3D._fall`): nothing on it
can be picked and its name and bar go; it tips onto its side over
`FALL_SECONDS` (300 ms) a little too far and back, flashes, drops its
lantern if it has one (which falls to the floor and goes out over 1.2 s),
lies `CORPSE_SECONDS` (8) and sinks into the floor over `SINK_SECONDS`
(1). The sim removed the creature at once, so a corpse never blocks
anything. A companion's last line shows over it. The death message and
the despawn can arrive either way round: a puppet whose entity went is
kept still for `DEPARTED_SECONDS` in case its death follows, and one whose
death came first falls when it goes. The local player's own death pulls
the camera back (`MOURN_PULL_BACK`, 1.4 times) and drains the colour
(`MOURN_SATURATION`) over `MOURN_SECONDS` (3), until they are back, when
both return in half a second. A broken thing (a crate) just breaks, with
a sound.

**Sound** (`client3d/sfx.gd`, `Sfx`): every sound a named set of files
in `art/audio/sfx/`, named by purpose (`swing_1.ogg`, `hit_3.ogg`, ...),
each an unchanged copy of a file from one of Kenney's CC0 packs
(`art/audio/sfx/SOURCES.txt` says which, the packs' licences sit beside
it and ship in the client). The packs themselves stay out of the repo and
the build (`.gitignore`, and a `.gdignore` in each). Played once from a point in the
world on an `SFX` bus, a different file each time where the set has more,
with pitch ±7% and volume -2..+1 dB at random so repeats do not
machine-gun. The listener sits on the ground under the camera's aim (the
ortho camera is 40 units off). What plays, on what:

| Event (from the server) | Set | Copied from |
|---|---|---|
| Swing or attack (`swung`), pitched by the swinger's mass | `swing_1-4` | RPG Audio `cloth1-4` |
| Hp lost to an attack (`struck`, attack) | `hit_1-5` | Impact Sounds `impactPunch_medium_000-004` |
| Impact against a wall | `impact_stone_1-5` | `impactMining_000-004` |
| Impact against wood | `impact_wood_1-5` | `impactWood_heavy_000-004` |
| Impact against a body | `impact_body_1-5` + `impact_body_soft_1-5` | `impactPunch_heavy_000-004` + `impactSoft_heavy_000-004` |
| A crate or other wooden thing broken | `break_1-5` | `impactPlank_medium_000-004` |
| Death of a monster / player / companion | `death_monster_1-5` / `death_player_1-5` / `death_companion_1` | `impactSoft_medium_000-004` / `impactSoft_heavy_000-004` / RPG `dropLeather` |
| A door opened / closed (its replicated state) | `door_open_1-2` / `door_close_1-4` | RPG `doorOpen_1-2` / `doorClose_1-4` |
| A creature's replicated tile moves on by one | `footstep_1-5` (quiet) | `footstep_concrete_000-004` |

Not yet: fire (a crackle loop on fire tiles, a hiss on a burn), grunts on
a body hit, and death cries: neither pack has them. `master_volume=` and
`sfx_volume=` in `settings.cfg` (0..1) set the Master and SFX buses.

## Testing

All sim behaviour is verified headless via `tests/run`, never through the editor.

```
tests/run.ps1        # Windows
tests/run.sh         # anything with a POSIX shell
```

Both run `godot --headless --path . --scene tests/push_test.tscn` from the
project root. Godot is taken from the `GODOT_PATH` environment variable, or
`godot` on `PATH` if that is not set.

The test scene stops `World`'s own clock, builds small ASCII rooms through the
normal `World` API, calls `World.step()` by hand, and checks tiles and damage.
It prints PASS or FAIL per assertion and quits with exit code 1 if any
assertion failed, 0 otherwise.

`tests/state_test.ps1` / `tests/state_test.sh` run a host three times with
`--state`: the first pushes a crate and must write a snapshot without
players; the second must load it with the crate where it was left; the third
starts from a corrupt file and must log it, generate the room fresh, and
replace the file on exit.

`tests/net_test.ps1` / `tests/net_test.sh` start one headless `--server` and
two headless `--client` instances on localhost (port 17777). Each client
orders its player to move (`--test-move`), everything exits on a timer
(`--test-exit-after`), and the script checks the logs: the server spawned two
players, both moved, occupancy was consistent at every move and at exit, each
client saw its own move arrive, and nothing printed an error. Client 1's move
pushes a crate, which must show at its new tile on both clients. Then both
clients order a move into the same free tile on the same tick
(`--test-contest`): each predicts the step, the server gives the tile to one,
and the other must count one misprediction and end up drawn on the server's
tile. The server runs with `--token`; a third client with the wrong token
must be rejected with its address logged, report `authentication failed`,
and never get a player; a fourth joins with no mode argument from a
`settings.cfg` (`--settings`) and must play; a fifth claims another version
(`--test-version`) and must be told `client out of date`.
