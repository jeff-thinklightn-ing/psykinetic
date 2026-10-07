# Decisions

Short record of choices that are settled. Add new entries at the bottom; if one
is reversed, say so in a new entry rather than editing the old one.

## 1. 2:1 isometric at 32×16

Tiles are 2:1 diamonds, 32 px wide by 16 px tall (TileSet: isometric,
diamond-down). All art, grid ↔ screen math (`sim/iso.gd`), and the
TileMapLayers assume this size.

## 2. GDScript

All game code is GDScript, targeting Godot 4.7 APIs (`TileMapLayer`, typed
dictionaries). No C#, no GDExtension.

## 3. Host-authoritative discrete grid sim, no continuous physics

The game state is a grid: every entity occupies exactly one tile, and `World`
owns the tile → entity map. Movement is whole-tile steps through
`World.try_move`. There are no physics bodies, no collision shapes, and no
continuous positions in the sim; on-screen motion is interpolation only.

The host is the single authority. All state mutation is gated behind
`multiplayer.is_server()`, from the start, even though there is no networking
yet.

## 4. 10 Hz tick

The sim advances at a fixed 10 ticks per second, independent of frame rate.
Durations in the sim (move time, attack cooldown) are counted in ticks.
Rendering interpolates between ticks.

## 5. Eight directions, uniform step cost, no wall corner-cutting

Entities move in eight directions and a diagonal costs the same ticks as an
orthogonal step. A diagonal may not pass between tiles where either orthogonal
neighbour is a wall; passing between two entities is allowed.

## 6. Pushes: mass decides if, force decides how far

Whether a push moves anything is decided by mass alone: the mover's mass is a
budget spent by each body it sets in motion. How far a body goes and how hard
it lands is decided by force, scaled by `mover_mass / body_mass` clamped to
0.5–1.5. Leftover force becomes impact damage. The push code has no
per-entity-type branches; `body_material` decides what damage means.

## 7. Hits resolve after everyone has acted, in entity id order

Attacks and shoves are queued during the act phase and resolved afterwards in
ascending attacker id. A hit whose target is no longer where it was aimed is
dropped, never re-aimed.

## 8. Diagonal steps take 1.5× the ticks (reverses the cost half of 5)

Uniform step cost made sideways movement on screen nearly twice as fast as
any other direction, and paths that mixed diagonal and orthogonal steps
visibly lurched. A diagonal step now takes `ceil(move_ticks × 1.5)` ticks
(`World.DIAGONAL_TICK_SCALE`), and A* is costed in ticks. Set the constant to
1.0 to get uniform cost back. The corner-cutting rule in 5 is unchanged, and
force pushes are unaffected: force is still counted in tiles.

## 9. ENet, three launch modes, host is the default

Networking is Godot's high-level multiplayer over ENet. `--server`, `--host`
and `--client --address=<ip>` pick the mode; no arguments means `--host`, so
single-player is simply a host with no clients. Default port 7777.

## 10. Replicate state, not results

Only `tile`, `hp` and `facing` per entity, entity creation and removal, and
the tick counter are replicated. Anything that can be derived — occupancy,
paths, static entity configuration, terrain — is rebuilt on the client from
that and from shared level data.

## 11. Clients send intents, never mutations

A client's only way to affect the sim is an order RPC, which the server
accepts only for an entity that peer owns. The authority gate is
`Net.is_authority()`: `multiplayer.is_server()`, and never true in a process
launched as a client.

## 12. No direct friendly fire

Players cannot attack or shove each other. The rule is applied where a hit is
accepted, not in the push code, which still has no per-entity-type branches;
indirect hits (a shoved crate or monster landing on another player) remain.

## 13. Predict only the local player's walking; interpolate the rest

A client shows its own player's move orders immediately and reconciles
against the server's replicated tile: a match changes nothing, a mismatch
snaps to the server and drops the predicted path. Nothing else is predicted —
not pushes, attacks, or other entities. Everything else is drawn one tick in
the past (`World.NET_DISPLAY_DELAY_TICKS`). Prediction is presentation only
and never writes sim state.

## 14. Force comes from strength, and effort costs stamina

Attack and shove force are no longer fixed numbers. Force is derived from
the attacker's strength and the mass ratio; a shove costs stamina, a tired
shover pushes less, and an exhausted entity cannot push and is easier to
push. One set of rules for every entity. Stamina is shown on the body, not
on a bar, and joins `tile`, `hp` and `facing` as replicated state (amending
10) because clients need it to draw that.

## 15. The server persists entities, not the room, as JSON

A dedicated server keeps a JSON snapshot of its level entities and restores
them on start; terrain is regenerated from the map and players are never
saved. Anything unreadable is logged and ignored rather than fatal. The
server itself is a Dedicated Server export run as a systemd service on a
Linux box (`docs/server.md`).

