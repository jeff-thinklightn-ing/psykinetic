# Psykinetic — design

## Layout

| Path | Contents |
| --- | --- |
| `sim/` | The simulation: `world.gd` (autoload `World`), `grid_entity.gd`, `player.gd`, `monster.gd`, `pushable.gd`, `terrain.gd` (the map format: cells and edges), `door.gd` (a door on an edge), `iso.gd` (grid ↔ pixel math). |
| `render/` | Drawing only, never sim state: `wall_edge.gd` (a wall edge as one flat face, near ones translucent), `click_ripple.gd` (the ring that answers a move click). |
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
first packet one of them cannot read. An
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

**Contested tiles are decided once.** When two orders want the same tile in
the same tick the act phase resolves them in entity id order: the first
gets it and the second's `try_move` fails. The loser is sent
`move_refused`. If the refused tile was its destination the order is
dropped; if it was a tile on the way, the order stays and is re-pathed
around next tick.

`F3` toggles a debug overlay: peer id, round trip time (from ENet),
mispredictions in the last minute, and snaps in the last minute.

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
diagonal step takes `ceil(move_ticks × World.DIAGONAL_TICK_SCALE)` (1.5, so 3
ticks against 2 for the player). This keeps world speed roughly constant.
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
**intent** (`FOLLOW`, `HOLD`, `ATTACK`, `SHOVE`, `RETREAT`, `IDLE`) with a
target entity or hold tile, and each tick the sim carries that intent out
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

**The mind never acts.** This is a hard rule. A `CompanionMind`
(`sim/companion_mind.gd`) is asked `decide(context) -> {intent, target,
say}` and nothing else: it never sets a position, deals damage, or touches
any sim state. The companion validates the answer — the intent against the
whitelist, the target against the live world — and anything that does not
hold up becomes `FOLLOW` and is logged. A decision window opens every 30
ticks, or at once when the owner is hurt, the companion is hurt or pushed, a
hostile first comes into line of sight, or an order arrives. The context is
the personality card, the last 20 party-log sentences, nearby entities with
offsets and types, own and owner hp and stamina, the owner's last order and
the current intent.

Two minds. `ScriptedMind`: obey the last order; retreat toward the owner
below 30% hp; attack the nearest hostile within 3 tiles; else follow. It is
what every headless test uses and the fallback for everything else.
`OllamaMind` (`net/ollama_mind.gd`): an asynchronous POST to Ollama's native
chat endpoint (`--llm-model`, and `--llm-url` if it is not the local default
`http://127.0.0.1:11434/api/chat`; or the env file). The body is `model`,
`"think": false`, `"stream": false`, `"format": "json"`, `"keep_alive": -1`
and the messages: a system prompt demanding one JSON object, then the
context. The answer is read from `message.content`, with any `<think>` block
stripped first in case a model reasons anyway. A URL ending in
`/chat/completions` is spoken to OpenAI-style instead (no `format` or
`keep_alive`; the answer read from `choices[0].message.content`). A 2-second
timeout and one request in flight per companion. A window that has no answer yet
uses the scripted one; the reply is applied when it arrives, if it parses.
The tick never waits.

**Party log** (`sim/party_log.gd`): the server keeps the last 200
plain-English sentences — pushes, impacts, damage, deaths, fire, orders,
joins and leaves — naming players by record name and companions by name.

`--no-companions` turns companions off for a server or host. The network
and snapshot tests use it so that their choreography stays deterministic;
`tests/companion_test.tscn` covers companions themselves.

**Orders.** Keys 1–9 send `World.command("order", {slot})`; the server maps
1 follow, 2 hold here, 3 attack my current target (or the nearest monster),
4 fall back, and ignores 5–9. An order is logged and opens a decision
window. **Speech**: a mind's `say` is broadcast as `Net.message("speech",
{entity, text})` and shown over the sprite for a moment, at most one line
per companion per 5 seconds. Console: `companions` lists each with owner,
intent and which mind answered last; `mind scripted|ollama` switches live.

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
nothing, with walls on its edges, so the west corridor is one cell wide
walled on both sides and the two-wide passage is two cells walled on the
outside) plus two corridors that bend out of view, the south one through
a door at the edge above (4, 13), and one half-wall off the north wall
between (5, 1) and (6, 1), there so a T and a free end exist. Every tile
the tests use is where it was.
Test rooms written as old cell maps go through `Terrain.expand`.

**Camera.** The camera eases toward the local player
(`CAMERA_FOLLOW_RATE`), starting on `CHAMBER_CENTRE`. The hover highlight
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
where the cursor is after that long, `--test-fullscreen=<seconds>` toggles
fullscreen as F11 does, and `--test-door=<tick>` works the door the local
player stands beside.

## Grid ↔ screen

Diamond-down isometric, tile 32×16:

```
local = ((x - y) * 16 + 16, (x + y) * 8 + 8)          # tile centre
u = (lx - 16) / 16;  v = (ly - 8) / 8
tile = (round((u + v) / 2), round((v - u) / 2))
```

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
`tests/respawn_test.gd`.

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
