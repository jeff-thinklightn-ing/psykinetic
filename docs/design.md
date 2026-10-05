# Psykinetic — design

## Layout

| Path | Contents |
| --- | --- |
| `sim/` | The simulation: `world.gd` (autoload `World`), `grid_entity.gd`, `player.gd`, `monster.gd`, `pushable.gd`, `iso.gd` (grid ↔ pixel math). |
| `entities/` | Entity scenes (`player.tscn`, `monster.tscn`, `pushable.tscn`). Scenes only add visuals and tuning values to a sim script. |
| `art/` | Placeholder SVGs and `tileset.tres` (isometric, diamond-down, 32×16; sources: 0 floor, 1 wall, 2 fire). |
| `net/` | `net.gd` (autoload `Net`): launch mode, ENet setup, the authority gate. |
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
  (built in `GridEntity._init`) sends `tile`, `hp` and `facing`, on change.
  Nothing else.
- *The tick counter*: `World._net_tick`, one RPC per tick.
- *Input*: `World.request_move`, `request_attack`, `request_shove` —
  `@rpc("any_peer", "call_remote", "reliable")`. Each checks that the calling
  peer owns the entity it is ordering (`GridEntity.owner_peer`) and then calls
  the gated `order_move` / `order_attack` / `order_shove`. Input code calls
  `World.command_*`, which is the direct call on the server and the RPC on a
  client. Clients never call `try_move`, `try_attack` or `try_shove`.
- *Feedback*: `GridEntity._net_pushed` / `_net_impacted` replay the hop and
  flash on clients. They carry no sim state.

**Nothing derived is replicated.** A client's `World` is a mirror: it loads
terrain from the same level data, keeps the list of entities the spawner has
created, and rebuilds the occupancy map from their replicated tiles whenever
one changes. Only the `mirror_*` functions write to it, and they refuse to
run on the server. Clients run no `_sim_tick`, no pathfinding for the sim, and
no push resolution.

**Players.** The server spawns one `Player` per peer (and one for itself when
hosting) on the first free tile in `PLAYER_STARTS`, tinted by join order, and
removes it when the peer leaves. A player that dies is respawned at a start
tile 20 ticks later with the same name and tint (a placeholder rule that
keeps the test room usable). `R` on the host rebuilds the room for everyone.

## Tick order

The sim runs at a fixed **10 Hz** (`World.TICK_RATE`), driven by an accumulator
in `World._process`. At most 5 ticks run per frame; past that the sim slows
down rather than spiralling. Every entity gets an **id** at spawn, ascending
in spawn order: the host's own player, then `LEVEL_ENTITIES` in `main.gd` in
order, then players as their peers join. Each tick (`World.step`), on the
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
5. Emit `World.ticked(tick)`.
6. Send the tick counter to clients.

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

Attacks and shoves carry **force** (an int, in tiles). All of this lives in
`World._push` and treats every entity alike — there is no player branch.

**Mass gate (decides whether anything moves).** The mover's mass is a budget.
Each body the push sets in motion spends its own mass from the budget. A body
heavier than what is left does not move: if that is the first target the push
does nothing at all; if it is further down the chain the push ends there.

**Travel.** With `ratio = clamp(mover_mass / body_mass, 0.5, 1.5)`, the body
travels up to `floor(force × ratio)` tiles (at least 1), one tile at a time
along the push direction, until something stops it:

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

**Materials** (`GridEntity.body_material`) decide what impact does:

- `FLESH` — a creature. Takes damage, dies at 0 hp, burns on fire.
- `WOOD` — takes impact damage; breaks at 0 hp and leaves its tile empty.
- `STONE`, `METAL` — never take damage, never break. Pushable if light enough.
- Walls are terrain, not entities: immovable, absorb nothing.

**Forces.** Player attack 2 (plus 2 damage), player shove 3 (no damage),
monster attack 1 (plus 1 damage).

Every push prints one line per body moved:

```
[tick 1] push: Player -> Imp1 dir=(1, 0) tiles=1 impact=6 stopped_by=Imp2 (Imp2 takes 6)
```

and each pushed entity's sprite hops; an impact flashes it for one frame.

## Hazards

Fire is terrain (tile source 2 on the Ground layer). It is walkable. Any
creature (`FLESH`) on a fire tile at the end of a tick takes
`World.FIRE_DAMAGE` (2). Non-creatures slide across it unaffected.

## Behaviours

- **Player** — an action order (attack, shove) waits for the cooldown, fires
  once, and clears. Otherwise follows its move order one step at a time,
  re-running A* each step; the goal tile may be occupied, so clicking a crate
  walks up to it and pushes it. Left click: attack an adjacent creature, else
  move. Right click: shove an adjacent entity.
- **Monster** — targets the nearest player it can see (within `sight_range`
  and in line of sight). Attacks if that player is in melee reach, otherwise
  takes the first step of an A* path toward them. Sees nobody: stands still.
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

On a client the same code runs from mirrored values: `World.tick` is the last
replicated tick and `tick_alpha` counts up locally since it arrived. A client
is not told why a tile changed, so it picks the slide length from the size of
the jump (one step: the entity's step time; more: a push).

## Grid ↔ screen

Diamond-down isometric, tile 32×16:

```
local = ((x - y) * 16 + 16, (x + y) * 8 + 8)          # tile centre
u = (lx - 16) / 16;  v = (ly - 8) / 8
tile = (round((u + v) / 2), round((v - u) / 2))
```

Clicks go `get_global_mouse_position()` → `ground.to_local()` →
`Iso.local_to_tile()`. `main.gd` checks at startup that `Iso` agrees with the
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

`tests/net_test.ps1` / `tests/net_test.sh` start one headless `--server` and
two headless `--client` instances on localhost (port 17777). Each client
orders its player to move (`--test-move`), everything exits on a timer
(`--test-exit-after`), and the script checks the logs: the server spawned two
players, both moved, occupancy was consistent at every move and at exit, each
client saw its own move arrive, and nothing printed an error.
