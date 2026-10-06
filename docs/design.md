# Psykinetic — design

## Layout

| Path | Contents |
| --- | --- |
| `sim/` | The simulation: `world.gd` (autoload `World`), `grid_entity.gd`, `player.gd`, `monster.gd`, `pushable.gd`, `iso.gd` (grid ↔ pixel math). |
| `entities/` | Entity scenes (`player.tscn`, `monster.tscn`, `pushable.tscn`). Scenes only add visuals and tuning values to a sim script. |
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
  server calls `spawner.spawn(spec)`; the same `spec` dictionary (scene, name,
  start tile, owner peer, static property overrides) builds the same node on
  every peer, so static configuration is never replicated.
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

**Joining.** A peer is admitted only once it has sent its version and, if
the server has one, the token (`Net.authenticate`, an `any_peer` RPC the
client fires on connect). Unauthenticated peers get no player and their
order RPCs are ignored; a version mismatch, a wrong or empty token, or
nothing within 5 seconds, gets the peer told why (`Net.rejected`),
disconnected, and logged with its address. Up to 4 authenticated peers.
`--server` refuses to start without a token; `--host` without one lets any
matching version in. The version is `version.txt` at the project root. An
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

- *Everything except the local player's own walking* is interpolated one tick
  in the past (`World.NET_DISPLAY_DELAY_TICKS`, the `net_display_delay_ticks`
  setting). A replicated tile change is stamped with the tick it arrived in,
  and its slide starts when the display clock, running one tick behind,
  reaches that tick. The change is therefore always in hand before its slide
  has to begin.
- *The local player's own walking* is predicted (`net/prediction.gd`). On a
  move order the client computes the path on its mirror and starts showing it
  at once, at the normal step timing. Each replicated tile for that player is
  then compared with the steps already shown: if it is the next one, nothing
  happens; if it is anything else, the sprite snaps to the server's tile and
  the predicted path is dropped. A shown step that the server never confirms
  (it refused the move, so no tile change is ever sent) counts as a
  misprediction once it is `RECONCILE_GRACE_TICKS` (4) plus the round trip
  time overdue. Only walking is predicted. Pushes of the local player are
  never predicted, and neither are attacks, shoves, or anything about other
  entities; the server's result always wins.

`F3` toggles a debug overlay: peer id, round trip time (from ENet), and
mispredictions in the last minute.

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
players keep their places), `respawn` brings every dead slot back at once,
`players` lists who is connected, `save` writes the snapshot.

**Persistence.** With `--state=<path>` the authority writes a JSON snapshot
of every level entity (type, name, tile, hp, stamina, facing, spawn
properties) and every player record every 30 ticks and on clean shutdown,
and rebuilds the room's entities and its memory of players from it on start.
Terrain always comes from the ASCII map. A missing or unreadable snapshot is logged and the room is
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
and `... left`. Players cannot attack or shove each other
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
diagonal step takes `ceil(move_ticks × World.DIAGONAL_TICK_SCALE)` (1.5, so 3
ticks against 2 for the player). This keeps world speed roughly constant.
Screen speed still differs by direction, as it does in any 2:1 isometric
view: a sideways diagonal covers 32 px, an orthogonal step 18 px, an up/down
diagonal 16 px.

A diagonal is blocked if either of the two orthogonal neighbours it passes
between is not open floor (wall or off-map). Entities on those neighbours do
not block it. The same rule applies to walking, to bodies being pushed, to A*,
and to melee reach (`World.can_melee`).

Walking into a `pushable` entity shoves it one tile if the chain of pushables
in that direction has total mass ≤ the walker's. This is the original push
rule; it carries no force and causes no impact.

Pathfinding is 8-connected A* in `World.find_path` over walkable terrain minus
occupied tiles, costed in ticks (a diagonal costs 1.5 orthogonal steps). Ties
prefer fewer diagonals, and fire tiles are avoided when a detour of up to five steps exists. Line of
sight is a Bresenham walk blocked by walls and by entities with
`blocks_sight`.

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
| wall (or wall corner, or map edge) | The body takes impact. The wall takes nothing and never moves. |
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

The sim position jumps at the tick; the sprite slides after it.

On a client the same code runs from mirrored values, one tick in the past:
`World.tick` is the last replicated tick and `tick_alpha` counts up locally
since it arrived. A client is not told why a tile changed, so it picks the
slide length from the size of the jump (one step: the entity's step time;
more: a push). The local player's own walking is drawn by the prediction
instead; see Networking.

## Grid ↔ screen

Diamond-down isometric, tile 32×16:

```
local = ((x - y) * 16 + 16, (x + y) * 8 + 8)          # tile centre
u = (lx - 16) / 16;  v = (ly - 8) / 8
tile = (round((u + v) / 2), round((v - u) / 2))
```

A click first looks for an entity whose sprite is under the cursor
(`main.gd`, `_entity_under_mouse`: opaque pixels only, the sprite drawn in
front wins, the local player is skipped) and targets that entity and its
tile. Otherwise it goes `get_global_mouse_position()` → `ground.to_local()` →
`Iso.local_to_tile()`. The hover highlight follows the same rule. `main.gd` checks at startup that `Iso` agrees with the
TileMapLayer's own `map_to_local`.

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
