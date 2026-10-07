# Changelog

Newest first. `tools/release_client.ps1` uses the top section as the release
notes.

## v0.1.26

Docs only; no code change.

- docs/decisions.md records each of v0.1.25's architectural choices on its
  own: the authority polls the network itself (37), the server relay is
  off (38), server sends go peer by peer through `Net.sendable_peers`
  (39), departures come from `Net.peer_left` (40).

The server must be updated to v0.1.26 too, as it refuses any other version.

## v0.1.25

The max-channels flake. Server and client.

- A peer whose ENet link is closing is dropped from the multiplayer
  before the frame's replication pass, and the server relay is off, so
  nothing is sent into a closing link any more: `Unable to send packet on
  channel 0, max channels: 0` is gone from the network test (six clean
  runs where it failed two or three in six).

The server must be updated to v0.1.25 too, as it refuses any other version.

## v0.1.24

Kit walls back; two-wide corridors.

- 3D: walls, posts, doorway, gate and floor are the Kenney kit's own
  pieces again at the kit's proportions, scaled in height only; the
  flat-colour boxes stay available for interior walls later. Everything
  else from step 2 as it was.
- Map: corridors are two cells wide. The west corridor keeps a single-cell
  dead end at (1..2, 8) as the one chokepoint; the links down to the
  passage and the cells inside the door are two wide, with (3, 13)
  walled on its north so the door is still the only way in.

The server must be updated to v0.1.24 too, as it refuses any other version.

## v0.1.23

3D client, step 2. Client only; `--renderer=3d`.

- Kit mapping: flat stone floor in the 2D floor's green-grey; walls as
  plain boxes in the kit's stone at the kit's 0.5 thickness centred on the
  edge, 3 tall; posts at 0.5; the kit's gate leaf scaled to a doorway of
  jambs and lintel; sun down to 0.1.
- Near/far walls as in 2D: the camera-facing side of walkable cells at
  0.3 alpha, recomputed when the camera yaw changes.
- Orbit: Q/E turn the camera 45° about the player, tweened; a middle
  drag nudges up to 45° and springs back; the yaw persists in
  settings.cfg.
- Picking by ray: entity and door colliders first (Area3Ds, no physics
  bodies), then the floor plane, snapped to the nearest walkable cell.
  Hover ring and click ripple as flat rings on the floor.
- Left click move/attack, right drag shove, hold-to-move, keys 1–4, R, F3,
  F11: the same commands the 2D client sends.
- Speech lines as Label3D above the speaker.
- `--test-yaw=<deg>` test hook.

The server must be updated to v0.1.23 too, as it refuses any other version.

## v0.1.22

3D client, step 1: the room. Client only; opt in with `--renderer=3d`.

- A 3D view of the same client: the test room built from the Kenney
  Castle Kit (floor pieces, narrow wall segments on the edges at 3 units,
  corner posts where walls meet or end, the kit's doorway and door leaf,
  fire as an emissive quad with a light), entities as tinted primitives
  at the scale table with Label3D names, lanterns on players and
  companions, a fixed orthographic camera at 50° matching the 2D diamond.
- The default view is unchanged; the renderer is Forward+ explicitly.
- The kit (CC0) ships in `art/kenney-castle/`.

The server must be updated to v0.1.22 too, as it refuses any other version.

## v0.1.21

Peek rotation prototype. Client only.

- The projection takes an azimuth, −45..45°: 0 is the 2:1 diamond view,
  ±45 the axis-aligned view. Floor, walls, doors, ripples, the hover cell
  and every sprite anchor follow it; sprites stay upright and sort by
  projected depth. Near/far walls are classified from the azimuth.
- Middle-button drag turns the view, the full range over about 400 px,
  eased near the limits; release swings it back over 200 ms.
- F3 shows the angle. `--test-azimuth=<deg>` test hook.

The server must be updated to v0.1.21 too, as it refuses any other version.

## v0.1.20

Translucent near walls. Client only.

- Every wall is full height; the occlusion windows and the stub rule are
  gone.
- Walls on the south or east edge of a walkable cell (facing the camera)
  draw at `Main.NEAR_WALL_ALPHA` (0.3); walls on north or west edges draw
  opaque. Interior partitions follow the cell they are the south or east
  edge of.
- Near walls draw as one layer with a single alpha, so where they overlap
  on screen they never stack toward opaque.
- A 1 px darker line along every wall top and up every corner, at the
  wall's alpha.
- Door posts follow the edge they stand on; the panel stays opaque.

The server must be updated to v0.1.20 too, as it refuses any other version.

## v0.1.19

Occlusion windows. Client only.