## 16. Players are identified by a client-made UUID

A client mints a `player_id` on first run and keeps it in `settings.cfg`;
the server remembers each id (tile, stats, colour, name) in the snapshot and
puts a returning player back as they were. No accounts, no passwords: the
join token guards the server, the id only says which player you are. One
connection per id at a time.

## 17. Level entities respawn by slot, away from players

The level's spawn table is the source of truth for what should exist. A
dead slot comes back on its own tile at full stats after a delay, but never
while a player is nearby, so nothing appears on top of someone. Pushed
things are alive and stay put. The server console is a localhost TCP port
under systemd (stdin is closed there), stdin elsewhere.

## 18. Mispredictions blend; only big ones snap (amends 13)

Prediction plans against the replicated world and re-checks each step as
it starts, so two players rarely predict into each other. When the server
still disagrees, an error of up to 2 tiles is blended away over 2 ticks and
re-planned from the server's tile; more than that snaps. A refused step is
reported to the client at once. Other entities are drawn 2 ticks behind
(`display_delay` in `settings.cfg`): 100 ms for no stutter.

## 19. A companion's mind only answers; the sim acts

Companions are ordinary entities under every existing rule, owned by a
player record and saved with it. Their behaviour is an intent chosen by a
mind — scripted, or a language model over HTTP — which can only return
`{intent, target, say}`. The sim validates that and carries it out through
the same calls everything else uses; the mind never moves anything or deals
damage, and a missing, late or malformed answer means the scripted answer.

## 20. A snapshot says where things are, not what they are

On load a level entity is rebuilt from its slot in the spawn table as the
map says now — script, shape, tint, scale, properties — and takes only its
tile, hp, stamina and facing from the snapshot. A server that restores an
old file after a deploy would otherwise keep showing the old build's crates
and boulder for ever, and differ from a fresh room for no visible reason.
Snapshots from before slots are matched to the table by name.

## 21. A mirror's slides are queued, never replaced

A client draws other entities two ticks late, so the next step of a walk
arrives while the slide for the previous one is half shown. Each tile change
is queued with its arrival tick and shown when the delayed clock gets there.
Overwriting the current slide instead made every walk a series of hops: half
a tile slid, the rest jumped, then a pause. Sampled in `tests/mirror_test`.

## 22. A dead companion returns only with a rebuilt room

Death still costs something: the companion stays dead across reconnects and
server restarts. Rebuilding the room (`reset`, `R` on a host) starts whole,
companions included. Before this there was no way to get one back at all.

## 23. While testing, any player may reset the room

The live server is headless, so nobody is ever its host and `R` did nothing
there; a reset needed a shell on the box. `R` is now a player command the
authority honours from anyone. It rides the generic command RPC, so it adds
nothing to the protocol. This is a testing convenience, not a rule of the
game: `--no-player-reset` turns it off.

## 24. The prediction applies the server's step rule, then gives up like it

A predicted step must be one the server would make: the client checks the
same things World._shift does, read off the replicated world, including
whether a crate has anywhere to go. And when the server has dropped a move
order (a refused step into the destination, or silence past the deadline),
the client drops it too. Guessing again after a correction is how a sprite
ends up bouncing between the same guess and the same correction.

## 25. One size table; walls drawn, not tiled

Sizes live in `Iso.HEIGHTS`, in tile heights, and nowhere else; sprites and
wall blocks are scaled to it at build time. Walls are drawn per tile from
their neighbours instead of being picked from a tileset, so continuous
walls, corners and end caps need no art and no autotile rules, and a wall
that would hide something goes translucent while it does. Placeholder only:
no lighting, no tileset, no sprites yet.

## 26. Walls are edges between cells

A wall used to be a cell nothing could enter. Now every cell is floor (or
nothing) and blocking belongs to the edge you cross: wall, door, or open.
Corridors are one cell wide with walls on their sides instead of three
cells of wall-floor-wall; a door is a wall with a state, on an edge, and
needs no cell of its own. The map is written at double resolution so edges
have a place to be written. The old chamber kept its coordinates: its wall
cells became nothing, walled on their sides, rather than being removed,
which would have moved every tested tile. Blocking, pushes, sight, melee
reach and pathfinding all read the same edge rule; a diagonal needs every
edge around its corner open. Door state is not saved.

## 27. Near walls are stubs; clicks hit the ground

A tall wall between the camera and a cell hides the cell. Rather than
fading or cutting walls away, the wall in front of a floor cell (the
south and east edges of walkable cells in this projection) is drawn as a
stub a third of a tile tall and the wall behind it at full height. It is a
drawing rule per edge; the sim never knows. With that, clicks and hover
read the ground plane only, so the target cell is always the one under the
cursor, highlighted and previewed above whatever stands in front of it.
Only a right click still picks a sprite or a door, for shoving and doors.

