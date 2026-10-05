# Psykinetic — design

## Layout

| Path | Contents |
| --- | --- |
| `sim/` | The simulation: `world.gd` (autoload `World`), `grid_entity.gd`, `player.gd`, `monster.gd`, `pushable.gd`, `iso.gd` (grid ↔ pixel math). |
| `entities/` | Entity scenes (`player.tscn`, `monster.tscn`, `pushable.tscn`). Scenes only add visuals and tuning values to a sim script. |
| `art/` | Placeholder SVGs and `tileset.tres` (isometric, diamond-down, 32×16). |
| `main.tscn`, `main.gd` | Test level, camera, HUD, and click input. View/input glue only. |

## The rule: no Node mutates position directly

The grid is the truth. An entity *is* at `GridEntity.tile`; `Node2D.position` is
only a picture of that.

- **`World` owns tile occupancy** (`tile → entity`) and is the only thing that
  changes an entity's tile. The single entry point for movement is
  `World.try_move(entity, direction)`. Pushing is part of that call: the mover
  may shove a chain of `pushable` entities whose total mass does not exceed
  its own.
- **Nobody writes `position`** (or `global_position`, or tweens it) on a
  `GridEntity`. The one exception is `GridEntity._process`, which derives
  `position` from sim state every frame for rendering.
- **Nobody writes `tile`** except `World`, through the `_world_*` hooks on
  `GridEntity`. Those hooks are not to be called from anywhere else.
- Entities act by *asking*: `World.try_move`, `World.try_attack`. Input acts by
  asking too: `World.order_move(player, tile)`.
- Other sim state (hp, cooldowns, orders) changes only inside `World` or
  inside `_sim_tick()`, which `World` calls.

## Server gate

Every mutating function in `World` starts with
`if not multiplayer.is_server(): return`, and the tick loop itself does not run
on a non-server peer. There is no networking yet, so `is_server()` is always
true (Godot's offline peer), but the shape is already host-authoritative:
clients will send intents (`order_move`) to the host and receive state, never
mutate it.

`World`'s query functions (`is_walkable`, `get_entity_at`, `find_path`,
`has_line_of_sight`, …) are read-only and safe to call anywhere.

## Tick order

The sim runs at a fixed **10 Hz** (`World.TICK_RATE`), driven by an accumulator
in `World._process`. At most 5 ticks run per frame; past that the sim slows
down rather than spiralling. Each tick (`World._step`):

1. `tick += 1`.
2. For each entity **in spawn order** (the order of nodes under
   `YSort/Entities` in `main.tscn`), call `entity._sim_tick()`. The entity
   reads the world, decides, and calls `World.try_move` / `World.try_attack`.
   Each call resolves immediately, so later entities see earlier entities'
   results within the same tick:
   - `try_move`: check cooldown → check target tile is walkable → resolve the
     push chain front-to-back → update occupancy → set the mover's cooldown.
   - `try_attack`: check cooldown and adjacency → apply damage → despawn the
     target at 0 hp (removed from occupancy immediately, node freed at end of
     frame).
3. Emit `World.ticked(tick)`.

Input (`order_move`) is applied when it arrives and is picked up by the
player's next `_sim_tick`.

Current behaviours:

- **Player** — follows its move order one step at a time, re-running A* each
  step. The goal tile may be occupied, so clicking a crate walks up to it and
  pushes it.
- **Monster** — if adjacent to the player, attacks; otherwise, if the player
  is within `sight_range` and in line of sight, takes the first step of an A*
  path toward them. Otherwise it stands still.
- **Pushable** — never acts.

## Rendering between ticks

`World.tick_alpha` is the fraction of the current tick that has elapsed
(0 ≤ α < 1). When `World` moves an entity it records the tile it left, the
tick, and the step duration in ticks (`move_ticks` of whoever initiated the
move, so pushed objects slide in step with the pusher). Each frame:

```
t        = clamp((World.tick + World.tick_alpha - move_tick) / move_duration, 0, 1)
position = lerp(Iso.tile_to_local(from_tile), Iso.tile_to_local(tile), t)
```

The sim position jumps at the tick; the sprite slides and arrives exactly when
the move cooldown ends, so continuous walking looks continuous.

## Grid ↔ screen

Diamond-down isometric, tile 32×16. With `h = (16, 8)`:

```
local = ((x - y) * 16 + 16, (x + y) * 8 + 8)          # tile centre
u = (lx - 16) / 16;  v = (ly - 8) / 8
tile = (round((u + v) / 2), round((v - u) / 2))
```

Clicks go `get_global_mouse_position()` → `ground.to_local()` →
`Iso.local_to_tile()`. `main.gd` checks at startup that `Iso` agrees with the
TileMapLayer's own `map_to_local`.

Pathfinding is 4-connected A* (Manhattan heuristic) in `World.find_path`,
over walkable terrain minus occupied tiles. Line of sight is a Bresenham walk
blocked by walls and by entities with `blocks_sight`.

## GridEntity data

`mass` (push rule), `body_material` (`FLESH/WOOD/STONE/METAL`; stored, not yet
used by any rule — named `body_material` because `CanvasItem.material` is
taken), `tile`, plus `pushable`, `blocks_sight`, `move_ticks`, `max_hp`
(0 = indestructible), `attack_damage`, `attack_ticks`.