- Every wall stands full height; the stub rule is gone.
- A creature (player, companion, monster) behind a wall face shows
  through a soft circular window in it, a tile across, centred on its
  sprite: the face fades to 25% at the centre and back to opaque at the
  edge, animating in and out over 150 ms as the creature passes. A
  shader per face, up to eight windows each.
- Doors are unchanged.

The server must be updated to v0.1.19 too, as it refuses any other version.

## v0.1.18

Window and resolution. Client only.

- The project is laid out at a 3840×2160 base viewport (canvas_items
  stretch, expand, hidpi): one to one on a 4K monitor, half-scale at
  1080p. The world and the UI look as before.
- First launch is a resizable 1920×1080 window. F11 toggles borderless
  fullscreen at the monitor's native resolution.
- The windowed size and the mode are kept in settings.cfg (window_width,
  window_height, window_mode) and restored on the next launch.
- Entity name and speech captions are rasterised sharp at the camera zoom.
- `--test-fullscreen=<seconds>` test hook.

The server must be updated to v0.1.18 too, as it refuses any other version.

## v0.1.17

Movement feedback. Client only.

- A move click ripples at the target cell: a ring on the floor, a step
  lighter than the floor, grows from 4 px to a tile across over 250 ms
  and fades. One per click; holding the button retargets as the cursor
  crosses cells, each new cell with its own ripple. The hover highlight
  stays on the cell under the cursor.
- A click off the floor (void, past a wall) goes to the nearest walkable
  cell within three tiles of the click point and ripples there; further
  out it is ignored.
- A click on an entity sprite targets that entity with either button,
  whatever cell is under the pixels.
- `--test-click=<seconds>` test hook.

The server must be updated to v0.1.17 too, as it refuses any other version.

## v0.1.16

Quiet walls. Client only.

- Every wall face is one flat neutral grey (`Main.WALL_VALUE`, 0.18),
  darker than the floor and a few steps above the void, the same whichever
  way it faces: no lit side, no gradient, no blue tint.
- No lit top strip and no end faces; the top of a wall is where the face
  ends. Corners get a 1 px line one step darker than the face.
- No shaded floor beside walls: the floor is one surface up to the wall
  base and stays the brightest thing on screen.
- Stubs follow the same rules at their height. Doors are unchanged.

The server must be updated to v0.1.16 too, as it refuses any other version.

## v0.1.15

Low walls wherever floor is behind them. Client only.

- A wall is a stub whenever a full-height one would hide floor: any
  walkable cell straight behind it within six cells counts, void cells
  between skipped. The walls on the near side of the old thick wall rows,
  which stood full and hid the room behind them, are stubs now. Only walls
  with nothing behind them stand full.

## v0.1.14

- stub rule: south/east edges of walkable cells are stubs

## v0.1.13

Wall tops that join, doors with height. Client only.

- Wall top strips are 4 px ribbons that miter at corners, run through at
  a T with the joining wall butting in, and end square at a free end with
  a short end face. Stubs get the same at their height.
- Doors stand at full wall height between two jamb posts, with a panel
  that swings; a closed door reads as a door, not a plank.
- Outside the map is near-black instead of wall grey.
- The path preview is gone; the hover highlight stays.
- A half-wall off the chamber's north wall, between (5, 1) and (6, 1).

The server must be updated to v0.1.13 too, as it refuses any other version.

## v0.1.12

Walls and picking: thin walls, low near walls, ground-plane clicks, a
path preview. Client only.

- Walls are drawn on the cell boundary with no footprint: a face and a lit
  top strip. Floor draws fully to the base of its walls.
- Walls in front of a floor cell (its south and east edges) are low stubs;
  walls behind stand full height. The fade-to-black ring and the see-through
  wall effect are gone.
- Clicks and hover resolve to the floor cell under the cursor on the
  ground plane; walls, doors and tall sprites never intercept a move. The
  hover highlight shows the target cell even behind a tall wall. A right
  click still picks a sprite to shove, and a door face to open or close
  it from beside it.
- A faint dotted path from you to the hovered cell, through any door on
  the way; it disappears on click.

The server must be updated to v0.1.12 too, as it refuses any other version.

## v0.1.11

Walls on edges, and a door.

- Walls are now the edges between cells, not cells of their own: corridors
  are one cell wide with walls on their sides, the passage two cells with
  walls on the outside. Moving, pushing, sight and melee all respect the
  edge between you and where you are going; diagonals cannot cut a wall
  corner. A body pushed against a wall edge stops there and takes impact as
  before.
- One door, on the south exit of the chamber. Click it from beside it to
  open or close it, or just walk through: creatures open doors on their
  way, monsters included, unless someone stands in the doorway. A crate
  cannot pass a closed door. A door takes impact like a wall and, being
  wood, breaks once its hp is spent.