## 28. Wall tops are ribbons that join; doors stand full height

A wall's lit top is a 4 px ribbon on its far side, so corners can miter in
plan and a T can butt, and joins are decided per end from the vertex's
other walls, not from tiles. A door is a wall-height object (posts and a
swinging panel) even between stubs, so a closed door reads as a door and
not a plank. Outside the map is near-black. The path preview is gone: the
hover highlight alone says where a click goes.

## 29. Walls are the quietest thing on screen

Every wall face is one flat neutral grey, `Main.WALL_VALUE`, with no lit
side, no top ribbon, no end face and no shadow on the floor beside it; the
only mark beyond the face itself is a 1 px darker line up a corner. The
floor stays the brightest surface, so the eye lands on where play happens,
not on the walls around it. The ribbons and joins of decision 28 are gone;
the door keeps its own top strip, since a swinging panel needs to show its
thickness. The value is one constant so it can be tuned without a release
of its own.

## 30. A move click answers with a ripple and lands on floor

A move click draws a ring where the player is going instead of marking
the target cell statically, so the answer is seen once and then gets out
of the way; the hover highlight alone stays. A click off the floor goes to
the nearest walkable cell within three tiles and ripples there, so a click
past a wall or into the void still does something sensible and shows what
it did; further out it does nothing. A sprite under the cursor takes the
click first with either button, so a tall body is never clicked through
to the cell behind it. A held button retargets as the cursor crosses
cells. Client only: the server sees ordinary move commands.

## 31. A 4K base viewport, half-scale by default

The project is laid out at 3840×2160 with `canvas_items` stretch, so a 4K
monitor gets the base one to one and a 1080p window exactly half; the
camera zoom (6) and the theme scale (×3) are chosen so the world and the UI
look as they did at the old 1152×648 base. First launch is a 1920×1080
window; F11 is borderless fullscreen at the monitor's own size, never
exclusive, and the window as last left is kept in `settings.cfg` with the
rest of the client's settings rather than in a second file.

## 32. Full walls with occlusion windows, not stubs

Every wall stands full height, and a creature behind a face shows through
a soft window in it, centred on its sprite and a tile across, that fades
in and out as it passes. The stub rule (decisions 27 and its later forms)
is gone: it lowered walls by a map rule and still hid whatever was deep in
a wall's shadow, while a window follows the one thing that matters, the
creature. It is per face, in a shader with up to eight centres, so a crowd
behind a wall costs nothing more. Doors are unchanged.

## 33. Near walls are translucent; stubs and windows are gone

Every wall is full height. A wall on the south or east edge of a walkable
cell is drawn at one low alpha and the rest opaque: the camera-facing side
of a room or corridor is see-through, its back solid. Stubs (27) lowered
walls by a map rule; windows (32) followed creatures with a shader; both
are reverted for this one rule, which is cheaper and reads the same
everywhere. The near walls are one CanvasGroup with the alpha on the
group, not on each face, so overlapping near faces never add up. Doors
follow the edge they sit on but keep an opaque panel.

## 34. The projection is one function of an azimuth

`Iso` is no longer a fixed 2:1 formula but a projection parameterised by
an azimuth, with the diamond view at 0 and the axis-aligned view at ±45,
and everything on the ground is drawn through it, including the floor
layer, which gets the change as a transform rather than a second tileset.
Prediction steps and entity slides are kept in grid units so the view can
turn under a moving sprite. A middle-button peek drag is the first use;
the sim is untouched. A prototype, to find out whether a turnable view
earns its place before anything is built on it.

## 35. The 3D view is a second drawing of the same client, not a second client

`--renderer=3d` adds a `Client3D` under Main and hides the 2D drawing; the
2D entity nodes stay as the replicated state and the 3D puppets read them.
Nothing in the net code, the spawner, the specs or the settings file knows
which view is up, so the two cannot drift apart, and a 2D client is
untouched by the 3D one. The room is assembled from the Kenney Castle Kit
by the same edge and corner rules the 2D renderer uses. The sim is the
physics: no physics bodies anywhere in the 3D scene.

## 36. The 3D client's input is the 2D client's input

Main keeps the one input handler and asks whichever view is up for its
picks (entity, door, ground point) and tells it what to draw (hover,
ripple); the view never sends a command. So the two clients cannot send
different things for the same click, and a rule such as snap-to-floor
lives in one place. The 3D walls are plain boxes in the kit's stone
rather than kit wall pieces: the kit is an exterior castle kit and its
walls carry battlements and walkways that read wrong indoors.