- Walls are drawn as thin tall faces on the cell boundary with posts at
  ends, corners and door jambs; a face over your own cell fades while it
  covers you. Doors swing open.

The server must be updated to v0.1.11 too; the map format changed.

## v0.1.10

Scale and space pass, placeholder art only.

- Everything drawn has a size in tile heights, from one table: characters
  1.5, walls 3, crates 0.8, barrels 0.9, the boulder 1.2.
- Walls are continuous blocks with a top face; straight runs, corners and
  end caps come from their neighbours. A wall that would hide something
  turns translucent while it does. The floor in front of a wall is shaded.
- The map is 48Ã—36. The room you know is one chamber in it; two corridors
  lead off it, east and south, and bend out of view.
- The camera follows your player with a little lag, and everything beyond
  about 12 tiles fades to black.
- Nothing else: no lighting, no tileset, no sprites.

The server must be updated to v0.1.10 too (the map is server data).

## v0.1.9

No more rubber-banding into a crate that cannot move.

- Clicking a crate that is against a wall (or heavier than you can push,
  or backed by other crates with nowhere to go) made your capsule bounce
  between you and the crate for as long as the order stood. The client now
  applies the same push rule as the server before showing a step, so the
  walk stops beside the crate. The server was never moving you, which is
  why nothing else reacted.
- When the server has given a move order up (a refused step into the
  destination, or no reply at all), the client stops predicting it instead
  of guessing again.

This is a client-only fix, but the server must still be updated to v0.1.9
to accept the client.

## v0.1.8

Anyone can reset the room.

- Press R to rebuild the room from the map: monsters, crates and the
  boulder back in place, dead companions back beside their owners, players
  where they stood. It used to work only when hosting, never on the
  dedicated server. The server logs who did it.
- This is on while the game is being tested; a server started with
  `--no-player-reset` keeps resets to its console.

The server must be updated to v0.1.8 too.

## v0.1.7

Companions come back where their owner is.

- A companion brought back by `reset` was put on its owner's last saved
  tile even when the owner was moved to a safe start tile, which could
  leave it alone among the monsters, out of sight. It now always appears
  beside its owner. The same goes for a living companion whose saved tile
  has a monster within 5 tiles.
- `reset` now says which companions it brought back, or that none were
  dead.

The server must be updated to v0.1.7 too.

## v0.1.6

Smooth movement for everything you do not control, and a way to get a dead
companion back.

- Monsters, companions and other players moved in hops on a client: half a
  tile slid, the rest jumped, then a pause; companions and players simply
  jumped from tile to tile. They now slide evenly, as on a host.
- A companion that died was gone for good. Rebuilding the room (`reset` on
  the server console, or R on a host) now brings dead companions back, at
  full health, beside their owners.

The server must be updated to v0.1.6 too: it refuses clients of any other
version.

## v0.1.5

Fixes a server looking different from a fresh room after an update.

- A server that restored its saved world kept the looks of the build that
  saved it: white crates and a square boulder, where a fresh room had tan
  crates and a round one. Level entities now take their shape, colour, size
  and mass from the current map on every start, and only their position and
  health from the saved world.
- Crates and the boulder saved by an old build keep their place in the
  level, so a second copy no longer respawns on their original tile.

## v0.1.4

Fixes the client closing a few seconds after connecting.

- A client and server built from different code now refuse each other with
  a "build mismatch" message instead of the client crashing. The 0.1.3
  client did exactly that against a newer server.
- Player names show over their capsules, like companions' names.
- Coming back or respawning never puts you next to a monster: if one is
  within 5 tiles you appear on the safest start tile instead. For the first
  3 seconds, or until you move or attack, monsters leave you alone and your
  capsule is drawn faded.
- Companions: the join log now says what happened to yours (new, waiting for
  you, or died earlier). The language-model mind talks to Ollama's native
  endpoint with reasoning off.
- Entities are built from one generic scene, so new kinds of things can be
  added on the server without a client update.
- The boulder is now round.

## v0.1.0

First playable build.

- Isometric grid sim at 10 Hz: eight-direction movement, walking pushes,
  force pushes with impact damage, stun on collision, fire tiles, stamina
  that fades knockback as it runs down.
- Click to walk or attack, right click to shove, drag to toss in a chosen
  direction, including over your own head.
- Multiplayer over ENet with a dedicated Linux server, client-side
  prediction, join tokens, and a world snapshot that survives restarts.
- Self-updating Windows client: `launch.bat` checks GitHub for a newer
  release before starting the game.
