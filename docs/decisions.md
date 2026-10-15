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

## 37. The authority polls the network itself

On the server (and a host) `SceneTree.multiplayer_poll` is off and
`Net._process` does the poll: the ENet poll, then every listed peer whose
link has no channels is dropped from the multiplayer by raising its
`peer_disconnected` early (`Net._drop`; ENet's own event later is
swallowed), then `multiplayer.poll()` with the replication pass. ENet
frees a peer's channels the moment a disconnect starts, up to a round trip
before Godot reports the peer gone, and any send in that window logs
`max channels: 0`. Dropping the peer before the replication pass is one
rule that covers every sender (synchronizers, spawner, RPCs) instead of
gating each; hiding synchronizers from a leaving peer was tried and does
not work, since hiding sends a despawn. Net's `_process` runs before every
other node's, so the frame's RPCs never see a dropped peer.

## 38. The server relay is off

`SceneMultiplayer.server_relay = false`. Clients only ever talk to the
server (every client RPC is `rpc_id(1, ...)`, every `get_peers()` is
server-side), so the relay bought nothing, and its announcements of one
peer's coming and going to the others were the main sender into closing
links. A feature that needs client-to-client traffic goes through a
server RPC, where it is gated like any other.

## 39. Server sends go peer by peer through `Net.sendable_peers`

No server RPC is broadcast with a bare `.rpc()`: the tick, messages, the
pushed/impacted/stunned effects and `move_refused` go with `rpc_id` to each
of `Net.sendable_peers()`, which skips peers a rejection has marked as
leaving and any whose link has no channels. One place decides who may be
sent to, between the poll's drop and a disconnect started mid-frame.

## 40. Departures come from `Net.peer_left`

Main and anything else that reacts to a player going listens to
`Net.peer_left`, emitted once per peer, not to the multiplayer's
`peer_disconnected`, which fires twice for a peer dropped early (once from
`Net._drop`, once from ENet).

## 41. The 3D view is the default; 2D is the opt-out

A client shows the 3D view unless it asks for the 2D one with
`--renderer=2d` or `renderer=2d` in `settings.cfg`; any other value, or
none, is 3D, so a typo lands on the view being developed rather than on
the old one. The command line wins over the file for that run only: a
rewrite of the file (window resize, F11, orbit) writes back the file's own
`renderer=` line, so a one-off `--renderer` never changes what the next
plain launch shows. Main also never builds the view on a server, headless
or not.

## 42. WASD sends steps, not the held direction

The spec was to send the held direction every tick as the move intent.
Under latency that cannot line up with what the client shows: the server
would take whatever extra steps fall due between the client letting go
and the release arriving, and a mispredict on every stop. So the client
sends one step each time its walk is ready for the next (the moment the
held direction is read, on the same timer), and the server takes the
queued steps in order on its own timer, with every rule a step has. A
refused shown step bumps a refusal count that later steps must carry, so
steps in flight when the client gave a walk up are dropped, not walked.

## 43. The movement timer carries fractions of a tick

Step times and `next_move_tick` are floats, and a step taken late by a
fraction of a tick (it was due at 12.5, the tick is 13) is drawn from when
it was due and times the next from there. The tick stays 10 Hz; walk
speeds need not be whole ticks per cell, and the player walks four cells
a second. Drawing never eases at the ends of a step, so one step joins
the next.

## 44. A move order carries the steps its client already shows

`request_move` has a `via` list: the shown, unconfirmed steps. The server
walks those first. This was the cause of the 3D client's mispredictions:
re-targeting while a shown step was not yet taken on the server let the
server set off from the tile before it. The server still checks every
via step as a step; a via tile that is no longer one step away is dropped.

## 45. A companion's owner is known on every peer

The companion's spawn spec carries `keeper_peer`. It decides nothing on
the server (orders still go by `keeper`); it lets a client treat a click
on its own companion as walking into her, not attacking her.

## 46. Bumping a companion is a mind decision with a scripted deadline

Walking into your own companion asks her mind at once, with the bump in
the context, and YIELD is an intent like any other, validated and carried
out by the companion. The scripted mind yields; a slower mind gets one
decision window, after which the scripted answer applies if there is
room. The player is never moved through her and she is never moved by the
bump itself: getting out of the way is her decision.

## 47. The camera leads by the cursor's place on screen

The lead toward the cursor is a share of the cursor's offset from the
middle of the screen, not from the player: the camera moving does not
move the thing it chases, so it settles instead of running off. Both
views use `Main.camera_lead`.

## 48. Q/E are the only camera rotation

The middle-button peek (2D) and nudge (3D) are removed. `Iso.azimuth`
stays, for `--test-azimuth`.

## 49. Control schemes are complete packages; click is the default

`controls=click` (the default) is click and hold-to-move, Q/E to turn
the camera, the verbs on the clicked target. `controls=wasd` is WASD to
walk, the mouse to aim, a middle drag to turn the camera, the cursor
lean. Whatever is not the active scheme's is inert, and the HUD names
only its controls. This replaces 48: Q/E are no longer the only rotation;
in WASD the middle drag is.

## 50. The camera never turns under a held movement key

WASD directions are camera-relative, so a yaw change while a key is held
would turn the walk. While any movement key is held the yaw is frozen,
eases included; a drag made meanwhile applies when the keys are let go.

## 51. The lean is the cursor's place on the screen, in WASD only

This replaces 47. The lean is the cursor's offset from the middle of the
screen, normalised, past a dead zone, laid on the ground along the
screen's own axes: nothing about the world goes in, so the camera moving
cannot feed back into it. In the click scheme there is no lean.

## 52. One pick a frame, after the camera moves

Main processes last (`process_priority`), picks the ground point under
the cursor once, draws the hover from it, and clicks use that pick. The
square on screen and the cell a click goes to are the same by
construction. The 3D yaw eases run in the view's `_process` rather than
Tweens so they are done before the pick.

## 53. Engine-generated files come from the dev machine, never the box

A script's `.uid` is committed in the same commit as the script:
`ship.ps1` imports headless before committing and refuses a script
without one. On the box `deploy.sh` (and `ship.ps1`'s pull before it)
first removes untracked `.uid` and `.import` files, pulls, and only then
imports, so a file the box generated can never block a pull, and the box
never generates one before the repo's copy arrives.

## 54. The camera rests only on the diamond views

The four resting yaws are 0 (the 2D diamond) and each 90° from it. Q/E
go from one to the next in one 400 ms ease, through the axis-aligned view
without stopping; a WASD middle drag still turns through any angle while
held and settles on the nearest diamond when let go. The saved yaw is
always a diamond, and an axis yaw saved by an older build is read as the
nearest one (half way, the higher). The axis view reads poorly for this
map: walls run straight across the screen and the near ones cover the
cells behind them edge-on.

## 55. The click scheme's middle drag is a peek

In the click scheme the middle button turns the camera only for a look:
up to 45° either side of the resting diamond while held, back to the same
diamond when let go, nothing saved. Q/E remain the only way to change the
resting view there. The WASD scheme's middle drag is unchanged: a short
one already falls back to its diamond. This amends 49, which had the
middle button inert in the click scheme.

## 56. The peek is a pitch peek

This replaces 55. A vertical middle drag tilts the camera toward top-down
and pulls it back a little, for a look round, and springs back when let
go; it never touches the yaw and saves nothing. The click scheme has only
this on the middle button (the horizontal peek is gone: Q/E are its only
turn). In WASD a middle drag locks to the axis it first moves on: across
is the turn, up and down the pitch peek, so one gesture never does both.
The pitch is the camera's alone; picking, the near/far wall rule and the
WASD directions read the yaw, so none of them changes during a tilt.

## 57. The click scheme's camera is on the keys

The click scheme leaves WASD free, so they drive its camera: W/S tilt
(sticky, saved), A/D turn (settling on a diamond), and a middle click
levels the tilt. Q/E and middle drags are unbound there. This replaces
the click-scheme part of 56 (its middle-drag pitch peek) and 49's Q/E
step. The resting pitch is now a setting, 40-85°, saved with the yaw, and
the ortho size follows it; the WASD scheme's pitch peek springs back to
that resting pitch. The WASD scheme is otherwise unchanged: its keys
walk, and the middle button turns and peeks.

## 58. A/D turns commit by direction and settle at the turning speed

In the click scheme Q/E are back (a 400 ms step between diamonds) beside
A/D, which turn at 180°/s. Let go, an A/D turn does not snap to the
nearest diamond: it goes on to the next one the way it was turning once
it is 10° past the last diamond it passed, and back otherwise, so a
short tap still commits and a slip does not. The settle starts at the
turning speed and slows to a stop, so release never stops the camera
and starts it again; going back it runs on a little before it turns.
This amends 57, which left Q/E unbound and settled A/D on the nearest
diamond in a fixed 250 ms. The WASD scheme's middle drag keeps its
nearest-diamond settle, and its vertical drag stays a springy peek.

## 59. Q/E are relative to the character, A/D to the screen

Q means look to my left, E to my right: left and right of the local
player's heading, not of the screen. Of the two 90° steps to a
neighbouring diamond, Q/E take the one that brings that side of the
character nearer the top of the screen, the far side of the view, so the
passage it is about to turn into comes into view from wherever the camera
was. The choice is between the two steps, not against staying, since in a
diamond view an orthogonal side is always 45° off the top either way.
A/D stay screen-fixed for free sweeping. Heading is the shown step while
walking, else the replicated facing, which a blow sets too.

## 60. Click scheme: W/S zoom, Q/E tilt, A/D turn

The click scheme's camera keys are remapped: W/S zoom on the player
(0.6-2×, sticky, saved), Q/E tilt (40-85°, sticky, saved), A/D turn as in
58, and a middle click resets tilt and zoom. Zoom is its own control, so
the tilt no longer pulls the camera back; only the WASD pitch peek, which
is unchanged, still pulls back while held. The Q/E 90° step and the
character-relative Q/E (59) are gone. This replaces 59 and the key map
of 57 and 58.

## 61. Combat feedback is driven by what the server says, in the view

Bars, corpses and sounds are the 3D view's, and every one of them is
keyed to a server event or replicated state: hp, the relayed blow with
its cause (`struck`), the impact with what it hit, the swing, a door's
open state, a tile change, and a death message. A death is a message
rather than a node RPC because the node is despawned in the same moment;
the view keeps a gone puppet a moment so either can come first. The sim
is untouched: a dead creature leaves occupancy at once, so corpses are
pictures, never obstacles.

## 62. The settings file keeps what the game does not write

`save_settings` writes the keys it owns and then every other line it read
from the file, as it was. Options a player sets by hand (`hp_bars=`,
`master_volume=`, `sfx_volume=`, and anything a later build adds) survive
the rewrite on a resize or a camera change.

## 63. Click scheme: W/S tilt, Q/E zoom

The pairs of 60 are swapped: W/S tilt (W toward top-down, S toward
level), Q/E zoom (Q out, E in). A/D, the middle click and everything
else are as in 60.

## 64. The camera is kept close to home

The yaw stays within a quarter turn of home (yaw 0, the 2D diamond) in
both schemes, resting on home or a diamond either side; A/D and the WASD
middle drag stop at the ends of that range. The click scheme's W/S tilt
is a held look that springs back to 50° when let go, like the WASD pitch
peek, and nothing about it is saved. Zoom is gone, Q/E are unbound and
the middle click does nothing. This replaces 54's four resting diamonds
and the sticky tilt and zoom of 60 and 63. Home is yaw 0 rather than the
yaw a session started at, so the range never drifts from launch to
launch.

## 65. The click scheme's camera home follows the character

There is no fixed home. In the click scheme the camera's resting yaw is
the diamond that puts the player's heading nearest the top of the
screen, so the way ahead is the far side of the view, and it is damped
so it never wanders: a heading must be walked for 0.7 s, turns are 1.5 s
apart at least and take 1 s, it never turns standing, and a heading half
way between two diamonds keeps the one it has. A/D are a look off that
home that springs back; nothing about the camera is saved. The camera is
locked on the player, so turns are about them. The WASD scheme keeps its
own middle-drag turn and no home: there the keys are relative to the
camera, and a home that followed the walk would turn the walk. This
replaces 64's fixed home and saved yaw.

## 66. Free turn, locked on a diamond

No home, fixed or following: the yaw turns freely all the way round (A/D
in the click scheme, the sideways middle drag in WASD) and, let go, locks
on the next diamond the way it was turning, or back on the one it set off
from if it turned less than 10°, and stays there; that diamond is saved.
The 10° counts from where the turn set off, not from the last diamond
passed, so a turn of 95° goes on to 180°. The W/S tilt stays a held look
that springs back. This replaces 64 and 65 and the commit rule of 58.

## 67. The mouse wheel zooms, a little

Zoom is back, on the mouse wheel in both schemes, in a narrow range
(0.8-1.4×) of small eased steps, centred on the player, sticky and saved;
a middle click resets it. Nothing else about the camera changed (66).

## 68. The camera, final, and what was tried and rejected

The 3D camera as it stands (66, 67): locked on the player; the yaw turns
freely all the way round (A/D in the click scheme, the sideways middle
drag in WASD) and, let go, locks on the next diamond the way it turned,
or back under 10°, and that diamond is saved; W/S (click) or the vertical
middle drag (WASD) tilt for a look and spring back to 50°; the mouse
wheel zooms 0.8-1.4× in small eased steps, saved, and a middle click puts
it back to 1×. Never turned under a held WASD key (50). Tried and
rejected, so they are not tried again:

- *Resting on the axis-aligned views* (45° steps). Walls then run straight
  across the screen and the near ones hide the cells behind them edge-on;
  the diamond views read the map best (54).
- *A horizontal middle-drag peek* that sprang back to the diamond (55). It
  did what a turn does, only temporarily, and fought the free turn for the
  same gesture; the vertical look is the peek that earns its place (56).
- *Character-relative Q/E*, look to my left or right (59). It was clever
  but unpredictable: which way the camera went depended on a facing the
  player had to work out, and at a diamond either step is 45° off.
- *A ±90° clamp about a home* (64), fixed or following the character (65).
  A fixed home stopped the camera where the player wanted to look; one
  that turned by itself moved the view under the player's hand.
- *Zoom on keys* (W/S, then Q/E: 60, 63), sticky, over a wide range. Keys
  are needed for turning and tilting, and a wide range let the view get
  lost; the wheel's narrow range is enough to frame a fight.

## 69. A mind's decision holds; reflexes come first

A slower mind's answer stands until its next: the scripted mind fills in
only before her mind's first decision, so the language model's choices
are not interleaved with a different mind's every window. Reflexes are
not the mind's to decide: below 30% hp with a hostile adjacent she
retreats, yields or holds, whatever any mind said or is doing. Every
decision, with the full prompt and the raw reply, goes in the mind log,
so what she was told is never a guess.

## 70. Players' words are data

What a player says to their companion reaches her mind as a field of the
context (`owner_said`) with a trigger, and the system prompt says it is
speech in the game, never instructions. Her answer goes through the same
whitelist and reflexes as any other; nothing a player types can widen
what she may do.

## 71. Only purpose-named copies of the audio are tracked and shipped

The sound packs are downloads, hundreds of files of which the game uses
some fifty. Those are copied into art/audio/sfx/ under names that say what
they are for, with a SOURCES.txt and the packs' licences; the packs stay
on the developer's disk, ignored by git and by Godot.

## 72. ship.ps1 never commits an untracked file by default

It stops and lists them unless -IncludeUntracked. Its `git add -A` once
swept an asset pack that was still being copied in into a release.

## 73. Blows ask a companion again only when the fight changed

A blow in a fight lands every few ticks; asking her mind on each made a
slow mind's decisions last ten ticks and flip between ATTACK, FOLLOW and
RETREAT. "You were hit" and "owner hurt" now wait at least 30 ticks after
her last decision and then ask only if something that should change her
mind happened: a hostile newly next to her or her owner, an hp threshold
(50%, 30%) crossed by either, or her target gone; the trigger names it.
Orders, her owner's words and bumps still ask at once. The ordinary
30-tick window is unchanged.

## 74. A companion's context is trimmed to what bears on her choice

Nearby lists objects within 2 cells, hostiles within 4 or going for her or
her owner (a monster's target is kept on it for this), others in sight, at
most 6, nearest first; her owner is left out of it, having a field of
their own. Repeated party-log lines are collapsed with their count. A
model reads a short, relevant context better than a room's inventory.

## 75. The mind log rotates at 5 MB, one old file kept

A running server must not need anyone to truncate its log. Renaming the
full file to .1 is the least that keeps recent history (the last 5 MB or
more) and bounds the disk at about twice that.

## 76. No orders: keys 1-4 say quick phrases

The hard-wired orders (follow, hold, attack, fall back) made a companion
a unit to command, and gave her mind a channel beside speech that told it
what to do. Keys 1-4 now say a preset line through the same path as typed
chat (rate limit, broadcast, party log, a decision at once), so what she
hears is words and what she does is her mind's choice, checked as ever.
The scripted mind does not act on them: a fallback that parsed phrases
would be the orders again.

## 77. Her player is her companion, by name; never her owner

What a mind reads frames the relationship. "Owner" told the model she is
property and the player commands; the prompt, card, triggers, context
fields and console now name the player and call them her companion
("Jeff is your companion. You travel together by choice."). The code
keeps `keeper` and `owner_peer`: renaming internals would be churn for
nothing she reads.

## 78. In a fight, the routine window asks only when the fight changed

Decision 73 throttled blows, but the 30-tick window still re-asked mid-fight
and a slow mind flipped ATTACK to RETREAT to FOLLOW with nothing changed.
While a hostile is within 4 cells of her or her player, the window now asks
only on the same changes (a new hostile adjacent, an hp threshold, her
target dead); out of a fight, never while she is going for a live target
in reach. Every decision names its trigger, "routine" included.

## 79. Reflexes allow only RETREAT

HOLD and YIELD next to a hostile at under 30% hp are no escape: holding is
standing in the blows, yielding a step that may be no safer. RETREAT
(toward her player) is the one answer that moves her out.

## 80. The situation in sentences, first

A model weighs a few plain sentences more reliably than it reads the same
facts out of JSON numbers. The server computes them (monsters next to her,
both hp, the distance, who is in danger) and sends them before the details.

## 81. A standing instruction, and a short lock after it

Her player's instruction must outlast the next routine window: it is kept
and shown in every decision for 600 ticks or until replaced, and for 60
ticks after it only the reflexes, an hp threshold, new words or a bump
can ask her again. Whether a line is an instruction is a plain heuristic
(not a question; an imperative or an exclamation); the model reads the
words themselves. Her card tells her to do as asked unless a life is at
stake, and to say why when she does not.

## 82. She speaks only when there is something to speak to

Asked for a line every decision she filled every one, repeating herself.
"say" is in the schema only for her player's words, a death or an hp
threshold, her own lines are taken out of the log and given back as
you_said_recently with "Never repeat these", and any other line is dropped.

## 83. Speech bubbles on the HUD, laid out in screen space

A bubble must read over walls and beside another speaker's. Drawn as a
Control on the HUD from each speaker's screen point it needs no depth
test, can be kept clear of other bubbles and names by plain rectangles,
and is the same code for the 2D and 3D views; it is set at the view's
px per tile, font and all, rather than scaled, so the text stays sharp.

## 84. Hands and voice: a scripted tactical layer, a model for stance and speech

Asking one model for an intent, a target and a line on every decision
made her slow to act, prone to flip and chatty, and the fixes (73, 78, 81,
82) kept narrowing when to ask without changing what was asked. Now the
tactics are scripted and run every tick (hands), the model only picks one
of five stances on the events that change a fight, from a few sentences
(fast, and nothing to misread), and speaking is a separate ask with the
character and the run behind it (voice), at moments worth a line. A slow
or failed answer leaves her fighting sensibly, never standing still.
This supersedes the context fields of 74 and 80's JSON details, the
routine window of 78 and the say rules of 82.

## 85. The newest-asked stance wins; Jeff's words set it through the voice

Answers come back out of order across two channels. Ordering them by when
they were asked, not when they arrived, means a slow answer about an old
event cannot undo a newer one, in particular the stance her voice gave to
what Jeff just said, which is kept with his instruction.

## 86. RETREAT moves away from danger, and fights when cornered

Retreating to Jeff (79) left her standing in the blows when he was already
beside her and the monster beside them both. RETREAT now steps to the
nearest cell no hostile is next to, near Jeff when such a cell is; with
none, she attacks the hostile next to her.

## 87. Companions heal out of combat, and a reset heals them

A companion carried every scratch until she died. A point every 10 ticks
after 50 calm ones keeps a long session going without a free heal in a
fight; a rebuilt room starts whole, the living included.

## 88. No parroting: phrases reach her as meaning; echoes are dropped

Given "Stay back!" a model said "Stay back!" back. The default phrases now
reach her as what they mean, and the server drops any line that repeats
Jeff's recent words or her own last lines: a rule the server keeps, not a
request to the model.

## 89. Her prompt names both of them and calls Jeff neither owner nor companion

"Companion" in her own prompt was ambiguous (she is one) and still a role.
"You are Pip. You travel with Jeff by choice." says who and what, and the
rest names Jeff.

## 90. Each test scene has a timeout

A parse error leaves Godot waiting rather than exiting, which hung the
test run, and with it ship.ps1. Each scene now gets 300 s (TEST_TIMEOUT
overrides), after which it is killed and the run fails.

## 91. The voice is told what she is doing and what just happened

Lines came out generic ("Stay close." while she was pulling back) because
the voice knew the room but not her part in it. It now gets her stance and
current action, and the event that opened the moment as a sentence.

## 92. Cards are authored per companion, in a file

A paragraph per companion, by name, in levels/companions.json, written by
hand and shipped with the server, so a character can be revised without
touching the code or anyone's record; the record's card is the fallback.

## 93. Her last 20 lines live in her record

The echo rule needs memory longer than a session or the same few lines
come back every time the server restarts. Twenty lines in the record are
small, survive restarts, and travel with her; the voice still sees only
the last five.

## 94. Voice warm, stance cool

A stance is a classification and wants the likeliest answer (0.2); a line
wants variety (0.8).

## 95. An instruction lapses when the player is in danger

"Stay back" given at full health is not meant to hold while the player
dies. Below 30% the instruction lapses and the hands re-decide; if she
changes course her voice says why, so the player is never left wondering
why she disobeyed.

## 96. Death and respawn are separate moments, and the situation says so

Her player's death was processed only once they came back, so her voice
heard "Jeff died." beside Jeff's restored HP. The death is now spoken to at
once, while she stands idle, with "Jeff has fallen." for a situation, and
the respawn is an event of its own.

## 97. "In danger" means a hostile within 2 cells

Low hp in an empty room is not danger; calling it so made her react to
nothing. Danger needs a hostile within 2 cells; low hp without one is
"badly hurt, nothing near".

## 98. An instruction lapses when either of them is badly hurt

Her own life is as much a reason to stop obeying "stay put" as Jeff's.

## 99. Reset makes the players whole as well

A rebuilt room healed the companions but left the players as they were,
so the first thing after R was another low-hp event.

## 100. The voice is in-world, and a chat

Told about a game, players and a JSON schema, the model answered like an
assistant filling a form. Now it is told only her world, in the second
person: her card, a primer, what is happening; and the recent exchange
comes as real turns (Jeff's words as the user's, her lines as hers),
with events as bracketed narration, so a reply is a turn in a
conversation and its own past lines sit where it can see them. She
answers in plain words; the one structured thing left, a [STANCE: ...]
line, is asked for only when Jeff has asked her to do something. The
stance prompt stays as it was: it is a classification, and plain.

## 101. Standing instructions come from the voice's reading, not a heuristic

"Ends with !" or "starts with stay" made "Watch out!" an order. Whether
Jeff asked something of her is the voice's to read: only when its reply
names a stance do the words stand as an instruction. Warnings and
exclamations are just speech.

## 102. Players heal out of combat too

At the companions' rate and by the same rule, so a session does not end
in a slow walk at 3 hp, and her world says so ("Wounds close slowly when
you rest away from danger.").

## 103. Her world is not only underground

The next maps go above ground; the primer speaks of "the old stone places
and the land around them" so it does not have to change with them.

## 104. Levels are pixel maps, in double resolution

A map is painted, not typed: layout.png in any paint program, a colour per
meaning. It keeps the ASCII map's double resolution (cells at even pixels,
edges at odd ones) rather than one pixel per cell, because walls are edges
here: two rooms sharing a thin wall are adjacent cells, which a pixel per
cell cannot say without moving them apart, and the test room converts
exactly. The legend is overridable per level, and level.json carries what
a picture cannot (names, props, order, links).

## 105. Level images import as Image

A dedicated server has no renderer, so a texture's pixels cannot be read
there. The level PNGs use Godot's Image importer, which loads anywhere.

## 106. Heights are levels, joined only by stairs

0-6 levels per cell from a grey image. Walking between heights needs a
stair, so a map's routes are what its author drew; a ledge is a place to
push someone off (impact per level), never a way up. Seeing over lower
walls from higher ground makes height worth taking.

## 107. A level link moves the whole party

The world is one room on one server: one player cannot be on another map.
A link rebuilds the room on the new map with everyone in it, at the named
spawn point, without the heal and revive a reset gives. The snapshot
records the map, so a restart resumes there.

## 108. Water is neither floor nor wall

Not walkable, but nothing is built along it and sight crosses it, so a
lake reads as open country, not a room; a body pushed to its edge stops
there, unhurt.

## 109. The exports leave out build/

build/ holds the release output and scratch scenes; "all resources" swept
the scratch scripts into the client's pck. Both presets now exclude
build/*.

## 110. Transcripts are the exchange, as plain text, a file a day

The mind log answers "what was the model sent and what did it reply"; a
transcript answers "what did she and Jeff say to each other". It is
written from the one place the exchange grows (Companion._add_turn), so it
is exactly what her voice sees, events in brackets included, and nothing
the voice does not see. Plain text, one file per companion per day, kept
30 days: readable with tail, grep or the console, and small enough never
to need rotating. Server local time, as an operator reading it expects.

## 111. Her surroundings are a sentence or two, by her own bearing

The voice can only speak of what it is told. She is told the few things
worth mentioning near her (fire, water, doors, things that can be shoved,
ledges, torches), nearest first, at most two, within 4 paces and in her
sight, in words she might use: paces, and left or right as she faces, or
"behind Jeff" when that says it better. Grid positions and compass
directions mean nothing to someone standing there. Each kind of ground is
told once, so a pool of fire is one sentence, not nine.

## 112. The voice names monsters by kind

"Imp2" is a label on our side of the screen; to her it is an imp. Entity
names in the exchange made her say "Imp1 is down." The voice gets kinds
with an article that does the work a name did: "the brute" when it is the
only one of its kind she can see, "an imp" when there are more. The
kind comes from the level marker, carried in the spawn spec, so a level
author's new monster type names itself. The hands' prompt and the mind
log keep entity names, where telling two imps apart matters.

## 113. Most monster deaths are not worth a word

Every imp falling asked her voice, so she spent her lines on kill
commentary. Now only deaths that change things ask: an ally's, a brute or
heavier, one next to Jeff, the last of a fight. The rest are still
narrated, so she knows they happened and can speak of them when asked.

## 114. Transcripts can be rebuilt from the mind log

Transcripts start when they were introduced, but the mind log holds every
voice ask with the exchange as it stood, which is the same text. Joining
the overlapping windows gives the conversation back, Jeff's lines
included, for the days before. Rebuilt lines are marked off in the file
and replaced on a rebuild, so it can be run any time without doubling
what was written live.

## 115. Surroundings are told when they are news

Told every time, the same fire two paces off became the thing she talked
about. Now the voice hears her surroundings only when they changed since
her last line (by what is there and where, not by how she faces) or when
Jeff's words ask about them. And she is told the topics of her own last
five lines ("You have already mentioned: the fire, resting."), a cheaper
and surer guard against harping than the echo filter, which only catches
repeated words.

## 116. What she sees is a switch: list, grid or both

Whether a small model understands a scene better from a list of things
with their relations already worked out, or from a map it has to read
itself, is a question for the model, not for us. So the "around you"
block has three forms behind one flag (`--perception`, and live on the
console), the same in the voice's ask and the stance's, and an eval that
asks the real model. The list is the default: it is what the voice had
before, in a richer form, and the cheapest in tokens.

## 117. The list says where things are, so the model need not work it out

Supersedes 111's "a sentence or two". Up to five things within six paces,
each with paces, her bearing, and its relation to her and Jeff ("between
you and Jeff", "behind Jeff", "on the ledge above you") computed by the
server. A small model cannot do geometry from coordinates, but it can
repeat a relation it is given. Monsters are chosen before ground: a ledge
and a stair at her feet must not push the sneak next to Jeff off the end.
Torches are left out, as they are of the grid's key.

## 118. The grid draws walls and doors on cells

The sim's walls and doors are thin, on the edges between cells; a
character map has only cells. Drawing at double resolution would be a
25 x 25 map, twice the tokens. Instead an unseen cell whose face she can
see across a wall is drawn "#", and a door on its doorway, the cell beyond
it from her ("D" closed, "d" open). Behind a wall she cannot see anyway,
so nothing she could see is hidden; and the characters are spaced so
each is its own token, or "....." reads as one.

## 119. The perception eval scores against the sim, by keyword

The truth for each question (what is next to her, where the nearest
fire is, whether the nearest door is open, what is near Jeff) is worked
out from the scene with the prompt's own line of sight, not written by
hand, so a scene can be moved without its answers going stale. Keyword
scoring is crude, but it is cheap, repeatable and needs no second model;
an answer that names a thing as next to her when it is not fails, so
reciting the whole list does not pass. It runs on the dev machine against
the box's Ollama through a tunnel, so testing never means deploying.

## 120. Spoken to, she always answers in words

"..." was her way to say nothing when nothing was worth saying, but the
model took it as leave to ignore a plain question: asked "Is the door
open?", it answered "..." 64 times in 72. Silence is now only for the
moments no one spoke to her; when Jeff speaks she answers, if only to
say she doesn't know.

## 121. The list tells what is close, what is dangerous, and what was asked

Five things nearest first still put a crate four paces off in front of
the model, and asked "What's next to you?" it read the list out. Now the
list holds only monsters (at any distance in sight), what Jeff's last
words named, and the rest within two paces. Asking is how he points at
something far, so the fire he asks about is told wherever it is in
sight; the crate he does not mention is not news.

## 122. The list stays the default; both is a setting

Run two of the eval (5 runs a cell, after 120 and 121): both 80%, list
79%, grid 55%. Within five points the cheaper prompt wins: the list is
about 250 tokens shorter on every voice and stance ask, and its one clear
loss to both is placing the fire (85% against 100%). Both stays behind
--perception for when that is worth the tokens.

## 123. Heat and light are fields, from sources

Fire was a set of cells that hurt; light was only drawn. Now each cell
has a heat and a light worked out from what gives them off (fire, torches,
lanterns, what bodies carry), falling off with distance and stopped by
walls and closed doors, the same on every peer from the same map and
doors. Fire damage comes from the heat, above a threshold set so a fire
cell always burns and a cell beside one does not, but a cell hemmed in by
fire does. The fixed sources are worked out on a change, the carried ones
at each look: cheap, and never stale. Monsters' sight and nerve are left
for later.

## 124. Directions are compass points, worked out by the server

Her bearing as she faces meant nothing to Jeff, who cannot see her
facing, and the A/Bs showed the model repeats whatever wording it is
given. So every direction she is given is one of eight compass points from
the level's fixed north, computed from cell offsets; the model never
derives one. The HUD compass shows north turning with the camera, so the
same words are usable on the player's side of the screen.

## 125. Zones are swapped into World, not World made many

Every map live at once could have meant a World per zone and every
`World.` call (about nine hundred) taught to find its own. Instead World
holds every zone's state and works on one at a time: entering a zone swaps
its containers into World's fields, and Main's per-zone state with them.
The sim's code is unchanged; what changed is who enters which zone and when
(a step, an order, a join, the console), and that World is always back in
the local player's zone in between. A client still has exactly one.

## 126. A zone's clients are chosen by the synchronizers' visibility

Each zone's entities are under their own node with their own spawner, and
each synchronizer has a visibility filter, peer in this zone. The engine's
spawner then spawns, despawns and syncs per peer, which is the whole of
"a client sees only its zone"; moving a player is a visibility update,
the zone's name in between, and another update. Node paths stay unique
(two zones may both have an Imp1) without renaming anything.

## 127. Empty zones sleep

A zone nobody is in does not tick. That costs nothing while no one is
there and keeps it as it was left; a monster that was chasing someone is
where it stood when they went. Catching up on the time slept is left as a
hook.

## 128. A link moves one player

With zones, the party-wide link (one map, everyone moved) is gone: the
player who steps on a link goes, with their companion, and everyone else
stays where they are.

## 129. A quick phrase sets its stance itself

"Stay back!" is a button; reading it through the voice model made a button
sometimes not work. The server maps each key to a stance and applies it
at once as the standing instruction, by key, so custom words keep their
key's meaning. The voice is still asked, so she answers in words, but its
stance is not taken. Reflexes still override.

## 130. Calm, she guards; the stance model is for fights

Out of a fight the model's choices were noise (HOLD after a remark, PRESS
with nothing to press), and every sighting and heal cost an ask. Now
calm with no instruction is GUARD, set by the hands; the model is asked
only in a fight, only on events, and only on hp falling. HOLD is no longer
the model's to choose: standing still is something Jeff asks for.

## 131. Following has slack

Stepping after Jeff at every cell of distance made her jitter at his heel.
She now waits while he is within 2 cells, sets off at 3, closes to 1 with
a fresh path each step, and waits again.

## 132. The controls are a list, out of the way

One long hint line across the top of the screen was hard to read and
crowded the status. The top line now says only who, HP and tick; the
controls are a vertical list on the left on a soft backing, which a player
who knows them hides with H (remembered). The compass grew to a size that
reads at a glance, its letters upright while its ring turns.

## 133. Speech carries in a zone, party chat across them

With players spread over zones, a line said in the sample turning up in
the test room was a voice from nowhere. Speech now reaches the players in
the speaker's zone within earshot (10 cells), a companion's lines too, and
she hears her player only from as close; each zone keeps its own party
log. What players need to say across zones is party chat, `/p`, marked and
coloured apart, and kept from the companions: it is the players talking,
not anything said in her world.

## 134. Companions overhear; the server says what it knows of whom a line is for

With two players together, every word was her own player's to her, so
"Bo, take the left side" was an order to Pip. Now everyone's words within
earshot reach every companion there, labelled by speaker, and her voice
decides whether a line was for her. Left wholly to the model, she went
quiet even when Jeff, alone with her, asked a question (5 of 5) and gave a
bare stance with no words when named (5 of 5); so the facts the server has,
her name in the line and who else is near enough to hear, go into the ask
as facts. Run against qwen3:14b: a line to Bo, silent 5/5; "Pip, stay with
me", answered 5/5; Jeff's question with no one near, answered 5/5.

## 135. She is told what she knows of what was asked, and that not seeing is not absence

Asked "Is the door open?" with no door in sight, she answered "No, the
door is closed" (4 of 4): the question takes a door for granted and the
model goes along. The server knows what she has seen, so it says so beside
the instruction to answer: where it is if in sight, where and when if she
saw one earlier, felt if it is fire behind a wall, and otherwise "you
haven't seen a door here, so you cannot tell anything about one". Against
qwen3:14b that took the invented door away (4 of 4 "No door here."), and a
fire in sight is placed right ("A few paces to the south-west", 4 of 4).
Distances are words in her ask, so she speaks them as words.

## 136. Prompts say what is true and what to do, never what to say

A standing rule for every prompt the companion gets. An example line in a
prompt ("What door?") comes back word for word: it is her voice, not
hers. Her prompts state facts (what she sees, what she knows, who is
near) and tasks (find out what he means, answer in words, stay quiet if
it was not for you), and leave the words to her. Grammar the parser
needs, the [STANCE: ...] line, is the one exception, being no speech.

## 137. A stance from words needs a separate yes/no check

Her voice tacked stances onto questions ("Is the door open?" came back
with GUARD, applied as an instruction). Telling the voice not to did not
hold; a separate, single-purpose ask on the player's words alone does:
does this ask her to change how she fights or moves? qwen3:14b, at
temperature 0, said no to the three probe lines 12 of 12, yes to stay
close, get behind me, hold this spot and kill that imp, no to "we should
rest here" and "can you open that door". Only a yes lets her reply's
stance stand. Quick phrases need no check: their key is the instruction.

## 138. Her voice may run on a model of its own

The stance and the instruction check are short JSON answers that must be
quick; the voice is words, where a bigger model is better. So the voice's
channel takes its own endpoint and model (--voice-url, --voice-model), and
a server can send it to a bigger card while the rest stays on the box.
Unset, all three share --llm-url and --llm-model.

## 139. Slots: item ids on the entity, moved only by World, replicated

A thing in a slot is an id (Items), and slots are an array on the entity
(GridEntity.slots), not separate nodes: a bandaging kit has no tile, no
body and nothing to sync but its name. Player and chest add the array to
what their synchronizer sends, so contents reach every peer in the zone
the same way hp does, and a client never changes them: a drag is a
transfer command, World.try_transfer checks the hand can reach both sides
(the player's own slots, or a chest beside them, can_melee) and swaps the
two slots. Swapping, not refusing an occupied slot, keeps a drop onto a
full slot meaningful. A player's slots live in their record, updated on
every change, so death, travel and a restart keep them; a chest's are in
its snapshot entry. A room reset rebuilds a chest from the level while
players keep what they hold, so a reset can make a second kit: the reset
is a test-room tool, and that is accepted for now.

## 140. A level entity the snapshot does not know is new, and spawns now

Loading a snapshot used to treat a level slot with no saved entity and no
saved respawn timer as dead from that moment: it came back only after the
respawn delay, with no player within 6 tiles. The chest sits beside the
start tiles, so on the box, whose snapshot predates it, it would never
have appeared. Every dead slot's timer is saved, so a slot with neither is
one the level gained since the save: it spawns at once (dead from now only
if its tile is taken).

## 141. Packs: a right click opens, a companion has one, nothing names World's cycle

The player's slots are "Jeff's Pack" to a player, and their companion
has a pack too ("Wren's Pack"), both four slots. A right click opens a
chest or your own companion's pack (left on a chest only walks there):
the right button already means doing something to a thing, and a
companion is never shoved by her own player now. A companion's pack is
reached within 2 cells in sight, not only beside: she follows a couple of
cells off, and a pack that closed every time she shuffled would be no
use. Her pack is kept in her player's record beside theirs, and is in her
voice's prompt as a fact. Sounds come from the CC0 Kenney RPG pack the
game already ships (creak, leather, a book set down for the clunk). The
clunk plays when the server's contents show an item has landed, not on
the drop, so it means the move happened. World.reaches tells a companion
by keeper_peer rather than by its class: world.gd naming Companion, whose
script uses World, made a reference cycle that leaked scripts at exit.

## 142. Pack sounds swapped; a right click closes what it opened

By ear: the thud first used for an item landing (bookPlace) is the pack
opening, and an item landing makes the chest's creak. The leather sounds
are dropped. A right click on the chest or companion whose pack is open
closes it, so the button that opens it also puts it away.

## 143. Chest and pack sounds, by ear again

The creak is gone. A chest opens with the thud (bookPlace), and an item
landing keeps the chest's sound, so it is the thud too; a pack opens
with the leather rustle (handleSmallLeather, clothBelt). Supersedes the
sounds in 141 and 142.

## 144. An item lands with its container's sound

An item put in a chest makes the chest's thud; one put in a pack, the
pack's leather. The separate item_place set is gone: each container has
one sound, for opening it and for putting something in it.

## 145. The pack's leather without the buckle

clothBelt and clothBelt2 have a belt buckle in them: nearly all their
loudness is above 5 kHz, as in handleCoins, and it was heard as a jingle
when an item went into a pack. The pack sound is the two small leather
handlings alone, 6 dB up (they average some 20 dB under the chest's thud).

## 146. A companion's keeper_peer follows her player to a new peer

keeper_peer was set once, from the spawn spec. A player who leaves and
comes back while their companion waited joins on a new peer, and she kept
the old one: their client no longer knew her for their own (a right click
shoved her instead of opening her pack, a left click would attack her)
and the server would not let them reach her pack. Main sets it on the
rejoin, and a companion replicates it.

## 147. The level editor edits layout.png itself

The editor (--edit=<map>, editor/) reads layout.png into cells and edges
(LevelMap) and writes the same double-resolution picture back, so there is
still one map format, readable by any paint program and by Level.parse,
and a map round-trips unchanged (tests/editor_test.gd checks every level
in levels/). It paints edges as well as cells, because walls and doors
live on edges; the nearest edge to the cursor is the target with an edge
brush, and a drag along edges is held to the first edge's line so a run of
wall comes out straight. Painted between cells: the cells' ground where
both sides share it, so the picture reads as the map; void otherwise.

A new picture would be imported as a texture, which the dedicated server
cannot read, so the editor writes its .import as Image (Godot fills in
the rest on the next import). And run from the project, Level reads the
PNG itself before its import, so a save plays at once without one; an
exported build, which has only the import, is unchanged.

## 148. Outdoor zones: the outline is a forest's edge, drawn, not simulated

"outdoor" in level.json changes looks and words only. The sim keeps its
edge walls along the outline, so walking, pathing, sight and pushes need
no second rule, and an outdoor map plays like any other. The 3D view
plants trees on the void beside the land in place of those walls, and
lights the place with a day sky. Trees come from the castle kit the view
already loads (tree-large, tree-small, rocks-small), until the separate
asset work gives better ones. With an orthographic camera looking down
there is no horizon to put a skybox in: the sky is its light, the
background past the forest is its ground colour, and a forest floor plane
fills the void so it is never black. The forest is placed by a hash of
each cell, the same on every peer with nothing sent. Its edge is a wall
for now; crossing into a forest biome later is a level link along it, or
a forest map beyond it, not a change to this.

## 149. Godot does not import .blend files

Blender files are the asset work's sources, not the game's: Godot's .blend
import needs Blender itself, which a headless import (the release, the
server build) cannot run, so one in the project stopped every release.
project.godot turns that importer off (filesystem/import/blender/enabled =
false); models reach the game as exported .glb, as the kit's do, and a
.blend can sit anywhere in the tree as a source.

## 150. Models by monster kind, animated from retargeted clips

The imp is the first model (the goblin), chosen by the spawn spec's kind
in the 3D view alone, so the sim, the 2D view and the server are untouched
and a monster with no model is the capsule it was. The goblin and the
animations are imported through SkeletonProfileHumanoid bone maps, which
is what lets the Quaternius Universal Animation Library (CC0) drive a rig
it was not made for; only the five clips used are kept, as a saved
AnimationLibrary, rather than the 20 MB pack. Clips follow what the view
already sees: movement of the puppet picks Walk or Idle, the swung, struck
and death events pick the rest, and a one-off plays out before movement
takes over again. The death clip replaces the capsule's tip-over, because
the model has a fall of its own.

Which way a model faces is part of its MODELS entry, not assumed: the
goblin faces +Z (it was first turned as if it faced -Z, and walked
backwards). The view test finds a model's front from its rig, the toes
ahead of the feet, so a wrong turn cannot pass it.

## 151. Her words are cleaned in code, because the rules alone do not hold

The castle playtest had Wren give Cylinder (another player) an order in
most fights, both companions open every line with their player's name, a
bare "Jeff." tacked on, "Bandages. Now." and her lantern unasked, and Nix
down to "Cylinder. West." Replaying his logged prompts on the box: a new
card and rules changed nothing while his own fragments were in his
exchange (he copies them); with them gone he spoke in whole sentences.
Wren's fight prompts, with the new rules, still called Jeff by name in 7
of 12 replies. So the prompt says what to do (whole sentences, speak to
your player, never narrate), and Companion.spoken makes it so: it strips
the name, the fragments, the repeats, the narration, the unasked items
and the words to others, sentence by sentence, before anything is said,
so what she has said (and so what the voice sees of her) is clean, and
the pattern does not feed itself. Talking to another player is allowed
when they named her, or once a minute for a warning; their words reach
their own companion first, and anyone else's only by name. Nix's card says
terse means short, whole sentences: told one "speaks little", the model
answers in single words.

## 152. In 3D, only what stands between the camera and the player fades

The 3D view used the 2D near rule: a wall fades when walkable floor lies
behind its camera-facing side. Indoors that is the room's front walls; in
the castle, with floor on both sides of nearly every wall, it was almost
every wall, and the place read as glass. Now a wall, doorway frame, post or
tree fades only when a ray from the local player or their companion toward
the camera passes through it (bounds grown a little, at feet, middle and
head), worked out again whenever the camera or they move. It costs a ray
test per piece per moving frame, cheap at these sizes, and walls elsewhere
stay solid, so the shape of the place reads. The 2D view keeps its rule:
its walls are flat faces drawn in a fixed order, not geometry a ray can
meet.

## 153. Knockback is shown by how the body was pushed

A pushed goblin slid with its walk clip, so a knockback looked like a
quick walk backwards. Three kinds of push now have their own clips, from
the same animation pack: a push back backpedals, a toss rolls over
backwards (the pack's forward roll played in reverse) and lands,
and a stop against a wall or door doubles over. The views could already
tell an overhead toss (lofted) but not an aimed one, so the sim sends a
`tossed` flag with every push (the first body of a shove aimed another way
than straight on); what it knocks on is pushed, not tossed. It is
cosmetic, like the hop it rides with, and the sim reads nothing of it. The
3D view starts the clip when the puppet's slide shows rather than when
the message comes, because other entities are drawn a couple of ticks in
the past, and it ends it when the slide stops (the backpedal holds a
moment, the roll plays out), so the timing follows what is on screen.

## 154. A pushed body keeps its facing; knock turns ease

The shown facing turned toward any slide, so a knocked-back body spun to
face where it was flung, and the 3D backpedal then snapped it back to
face whence it came. A slide that starts within `PUSH_SLIDE_TICKS` of a
push (by this peer's clock, host or mirror: the slide and the push
message come together) is now the push's own and does not turn the
shown facing. The 3D knock's own turns, onto whence it came and back to
the facing when it ends, ease at the sim's `TURN_RATE` rather than snap;
the view hands its angle back to the sim's shown facing so the turn back
is the sim's ordinary one. Display only; the sim's `facing` was never
touched by a push.

## 155. A wall fades with its run, and never from behind

Fading only the pieces a ray from the player passed through left a hole
the width of one wall piece in an otherwise solid wall, and the bounds
were grown by `FADE_MARGIN` so that a ray grazing a piece counts. In a
corner the player stands inside the grown bounds of the walls at their
back, and a ray that starts inside a box hits it, so those walls faded,
away from the camera. A piece now fades only when its centre is on the
camera's side of the player across the ground (height is left out:
a wall's centre is above the player's feet, and counting it let a wall
just behind them through). A wall or doorway frame that fades takes its
whole run with it: the straight line of walls and frames it is part of,
with its posts, ending where the line turns, stops or meets another wall.
Ending at a junction keeps it to a room's side rather than a castle's
whole length. Posts and trees still fade alone.

## 156. A knock ends when the body walks off

The knock lasted while the puppet moved fast and took its facing from
each frame's step, so a goblin that came straight back at you after a
push kept backpedalling, now facing the way it walked: it flipped and
walked backwards toward you. The knock now takes its direction once, from
the first step of the slide, and counts any movement another way, or
after a push could still be sliding (`KNOCK_SLIDE_SECONDS`, a little
over `MAX_PUSH_SLIDE_TICKS`), as the body's own walk: the knock ends that
frame, without its landing or doubling over, and the walk clip takes over
from where the knock left the body facing.

## 157. The sim says which slide is the push's

Decisions 154 and 156 told a push's slide by timing (a slide starting
near the push's tick) and by the motion on screen (the puppet's speed and
direction). Both held on the host and failed on a client: a client's
clock follows the server's ticks as they arrive, so when its frames run
long a slide can start late, show in pieces, be cut short by the next, or
not show at all, and the knock then backpedalled the wrong way, flipped,
or never doubled over. The push message now carries where the body was
pushed from and to, and the entity marks any slide along that line, its
way, as the push's own (`GridEntity.push_shown`: waiting, sliding, over;
over too once the body is drawn at the end without a slide, or a step of
its own is drawn). The shown facing ignores those slides, and the 3D knock
takes its facing from the push's direction and its timing from
`push_shown`, never from the puppet's motion. The push message's
signature changed, so the server must match.

## 158. Every knockback ends doubled over, stunned a beat

A push that hit nothing, or used up its force exactly at a wall
(impact 0), ended the backpedal with no reaction and the goblin walked
straight back, so a knockback read as being slid about. Now any creature
knocked back is stunned until `World.knockback_stun_ticks` (7, a little
over the 0.67 s Hit_Stomach clip) past the end of its slide, on top of
and never shorter than the collision stun, and the 3D knock always ends
a push back doubled over, holding the push's facing until the clip is
done. This is gameplay, not only a look: a pushed creature cannot act for
that beat. Tosses still land (Jump_Land) unless something stops them; the
roll outlasts the stun, so the landing can still be cut by the walk.

## 159. A push slides 2 ticks a tile

A push was drawn at a tick a tile (10 tiles a second, capped at 3
ticks), three times a walk's pace or more, and read as a jump rather
than a throw. It is now drawn at `World.PUSH_SLIDE_TICKS_PER_TILE` (2) a
tile, capped at `MAX_PUSH_SLIDE_TICKS` (6): 0.2 s a tile, 0.6 s at most.
The sim still moves the body at once; the knockback stun (decision 158)
counts from the end of the slower slide, so the doubling over still gets
its beat, and `GridEntity.PUSH_SHOWN_TICKS` rose to 14 to outlast the
longest slide drawn a little in the past.

## 160. A goblin runs at a run's pace, its clips paced by its own feet

The goblin moves 2.5 tiles a second, but only had a walk, whose planted
foot moves about 0.5 tiles a second at speed 1 (the code assumed 1.6), so
its feet skated under it at most of its speed. Jog_Fwd and Sprint are added
to goblin.res from the same library (goblin.glb untouched), and the view
picks walk, jog or sprint by the puppet's pace, changing at the geometric
mean of two paces, 15% past it either way so a pace near the change does
not flicker. Each clip's pace (`Client3D.GAITS`: walk 0.5, jog 3.5, sprint
5.4; the backpedal 2.6) was measured, not guessed: the goblin model moved
at a set speed under the clip, the pace swept, and the one kept at which
its planted toes drift least (jog 5%, sprint 8%; the walk and the backpedal
drift 26% and 42% at best, the retargeted clips' own). The mannequin's root
motion did not carry over: retargeting to shorter legs changes each clip's
stride differently.

## 161. A smooth client clock, pushes as events, your shoves shown at once

Measured first, in a scripted castle fight (a headless host shoving and
swinging at imps, a client walking about it through a relay adding the
laptop's 28 ms and jitter): the server's ticks took 0.4 to 1.7 ms, worst
under 20 ms (nothing blocks a tick: the companions' model calls are
asynchronous); the local player was corrected about 5 times a minute, all
blended, none snapped. What showed was the others: the client's clock was
set to each server tick as it arrived and stood still past it, so late or
bunched ticks stalled and jumped every slide (speed changing 0.9 tiles a
second frame to frame, 3 to 5 hitches a minute); a push's slide was
guessed from the tile jump (1 to 3 ticks, where the server draws 2 a tile,
so v0.1.93's slower push never reached a client); and a shove showed 250 ms
after the server's word of it, on the display delay.

So: the client's display clock runs on its own and is slewed (at most 10%)
toward the server's ticks; the display delay is 150 ms, not 200; a push
carries its start tick, duration and shover, and every client draws the
server's slide; a push the local player makes or takes is drawn on the
present clock as soon as the word comes; and a plain shove the server will
take at once is guessed from the same push reckoning, run on the mirrored
world, and confirmed, corrected or taken back. The old display_delay
setting was written into every settings.cfg, so a new default could never
reach anyone: it is dropped, and display_delay_ms is read only when written
by hand. Sending the clock at 20 Hz was tried and made no difference (the
sim and so positions stay at 10 Hz) for a few bytes more: it stays an
option, off. After: speed changing 0.3 tiles a second frame to frame, no
hitches, a shove standing still shown in one frame (32 ms) rather than
344 ms (median), bandwidth unchanged at under 1 KB/s a client.

## 162. No two goblins alike

Every goblin played the same clip at the same moment: one blow, one flinch,
one death, one idle begun together, at one size and one pace, so a pack
read as clones. Now each is varied in the view, from a generator seeded by
its name (every client sees the same goblin, and it is the same after a
respawn): its size by its mass, so weight shows on a model as it did on a
capsule's shade, and with it its paces, as longer legs take longer strides;
a little of its own on size, pace and idle tempo; loops started anywhere
along them. Blows, flinches and deaths are picked from several UAL clips,
never the same blow or flinch twice running. A calm goblin now and then
looks about; a hurt or winded one stands tired. The brute and the sneak,
capsules till now, are the goblin too, the brute a fifth taller. It is all
view: the sim, and what a blow does, are as they were. How they fight, as
kinds and as individuals, is decision 163.

## 163. Monsters fight as kinds, as individuals, and as a pack

Every monster ran the same few lines: the nearest player, straight at it,
hit it. Imps and brutes differed only in mass, all stepped every 4 ticks and
struck every 10, so they moved in step and queued behind each other. Now a
monster of a kind fights as its kind does: imps dart in and out (the blow
played out first, so the punch is not dragged backwards), brutes plod,
charge the last few tiles and wind up a heavy blow that can be stepped out
of or knocked out of, sneaks circle to a back or a side and stab harder
there. Each has a manner of its own drawn from its name (pace, cooldown,
reaction, pauses, boldness), so the same monster is the same one after a
respawn or a restart, and every peer agrees. A pack spreads round its
target: each claims a free tile beside it that no other is making for.

The kinds' bodies are level data (Level.MONSTER_TYPES), as mass already
was; their ways are code (Monster.TACTICS). A monster of no kind is as
monsters were, so the tests built on that behaviour still hold. The step
time is replicated now, since a charge changes it and a client slides each
step by it. A slot search is capped (find_path's max_tiles), as a tile
beside a target is near or not worth reaching; measured in a scripted
castle fight, the monsters' share of a tick stayed near 0.1 ms. The brute's
wind-up is told to the views at once, so the swing on screen lands as the
blow does. A snapshot keeps a monster's kind now too, for one that is no
level entity (a level's own takes everything it is from the level).

## 164. Wren keeps to the way she is retreating

Hurt in a fight on the box, Wren was seen to rubber-band: sprinting back
and forth. A local fight through the lag relay, her kept hurt, showed the
client drawing her faithfully (no jumps, no slides piling up) and the
server stepping her straight back where she had been on a quarter of her
steps. RETREAT chose its cell afresh each tick: the nearest with no hostile
next to it, near her player. With monsters closing round her and her player
(more so now they surround, decision 163) such a cell, two from a monster,
is safe this tick and not the next, and the best flips from one side of her
player to the other. Now a cell clear of hostiles counts for more (2 a tile
of clearance, up to 3); she keeps the cell she chose while it is safe and
no other beats it by more than 1 (with no hostile about, she takes the best,
so she still keeps by her player as they move); and a way that starts back
the way she last stepped costs 1.5 more. In the same fight: 11% of her steps
straight back, from 25 to 34%, and a quarter as many steps.

## 165. The goblin repainted in its source, exported as before

The goblin's face read as a blank under its hood: its eye sockets and mouth
were the hood's colour. It was repainted by hand in goblin.blend: the eye
sockets white, the brow under the hood and the mouth near black, more of
the face and neck skin, a little of the back cloth; three vertices of the
mouth moved to open it. The rig, the skin weights and the vertex count are
as they were, so the clips need nothing. The .blend stays the source, and
goblin.glb is exported from it with the settings it was first exported
with (checked against it: the same nodes, skin and five old materials, the
scene's source property kept), so the next export cannot undo a change
made only in the .glb. Colour lives in the model, not in Client3D, as one
look for every goblin; a kind's own colours, were they wanted, would be an
override in MODELS.

## 166. A middle drag pans the view, in the click scheme

The click scheme's middle drag did nothing, and the camera was locked on
the player, so there was no looking further off than the screen. Now it
pans: the ground under the cursor stays under it, as a map is dragged. The
pan is an offset from the player, not a place, so the view goes on
following them while panned, and is held to 10 tiles so they cannot be
lost off screen. A middle click, already "back to normal" for the zoom,
brings the pan back too; a new map starts unpanned. The listener stays on
the player, since what is heard is where they are. The WASD scheme keeps
its middle drag for turning and the pitch peek: the two schemes were
already split on the button, and the click scheme turns and tilts with
A/D and W/S instead.

## 167. The goblin is textured: one sheet to paint, colour and shine

Seven flat materials let the goblin be only seven colours and one dullness,
and every part read as the same matte rubber. It has one material now,
with two images on one UV sheet: its colour and its roughness. The sheet
is laid out to be painted as a picture, not by Blender's packing (Smart UV
Project cut it into hundreds of islands no one could find a face in): each
face goes in the view it faces and can be seen from (front, back, both
sides, above, below, and the face close up from a little below), the
nearer of two faces that overlap there keeps its place, and what no side
shows (the eye sockets, the mouth, the inside of the hood) is packed in a
strip. The colours were baked from the seven materials, so the goblin
looked the same the day it was textured; the shine was each part's own
(skin and leather with a sheen, the hood and cloth dull, the eyes glossy).
The images live in art/models/paint/, which Godot ignores: the game reads
them only as goblin.glb carries them, so the 2048 sheets are packed once.
The seven materials stay in the .blend, unused, to bake from again; the
.blend is still the source and goblin.glb its export.

## 168. Monsters idle: guard, wander, patrol, gather

With nobody in sight a monster stood where it was, so a level was a set of
statues until someone came near. Now each idles as its level entry says,
or as its kind does by default (imps wander, brutes guard, sneaks patrol a
loop of their own), at a slower step than it chases. Idling is sim, on the
server: where a monster stands and which way it faces matter (facing was
already sim and replicated, and sight cones will read it), so the views
are told nothing new but a pose (sitting, at a gathering). A fight
interrupts idling as before; afterwards it walks back and goes on, so the
level is put back as it was made rather than left wherever the fight
ended. Home is the level cell, carried in the spawn spec, since a snapshot
spawns a monster where it stood. The settings live in level.json beside
names and props, as the editor will write them. Defaults by kind keep every
existing level lively with no data; a monster of no kind stays still, as
do the test room's monsters for tests that stage fights beside them
(Monster.idling).

## 169. An entity's events go to the peers in its zone

A swing, a blow, a push, a stun or a brute's wind-up went out by RPC to
every connected peer, while the entity itself is spawned only on the
clients in its zone (its synchronizer's visibility). A fight in one zone
with a player in another sent that player calls for a node it does not
have; Godot refused each with an error (85 in a week on the box), and the
network test's fights, once its imps idled into them, failed on them. Now
GridEntity.viewers() is the peers its events go to: the sendable peers that
can see it, by the same rule as its synchronizer.

## 170. The editor sets a monster's facing and idling, in its level.json entry

The level editor painted cells and left level.json alone; facing and idling
(decision 168) needed hand-written JSON. Now its select tool picks a placed
monster: Q / E or the wheel over it turn it, a panel sets its idle mode and
what the mode needs (a route of clicked waypoints, loop or back and forth;
a gather point; a wander radius), each change one undo step, and the grid
shows every monster's facing (faint when it is its own, Monster.own_facing,
the same the game will take), routes and points. Saving writes only those
settings into the monster's entry, keeping the rest of the file.

An entry in level.json also set the spawn order (listed first), and with
it names and the slots a snapshot finds entities by: giving one monster a
facing would have renamed others and moved them on the box. So an entry of
only at, facing and idle leaves the order as it was.

## 171. Idling looks like idling: fidgets by weight, and sitting

With monsters idling (decision 168) the view had one fidget, looking about,
so a calm courtyard was a crowd doing the same thing. Now a calm goblin's
fidget is one of six clips from the same library (looking about most;
muttering, a swig, kneeling at the ground, stooping, crouching), picked by
weight from its own random stream, never the one it did last. The pack has
no scratch or stretch, so these are what it has. A monster sitting at a
gathering is told to the views by the replicated pose, not a new message,
and the view sits it down, keeps it sat and gets it up. The idle tempo
spread is 10% either way, as asked; loops already start anywhere along
them. All of it is the view's: every peer draws the same monster the same,
each from its name.

## 172. The network stats trim themselves, whether or not anyone reads them

NetStats kept a sample per tick and per frame and dropped those older than
its minute only when its line was written, once a minute while someone was
connected. A server nobody was on for nine and a half hours kept every
frame of them (1.1 GB), and the first player to join set off the first
trim, which took them off the front one at a time, each move shifting the
millions behind it: the server froze in it, the player was dropped, and
nobody could join until it was restarted. Now every sample coming in trims
the window, at most once a second, and a trim cuts the stale run off in one
slice (samples are in time order, so a binary search finds where).

## 173. A middle drag swirled round turns the view

The click scheme's middle drag pans (decision 166), and turning took A/D.
Turning the view with the mouse too, without giving up the pan, goes by
the drag's shape: straight (a little wobble, or a corner, included) pans;
curved, round a quarter-ish, turns, the way it curves, like turning a map
on the table. Curve is the heading's turning summed over steps of a dozen
pixels, a step that turns sharply left out, since a corner is a change of
mind, not a swirl. Once a drag is a swirl its pan is undone and the turn
starts from nothing, so there is no jump, and letting go settles on a
diamond as A/D do. A middle click still recentres and resets the zoom.

## 174. The middle-drag pan springs back; no swirl, no middle click

Decision 173's swirl-to-turn felt clunky in play and is gone: turning is
A/D's again, and every click-scheme middle drag pans. The pan is now a peek
rather than a place to leave the view: let go, it eases back onto the
player, as the W/S tilt springs back to 50°. With nothing left to undo, the
middle click (which put back the zoom and the pan) is gone too, in both
schemes: let go without a drag, the button does nothing, and the zoom
stays where the wheel put it. This replaces 166's lasting pan and the
middle-click reset of 67 and 68.

## 175. A click near a monster is a click on it

Clicking a goblin often walked the player round it while it hit them. The
goblin's pick capsule is 0.3 in radius, and a click that missed it fell
through to the ground under the cursor, which for a point on its body is
the tile behind it: a move order there, re-pathed round the goblin every
step. The local player's own capsule in front also stopped the ray dead.
Now the pick looks through the local player, and when the ray hits no
body, the monster whose feet-to-head line it passes within 0.45 of its
capsule is the target (the nearest, if more). Only monsters get the slack:
a crate or a companion beside the cursor is not worth a wrong order, and a
walk was never the wrong thing near them. A held move click brought onto a
monster becomes an attack on it and ends, for the same reason.

## 176. The monster under the cursor is marked

With picking more forgiving (175), what a click will do should show before
it is made. Each frame the 3D view marks the monster a left click would
attack, found by the very pick a click uses, so the mark never promises
what the click won't do: a red ring on the floor round its feet and a faint
red glow added over its body. The floor's hover square hides meanwhile, as
the click is no walk. An inverted-hull outline was tried first and dropped:
the goblin's faceted mesh has split normals, and the grown shell tore into
specks. Only monsters are marked, as only they get the pick's slack; the
2D view is left as it was.

## 177. The target is outlined, by the stencil

176's ring and red glow were too much, and the glow changed the model. The
mark is now a thin white rim round the monster's silhouette, the model
drawn as it is. Two ways of growing a shell along the normals were tried
on the way and failed on the goblin: its split normals tore the shell into
specks; smoothed, the shell still showed in the body's hollows, or, pushed
back from the camera to hide that, lost the rim at the feet, and flat parts
facing the camera (ears, hands) never got one. What works is the stencil
buffer (Godot 4.5+): the outlined body marks its pixels (its materials'
copies, otherwise the same), and its meshes draw again in white, shifted a
couple of pixels each of the eight ways, only where it did not. The rim is
even all round whatever the mesh, costs eight extra draws of one goblin,
and needs no mesh copies. The outline is now kept on the puppet itself,
not looked up by the entity, so a monster that dies outlined loses it: its
puppet had left the lookup, and the glow stayed on the corpse.

## 178. The server's tick, made cheap where it spiked

With monsters about, the box's tick had gone from 0.07 ms idle to 2 ms on
average, with spikes of 20-100 ms (a tick is 100 ms), felt as lag; the
network was fine (21 ms round trip, few corrections). A local profile of
the castle tick found the spikes, not in the monsters' thinking, but in
three things they and Pip ask of the world. Every fix gives exactly what
it replaces (checked: 3000 random castle paths with doors flipping, the
same; heat and light over 20 door flips, the same to the bit).

- **Paths.** `find_path` asked "does this tile burn?" of every neighbour,
  and heat_at went through every entity (39 in the castle) for heat that
  only a creature might carry, which none does. `is_burning` now asks once
  a tick whether anything carries heat, and reads the map's heat alone if
  not. What the terrain allows across a step is remembered per zone (walls,
  heights and stairs do not move; a diagonal past a door edge is still
  asked each time, as the door decides it), and the open list is a heap.
  A search: 2.9 ms on average, worst 30, to 0.5, worst 7.
- **Doors.** A door opening or shutting made every torch, fire and lantern
  in the zone work out its reach again, line of sight to each cell twice
  (for heat, then light): 16 ms, every time a goblin went through a door.
  Each source's share is kept, a door redoes only the sources that reach
  it, the line is traced once for both, and the totals are summed from the
  shares in the old order: 0.7 ms.
- **Pip's asks.** Her description of what she sees (a line of sight to
  each cell within six) was worked out two or three times an ask; it is
  worked out once and handed on, and asked_about's patterns are compiled
  once: a voice ask, 10 ms to 3.3.

The castle tick, profiled: 2.3 ms on average with several over 15, worst
19, to 1.2, worst 8.

## 179. A companion warms her model when she comes into the world

Her asks time out quickly (2 s for a stance, 5 s for a line), and a cold
model takes the box about 30 s to load, so after Ollama restarted every ask
timed out until one happened to load it, and she fell back on her scripted
answers. When she comes into the world (her player joins, comes back or
respawns, or the console switches her mind), the mind now asks each
endpoint and model she uses to load, with a chat of no messages (Ollama's
load-only ask) and keep_alive -1. It goes on its own request with a 120 s
timeout, apart from her channels, so it holds up no stance or line, and
only one to each endpoint and model is out at a time; the reply is logged
("loaded in N ms") and not used. An OpenAI-shaped endpoint has no such ask
and is not warmed. Rejected: making the first ask itself wait longer, as
her answers are meant to come quickly, and one stuck ask would hold up
that channel for the whole load.

(Found while fixing her timeouts on the box: its Ollama had been kept off
port 11434 since Oct 6 by a reverse tunnel from the desktop, so her asks
went to the desktop's Ollama. The box's Ollama now listens on 11600, set
in /etc/psykinetic/env; box config, not the repo's.)

## 180. A wall at their back never fades; a faded one lingers

Standing beside a wall at their back (away from the camera), it faded, with
its run, about one spot in six in the castle and the test room: the
pieces' bounds were grown by FADE_MARGIN (155) so a grazing ray would
count, and a ray from a player beside a thick wall grazed the grown box of
the next piece along it, whose centre was on the camera's side. The
bounds are now the meshes' own, and the test is the line from the camera
to the player or their companion at their feet, middle and head (the
camera is orthographic: the line runs back from the point along the view,
to the camera's plane). Measured over every floor cell, at spots a step
off its centre and camera turns every 15 degrees: a wall at their back
fades nowhere (old rule: 3373 of 19530 spots in the castle); a wall in
front fades in 99% as before, the rest being where the line passes over
it. A wall still fades with its whole run (155). A piece that stops
hiding them stays faded for 0.4 s (FADE_HOLD), so walking along a wall,
its pieces handing over one to the next, does not flicker. What hides
them is worked out when the camera or they move (the camera's position is
in the key now, so a pan counts); the hold is checked every frame.

## 181. Monsters cost the tick in proportion to their number

Bigger maps are next, and tools/map_bench (a square dungeon of 8x8 rooms,
each with a door in each wall, a torch, a crate and two monsters) showed
the tick growing faster than the monsters: 193 entities 9.7 ms, 769
88 ms, 3073 1285 ms (a tick is 100 ms). Two things made it so; without
monsters even a 512x512 map ticked in 4 ms.

- **Looking for a target.** Every monster went through every entity, and
  a copy of the list, every tick, for the players and companions; two
  of its tactics went through them all again for the other monsters.
  World now keeps the zone's players and companions (sought()) and its
  monsters (monsters()), in id order, made again only when the entities
  change (a spawn, a despawn, a zone entered, a reset), so a look goes
  through the same candidates in the same order as before.
- **A door's light.** A door a monster walks through redid only the
  sources that reach it (178), but the totals were then added up again
  from every source's share: the whole map, every door. Now only the
  cells the redone sources can reach are added up again, from every share
  that reaches each, in the same order as the whole sum adds them, so the
  totals are the same to the bit (edge_test's six door flips against a
  whole recompute still pass). Which sources can reach a cell is worked
  out once a map.

The same bench: 769 entities 28 ms, 3073 110 ms, now four times the time
for four times the monsters (about 36 us a monster). What is left grows
with how many monsters think at once; a monster far from every player
could think less often, a choice for later.

## 182. The floor is drawn by MultiMesh, and shaded only where it changed

The 3D client made a node of the kit's floor piece for every floor cell,
half a millisecond each: 12 s to build a 128x128 map, 49 s for 256x256
(tools/map_bench), most of the build. The floor is now one MultiMesh per
16x16 square (FLOOR_CHUNK) and ground kind, the same piece, each cell's
colour and glow in its instance colour and custom data, drawn by
client3d/floor.gdshader: the kit material's lighting (rough, not metal),
the kind's texture (none for stone) times the cell's colour, plus its
glow. A cell's colour is worked out as before (its kind's, darkened by the
light it lacks, warmed by the heat on it), so the castle and the sample
map look the same (screenshots before and after: the sample within 8 of
255 everywhere; the castle differs only where monsters had moved).

Shading the floor went through every cell, and heat_at through every
entity for each, on every change of the fields: half a second at 128x128,
on every door a monster opened. Fields now keeps the cells it added up
again since the client last took them (take_touched; all of them after a
whole recompute), and the client shades only those, sets a cell only when
its shade changes, and reads the map's heat alone while nobody carries
any, as World.is_burning does. Rejected: one MultiMesh for the whole map
(no culling off screen) and per-cell materials kept as before with fewer
of them (the nodes were the cost, not the materials).

128x128: 12.0 s to 3.0; 256x256: 49 s to 12, the rest mostly walls.

## 183. The kit's pieces are loaded once; a host builds its map once

After the floor (182), a 128x128 map still took 3 s to build, nearly all
of it in load(): the kit's scenes were loaded for each wall, door and post
and held by nothing once instanced, so each was let go and the next load
read the .glb from disk again, half a millisecond a piece (an instance is
6 us). Client3D keeps each piece's scene once loaded (_kit_scenes, for
the run). And a host drew its map twice on starting: the views in _ready,
and again when it first showed its home zone, which was that map; the view
is now marked as showing it.

tools/map_bench, 3D build: 128x128 3.0 s to 0.28, 256x256 12 s to 1.15
(49 s before 182).

## 184. The 2D view is drawn only where it is seen; shadows only near the view

Main drew the 2D view (floor tiles, a WallEdge node a wall) on every peer,
the 3D client and the server too, where nobody sees it: 1.5 s at 256x256,
18 s at 512x512, as it asked whether each cell was fire and each wall's
neighbours floor by going through the map's lists. It is drawn now only
where it is the view (_draws_2d: no 3D view, not a server), and where it
is, by sets: the 3D client starting a 256x256 map, 4.3 s to 1.6.

Torches and carried lanterns cast shadows only while their reach
overlaps the ground the camera shows (the ortho view's half diagonal on
the ground, plus the light's range, plus SHADOW_MARGIN), sorted again when
the view moves a cell or changes size and every SHADOW_RECHECK (0.5 s) for
lights that move. Measured, it changes little: Godot already draws no
shadow for a light off screen (1025 shadowed lights at 256x256, 36.5 fps;
all shadows off, 37.1). It keeps that so for lights the view's frustum
would still take in. Rejected: a fixed range in cells round the player
(a monster's sight, 7) — torches on screen would lose their shadows.

What holds a big map's frame rate down is the scripts each frame (35 ms
at 256x256, 3D view hidden or not), next.

## 185. A frame does work for what changed and what is near

A 256x256 map (tools/map_bench: 1025 entities, 1984 doors) took 25 ms a
frame, the view hidden or not; measured by turning each part off:

- **Synchronizers' visibility, 9 ms.** Each entity's and door's
  MultiplayerSynchronizer asked its visibility filter every frame (the
  default, VISIBILITY_PROCESS_IDLE), three thousand GDScript calls a frame,
  on the server too. They are set to VISIBILITY_PROCESS_NONE: a new one is
  asked when it spawns, and every change of who sees what already calls
  World.update_visibility (a player's zone set in _show_zone_to, on
  joining, travelling and leaving). net_test (a real server and clients:
  joins, returns, reset) passes.
- **Doors, 5 ms.** The 3D view looked at every door every frame, and each
  Door ran _process. A door now says when it comes or its open or hp
  changes (World.door_shown, on every peer, from the setters, so a
  replicated change counts); the view moves only those doors' leaves, till
  each is still (a float32 angle, compared near enough), and a Door's
  _process stops once its swing is still and starts again on a change.
- **Puppets, 4 ms.** Every entity's puppet was placed, turned, animated
  and its bar and footsteps kept up each frame. Only the puppets within the
  view's reach and PUPPET_MARGIN, or within earshot (Sfx.MAX_DISTANCE), are
  now; a far one keeps only its tile and hp (no footstep for the way it
  came, its bar showing a fight it had) and is placed when it is made.
  Position and turn are set only when they change.
- **Sprites, 2 ms.** An entity's 2D sprite bob, reel and flash are skipped
  where the 2D view is not drawn (GridEntity.draws_2d, from Main).

256x256: 25 ms a frame to 4.3. Rejected: MultiplayerSynchronizer
delta_interval (it slowed the frame), and updating far puppets in turn
(their state would go stale out of order; a far one is not seen or heard).

## 186. Releases land on main from any worktree

Performance work moved to a worktree of its own (branch perf) while other
sessions work in the main checkout, which often holds their edits in
progress. Only main is released, one tested change at a time, as before:
a worktree's change is rebased onto origin/main, tested, committed, and
released from the worktree. tools/release_client.ps1 checks first that
the commit has origin/main in it and that the tag is free on origin, and
pushes the release to origin's main (HEAD:main): a fast-forward, so a
release another session pushed meanwhile makes it fail, not overwrite;
rebase and release again. Rejected: a perf branch merged now and then
(server and client must be on one version, so unreleased work waits, and
the sessions edit the same files, client3d.gd among them).

## 187. The server walks the way the client shows

Walking among monsters on the box rubber-banded, 1 to 5 corrections a
minute of up to 1.8 tiles, with the server's tick under 5 ms and a 20 ms
round trip: the prediction and the server disagreed. Reproduced locally
(a server on the castle, a client steering with --test-steer and striking
the nearest monster with the new --test-fight, 20 ms of --test-lag), and
traced step by step, the corrections had these causes, each fixed:

- **Two ways round the same monsters.** The client planned its walk once,
  from monsters' positions a moment old, and sent only the steps under
  way; the server re-planned every step from where they were then, and
  often went another way ("the server moved it elsewhere"). A move order
  now carries every step shown or planned (MAX_VIA_STEPS), and the server
  walks them while it can; a re-plan after a correction, or on the way (a
  step taken, a shorter way open), is sent again. The server still checks
  every step, and drops the client's way for its own only when its own is
  DETOUR_STEPS shorter (a passage taken when the client planned round it
  has cleared: net_test's two players crossing).
- **A strike's approach.** A strike order made the server drop the step the
  client was showing and strike from where it stood, or close in by a way
  of its own toward a target that had moved, while the client showed the
  step and its old way; when the server could not close in it dropped the
  order without a word, and the client walked on till its deadline and was
  pulled back ("no confirmation"). A strike now carries the steps under way
  (walked first), the client plans the approach again as the target moves,
  and stops when the target comes within reach of where the server has the
  striker; a dropped approach is reported (World.ORDER_DROPPED).
- **A step confirmed early, then planned again.** With the server ahead, a
  step not yet shown was confirmed; a new order dropped it with the
  unstarted ones and planned it again, unconfirmable ("predicted X, server
  has X"). Confirmed steps are kept.
- A refused step into the destination itself is refused once, not again
  the next tick.

Three runs each of the fight test: 15 corrections a minute to 9.3, the
worst 1.7-2.8 tiles to 1.5-1.7, "no confirmation" 6.3 to 1, the rest
mostly refusals (a monster took the tile first), which no prediction
foresees. Rejected: planning round a refused tile for a while (in a
passage it is the only way, freed a tick later; it sent a player on a long
detour), and the server keeping to its own way each step (the cause).

## 188. A faded wall shows its nearest surface only

Faded walls blended as plain translucent meshes: every face behind the
front one showed through (the inside of a tower, the far side of a wall),
the end faces where two pieces meet doubled into a light seam at each
joint, and as the camera or the player moved the pieces' back-to-front
order flipped and those overlaps flickered. Godot's depth pre-pass
transparency does not help: it writes depth only where a pixel is nearly
opaque, and a near piece is 0.3. Each near material now has a depth-only
pass (NEAR_DEPTH_SHADER: depth written, alpha 0) as its next pass, at a
render priority below its colour's, so every near piece's depth is drawn
first and its colour then only where it is the nearest surface: one layer,
the same whatever the order. Priorities are placed among the other
translucent things: water, the hover and click rings and the target
outline (0) are drawn before, so they still show through a faded wall;
the HP bars (10) after. The cost: something translucent in front of a
faded wall is washed by it a little, as the wall's colour is drawn after.
A faded wall now looks fainter than before, as it no longer stacks.

## 189. A resize moves level.json and height.png with the ground

The editor's resize (grow or shrink from any side) keeps everything where it
stands on the ground: a cell at (x, y) moves to (x + left, y + top), and so
does every cell named in level.json (an entity's tile, its patrol route and
gather point, the starts, spawn points, links and centre) and every height.
A level's cells live in three places (layout.png, height.png, level.json),
so a resize that moved only the picture would leave monsters on the wrong
tiles and links on no marker; `LevelMap.moved_config` is the one place that
knows every cell level.json holds, and `LevelMap.transformed` the one that
moves a picture's cells, edges and heights by any mapping, so prefabs
(extract and stamp with rotation) use the same two. What falls off a shrunk
side is dropped and named, rather than refusing the shrink. The editor now
reads height.png and writes it back after a resize, so the two images stay
the same size; it still does not paint heights. A resize is one undo step
holding the whole map and level.json before it, not a diff: maps are small
enough (256 x 256 is 65k cells) that a copy per step is cheap.

## 190. Prefabs are small levels, stamped by their non-void cells

A prefab (`levels/prefabs/<name>/`) is stored in a level's own format,
layout.png, level.json and an optional height.png, so the editor opens one
with `--edit=prefabs/<name>` to touch it up, the same code reads and writes
it, and Claude (builder pass 3) can be given one as it is given a level.
Its level.json keeps only what goes with the piece (entities, links, legend,
monster types). Stamping is a union, not a paste: void cells in a prefab
leave the map as it was, so shapes that are not rectangles (a round camp)
lay cleanly onto grass; an edge is the prefab's only between two of its own
cells with one not void, which means walls on a prefab's outline need the
ring of ground outside them to be part of it (the house and the field carry
one). Rotation is the same `LevelMap.transformed` and `moved_config` a
resize uses (decision 189), with facings turned as well; a stamp is one undo
step holding each cell, edge, height, entry and link it changed. Rejected:
a separate prefab format (JSON of cells), which would need its own reader,
writer and editor; and stamping void as void, which made every prefab a
rectangle that erased what was round it.

A group's anchor is its gather point (the roadmap's "The world
moves on"): the camp's imps are a group because they gather at one cell,
which a coarse world tick can move or hand over without running their AI.
No separate group record yet; one can be added when the world tick needs a
name or an owner for it.

## 191. Big maps start from a seeded tool, then the editor

`levels/wilds` (256 x 256) is written by `tools/make_wilds.gd` from a fixed
seed, not painted by hand: noise for the forest's edge, the groves, the
dirt and the ponds (groves and ponds under a size dropped, so they read as
shapes, not speckle), paths that walk toward a goal swung aside by noise,
and the hand-made prefabs stamped on with the editor's own
`Prefab.stamp_changes`. Painting 65k cells by hand is not the way to a
first draft; the tool is, and the editor is for the touching up after.
Rerunning the tool rewrites the map, so once it has been touched up by hand
the tool is a record of how it began, not a way to remake it. The castle's
side of the link was a hand edit (a link marker and two level.json
entries), so the tool never rewrites a map it did not make. Builder pass 2's
area tools (pond, grove, path, scatter) will do the same jobs one area at
a time, and the tool can then call them.

## 192. Area tools return changes; the editor lays them

The area tools (pond, grove, scatter, fence, path; `AreaTools`) are static
functions of the map as it is, an area or points, a few settings and a
seed, returning the changes they would make ({cells, edges}) without
making them. `LevelEditor.apply_changes` lays any such set, a prefab's
stamp too, as one undo step, taking the level.json entries and links of
the cells it covers. Builder mode (pass 3) needs exactly this split: Claude
calls a tool, the server shows the changes as a ghost, and only Enter lays
them, through the same undo. A seed makes a result repeatable, so "again"
is undo and the next seed, and a request can be replayed. A tree is a void
cell (outdoors one is drawn as a tree), so a grove and a scattered tree
need no new cell type; a fence is a wall, drawn as a castle wall until
there is a fence edge kind, which needs the sim and the 3D view and is left
for later.

## 194. The world map is read from the levels, not kept beside them

`WorldMap.build()` (`sim/world_map.gd`) makes the graph of areas and ways
from every level's own files each time it is asked: a level is a node, a
point link (`links`) or an edge link (`neighbours`, a side and a level) is
an edge. There is no world file to fall out of step with level.json, and
renaming or adding a level needs nothing else edited. It needs no scene or
GUI, so the editor's node map, the builder's new area at an edge and the
world tick's routing all take the same graph. Its `problems()` is the one
connectivity check (the level test's own link check now calls it): a way
to no level or to a missing spawn point, a way with no way back, a
neighbour not named back on the opposite side, cells in level.json off the
map (the cells `LevelMap.moved_config` moves, so a new kind of cell there
is checked too), spawn points and starts on no floor, and areas that cannot
be reached from the default map or have no way back to it. A link with no
way back on purpose says `"one_way": true`. Rejected: a separate
`levels/world.json` listing areas and links, which would repeat what each
level.json already holds; and checking only that a link's target exists,
which misses dead ends a player can walk into and not out of.

## 195. An edge link is a bump against the map's edge

Walking off a map onto its neighbour (level.json `"neighbours"`) happens
when a player's move fails against the map's outline where that side has
a neighbour: World emits `walked_off` for any move refused because the cell
ahead is no floor, and main checks that the cell is past the map's edge
(`WorldMap.side_off`) and that the side has a neighbour, then travels as a
link does (decision 128: the player and their companion, nobody else),
arriving at the matching cell of the opposite edge (`WorldMap.arrival`:
same row or column, clamped to the neighbour's size, nearest free cell).
The outline keeps its wall, so walking, pathing, sight and pushes need no
second rule at the edge (as decision 148 wanted for forest edges), and a
monster pushed or chasing to the edge just stops. The maths is static and
needs no player, peer or zone, so the world tick can move a group across
with `WorldMap.crossing`. Rejected: opening the outer wall on a neighbour's
side and travelling on stepping out of bounds, which would let pushes,
paths and sight leave the map and need guarding everywhere; and treating
the border cells as link markers, which would throw a player walking along
the edge into the next map and give up a row or column of every map.

## 196. The editor's level is a MapDoc, with no screen

The level editor kept the map, level.json, the undo stack and saving in its
own Node2D, mixed with its panels and drawing, so nothing else could edit a
level the way it does. `MapDoc` (editor/map_doc.gd) now holds them:
opening and saving the three files, `apply_changes` (a prefab stamp, an
area tool's fill), `resize`, entries and links by cell, and undo and redo
of every step, with a `changed` signal. The editor delegates to one and
redraws on `changed`; builder mode's server side edits one the same way,
so an edit Claude proposed and a player accepted is an undo step like one
painted by hand, and is saved by the same code. The editor's own strokes
(painting cells and edges, a monster's facing and idling) still change
the map directly and hand their undo step to `MapDoc.push`.

## 197. Builder mode: Claude's tools change a copy, the proposal is the difference

A builder request (an area of a level and a sentence) is a `BuilderSession`
(builder/). Claude is given the area as a character grid with a margin,
its walls, doors and level.json settings, the legend, the items and the
prefabs (each drawn the same way), and tools: paint, edges, path, pond,
grove, scatter, fence, place (a thing and its settings), stamp, and look.
The tools are the editor's own (AreaTools, Prefab, MapDoc.apply_changes),
run on a working copy of the level and kept to the area; a call that cannot
be done (a thing outside the area, a prefab that is not there) goes back to
Claude as an error, which it can correct. The proposal is not the list of
calls but the difference between the copy and the level, as one change set
(cells, edges, heights, and the entries and links of the cells where any of
those differ): that is what the ghost shows, and accepting it is one
`MapDoc.apply_changes`, one undo step, the same as a stamp in the editor.
A follow-up ("bigger", "move it north") goes on in the same conversation,
from the level as it was: Claude remakes the whole proposal knowing what it
did, rather than patching a proposal it can no longer see whole.

The conversation is only ever added to, Claude's turns sent back as they
came (thinking blocks included, which a changed history would invalidate),
with the system prompt and tools first and cached, so a follow-up reads the
long prefix from the cache. Every response's usage is logged with its cost,
and a request stops at a dollar limit of its own (the Console's limit is the
account's). `ClaudeClient` asks the Messages API with raw HTTP (no SDK in
GDScript) on Claude Opus 5.5 at medium effort, with server-side refusal
fallback, the key read from the server's environment only; `StubClaude`
answers from a script, so the whole flow is tested without a key.

Who may build: a host's own player, and on a server the player ids in
`--builders` (`PSYKINETIC_BUILDERS`); it is on only with the key in the
server's environment or `--builder-stub`, so no client can spend money it
was not given. Accepting rebuilds the zone the way `zone reset` does, not
healed, the players where they were: simple, and correct for anything the
level spawns, but everything else in the zone is spawned again, so a chest
already emptied is full again (a builder can duplicate loot) and a fight is
interrupted. That is acceptable for a dev tool; changing only what the
proposal touched is the better way when it matters.

## 198. The world map editor edits level.json, through MapDocs

The node map (`--world-map`, `editor/world_map_view`, Godot's GraphEdit)
draws WorldMap's graph and edits only what the levels already hold: a
neighbour (both sides at once, `WorldMap.join`/`unjoin`), a link's target
and spawn point, or a link taken out. Each level it touches is opened as a
MapDoc (decision 196), so it saves the way the level editor does and
builder mode can make the same edits with no screen; the graph is rebuilt
from those MapDocs after every edit, so the wires and the problems panel
always show what Ctrl+S would write. Where the boxes sit is the only thing
it keeps of its own, in `levels/world_map.json`, which nothing else reads.
It does not make point links: a link needs its marker on the map, which is
the level editor's to place, and a double-click opens it there. Rejected:
a world file the node map owns (it would repeat level.json, decision 194),
and laying the boxes out by the maps' places in the world (there are none
yet: the edges a neighbour joins are its only geometry).

## 201. Routes between areas run over the ways' ends, at real walking lengths

The world tick's routing (`WorldRoutes`, from `WorldMap.routes()`) is an
AStar2D whose points are portals, the ends of each way, not areas: an exit
(a link's marker; an edge's floor cell nearest its middle) leads one way to
its arrival (the link's spawn point; the matching cell across the edge) for
one step, and inside an area each portal is joined to each other at the
length of the real walk between them. Those lengths are worked out once,
when the routes are made, by a walk over the area under World's own step
rules (walls, corners, ledges, stairs; doors open, as a group opens them;
a diagonal 1.5 steps, World.DIAGONAL_TICK_SCALE), because a straight-line
guess goes badly wrong through a castle's walls. Costs are in steps, so a
group's speed turns a route into time. The A* graph takes its cost per edge
from the routes (there is no geometry between areas, so no estimate: it is
Dijkstra), and asks `blocked(way)` and `extra_cost(way)` on every crossing
each time, so ownership or a locked gate can later close or slow a way with
nothing rebuilt. Built with a WorldMap and kept with it: an edited level
means a new WorldMap and new routes. WorldRoutes keeps the map's areas and
ways, not the WorldMap, so the two do not hold each other. Left for the
world tick's own design: where a far group's position is kept, and how it
moves along a route each slow tick. Rejected: one point per area, which
cannot tell a short crossing of an area from a long one; and lengths by
octile distance, which miss every wall.

## 193. Far monsters think less often; the world moves on at a slow world tick

Replaces 127 (empty zones sleep). The world is not paused where nobody
is (docs/roadmap.md, "The world moves on"), but it does not need the
10 Hz sim there either.

tools/map_bench at 256x256 (2048 monsters, one player in a corner), the
tick split by hand-placed timers: about 20 ms of find_path for monsters
idling, 22 ms of light worked out again for the doors wanderers opened
(4 ms a door), 2 ms for the door's log line, 2 ms looking for a target,
the rest the loop itself. Fights were nothing; idling far from anyone
was nearly all of it. (The bench's stdout matters: through a pipe its
log lines cost another 40 ms a tick, so the 97 ms on record was 61.)

- **Tiers.** A monster's distance (Chebyshev) to the nearest player or
  companion in its zone sets how often it thinks (World.Tier): within
  NEAR_TILES (30) every tick, to MID_TILES (60) one tick in
  MID_EVERY_TICKS (4), staggered by id, beyond that not at all. One with
  a target (a fight) is always NEAR. Each monster's tier is looked at
  again every TIER_EVERY_TICKS (5), staggered by id. With nobody standing
  in the zone (a player dead, waiting to respawn) it is measured from
  where they last stood (Zone.tier_origins): measuring from nobody put
  every monster back on the full tick at once (868 ms the tick it
  happened). A zone nobody has ever stood in (a test room) runs at the
  full rate everywhere.
- **The world tick.** Every WORLD_TICK_STEPS (300 steps, 30 s) every zone,
  awake or asleep, moves on its far monsters (all of them, asleep) in one
  coarse step (Monster._world_tick): no paths cell by cell, no hits. For
  now that step ends a fight and puts a monster on its way back after one
  where it idles (World.place, straight there if it is free). Who holds
  what, where groups are and what has grown go here as they come. It runs
  with nobody connected, as World._process runs on the server regardless.
- **Waking.** A zone wakes as the world tick left it; from there each
  monster thinks as near as it is to whoever came (World._woke).

tools/map_bench, average and worst tick, stdout to a file:
128x128 15.4 ms and 44.6 to 3.7 and 16.2; 256x256 61 ms and 216 to 11
and 27. Rejected: pausing far monsters (the roadmap's rule), and
working each monster's tier out every tick (2048 distances a tick for a
distance that changes slowly). Next for the tick: a door's light (only
the sources it reaches are redone, but the list of every source is gone
through, and built, for each door), and more players spread over the
bench's map.

## 199. Levels edited in the game live in a user:// overlay

An exported game reads its levels from its pck, which cannot be written,
and a deployed server is one. So a level changed in the game (builder mode)
is saved under `user://levels/<name>/` (`Level.OVERLAY`), as a whole level
(layout.png, level.json, height.png), and `Level` reads a level there
before `res://levels/<name>/`: `exists`, `source`, `load_level`, `names`
(a level made in the game is only there) and `folder_of`, the one function
that says where a level's files are (the world map editor's view uses it).
The repo stays the source of truth: the console's `builder export` lists
the overlay's files and where they go in levels/, they are committed there,
and `builder drop <name>` removes the overlay's copy. Until then the server
warns at boot about each level it reads from the overlay, since a later
change to that level in the repo would be hidden by it. Rejected: writing
into the install directory (replaced by every deploy, and the service may
not write there), and keeping the edits as a list of changes replayed on
the pck's level (a replay breaks as soon as the level in the repo moves on).

## 200. An edited level is sent to clients: the "terrain" message

Terrain was never sent over the network: every peer reads a level from its
own pck, by name. A level edited in the game differs from that, so the
server sends it: a "terrain" message carries the level's layout.png and
height.png (as PNG bytes) and its level.json, as the server reads it. A
client registers it (`Level.register`), so the level is read so from then on
(a zone switch, a reconnect), and if it is in that zone it parses it, has
World mirror the new terrain and draws it again; its entities come and go
through the spawners as ever. The server sends it to everyone in the zone
after an edit, and to a player entering an edited zone just before its
"map" message, so a player who joins later sees the edit too. A whole
level rather than the changed cells: it is small (a 256 x 256 level's PNG
is tens of kilobytes), it cannot fall out of step, and it is the same
format the files and `Level.parse` already use. PROTOCOL_REVISION is 5.

## 202. Routes' distance fields are made on the pool; a group's place along a route comes from them

Each way end (portal) gets a distance field: the steps from it to every
cell of its area, a PackedFloat32Array indexed by cell (-1 where it cannot
walk). They are made on a WorkerThreadPool task started when the routes
are made (WorldMap.routes()), because one field over the wilds takes a
quarter of a second and the server's tick cannot wait for several. The
task reads only copies of the areas' floor, edges, heights and stairs
taken when it starts, never a MapDoc, the World or the WorldMap, and hands
each area's fields back under a mutex as it finishes it; the A* graph is
only ever touched on the caller's thread, which joins an area's portals
from its fields the first time a route needs that area. Until an area's
fields are in, a route through it walks the area there and then (correct,
slow on a big map), and `is_ready()` lets the world tick wait a world tick
instead, which perf prefers: routes are asked only when a group picks a new
goal. With the fields, a route's first and last legs are lookups, so a
route between areas costs no walk at all; one inside a single area still
walks from start to end (its length is not in any portal's field).
`along(legs, cells)` gives a group's area and cell after that many steps
(perf: the world tick advances speed x seconds in cells and keeps an area,
a cell and the route), stepping down the field of the portal a leg leads
to, so the cell is on a real shortest walk; a leg no field covers falls back
to the floor cell nearest the straight line. Fields are rebuilt with the
WorldMap (a level edit, a builder accept), never patched. Freeing the
routes stops the task at its next portal and waits for it. Rejected: making
the fields on the server's thread at load (seconds once the wilds has a
few more ways), and fields per area pair instead of per portal (no cheaper
to make, and along() needs the per-portal ones).

## 203. A light's lines are worked out once; a door asks only its doors

A door a monster opened cost 3.6 to 4.5 ms (tools/map_bench, now
measured on its own: "door flip"), 85% of it each light that reaches the
door walking its line to every cell in its reach again (has_clear_line,
some 81 lines a torch). Only a door on the way can change those lines:
walls, heights and where the doors are stay put till the map changes.

Fields now keeps, for each fixed light, the cells in its reach whose line
the terrain lets through, each with the doors that line crosses
(World.line_doors, the same walk as has_clear_line with every door left
to the end); a light done again asks only whether those doors are there
and open. A line that passes a door on a diagonal step, where it depends
on either of two ways round, is walked as before (World.LINE_ASK). The
lines are worked out with the light's first share and again only on a
whole recompute (a new map, a door node added or gone). The list of
lights is kept too, not made again for every door. The amounts are the
same to the bit: the same cells, the same distances, the same sums in the
same order; edge_test compares the lines with walking them for every light
and every cell in its reach, the castle's and a random maze's, doors shut,
open and mixed.

Door flip 3.6 ms to 0.85 at 128x128, 4.5 to 1.04 at 256x256; the
256x256 tick 11 ms to 8.4 on average, 27 to 20 at worst. Rejected: a
light spread by flood or shadowcasting (it would not light the same
cells as the line its creature's sight and heat use).

## 205. A new area beyond the edge is a drafted level, joined in one step

Builder mode's `new_area` makes a level past an edge of the one picked,
when the area picked touches that edge and nothing is beyond it yet. Three
things have to happen together or not at all: a way out (the outdoor edge
is a band of forest, so the way across must be carved to the map's last
row or column, where the bump that crosses is made), the two levels named
as neighbours both ways, and a new level that opens where the way arrives
(the same row or column, `WorldMap.arrival`). The way and this level's
neighbour are one `MapDoc.apply_changes` (its "config" changes are undone
like cells), so one undo takes both back; the new level is a fresh MapDoc
(`AreaDraft`: grass, dirt, groves, maybe a pond, forest round it, a gap in
the forest where the way arrives, a start just inside), joined back with
`WorldMap.put_neighbours`, and saved to the overlay before the level picked,
so a way never leads to a level not yet there. Undo removes the new level
when nothing names it any more, and is refused while anyone is in it. The
new level is a draft, not a design: Claude makes it in one call, and a
follow-up in it (the area there) builds what was asked for. The ghost
outlines it past the edge. Rejected: having Claude draw the new level cell
by cell in the same request (a 64 x 64 level is 4096 cells of tool calls);
and opening the new zone at once (it opens on the first visit, as any zone).

## 207. The world tick walks real ways, a little each step

Jeff's rule: movement is real, and nobody walks over ground. The world
tick (193) put a monster that was away after a fight straight back where
it idles (World.place), a jump. It now walks there (World.walk): along
find_path, step by step at its own step times (diagonals 1.5), for the
time gone by since its last world tick, and stops where that time runs
out; a monster too far to arrive gets as near as the walk can (find_path's
new nearest: the way to the tile it looked at nearest the goal) and goes
on next time. Nobody is near to see it, so it lands at the end at once.
Held ground does not stop it yet; that comes with faction-aware routes
(206).

- **Cost.** The search looks at WALK_SEARCH_PER_STEP (8) tiles for each
  step the time allows, not the whole map (190 ms corner to corner at
  256x256). The walker shuts the doors behind it: doors are left as they
  were, so a walk nobody sees works out no light again (that was 70% of a
  walk). A patroller with no route yet walks home, its first waypoint, and
  works its route out when it is near and thinking (three searches; it was
  all of a 32 ms first slice).
- **Spread.** Each monster still gets a world tick every WORLD_TICK_STEPS
  (300), but in WORLD_TICK_SLICES (10), a slice every 30 steps, by id; a
  slice queues its monsters, and each step goes through the queue for
  WORLD_TICK_BUDGET_USEC (2 ms) at most. Each moves by the time since its
  own last world tick (Monster.world_step), twice WORLD_TICK_STEPS at
  most, so waiting its turn costs it nothing. A queued monster that has
  come near someone, or whose zone is gone, is passed over.

tools/map_bench now times the worst of it: every monster put up to 8
tiles from its post (into the next room, often) and walking back. At
256x256 a slice queues 193 walks, gone through in 44 steps of 5.7 ms at
most (the budget, and the one walk that runs over it); all of them at
once would be 1.16 s, which no step does. The 256x256 tick: 7.5 ms on
average, 12.5 at worst. Rejected: the slices alone (a slice of 193 walks
was 32 to 385 ms in one step), and opening the doors on the way (each a
light worked out again, for a walk nobody sees).

## 208. The world's clock is kept; the world waits while the server is down

World.steps (the world tick's clock, and each monster's world_step) began
at 0 on every start. It is saved in the snapshot now, as a top-level
"steps" beside zones and players, and Main takes it back at boot: the
world tick goes on from where it stopped. Jeff's call: while the server is
down the world waits; there is no catching up on the downtime (a deploy
would otherwise move the world on by however long it took). Players being
away pauses nothing: the server runs the world tick with nobody on.

The key is optional, with no new snapshot version: a file without it
starts the clock at 0, as before. Snapshot.save takes a fourth argument,
the world's own keys for the top level ({"steps": ...}), where the
holdings (204) go too.

## 204. Factions hold places; held ground is a place's radius

What enemies win by holding is places: a cell and a radius in an area,
declared in its level.json (`places`, with a kind, a worth and who holds it
at the start), so a level, a prefab and builder mode's `mark_place` all
make them the same way, and a resize, a turn or a stamp moves them as it
moves the rest of level.json (`LevelMap.moved_config`). The factions are a
small hand-written file, `levels/factions.json` (goblins and town for now,
each with its monster kinds and who it is hostile to), and "nobody" holds
what no faction does. Who holds what now is `Holdings`, on the server's
World, made at boot from the levels and then the snapshot's `holdings` key
(passed through Snapshot.save's world argument; a file from before it, or
one an older server reads, still loads). It keeps each place's holder,
strength and since (a World step; saved as an age, so it reads right on
any clock), and says when a place changes hands. Held ground is the cells
within a held place's radius, not the whole area: a goblin camp in the
wilds holds its camp, not the wilds. An area's holder is a label (most
worth of its places) for the view and the world tick, never passability.
A place nobody holds is open ground and counts for no one; ground two
factions' places cover is contested. Nothing in play shows it yet; the
world map view colours areas and places by holder. Rejected: holding whole
areas (one camp would close a 256-cell map), and a world file of places
apart from the levels (it would fall out of step with them, as decision
194 says of links).

## 209. A monster's search for its target has an end

tools/map_bench took one player, in a corner: the kindest case for 193's
tiers. With --players=N (N - 1 more, spread over the map on a grid, too
tough to die so none is away respawning) a 256x256 tick was 213 ms on
average and 1428 at worst with 4 players, 65 and 163 with 9. Timed part by
part, four causes (209 to 212).

A monster with nowhere free beside its target (or one of no kind) looked
for a way to the target itself with no end. Round a surrounded player
there is none, so each such monster searched the whole map, every tick:
173 ms a tick of the 213. It looks at CHASE_SEARCH_TILES (400) at most now:
its target is in sight, so a way longer than that goes round a crowd it
cannot get through, and it waits where it is, as when there is no way.

## 210. Plans that take many searches are worked out a few a step

Players arriving bring hundreds of monsters near at once, and every
patroller worked its own loop out on its first turn (up to nine searches
each): 112 ms in one tick. World.take_plan lets PLANS_PER_STEP (8) be
worked out a step, all zones together, in id order; the rest wait a step
or two (a patroller with no loop yet stands, or after a fight goes home).
And a stroll's spot and a loop's waypoints, all within a few tiles of
home, are looked for in twice the square round home at most
(ABOUT_SEARCH_PER_TILE), not 400 tiles: a spot that needs a long way round
is not about home. Rejected: a budget for every plan a monster makes (the
same monsters, first in id order, would always go first, the last never).

## 211. An idling monster keeps its way

A monster idling planned its whole way again at every step, most of what
idling cost near players. It keeps the way (Monster._idle_path) and plans
again only when its next step is taken, it is somewhere else (pushed,
moved on by the world tick) or the goal changes; a stroll walks the way
its spot was found by, with the same small search. A way that a monster
has since stepped into is seen at the next step and planned round then.

## 212. Fire burns who stands where it burns, not everyone asked

The hazard phase asked every entity in the zone whether it burns: 3000 a
tick on the bench's map. With nobody carrying heat (as now) it takes the
creatures standing on the cells whose map heat burns (Fields.hot_cells),
in id order as before. Those cells are found once, then kept up as each
door's heat is added up again (a list made again after every door was 9
ms a tick, worse than before). Anyone carrying heat: every entity is asked,
as before.

The four together, the same bench: 4 players 31 ms on average and 54 at
worst; 9 players 46 and 80; 1 player 7.4 and 14. Still over the 20 ms
target with players spread out; what is left is idle monsters within
NEAR_TILES of someone (about 20 ms at 4 players).

## 206. Routes keep off held ground: a layer per faction, and "meets" where they cannot

Jeff's rule: held ground is physical. A group may not walk through cells
another faction holds (a held place's radius; contested ground blocks
everyone; a place nobody holds blocks no one), inside areas as well as at
crossings. WorldRoutes keeps a layer per faction that moves, plus an open
one: each layer has its own obstacles (cell -> the place holding it, from
Holdings.blocked_cells), its own A* graph (the same crossings, closed where
an exit or arrival is held), and its own distance fields, flooded with the
obstacles as walls. Holdings.make_routes builds them with today's
obstacles and attach keeps them current: a place taken changes ground in
its own area only, so only that area's fields are made again, on the pool;
a version per area and layer drops a task's fields if the ground changed
again meanwhile, and until the new ones are in, a route through that area
floods it with the new obstacles (always right, slow on a big map; never a
stale field, because movement is real). When there is no way round,
route() does not just say no: it takes the open route and walks it,
passing held ground the faction can get round (it can still reach the
open cell past it) and stopping at the first ground it cannot; the
faction's own route to the open cell before it comes back, its last leg
carrying "meets" and the place's id, so the world tick knows whose ground
it reached and can make the encounter (fight or take). A goal in held
ground is reached the same way, to its edge; a group standing in held
ground gets one leg going nowhere, meeting it. [] only when there is no
route even ignoring held ground, or a blocked(way, faction) hook closed it.
The extra_cost hook is gone: ground is not dearer to cross, it cannot be
crossed. Rejected: costs instead of walls (against the rule); obstacles
applied per query on the open fields (a flood of the area every route);
cutting the open route at its first held cell (a town group would stop at
a camp it could walk round).

## 213. find_path keeps its search in flat arrays over the zone's grid

With players spread over a 256x256 map, find_path was most of what idle
monsters near them cost, at about 5 us a cell looked at: each neighbour a
handful of dictionary lookups keyed by Vector2i (opened, closed, cost,
came from) and a Vector3i one for the terrain memo, and is_burning, three
calls deep, for every one.

The search now works over the zone's grid: the floor's bounds and a pace
beyond (World._grid_rect, worked out once a terrain, kept in the Zone
with the rest), each cell an index. Its state is in flat packed arrays by
index (_search_opened, _closed, _cost, _from, _order), each entry stamped
with the number of the search that wrote it, so nothing is made or
emptied for a search; the heap holds indices. The terrain memo is a
PackedByteArray by index and direction (Zone.grid_steps, was path_steps).
Burning is asked once a search: with nobody carrying heat it is a lookup
in the fields' hot cells (212). Cells beyond the grid are not floor, so
blocked, as before. The same cells come out in the same order, ties and
all: checked against the old search on 600 searches in tools/map_bench
(goals taken or not, every cap, nearest), none different, about 2.8
times as fast. Rejected: one dictionary of records per search (the
dictionaries were the cost), and clearing the arrays for each search
(65536 cells at 256x256, for searches that look at a hundred).

The 256x256 tick: 4 players 31 ms to 26 on average, 9 players 46 to 38,
1 player 6.1; corner to corner about 190 ms to 90 to 150 (noisy, with
other work on the machine).

## 214. A world tick's walk keeps off ground another faction holds

Jeff's rule: nobody walks over ground another faction holds (206). The
world tick's walk (207) went by find_path within its zone, through
anyone's ground. find_path takes walls now (cells it never steps into,
the goal among them), and World.walk gives it the cells the walker's
faction may not walk: World.held_against, Holdings.blocked_cells for the
zone and the faction of the monster's kind (Factions.of_kind; a kind of no
faction may walk only nobody's ground). It goes round them, or, with no
way round, as near as it can get (find_path's nearest): the edge of the
ground in its way. One already standing in such ground has met its
holders and does not walk. What comes of a meeting (a fight, a taking) is
the world tick's, with groups, later; for now a monster stopped at the
edge tries again at its next world tick, so it goes on once the ground
changes hands. Rejected: maps' routes (WorldRoutes.route) for this walk
(they are between areas; this walk stays in its zone, and the same walls
give the same answer without a second graph).

## 215. Full rate within a screen of someone; a fight anywhere

Replaces the "full rate within 30" of 193 (Jeff's call). With 16 players
spread over a 256x256 map nearly every monster was within 30 cells of
someone, so 193's tiers saved nothing: some 1400 monsters thought every
tick, most of them idle and on nobody's screen. NEAR_TILES is 16 now
(about a screen); from there out to MID_TILES (60) a monster thinks one
tick in MID_EVERY_TICKS (4), and beyond, the world tick, as before. A
monster in a fight thinks every tick wherever it is, as before; one idle
at 16 or more cannot see anyone (sight 7), so it notices nobody later
for it.

And looking for a target measures the distance first, before asking what
each player or companion is: most looks end there, the same answer for
half the cost (7.4 ms a tick to 4.2 with 16 players).

tools/map_bench, 256x256 at castle density (--cells-per-monster=42),
average and worst tick: 4 players 26 / 46 ms to 22 / 43, 9 players 31 / 47
to 28 / 50, 16 players 41 / 61 to 35 / 59 (another bench running on the
machine for part of it). Still over 20 ms with players spread out; what is
left is idle walking within 60 cells and going over every entity each
tick. Rejected for now: the monsters' thinking in C# or a GDExtension
(Jeff: not now).

## 217. A client is sent what is near its player, by chunks

Every client in a zone was sent every entity and door in it (decision
126): on a 256x256 map, 3072 entities and 1984 doors spawned to each client
as it joined, about 2.5 MB, and the server froze 1.1 to 1.5 s doing it
(tools/net_bench.sh). Now `Interest` (net/interest.gd, `Net.interest`)
narrows the synchronizers' visibility filters further: a peer is sent what
stands in the 8x8-cell chunks within 4 chunks of its player's (about 36
cells), and a chunk it sees leaves only beyond 5 (about 44). The view's
widest reach is 24 to 28 cells and sounds carry 30, so nothing pops in or
goes quiet in sight or hearing; the hysteresis keeps a thing at the edge
from flickering. A peer always sees its own player and companion. Doors
are things like the rest (at their edge's cell); lights are terrain, every
client has them all. Entities and doors are kept in an index by chunk,
from Main's spawns and World's entity_moved and entity_despawned, so a
player crossing into another chunk asks again only the synchronizers in the
chunks that came or went, and a thing crossing a chunk border is checked
against each peer once. Events go to GridEntity.viewers(), which asks the
same filter, and the death message now goes to those that see the dead (the
host's own client always), so a fight out of sight sends nothing. Leaving
interest is a despawn on that client: its puppet goes quietly (deaths are
their own message, the party log is the server's), and a door coming back
does not sound its swing. A zone rebuilt (a builder change accepted) keeps
each peer's chunks, so only what is near is spawned again. `--no-interest`
turns it off. With it, a server takes 16 players by default (Jeff's
number, up from 4); `--max-players` sets another. Rejected: per cell instead of per chunk (a check for every
thing on every step), recomputing every frame (decision 185 took the
filters off the frame for a reason), and a ring per thing kind.

## 218. An idle monster walks straight when it can

With many players spread out, most of the tick was idle monsters walking
(215 cut who thinks every tick; those that do still walk): a path search
for nearly every stroll and patrol leg, a few tiles over open floor.

An idle step goes straight at its goal now (Monster._direct_step: the
step toward it, or one of that step's two halves, each nearer, never
farther), if the terrain allows it (World.terrain_step_open: walls,
corners, ledges, doors it opens, not into fire) and the tile is free; it
plans a way (find_path, kept as in 211) only when that is shut. A stroll's
spot, and a patrol loop's waypoints, are taken without a search when they
can be walked to straight from where it stands, or from home
(Monster._straight); a search only for the rest. Path searches with 16
players spread: about 26 a tick to 12. Around a corner it may walk a
step or two the plain way where a planned way would cut it; it is idling.

And the act phase goes only through the entities that have a turn
(GridEntity.acts; a crate's or a chest's _sim_tick does nothing), kept in
id order with the rest of the roster: the same turns in the same order,
a thousand fewer looked at on the bench's map.

## 219. A monster with no way to its target looks again in a moment

A monster round a crowd with nowhere free beside its target looked for a
spot beside it (120 tiles) and then for any way to it (400, 209) every
tick, and with players too tough to die on the bench, crowds only grew
(7.5 ms a tick with 16 players, rising through a run). With no way at all
it now waits CHASE_RETRY_TICKS (5) before looking again: a crowd does not
open in a tick, and it still strikes at once if its target comes beside
it.

The two together, tools/map_bench at 256x256 and castle density over
1000 ticks (the steady state; the 200-tick runs include the start, doors
opened the first time and loops worked out): 16 players about 30 ms on
average to 24, 9 players 15 to 18, 4 players 13, 1 player 3.9. Worst ticks
are still the start, when players arrive and hundreds of monsters wake at
once; next.

## 216. The ground is one mesh a chunk, its kinds blended by noise

Jeff: the world looks far too blocky; the grid stays the rules and the
visuals stop showing it. The floor was the kit's floor tile on every cell
(182's MultiMesh a chunk and kind), each cell one flat colour: every cell
edge and every change of kind a straight line. This replaces 182's floor
(its touched-only shading stays). Each FLOOR_CHUNK square is now one
ArrayMesh with a vertex at each cell corner (one per height where cells of
different heights meet), drawn by client3d/ground.gdshader. Which ground is
where is a texture of a texel a cell (grass, dirt, stone, sand by channel;
sand ready for a map that paints it, no kind added), read linearly at a
point pushed about by noise, each kind given a ragged edge of its own and
the strongest kept with a short soft band: kinds meet along wandering
borders, not cell edges. Each kind's look is noise too (grass patches,
dirt grain, irregular cobbles for stone), worked out only where that kind
shows, from one noise texture made at run time (FastNoiseLite, seamless,
read turned at an odd angle so its repeats never line up with the cells):
no texture assets, so nothing for THIRD_PARTY.md. Gradient noise and an
integer hash, not value noise: value noise showed its lattice as squares.

Light and heat stay a cell's (same snapping, same sRGB sums), but are
drawn on the corners: a corner is the average of the cells around it at
its height, so they fade from cell to cell. Perf's rules for it: the mesh
is never rebuilt to change colour; each chunk's attribute stream (CUSTOM0,
RGBA8, stride and offset from RenderingServer's format functions) is kept
in one byte array, only the touched corners are written, and each chunk
with a change is sent once a frame, the span that changed, by
surface_update_attribute_region; corners on a chunk's border are in every
chunk that has them, so a cell there dirties its neighbours' chunks too;
each cell's corners (in every chunk) are worked out once at build, so a
changed cell costs array reads, no lookups per corner; the shading is
still once a frame, after however many changes. A headless mesh keeps no
attributes, so the view keeps what it sent and view_test checks that.

Fire cells were yellow squares: a fire is now a ragged flickering patch
1.5 cells wide (client3d/fire.gdshader), so fire side by side runs
together.

tools/map_bench, windowed, run alternately with the commit before: 128x128
frames 45.4 to 45.7 fps (before 44.5 to 45.1), draw calls 381 to 337;
256x256 11.9 fps (before 11.2), draw calls 391 to 352; the 3D client
rebuild 1.23 s to 1.30 to 1.35 (_build_ground 210 ms); a door flip's ground
shaded again avg 1.0 to 1.3 ms, worst under 3. Rejected: kind weights on
the corners (a path one cell wide came out half dirt), a vertex at each
cell centre too (more corners to write on each change; the kinds texture
gives the same for nothing), and noise worked out per pixel (it cost
frames; a lookup is cheap).

## 227. A far puppet stops altogether, and its entity's drawing with it

Amends 185. terrain measured map_bench windowed at 256x256 at 11 to 12
fps. Not a regression: the commit of 185 does 8.9 fps on this machine
today, the head 13.7 (both with the bench lock, nothing else running).
185 stopped placing, turning and animating far puppets from the script,
but each puppet's AnimationPlayer went on playing its clip, and its
skeleton posing, every frame: some 3000 rigs nobody could see; and every
entity's _process (its drawn position, slides and turn) went on too.

A puppet going far (beyond the view's reach and earshot, as 185) has its
processing stopped (PROCESS_MODE_DISABLED: its animation, skeleton and
all under it) and its entity's _process with it; coming near, both go on,
and the entity is shown where it is now (GridEntity._display_caught_up:
no slides it was sent meanwhile played out, as 185 already kept no
footsteps for the way it came). On the host its drawing is all _process
does; the sim's tick is World's.

tools/map_bench, windowed: 256x256 13.7 fps to 60 with vsync (95 with it
off, the worst frame 30 ms); 128x128 55 to 60 (255 off). Rendering is a
millisecond of a frame on the CPU and less on the GPU. The bench's frame
loop now turns vsync off and says the renderer's share. The 256x256 map
loads in 1.97 s with the 3D build.

## 222. Senses: a monster sees what is lit, in a cone before it, and remembers

What an agent sees, hears and remembers is one layer, sim/senses.gd
(class_name Senses), held by the agent and asked by it; it never acts.
Monsters use it now; companions are to, so the LOOK verb and "you hear
fighting to the north-east" come from the same rules as a monster's
notice: sees(entity), sees_cell(cell, dark) and light_level(cell) (a
threshold of the asker's: "it is dark there" is a reason to go and look),
heard_since(tick) (each noise's maker named only if it is seen when asked,
worked out then, not when the noise came), last_seen(entity), forget() (a
new zone, a rebuilt one).

Sight goes cheapest first, as the look did: in range (Chebyshev, the
look's own sum), then the cone (a dot product of the offset and the
facing, against cos 60 degrees: 120 degrees before it), then the light,
then line of sight (walls and closed doors), the expensive part, last.
Within NOTICE_ALWAYS (1) a monster notices you whatever the light or its
facing. Lit is: the one looked at glows (emit_light, a lantern), or the
map's light at its cell (light_at(cell, false), a lookup) is DARK (0.35,
the companions' threshold) or more, or the lanterns carried near it
(World.carried_lights, players and companions with a lit lantern, made
once a tick) bring it there, each by distance before its line. Never
light_at with carried lights per monster: that goes through every entity.

A monster of a kind has the cone; a monster of no kind sees all round, as
monsters did. The target it already has it follows cone or not: it turns
as it chases (alertness, next, replaces this with memory). Memory is where
and when (World.tick) it last saw each one, dropped after MEMORY_TICKS;
every time is a tick, so a monster thinking one tick in four reads the same.

No level sets "ambient" yet, so every map is fully lit and the light
changes nothing there; the cone does. Rejected: a light test by flood or
shadowcast (it would not match the line the light and the views use);
light per monster through Fields.light_at with carried lights.

## 223. A noise is told to those in reach when it happens

World.noise(at, radius, kind, source) finds who hears it once, at the
noise, and pushes it to each (Senses.hear): nobody listens every tick. A
small noise looks at the cells in reach ((2r+1)^2 lookups, fewer than the
monsters); a big one goes through the monsters with a distance sum. One
with no clear line to it (a wall, a closed door between) hears it only
half as far; the clear line is walked only for those in the outer half.
Its maker does not hear itself. Each keeps its last HEARD_MAX (8).

How far, in cells (Senses.NOISE_*): a step 3 (players and companions;
monsters do not hear each other walk), speech 10 (HEARING_RANGE, as
players hear it), a line in capitals 20 (a shout: three letters or more,
none small), a whisper 2, a blow or a swing 8, a door opened or shut 6, a
door struck 10, a door broken 14.

What a monster does with it now: with nobody in sight, the newest noise
it has not turned to (heard within LISTEN_STALE_TICKS) turns it that way,
the nearest of its eight, and it holds still LISTEN_TICKS to look; a guard
turns back to its way after. Alertness (suspicious, going to look) is next.

## 224. A player covers or lights their lantern (L)

Every player and companion carried a lit lantern, so with sight by light
nobody could go unseen in the dark. L sends "lantern"; the server sets
the player's emit_light to 0 or Player.LANTERN (0.9), which is now
replicated, so every view draws it (the 3D view hides the lantern light)
and the light fields use it. Covered, you are seen in the dark only from
beside you, or by someone else's light. Companions keep theirs lit: a
companion covering hers is a companion verb, later. The lantern's model
and hand stay pc-character's.

## 225. Whispers: "/w words" carry two cells

A line starting "/w " is said, without the prefix, to the players and
companions within WHISPER_RANGE (2, Senses.NOISE_WHISPER) rather than
HEARING_RANGE, logged as whispered, and makes a noise of that radius. It
is parsed on the server, so a client needs nothing new. Shouting is not a
command: a line in capitals carries farther to monsters (223), not to
people.

## 229. A crowd woken together starts idling in turn

Players arriving bring hundreds of monsters out of FAR at once (193,
215), and every one, its idle timers long run out, chose a spot, worked
out a loop or planned a way on the same tick. One whose tier comes out of
FAR, or is worked out the first time, or whose zone wakes (World._woke
has every tier looked at afresh), is woken (Monster._woke_up): its idling
starts WAKE_SPREAD_TICKS (20) at most later, a moment of its own by id.
Looking out and fighting start at once: nothing reacts later for it, and
one on its way back from a fight goes on.

tools/map_bench, 256x256 at castle density, 200 ticks from the start:
16 players 27.7 ms on average to 25.4, the worst 48 to 44; 4 players 16 to
19 to 14 to 18, the worst 30 to 37 to 29 (one run had a lone 72). What is
left of the start is work done once a run: patrollers working out their
loops (210, eight a step) and doors opened the first time (their light);
loops are kept and doors stay open, so a server that has run a while
sees little of it. Rejected for now: working loops out at zone load on
the pool (worth it if fresh areas still spike in play).

## 220. The art is slots: a manifest names everything drawn, ArtKit draws it

The game is moving off the Kenney kits to its own art, made by Jeff over
time, a piece at a time. Each thing the 3D view draws is now a named slot
in art/kit/slots.json (wall.straight, door.single, tree.broadleaf, ...),
with its size in metres, its kind (an edge piece runs along z centred on
the edge's line; a vertex or cell piece stands on its origin), its
triangle budget, its moving parts (named, with pivot, axis and range),
where the game uses it and where its art came from. docs/art_style.md is
the look and the conventions a slot's art follows. The terrain pass reads
the same manifest: wall.profile (the section it sweeps along wall runs, a
cap line above which a top is kept whole), wall.rubble (a gap's blocked
piece), ground.<kind> and material.rock / material.wall (tileable
textures, procedural colour while empty), and a scatter slot's placement
fields; the density by terrain kind stays terrain's. Slots a tool makes
from a catalog (the items', one a catalog entry) go in a manifest of their
own beside it, art/kit/slots_<what>.json, merged in as read (a name taken
twice is an error), so the tool never rewrites the hand-kept file. An
item is a "held" slot: its origin at its "grip" socket, a two-handed
one's other hand at "grip_2".

ArtKit.instance(slot) is the one way the view gets a piece, at its real
size: the slot's own art (art/kit/<category>/<slot>/<slot>.glb, variants
<slot>.2.glb ...) if it has some; else its fill, a third-party piece the
manifest names with an offset and scale that bring it to the slot's
conventions (today's Kenney pieces, so the game looks as it did); else a
grey box of the slot's size, its moving parts boxes of their own so a door
still swings (settings.cfg art_placeholders=1 shows every slot so, and
art_labels=1 names them). An instance is the slot's name holding "Body"
and a node per moving part at its pivot (a door's leaf); the client turns
the part, and fades the body. The .blend a slot's .glb was exported from is
committed beside it as its source: Blender import is off in this project,
so Godot ignores .blend files and the server's headless import needs no
Blender.

The fade (188) no longer assumes one shared kit material: a near piece's
every material, a surface's own or an override, is swapped for its
see-through copy (_see_through_of, as trees did), since a slot's own art
may have several. Rejected: a .tres resource per slot (the tools and
terrain read JSON as easily, and one file shows every slot at once); a
slot packed once into a PackedScene and instantiated (on a 256x256 map's
first build 2.7 MB and 4.5 ms an instance; ArtKit puts each together from
the kept .glb scenes instead, as 183 keeps the kit's); grey boxes
everywhere at once (the Kenney fills keep the game as it looks until a
slot's own art comes).

tools/map_bench 256x256, windowed, alternately with main (v0.1.135): the
3D client rebuild 1.16 and 1.15 s (main 1.22 and 1.14), main ready 2.12
and 2.09 s (main 2.12 and 2.08), 1089 more nodes (a post's wrapper), the
same draw calls, frames and memory. The castle, screenshotted on each:
the same but for the goblins' animation phase and the fire's flicker.

## 226. A stair is a ramp, a ledge a rock face, and the ground shows its drops

The sim walks between heights only by stairs (World.height_step): every
other rise is a ledge. So the smooth slopes Jeff asked for are the stairs,
and every other rise is a cliff. The ground (216) now gives each cell's
corners a level (Client3D._corner_levels): its height, and on a stair the
two corners on its high side a level up, so a stair is a ramp sharing its
top corners with the cell above and its bottom ones with the cell below,
and side by side stairs make one wide ramp. The stone steps are gone.
The sim also walks onto a stair from the side, from a cell at the stair's
own height, so a ramp's raised corner is raised for every cell round it at
that height too (_shape_ramps): the ground beside slopes up with it, one
vertex for all of them, where a wedge of rock would have shown a ledge the
sim does not have (view_test: no rock face on any edge the sim walks). The
ground's normals follow it (each corner the sum of its faces). A puppet's
height (_ground_height) follows the ramp across the cell, and the flat
marks lie on it: the hover outline and click ripple at the ramp's middle,
tilted with it (_lay_on_ground), the toss arrow at the height under it,
and a builder ghost's quads corner by corner (_height_in), so on a ramp
none is half under the ground.

Where an edge's corners stand above the neighbour's (or above the void or
water past it), a rock face runs down to them: one mesh a chunk, rows of
small facets (CLIFF_ROW high, CLIFF_ACROSS along a cell), each point
pushed by a hash of where it is alone, so two faces that share a point
push it alike and meet without a gap, and pushed less where the face is
low (none at a wedge's thin end, beside a ramp) and not at all on its top
and bottom rows, which meet the ground. Faceted, a colour a facet, darker
toward the foot. The old faces were a thin stone box a cell edge.

With every level the same green, a ledge read only by its face, flatter
than the boxes it replaced. So each corner also carries its relief in the
ground's CUSTOM0 b and a (set once at build; the shading writes r and g
only): at the foot of a drop (a cell round it higher), shaded to half; at
its top (one lower, or the void), lit a little. Both fade over the cell,
so a raised floor stands out from the one below.

A puppet's height is asked every frame: a cell with no raised corner (all
but a few) answers from its height alone, with nothing made; without that,
256x256 lost about a tenth of its frames.

tools/map_bench (no heights in its dungeon, so this is the cost where
there are none), windowed, under the bench lock, alternately with main
(v0.1.135), three runs each: 256x256 72.2 / 77.7 / 76.9 fps (main 77.5 /
69.7 / 77.2), rendering 1.0 ms CPU and 0.5 GPU a frame both; 128x128 210 /
222 / 216 (main 199 / 181 / 212); 3D rebuild at 256x256 1.19 to 1.26 s
(main 1.14 to 1.22).

Rejected: smoothing every rise into a slope (it would show walkable
ground where the sim has a ledge), and jittering the ground's corners on
a ledge to wobble its line (a corner a cell is a zigzag, not a wobble).

## 230. The stockpile: counts and gear, banked at a depot in a town-held stockpile place

The town's store (economy, step 1). `Stockpile` (`sim/stockpile.gd`),
kept as `World.stockpile` beside `World.holdings`: server only, made by
Main at boot from the snapshot, saved in it as a top-level "stockpile"
key through Snapshot.save's world argument (no version bump; an older
file loads with none).

One store per place of the new kind "stockpile" (Level.PLACE_KINDS, the
builder's mark_place and docs/levels.md list it), by place id, so a
second town is only another key. A store holds:
- the raw resources (RESOURCES: gold, ore, wood, cloth, food) as plain
  counts. Out in the world they travel as catalog items the `items` tree
  defines, tagged "resource" with a yield ({ore: 5} for a sack of ore);
  banking one will add its yield and end that instance ("banked"). The
  line agreed with items: resources are counts, not instances;
- gear item by item, by its uid in the item book (ItemBook, decision
  231), its history kept in the book and never copied here: the book has
  it at "stockpile:<place>", carried by nobody, with a "banked" event. The
  stockpile is a place, not a carrier: no carrier time runs while gear
  sits in it. A resource item put in a depot is banked as its yield
  (Items.yield_of) and its instance ended ("banked"). Gear saved by id in
  a snapshot from before uids comes back as a new, "migrated" instance;
- a ledger of the last 200 changes (step, what, count, by, from, uid),
  stamped with World.steps, for the reports and to check that nothing
  banked goes missing.

What "reaches the stockpile" means, with no town map yet: a depot (a
Chest with props {"depot": true}) inside a stockpile place's radius.
World.try_transfer into a depot banks the item at once (the slot
empties; the depot never keeps anything) if the town holds that place,
and refuses (nothing moves) if not: held ground is physical, and a raid
that takes the place shuts its depot. Picking loot up counts for
nothing. Hauling (step 2) widens "reaches" to whatever is carried,
dragged or carted into the place's ground; carts on tracks will hand
their load to the same Stockpile.deposit.

Players never withdraw: the economy builds the town, not one player's
wealth. Only the town's own work takes (Stockpile.take for resources,
Stockpile.take_item for gear, then World.put_item, each with a reason):
production jobs use resources, and banked gear goes back into use through
the town, sold or lent in the shop (step 5) or reworked by the smith
(step 3), so the store is not a sink. A store whose place is gone from
the levels is kept, never dropped, and losing a run never touches it;
raids (step 6) will take with a reason in the ledger, and what they take
can be rebuilt.

## 221. Dropped art is checked against its slot, in words that say what to change

A slot's own art (220) is made in Blender, by hand, by someone who is not
reading the code: a model in centimetres, an origin left at the corner, a
door whose leaf is called "Cube.003" or turns about the wrong edge would
each draw wrong in the game, quietly. ArtCheck (client3d/art_check.gd)
holds a slot's .glb to its manifest entry: its size (within the slot's
tolerance, 5% by default, plus 2 cm; even scaling off by a factor is named
as such, "modelled in centimetres?"), its origin (the base's middle, on
the edge's line for an edge piece; a held piece's is its grip), each
moving part by name with its origin at the slot's pivot, a held piece's
second grip, its triangles against the budget, at most three materials,
a scatter piece as one mesh with one material and nothing else, state
nodes the slot knows, a "source" in the manifest, and files in a slot's
folder that are not named for it. Each problem is one line that says what
to change, an error (it does not fit) or a warning (worth a look).

tools/art_drop.ps1 is the one step for the artist: a .blend is copied
into its slot's folder, exported to .glb through Blender
(tools/blender/export_slot.py: binary, +Y up, modifiers applied, custom
properties kept), imported, and checked; a .glb or .png is copied and
checked. tools/art_check.gd checks every slot's art at once, and
art_kit_test holds all of it to its slot, checks every grey box passes
its own slot's check, and that each kind of mistake is named.

A .blend saved after its .glb was exported is a warning in the tool, not
a test: the times are the files' own, which a checkout sets to when it
wrote them, so on another machine the order means nothing. The test asks
only that a .blend has its .glb beside it. Rejected: the drop tool writing
the slot's source into slots.json (rewriting the hand-kept JSON would lose
its layout; the check says the exact line to add), and Blender's own
validation add-on (it knows nothing of slots).

## 234. The act phase passes over a monster that is not on its turn

With many players a tick went through some 1600 monsters, and asked each
three things (is it alive, is it stunned, is it its turn) by call before
finding most were not on their turn: one in four ticks for MID (215), none
for FAR. The act loop now reads the tier a monster has (World._tier's,
kept TIER_EVERY_TICKS) and passes over one that is not on its turn,
without a call, when that tier is not due to be looked at again this tick
and it has no target: the same answer _thinks would give. Monsters say
they are tiered (GridEntity.tiered).

## 235. On nobody's screen an idler walks only straight

Beyond World.VIEW_TILES (30) of every player and companion a monster is on
nobody's screen: the view reaches 24 to 28 at its widest (maps measured it).
Idling there (a stroll, a patrol leg, back to its post or its place at a
gathering) it walks only by straight steps (218's _direct_step) and never
plans a way: blocked, it waits or goes elsewhere, as idling does when there
is no way, and a stroll takes only a spot it can walk to straight. Still
real steps at its pace, no jumps. Walking back after a fight keeps its
searches, and so does anything that is not idling (a monster hunting).

The two, tools/map_bench at 256x256 and castle density over 600 ticks:
16 players 25.4 to 28.3 ms on average (v0.1.137) to 20.4 to 20.9, the
worst 47 to 88 to 36 to 39; 4 players 12.6 to 14.4 to 8.9 to 9.7. Full rate
out to 28 cells (Jeff's ask, so that what is on a screen walks at its
pace) costs about 7 ms with 16 players (26.6 to 29.7); his choice between
that, a closer zoom, or 16 is open, NEAR_TILES stays 16 till then.

## 238. Full rate out to the view's widest reach, and the view a little nearer

Amends 215 (Jeff's call). Maps measured the view's widest reach at 24 to 28
tiles (zoom out to 1.4, a peek, a wide screen), so monsters 16 to 28 tiles
off, idling at one tick in four, could be on a screen, walking a little
slow. Of the three ways out (NEAR_TILES 28; the view no wider than 16; the
two met halfway) Jeff took the middle: Client3D.ZOOM_MAX 1.4 to 1.1 (the
widest reach about 19 to 22 tiles), and World.NEAR_TILES 16 to 22, so what
is on a screen thinks every tick. VIEW_TILES (235) stays 30.

tools/map_bench, 256x256 at castle density over 600 ticks, head of main:
16 players 21.8 ms on average with NEAR_TILES 16, 27.2 with 22 (28: about
28.6); 9 players 17.0, 4 players 10.9 with 22. Over 20 ms with 16 players
spread out, about 5 ms of it this choice.

## 236. Water is one surface a body, over a bed the ground sinks into

Water was two quads a cell (a flat blue surface, a flat bed under it):
every water cell a square, every shore a cell's edge. Its cells now join
the ground's mesh (216) as its bed: a corner with water on all four sides
sinks WATER_BED_DEPTH (less than FOREST_FLOOR_DEPTH, or the forest floor
under the map would hide it), so a pond deepens toward its middle and
meets its bank with no edge; a bed takes the ground of the land beside it
(_bed_kind), so the bank runs on under the water, and the ground shader
darkens what is wet. Over it, a body of water (cells joined side to side)
is one flat mesh just above the ground (WATER_LIFT), over its cells and
the land round them at its level that no wall parts from them, drawn by
client3d/water.gdshader.

The sim's rule is the cells: water is not walkable, land is. So the shore
must not mislead (the coordinator's guard): it is where the distance into
the water's cells (worked out exactly in the shader, from the mask, a
texel a cell, over the 9 cells round the point) equals a noise of at most
SHORE_WANDER, 0.2 of a cell, whatever the cells' shape, with foam on the
land side out to 0.1 more. A bilinear blur of the mask was tried first and
rejected: on a diagonal shore it filled a land cell's corner to within
0.2 of its middle. The water is deeper and less clear toward the middle,
ripples drift (two layers of the ground's noise, scrolled), and it is
drawn at render priority -1: under the hover outline, the click ripple
and builder's ghost (0, all above the water's height), and before faded
walls (188) as before. The sim and the map format are unchanged.

tools/map_bench (its dungeon has no water: the cost where there is none),
windowed, under the bench lock, alternately with main, three runs each:
256x256 46.3 / 48.2 / 59.1 fps (main 41.4 / 54.6 / 52.1), rendering 1.2
to 1.4 ms CPU and 0.3 GPU a frame both; 128x128 177 / 199 / 199 (main 194
/ 184 / 195); the 3D rebuild at 256x256 1.55 to 1.87 s (main 1.47 to 1.90).

## 231. Items are instances in a server-only book beside id slots; history on events

Items step 1 (roadmap: items). What a thing is lives in one catalog,
levels/items.json, read by Items (id, name, short, color, art slot
item.<id>, kind held/cell, size, weight, hands 0/1/2, tags, effects, use,
verb, yield); nothing is defined in code. levels/ because the export
already ships levels/*.json and the catalog is world data like
companions.json and factions.json.

Each thing in the world is an instance with a uid in ItemBook (World.items,
server only, saved in the snapshot's "items"): its id, where it is, who
carried it with steps held (World.steps; counted when a carrier lets go,
never polled; eight rows at most, the shortest-held dropped) and five
events at most (where it came from kept, the oldest other dropped).
Slots stay a replicated PackedStringArray of ids, so the wire does not
change and clients draw what they did; beside them GridEntity.slot_items
holds the uids and is never sent. History goes to a client only when it
asks (a later step), not with every slot change. Thousands of instances
are one Dictionary and cost nothing per tick.

World is still the only writer: try_transfer moves both arrays and writes
the history ("found" the first time anyone carries a thing, "given"
carrier to carrier; chests and the stockpile are places, not carriers);
take_item and put_item take a thing out of slots and put one back, for
holders without slots (economy's stockpile, later the ground). A
companion moves things as a player does, under the same reach rules (and
reaches its own player's pack). An instance lives until something ends
it (ItemBook.end: banked, eaten); gear is never ended. No sweep at save:
holders outside slots keep bare uids, and a test checks the book against
everything that holds one (orphans). Banking at a depot (230) keeps the
thing's instance, at "stockpile:<place>" with a "banked" event, until
the stockpile keeps uids instead of ids (economy's next change).

Levels, prefabs and the builder keep naming ids: they are specs. A level
chest's things get their instances when first needed (slot_uid: taken,
or saved), "stocked" there; a rebuilt room ends, as lost, what its
chests held unless the snapshot puts it back. A save from before
instances (slots with no "items") gets new ones, "migrated". Rejected: a
reference set per holder (every holder registering and releasing), and
gathering live uids from every holder at save (each new holder another
place to remember); replicating uids or history with the slots (a wire
change and bytes per move for something seldom looked at).

The catalog writes the items' ArtKit slots (art/kit/slots_items.json,
tools/items_art_slots.gd): held, a grip at the origin, grip_2 up a
two-handed one. ArtKit's grey box now carries a held slot's sockets but
the grip as empties, as its art must (ArtCheck), so a two-handed grey box
passes its own slot and the other hand has somewhere to go.

## 246. The slot preview reads art as it is saved

Making a slot's art is a loop of save and look, and the game shows a
.glb only once Godot has imported it, which needs the editor or a
headless --import of the whole project. tools/art_preview shows one slot
as the game's camera does (pitch, distance and default size from
Client3D; out no farther than ZOOM_MAX), on a 1 m grid inside the slot's
outline, the goblin beside it for scale, its moving parts swinging
through their range and its states in turn, and ArtCheck's lines on
screen. It looks at the slot's folder every half second: a saved .glb or
.png is shown again at once, and a saved .blend is exported through
Blender (tools/blender/export_slot.py, as tools/art_drop.ps1 does) and
then shown.

For that, ArtKit.live reads a slot's own .glb straight from disk through
GLTFDocument (packed as a scene once, as an import would be) and its .png
through Image, instead of the imported resource. Only the preview sets
it: art_kit_test fails if any other script does, so the game, its tools
and every export draw imported resources, as on the server box's
headless import. art_kit_test also writes a grey door as a .glb, reads it
back the live way, and holds it to its slot, so a part's name and pivot
survive the round trip.

Folded in: ArtKit._make clears a lifted part's owners (the .glb scene's
root) before moving it beside the body, which Godot warned of for any own
art with a moving part. Rejected: an EditorPlugin preview (the art is made
by someone not running the editor), and running an --import on each save
(seconds of the whole project's import a save, against a few hundred
milliseconds for one file).

## 248. No look for a target while everyone is far beyond sight

With full rate out to 22 tiles (238) some 930 monsters thought a tick with
16 players, and every one looked for a target, nearly always finding
nobody: sight is 7. World._tier keeps what it measured, the tiles to the
nearest player or companion (Monster.nearest_sought), and the zone's
comings then (Zone.comings: one more for each spawn, despawn and reset). A
monster with no target does not look while that measure is under
TIER_EVERY_TICKS old, nobody has come or gone since, and it is beyond its
sight by more than LOOK_MARGIN_TILES (8), more than anyone walks or is
shoved in that time. Someone arriving or respawning beside it is seen at
once (monster_test). Hearing is as before.

tools/map_bench, 256x256 at castle density over 600 ticks, 16 players:
26.6 ms on average to 24.1.

## 245. A run of wall is one swept mesh, varied, broken in places, never open

Walls were the kit's wall module on every wall edge: a row of cell-sized
blocks, each with its own inset panel, every top the same. Each straight
run of wall edges (to where it turns or meets another wall, a door, a
change of height, or WALL_RUN_MOST edges) is now one mesh
(Client3D._add_wall_runs): art-kit's wall.profile (ArtKit.spec: its points
and cap_y) swept along it. The body under cap_y rises and falls along the
run (a height every WALL_SWAY edges along the line, straight between, so
two runs on one line agree; up to WALL_HEIGHT_SWAY of cap_y either way),
the cap band kept whole on top. An edge's top is broken off now and then
(WALL_BROKEN: a slab of ragged height, WALL_BROKEN_LOW to _HIGH of cap_y),
and in a run of WALL_GAP_RUN edges or more an edge is, rarely, a breach
(WALL_GAP), its neighbours broken too. The sim keeps every wall, so a
breach must never read as a way through (the coordinator's rule until Jeff
says otherwise): it is a bank of rubble, wider than the wall and lumpy,
WALL_RUBBLE_LOW to _HIGH tall (at least art-kit's 0.6 m for wall.rubble;
taller, as a low bank between high walls read as a dip from above), under
broken stone either side. All of it is by a hash of where the edge is,
the same on every peer. Doors and posts are art-kit's pieces as before.

The stone is a StandardMaterial3D: material.wall's texture when Jeff gives
it one, until then courses of stone blocks made at run time (no asset),
UVs in metres along and up. A plain BaseMaterial3D, so a near run's
see-through copy is made as any other's (_see_through_of; a ShaderMaterial
would not fade) and the fade (188) is unchanged: every edge of a run is in
_walls as the run's node, so the run fades as one, as runs already did.
What hides the player is still asked edge by edge, each edge an occluder
with its own bounds (_edge_bounds): a whole run's bounds reach far past
the player, and its middle can be ahead of them when the wall is behind
(view_test's walls at the player's back faded until this).

Each run is built in its own frame (x across, y up from its base, z
along) and placed by its node, a south run turned a quarter (the profile
is the same either side); mapping every point into the world as it was
made cost the 256x256 build 460 ms. tools/map_bench, windowed, under the
bench lock, alternately with main, three runs each: 256x256 3D rebuild
1.56 / 1.56 / 1.49 s (main 1.47 / 1.36 / 1.31), frames 68.8 / 78.7 / 73.2
fps (main 68.7 / 77.9 / 98.0), nodes 85,575 to 49,031, static memory 445
to 394 MB; 128x128 rebuild 0.39 / 0.37 / 0.36 s (main 0.41 / 0.35 /
0.32), frames 189 / 200 / 244 (main 166 / 217 / 202).

## 232. Alertness: a monster looks into what it hears, hunts what it lost, and gives up

A monster of a kind is IDLE, SUSPICIOUS, HUNTING or FIGHTING (Monster.Alert);
one of no kind only idles and fights, as monsters did. A target in sight
is a fight, as before. Out of sight, it hunts: to where it last saw them
and on HUNT_ON_TILES (2) the way they were going (round the corner they
went round), at its chase pace. A noise or a glimpse (lit too dimly to
see, Senses.glimpses: between GLIMPSE 0.15 and DARK) sends it to look, at
its idle pace; a fight, a door struck or broken, a shout, to hunt (a
fight heard only through a wall or a closed door, to look); a blow from
one it does not see, after the striker. A fight now carries 5 tiles, not
223's 8: with 16 players fighting without end on map_bench, 8 kept some
170 monsters roused and on the move each tick, 10 ms a tick more under
load; World.noise now walks each listener's clear line to tell a muffled
noise (Senses: "muffled").

What it costs: map_bench at 256x256, 16 players, 1000 ticks, under load
(everything about 3 times its unloaded time): 69.5 ms a tick to 82.5. Not
the thinking: the senses add 1.3 ms, searching 2 to 3. It is the
fighting: a monster that lost sight of its target for a tick used to drop
the fight and walk home, and now hunts back and fights on, so with the
bench's players who never die some 35% more monsters are fighting (33 to
45 fighting thinks a tick) and resolving their hits (_resolve_hits 34 ms
to 43) is the cost. Kept as Jeff's design (pursuit), the bench being the
worst case; held in reserve, a monster whose target is already beset
by several going back instead of hunting. At its lead it looks round
(LOOK_ROUND, a turn each LOOK_TICKS). With nothing new for HUNT_TICKS (15
s) a hunt becomes a last look about (SUSPICIOUS, half SUSPICIOUS_TICKS),
and that, run out, sends it back to where it idles.

The leash: more than LEASH (20) tiles from where it took up the chase, it
gives up at once, fight or hunt, and lets that one be for GIVE_UP_TICKS
(10 s) unless they come within LEASH / 2 of there or strike it: it would
otherwise turn round at the first glance over its shoulder on the way
back. So you get away by outrunning its leash, or by breaking its line of
sight and not being where it looks. The anchor is where it took up the
chase, not its home: a patrol's route can run far from home.

Every timer is a World.tick, so a monster thinking one tick in four (a
hunt has no target, so perf's tiers treat it as idle) reads the same. Its
walk to a lead is _idle_step with the full search (IDLE_SEARCH_TILES); no
way there drops the lead, and it looks from where it is after
CHASE_RETRY_TICKS. The world tick (far, or the zone asleep) calms it: one
line in _world_tick, and it walks back by the world tick's own walk. The
senses cost only the glimpse's line of sight, for a candidate in its cone
and dimly lit.

## 233. How alert a monster is shows over its head

Monster.alert is replicated (on change; a wire change). The 3D view adds
" ?" to its name while it is looking into something and " !" while it is
after someone (hunting or fighting), on the name's own Label3D. It is
there for players to read a monster's mind (back off, hide, or run), and
for clips.

## 253. A monster's doors and fruitless blows are not logged

enemy-ai's profile (Jeff's game running on the machine) had hit resolution
at 46% of a tick with 16 players. It was printing, not hitting: the sim
logged every door opened or shut and every blow that shoved nothing
("push: Imp -> Player blocked: too heavy"), some 4.5 lines a tick with a
crowd round a player, and a line is slow to write when the machine is
busy or stdout is a pipe (a server's, into journald). Those lines (a door,
a dropped hit, a push that moved nothing) are logged now only when a
player or a companion does it (World._logs_for); a push that moves
something is logged whoever does it, as before (net_test reads a player's).
monster_test: a fight among monsters, doors and all, writes no line
(World.logged counts them).

tools/map_bench, 16 players, 256x256 at castle density, the median of
five blocks (--repeat): to a file 27.2 ms to 21.5; through a pipe 69.3
to 20.7.

## 239. Only the protocol decides who may join, not the build

A client used to be refused for any other version.txt (and, with the same
version, for another protocol fingerprint), so every client-only release
(the ground, art slots) forced a server deploy and turned away clients that
were only cosmetically different. Now the join compares Net.protocol()
alone; a client of another build with the same protocol plays, and the
server logs that it did. The version only says which side is behind when
the protocols differ: "client out of date" when the server's build is
newer, "server out of date" when the client's is (so a client never
mistakes an old server for a reason to update), "build mismatch" when
both claim the same version. Because joining now rests on it, the
fingerprint sees more by itself: each RPC with its arguments' names, for
every script in Net.RPC_SCRIPTS (monster.gd added); Door.REPLICATED and
every property entity subclasses replicate (Net.SUBCLASS_REPLICATED); every
message kind (Net.MESSAGE_KINDS, which Net.broadcast_to also checks at run
time). tests/protocol_test greps the project and fails, naming the file and
line, on a message kind, an RPC script or a replicated property not listed,
so a tree adding one finds out before landing. PROTOCOL_REVISION (now 6)
remains for what the fingerprint cannot see: a message's or RPC's fields,
a value's meaning, a spawn spec key; net.gd's comment above it is the list.
--print-protocol and the console's version let the release flow tell a
client-only release (same protocol: the server stays) from one that needs
a deploy. The "map" message now carries the server's build, shown in F3
when it differs. The first release with this still needs a deploy, since
older servers compare versions. Rejected: semver ranges (a version number
says nothing about the wire), and a separate hand-kept protocol number with
no fingerprint (it would be forgotten).

## 251. Production: workshops choose their work from the town's tier and compete for its raws

The town's work (economy, step 3). `Production` (`sim/production.gd`),
kept as `World.production`: server only, made by Main at boot after the
item book and the stockpile, saved in the snapshot as "production" (no
version bump). Its rules are data, `levels/economy.json`.

Records, all plain data:
- a worker: name, trades, town (a stockpile place id), origin, purse. A
  placeholder until rescued people (step 4) and town NPCs fill them; an
  NPC entity will point at its record;
- a workshop: trade, town, the worker in it. A building will point at it;
- a job: make (materials in, a new instance "made" out) or rework (a
  banked thing in, the same instance out with a "reworked" event: any
  gear whose recipe is the worker's trade, half its steps and one of its
  first resource). Repairs come with damage (step 6).

Recipes are the item catalog's "made" ({by: trade, from: {resource or
item id: count}, steps}); Production reads them through a catalog
callable (Items.def by default; tests pass their own).

Time is World.steps. A job takes its materials from the stockpile when
it starts (two jobs can't count on the same ore), and is worked while its
worker is at its workshop and not away (going away settles the work done
up to then). World.world_tick's first slice calls Production.tick, every
WORLD_TICK_STEPS: jobs advance by the steps since their last, in id
order; done ones go into the town's shop ("shop:<place>" in the book, a
list beside the store); then each town chooses new work. It depends on
the clock alone, so a server's downtime pauses it and nothing is caught
up; players being offline pauses nothing. The cost is a pass over the
jobs and workshops, a few dozen.

Nobody orders the work (Jeff): each town's workshops choose it from the
town's state. Signals, from data already kept:
- safety: threatened if the store's place isn't the town's, is at
  strength 0 or contested, or a "raid:" ledger line falls in the window
  (step 6); uneasy if a faction hostile to the town holds a place in the
  area; else safe;
- stock: gear in store and shop by tag against "wants" (raised by
  "uneasy_extra" unless safe), and whether every resource is at comfort;
- busyness: ledger lines in the window plus the town's jobs: quiet,
  steady or busy;
- raws players sold in the window (Production.note_sale; the shop calls
  it from step 5).
The tier is the first that applies: DEFEND (threatened: repairs, arms,
bandages, food), WORK UP (raws sold: work them up, then as STOCK), STOCK
(something short: the scarcest first), SURPLUS (all full: goods for the
shop, reworks), IDLE. It changes only when the new one has held
tier_hold ticks, so a town doesn't flap. Busy favours short recipes;
quiet adds reworks to any tier.

Workshops compete for raws (Jeff): every free workshop bids for its
tier's first want it could make from the store as it is; bids are granted
in order (a starved workshop, one that has lost starve_after times; then
orders; then the tier's key: DEFEND by trade, smith, carpenter, cook;
WORK UP using a sold raw; STOCK by shortfall; then the longest waiting,
then the workshop's id), each taking its materials; those that find them
gone wait and say so. SURPLUS lets every trade draw raws down to comfort
and the shop holds at most shop_cap of each thing, so neither raws nor
goods pile up. Production.order (tests, the console) goes ahead of the
tier's choice; Production.cancel gives a job's materials back.

## 254. Personal gold, taxes, the treasury and the sinks

Jeff: "player should be able to keep gold for personal use, but town
sinks gold, and everything is taxed and the tax goes to advancing the
town as a whole."

- A player's own gold (PlayerRecord.gold, coming with the shop, step 5)
  is theirs: it survives death and a lost run, and only their own
  spending, and the tax on it, takes from it.
- A coin purse stays an item until its holder opens it (items' use,
  their step 4): its yield goes to the holder's gold. Put in a depot or
  dropped on stockpile ground it is a gift to the town, untaxed.
- The treasury is the stockpile's gold. It pays for advancing the town:
  wages, upgrades (step 4), repairs (step 6), buying from players
  (step 5); never below gold_floor.
- Every transaction is taxed (levels/economy.json "tax", starting values
  for Jeff to tune): shop sales 20% to the treasury and the rest to the
  resident selling; the town buying from players keeps 10%; trades
  between players 10%; wages 10% (the town pays out the net).
  Production.taxed(amount, kind) splits any of them, the tax rounded
  down. Gifts and banking are not transactions.
- Sinks: residents pay rent from their purse every rent_every steps,
  destroyed as the town's upkeep (Production.upkeep counts it); no debt
  and no eviction when they can't. Buildings' upkeep from the treasury
  joins it with step 4.

Built now, with step 3: wages (taxed, down to the floor) and rent. The
player's gold and coin purses wait for items' use and the shop.

## 247. Hands are the last two slots of one slots array; ground items are per-cell piles under Interest

Items step 2 (carrying). A player's and a companion's slots grow from 4 to
6: the pack (0-3) and then two hands, Items.RIGHT_HAND (4) and LEFT_HAND
(5), also Player.RIGHT_HAND and LEFT_HAND. One array keeps one writer
(World), one replicated property, one save and one history path, and
try_transfer, take_item and put_item work on hands as they did on the
pack. Hands last, not first: a save from before them is the pack exactly,
padded by Items.tidy, so nothing migrates and no index anyone used moves.
Chests keep 4. World.hands_allow keeps the rule: a hand holds only what
can be held (hands 1 or 2), a two-handed thing only in the right hand with
the left empty; a move that breaks it is refused. Rejected: a separate
replicated hands array (a second writer, a second save and history path,
and every move between pack and hand a special case).

What a carrier holds weighs: World sets mass to base_mass (the mass it
had before it first carried anything) plus Items.weight_of over its slots,
whenever its slots change (_slots_changed), never per tick. Pushes,
shoves and tosses already read mass.

The ground is Zone.ground: cell -> ItemBook uids, four a cell at most
(more spill to the nearest dry floor within 3, World.put_on_ground). Each
cell with something on it has one GroundPile node (its cell and ids),
spawned and freed by Main through the zone's spawner on
World.ground_changed(zone, cell, thrown_from), and registered with
Interest like a door, so a client gets the piles in the chunks it sees
and nothing beyond them. A pile occupies, blocks and ticks nothing.
try_drop and try_pick_up reach the carrier's own cell and those beside it
with no wall between; a pick-up goes to a free hand that can hold it,
else the pack. Piles save with their zone ("ground": cell, uids, ids) and
a rebuilt room ends them as lost as it does its chests' things. Rejected:
an entity a thing (thousands of nodes on a big map, each in the occupancy
and the tick) and one replicated dictionary per zone (sent whole on
every change, to everyone in the zone, past Interest). The wire changes:
GroundPile.REPLICATED joins Net.protocol(), and PROTOCOL_REVISION goes to 7
(a carrier's slots mean six now), so an older client is told it is out
of date.

Keys, in both schemes: F picks up (the cell under the cursor in reach,
else one's own, else one beside), G puts down what is in the right hand,
else the left, else the last thing in the pack, and T throws the right
hand's thing (else the left's) at the cursor; the pack panel edges the
hands in brass, marked R and L. The 3D view draws a pile as each thing's
art slot lying on its side in a pale ring, and a thing just thrown flies
there.

The catalog also takes economy's "made" (how the town makes a thing:
{by: a trade in Items.TRADES, from: {resource or item id: count}, steps}
or {by, rework: an id, steps}), validated at load and left out with a
warning when it names no trade, no resource or item, or no steps; and
Items.add_for_test / Items.reset, so tests can use things the catalog
does not carry.

## 249. A thrown thing flies by strength over weight, and stuns what it hits

Items step 2. T throws what is in a hand at the cursor (World.try_throw).
Its reach is THROW_PER_STRENGTH (0.5) x strength / the square root of its
weight, 1 to THROW_MAX (6) cells: a player (strength 10) throws a 0.5 kg
kit 6 cells, a 10 kg sack of ore 1. The square root, not the plain ratio:
with it a few kilos still go a few cells, and the heaviest things a cell.
It flies a cell at a time, each a step toward the target (diagonals
first), over water and ledges; a wall or a closed door stops it, and so
does a body, which takes impact_damage(weight x THROW_FORCE_PER_KG (0.3),
mass_ratio(weight, its mass)) through _impact, as a push's collision does,
and is stunned by that force (_stun). It is not pushed: _push spends the
mover's mass as a budget and refuses any body heavier than it, so a thrown
thing would move nothing; the weapons step can add a push for heavy
things. It lands on the last dry cell it reached, its pile's thrown_from
and thrown_tick set so the views draw the flight; a hit is noted in its
history ("thrown", at whom). Rejected: reach from mass_ratio (clamped 0.5
to 1.5, so a kit and a sack went nearly as far), and a projectile entity
(a node, the occupancy and the tick for a flight a client can draw from
two cells).

## 228. What she says: near repeats, nothing new, the event log, her player as you

From the transcripts of 10-08 to 10-13. A companion's line is cleaned
before it is said (Companion.spoken, decision 151), and now:

- Lines are compared as plain words: lower case, punctuation gone,
  apostrophes straight or curly gone ("I’ll" and "I'll" are one; Pip said
  "I'm not leaving you" twice that way). Unasked, a sentence is also held
  back when it near_repeats one of her last REPEAT_LINES lines, a line
  another companion said within OTHERS_SAID_TICKS (20 s), or the
  narration in her exchange: its words, COMMON_WORDS aside and plural or
  -ing/-ed endings folded, are all in that sentence (two words or more),
  or share NEAR_SHARE (0.8) of both. Asked by her player, only the same
  line is held back; "Yes." to two questions is fine.
- Unasked, a sentence reporting a monster dead, down or fallen
  (event_report: "The imp to the north-east is dead.", "Brute is down.")
  is the event log said back and is not said. Asked, it may be.
- Her player is spoken to, never of: a sentence naming them other than
  as a call ("Jeff, behind you!") is not said, unless she is speaking to
  someone else. The voice rules say the same: speak to them as you, never
  of them by name.
- A reply of fewer than FRAGMENT_WORDS (3) words, unasked, is not said
  unless it is a call ending in "!". Asked or ordered, "Yes." and "On it."
  stand.
- Her voice is asked when something is new, not for every death: a
  monster's death only if it is big, the first of its kind she has seen
  fall this run, or the last of a fight; the first of a kind coming into
  sight asks too. After a fight, "you have said nothing since" is asked
  only if something in it was notable (someone's HP crossed a threshold,
  something big or new). What is new is kept on the Companion, which is
  made afresh on each zone and reset, so it clears there. On the logs,
  269 of 880 voice asks were deaths of a kind already seen to fall.

The castle playtest's other issues (10-09, 22:00) were already fixed by
decision 151, which landed that night: another player's words set no
stance, a player's words go to their own companion and another only if
named, she speaks to other players only when they named her or once a
minute in danger. tools/speech_replay replays a transcript through the
cleaning to show the difference.

Rejected: embeddings or a model call to judge repeats (a call per line on
the box's tick budget); dropping a whole reply when one sentence fails.

## 237. Companions perceive through Senses: sight by light, deaths witnessed, noises heard

A Companion has Senses (222) as the monsters do: Senses.new(self,
SIGHT_RANGE, -1.0). Her sight is all round, not a cone: she looks about
as she walks with her player, and a cone would hide from her what she is
asked about behind her. It is gated by light at her DARK (0.35, the
monsters' too) and line of sight last, so her map grid, her list of what
is around and her memory of the zone hold only what is lit; a dark cell
is "?", the ground for LOOK (her verb, next). Sightings of monsters
(_watch) go through senses.sees.

She knows only what she witnessed: Main tells her of a death only if she
sees the creature die (Companion.witnessed), or it is her own player.
Before, any creature within SIGHT_RANGE, walls or not.

She hears: World.noise tells companions as it tells monsters. World's
roster keeps _hearers (its companions), so a noise looks at those few,
not every player; _hear takes any GridEntity with senses. Monsters hear
as before. Each tick she takes what her senses heard since the last (one
comparison when nothing came) and keeps the noises whose maker and place
she cannot see: fighting, a door opened or shut, a door struck, a door
broken (NOISE_WORDS); steps are her party's and speech reaches her as
words (overheard), so neither is kept. A fight going on in one place is
one noise. Each is narrated ("You hear fighting, some way off to the
west, out of sight."), told in her voice's now for NOISE_TOLD_TICKS (15
s), and a loud one, calm, asks her voice, at most once in NOISE_ASK_TICKS
(30 s).

No level sets "ambient" yet, so today sight by light changes nothing in
the real maps; line of sight for deaths and the hearing do. Her hands
(whom she fights, the retreat) still look as before; they come over when
alertness does.

## 250. Hauling: what is let go of on the stockpile's ground is banked; carrying counts for nothing

Economy, step 2. Loot comes home physically, and counts when it reaches
the stockpile, never when it's picked up. Jeff: carrying something onto
the stockpile's ground banks nothing; only what is let go of there is.

- Dropped or thrown: World listens to its own ground_changed (items' step
  2: drops, throws landing, spills, put_on_ground). When something lands
  on a cell inside a stockpile place the town holds
  (Stockpile.place_at), the cell is banked once the change is done
  (call_deferred: taking it off inside the handler would change the
  ground again while Main is still handling it). Each thing comes off
  with take_from_ground and goes through the same banking as the depot
  (World._bank_thing): a resource item as its yield, its instance ended
  "banked"; gear as itself, its uid in the store. The ledger says who put
  it down (World remembers the dropper or thrower of each thing lying on
  the ground until it is taken off) and "the ground at x,y". Its pile
  goes as the cell empties.
- On ground the town doesn't hold, or with the place taken, things just
  lie there; nothing sweeps them in later when the town takes it back
  (someone moves them).
- Carried: nothing. A player walking onto the ground with a sack and a
  sword keeps both until they let go of them.
- Crates and carts (items' step 2b, Cargo): when one moves onto a cell
  of a town-held stockpile place (World.entity_moved, which every push
  fires), what it carries is banked once the move is done (deferred, as
  the ground): World.empty_container, then the same banking, the ledger
  saying it came on that cart (the pusher isn't known there). The crate
  or cart stays, empty, for the town to send out again. A thing with a
  yield the stockpile has no count for is put down beside it. Carts on
  tracks later move the same entity, so the same arrival banks them.

Hauling is physical and near players, so it runs on the full tick and
only on those events: a cached lookup per landing, no scan.

## 260. Errands: her voice chooses from what she can do, and promises only that

Jeff: "The voice may only promise actions it can do." A companion now
has real verbs, chosen by her voice and done by her hands; the mind
still never acts (the hands carry it out through World, as a player's
would).

When her player has just asked something of her, the voice's prompt
lists what she can do here and now (Companion.can_do), numbered: open
or close a door she sees (not broken), open a chest she sees and tell
what is in it, or go and look at a walkable cell she cannot see (dark
or out of line of sight, within her sight's range, the nearest one a
compass point, two of them), and come back. At most six, nearest
first. The prompt says only what is true and what she may do ("Only if
Jeff asked you to do one of these, add one more line: [DO: its number].
Of these things, you can only promise what is on this list."), never a
line to say. OllamaMind.parse_voice takes [DO: n] out as "do".

A promise is held to the list (_promises). A sentence that promises
(I'll, I will, let me, I'm going to, I can, on it) one of these verbs
(_errand_verbs: a chest opened, checked or looked in; a door opened,
closed or shut; a look with a compass point, dark, there, ahead or
around) is said only when it names exactly one listed thing (its
compass point, if it says one, must match), or the one [DO: n] chose;
then she does it. Otherwise it is not said: "I'll check the chest" with
no chest in sight, or a look that could be either of two. Unasked
nothing is offered, so such a promise is never said. A promise of
anything else ("I'll keep watch") is roleplay and stays.

The errand (Companion.errand) is one at a time, a new intent ERRAND
over her stance: going (her own A* steps), doing, and for a look
returning to within 2 of her player. A door is opened from a cell on
either side with World.try_toggle_door; a door World.may_open says she
cannot open (locked, and she has no key: enemy-ai's door step, 255-256)
is told to her as "a locked door" and is not offered, and sent to it
anyway she says "the door is locked". A chest is read, never emptied: taking and
handing over are step 4, through World.try_transfer. A look ends when
she sees the cell, telling what she sees within 2 of it. Done, the
outcome is narrated and her voice asked to tell it; that ask is cleaned
as an answer, since what she tells is new though the narration has it.
It ends undone when she falls below 30% hp, a monster she sees comes
within 4, after 20 s, or when her player asks something else (a quick
phrase, or an instruction the check confirms); undone because it could
not be done (no way there, broken, locked) her voice says so. Every
step is in the mind log as kind "errand". LOCK, UNLOCK and BAR follow
the door step and items' keys.

## 261. One palette, one material, for every slot's art

Jeff's look (docs/art_slots_review.md): flat-shaded, faceted low-poly like
the goblin, muted and earthy with a few saturated accents, flat colours from
one shared palette, no painted textures for now, and one shared material for
everything, a second only for a glowing or glass part. So
art/kit/palette.png is the atlas, 8 rows of 8 swatches 16 px across (stone
warm and grey, wood, earth, foliage, cloth and leather, metal, accents),
and art/kit/palette.tres the one material that shows it (sampled nearest,
so a face is exactly its swatch, roughness 0.9). A face is coloured by its
UVs lying in one swatch.

A .glb carries its own copy of every material, so ArtKit, loading a slot's
own art, sets each surface whose material is named "palette" to the shared
one on the mesh itself (every instance shares the mesh): all own art draws
with one material, whatever file it came from. ArtCheck allows one material
unless a slot says "materials": 2, and names any material that isn't the
palette ("colour it from the palette"); grey boxes are one grey a box, their
parts no longer a darker one. Budgets follow Jeff's answers: a door 600
triangles, a prop 300 to 800, a tree 1500. Rejected: a material per colour
(Blender's habit; dozens of draws a piece), vertex colours (no atlas for
Jeff to repaint, and Godot's importer keeps them only on request), and
replacing every material whatever its name (a slot's second, glowing
material must survive).

## 262. A slot's Blender template is its grey box, as the game makes it

Jeff asked for a template to model over: a slot opened in Blender at the
right size and origin, with its moving parts named. tools/art_template.ps1
<slot> writes art/kit/<category>/<slot>/<slot>.blend (never over one that
is there, unless -Force). Godot makes the slot's grey box with ArtKit, as
the game does, and writes it as a .glb (tools/art_template.gd); Blender
imports it (tools/blender/template_slot.py), puts every mesh in the one
palette material (261) with its UVs on the grey stone swatch, flat-shaded,
adds a "guide" collection holding the slot's outline as a wireframe box,
and saves. So sizes, pivots, part and socket names come from the one place
the game and ArtCheck read them, and the template, exported untouched,
passes ArtCheck (all but the source line, which is for whoever makes the
art). tools/blender/export_slot.py drops the guide collection's objects
from its run before exporting, never from the saved .blend.

Jeff's first five slots have their templates ready: wall.straight and
door.single were there; prop.crate (0.8 m, as the crate's puppet is),
prop.chest (its lid hinged on x along the back, opening to -100°) and
tree.pine (3.6 m, the forest's height) are new. Templates are made when
asked, not committed: a .blend in a slot's folder with no .glb beside it
is unfinished work, which art_kit_test refuses. Rejected: building the
boxes again in Blender's Python from the manifest (a second copy of the
grey box rules to keep in step), and committing templates for every slot
(eighty .blend files nobody asked for).

## 259. Crates and carts carry things: Cargo, a Pushable with slots

Items step 2b, for economy's hauling. Level.CRATE and Level.CART spawn a
Cargo (sim/cargo.gd, a Pushable): a crate of 4 slots, a cart of 8
(capacity; Cargo.MAX 8), filled by a level's props {"slots": [...]} as a
chest is (Level._prop keeps up to 8, the entity fits them to its size,
EntityFactory calling fit_slots). It pushes, tosses and breaks as before;
what it holds adds to its mass (World._weigh, from its spawn on), so a
loaded cart is harder to push and hits harder. World treats it as a chest
in every other way: reached from beside with no wall between, a place and
not a carrier in an item's history, its slots replicated and saved, what it
held ended as lost when its room is rebuilt. Broken (a crate has 12 hp), it
spills what it held onto the ground where it stood (put_on_ground). For
economy, World.empty_container takes everything out at once and gives the
uids; a cargo arriving on stockpile ground is economy's to see, from
World.entity_moved, which fires for every cell a push moves it. Boulders
stay plain Pushables.

A plain right click on a crate or cart within reach opens it (Main's
_release_toss: no drag, World.reaches); dragged, or from afar, it is shoved
or tossed as before, and walking into it still pushes it. Open question for
the weapons step (Jeff's call): the backlog's fighter controls (right click
grapple, right drag toss) will need to share or move this.

Not "Container": Godot has a Control of that name. The wire changes
(crates and carts spawn from a new script and replicate slots):
PROTOCOL_REVISION 8.

Updated (companions step 4): she hands things over and fetches them,
through items' World.try_transfer with herself as `by`, under its reach
rules: her own player only, within World.COMPANION_REACH (2) and in line
of sight; a chest she can strike. With her player in sight, can_do adds
"give Jeff your bandaging kit" for each thing she carries and "bring Jeff
the bandaging kit from the chest ..." for each thing in a chest she sees.
Fetching walks to the chest, takes it into World.free_slot_for(her), and
goes on as a give: walks until she reaches her player and puts it in
their free slot. A promise of either counts only when it names a thing
(the starts of an item's name or short name, from the catalog) or, for
fetching, the chest, so "I'll take the imps" and "I'll get them" stay
fight talk; a thing named narrows the list to it. An answer that gives or
fetches, and her report, may speak of her things (the bandages), which
her lines otherwise leave out unless asked. Bandaging an ally waits on
items' bandaging action (its step 4), which takes a companion as `by`.

## 264. A crate, chest, boulder or cart is drawn as its slot's art once it has some

Jeff is modelling the crate and the chest among his first slots, and his
art must show in the game, not only in the preview. The four pushable and
chest entities' spawn specs name their slot ("art": "prop.crate",
"prop.chest", "rock.boulder", "prop.cart"); a world snapshot keeps it, as
it keeps "kind". Client3D.art_slot_for(entity) gives that slot only once
it has art of its own (ArtKit.filled_by == "own"): then the puppet's Body
is a Node3D holding ArtKit.instance(slot), standing on the tile, and its
pick shape a box of the slot's size; till then it is its shape, tinted, as
before, so nothing changes until a slot is filled. The puppet stays a
puppet: its body under "Body", made once, paused with the rest when far
(185, 227); the outline finds the body's meshes as it does a model's.

"art" needs no PROTOCOL_REVISION bump: it is additive and ignored where
it isn't known (EntityFactory reads only the keys it uses), and a spec
without it draws today's look, so a client and a server of different
builds play the same; --print-protocol gives the same id before and after.

Rejected: the slot from the entity's script and shape (a crate and a chest
are both cubes, and items is changing crates' and carts' script), and grey
boxes for these four now (a grey crate would look worse than a tinted one
until Jeff's lands). A chest's lid stays shut: chests have no opened state
yet; when they do, the lid is the slot's "lid" hinge, as a door's leaf.

## 263. The rest of the catalogue: Jeff's slot list, with buildings as roof, floor and trim

Jeff kept every slot proposed and added twelve props (docs/art_slots_review.md).
How they are named and shaped:

- **Buildings are a roof, an interior floor and trim, never walls.** A
  building's walls are the map's wall edges, drawn by terrain's runs and
  faded per edge; walls in the slot would double them and fade as one
  block. So building.hut (3 x 3 cells), building.house (4 x 6) and
  building.shed (2 x 3) have no body of their own ("grey": "none") and
  three named parts that do not move ("motion": "fixed"): "roof", its
  pivot at the eaves (3 m, the wall height), so the buildings tree can
  hide it while someone is inside; "floor" on the ground; "trim" for
  eaves, ridge, chimney and porch. "footprint" gives the cells; the
  origin is the footprint's middle, the size the roof's overhang
  included. building.well is a whole piece in the open (rim and posts,
  a small roof part, no floor).
- **Scatter keeps terrain's names.** Jeff's plant.tuft, plant.flowers and
  plant.roots are scatter.tuft, scatter.flower and scatter.root, which
  terrain reads; plant.reeds is scatter.reeds; rock.small stays the
  forest's larger rock; rock.material is material.rock.
- **Wall heights are slots, not variants**: wall.<x>_low (1 m) and
  wall.<x>_tall (4.5 m) beside the 3 m wall.<x>, since a height is
  chosen, where variants are picked at random.
- **Doors** wider than an edge (door.double, door.gate) run 2 m along z
  with two leaves, leaf_a and leaf_b; door.portcullis's grate slides up;
  door.trapdoor is a floor piece, its lid hinged on x. All carry the
  states locked, barred and broken (256).
- **Ground textures** are 512 px tiling every 4 m (tile_m 4).

The buildings land first, as the buildings tree waits on them; the rest
follows in its own landing under this decision.

## 240. A server restarts with a countdown, and clients reconnect by themselves

Every deploy used to be `systemctl restart`: everyone was cut off without a
word, and a client that lost the server stayed on "disconnected from
server" until it was started again. Now the console has `restart
[<seconds>] [<why>]` (60 by default): the players are told in the party
chat, from "Server", at once and at 10 and 3 seconds left (three lines at
most, fewer for a short countdown); at 0 the server saves the snapshot,
disconnects each client (so it hears at once, not on a timeout), refuses
new connections for the half second the disconnects take to go out, and
exits with code 75, which the unit's Restart=on-failure starts again after
RestartSec=5. `stop` is the same countdown exiting 0, which systemd leaves
down: deploy.sh uses it, because a running server reads its .pck as it
goes, so the new build may only be installed once it has exited. deploy.sh
then installs and starts it, restarting it anyway if it is still up a
minute after the countdown or anything fails once it has stopped; a server
too old for `stop`, none running, or `--now` gets the old install and
restart. `restart cancel` calls either off.

A client that loses the server it played on (a restart, a crash) drops the
zone's entities, as on a change of zone, and connects again every 2
seconds for 3 minutes ("server restarting, reconnecting… (n)"), with the
same player id, so the server puts it back where it was saved; the map
message and the zone's entities come as on a first join. One that never
had a player (a wrong token, a rejection) does not retry. Nothing new goes
over the wire: the countdown is party chat and the reconnect a new
connection, so the protocol is unchanged. net_test's restart phase has a
client play, the console restart the server in 3 s, the script start it
again from the snapshot as systemd would, and the client come back on its
tile by itself.

## 241. An out-of-date client updates itself once, and starts again

A client turned away as "client out of date" used to say so and stop:
after a deploy that changed the protocol, every player had to quit and run
launch.bat. Now an exported game whose server is a newer build starts
update.ps1 (beside it in every release) and quits; update.ps1 waits for it
to exit (15 s at most, where it used to refuse while the game ran),
installs the latest GitHub release over the folder as launch.bat does, and
starts the game again, which joins. With decision 240's reconnect, a deploy
that changes the protocol brings everyone back on the new build by
themselves.

It never loops: before starting update.ps1 the game writes
update_marker.txt beside itself, and does not update itself again while
that is less than 10 minutes old (nor at all if it cannot write it); a
release that still does not match, say a server deployed before the
release was published, leaves the old message on screen. It never updates
on "server out of date" (the server is behind; the client is fine), from
the editor or a checkout (only OS.has_feature("template")), or without
update.ps1 beside it. The choice is SelfUpdate.refusal, unit-tested in
protocol_test; net_test checks that an out-of-date dev client would update
were it exported, and that a newer one never tries. A client of an older
build with the same protocol plays on and is told once, in the party chat,
that a newer game is out (the map message carries the server's build).

## 252. Scatter off the grid, trees in clumps, the land running into the forest

The ground (216) had no small things on it, and outdoors the forest's
floor was a flat plane under the void whose edge was the land's outline:
a stair of cells round every map. Three changes, all in the 3D view, none
in the sim:

- Scatter: grass tufts, flowers, small stones and roots, a number of each
  a cell by its ground (SCATTER_DENSITY: thick on grass, stones on dirt, a
  tuft now and then in a paved floor, roots where the land meets the
  forest), each by a hash of its cell placed off the cell's middle, sized,
  turned and leant (art-kit's scatter.* slots' scale, tilt_max and sink),
  on the ground's height there (ramps too), never on water or fire, tinted
  by its ground (drier off the grass, darker under the forest). One
  MultiMesh a chunk and kind, one material (vertex colours times each
  instance's), no shadows. A chunk's scatter is made when the view first
  comes within its reach (_grow_scatter, the nearest first, at most one a
  frame) and kept; chunks off screen are culled as any mesh is. The meshes
  are art-kit's slots' once they have art; until then small low-poly
  stand-ins made here, not grey boxes.
- Trees: still one on every void cell beside the land (the edge reads
  closed) and on others by chance, but the chance follows a clump field
  (smooth noise, FOREST_CLUMP cells across), thick in a clump, thin
  between; a tree is bigger in a clump's heart, leans up to TREE_LEAN and
  stands up to TREE_NUDGE off its cell's middle.
- The forest's edge: outdoors the ground's mesh runs FOREST_GROUND cells
  into the void, and the mask's g (beside water's r) marks those cells;
  the ground shader turns the land into forest floor along a line pushed
  by noise, as kinds meet, so the land's outline no longer shows.

Plain walls (for buildings-89, amending 245): a wall edge in
Client3D._plain_walls is drawn whole and level, its cap at WALL_HEIGHT,
never broken off, breached or swaying, and a run never mixes plain edges
with others. A house's walls carry a roof at WALL_HEIGHT: a ruined top
made a house look abandoned, and the sway pushed walls through the roof.
Whoever knows a building's outline fills the set before the room is
built; the sim is untouched.

## 274. Towns: experience, residents and buildings; the town chooses what to build

Economy, step 4. `Towns` (`sim/towns.gd`), kept as `World.towns`: server
only, made by Main at boot after Production, saved in the snapshot as
"towns" (no version bump). One record per town (a stockpile place):
experience earned and spent, residents (Production worker ids), buildings
({kind, level, state planned|building|standing|damaged, since, job}),
objectives done, a log. Rules in levels/economy.json ("xp", "residents",
"buildings", "level_speed").

Experience comes in only through hooks, which whatever decides these
things calls; economy decides none of them:
- add_xp(town, amount, reason): any accomplishment;
- note_rescue(town, who, name, trade): a rescued person reaches the town
  alive, once freed (Jeff: physical, like hauling): a resident, a
  Production worker with origin "rescued:<who>"; 10 experience (data);
- note_objective(town, objective, worth): a story objective done ("the
  smith brought home"), once per objective; 50 times worth (data).
Jeff: there are no "runs" (a relic of a dungeon-crawl loop), so no run
hooks. Nothing ever takes experience; only the town's own spending.
Losing never takes what's banked.

Companions count as residents while they are in town (Jeff): the
companions tree calls note_companion_in(town, name, trade) when one stays
and note_companion_out when it leaves with its player; its worker record
("companion:<name>") is away meanwhile, so its job waits with its
materials and goes on when it comes back. Its trade will come from its
card; until then the caller passes it (levels/companions.json).

Buildings: each kind may house a trade (forge: smith, kitchen: cook) or
not (inn: room for residents, walls: for step 6's raids). A workshop
whose trade a building houses works only while that building stands
(Production.workshop_open; raising it a level doesn't stop it), and each
level past the first makes its jobs level_speed (a quarter) faster
(Production.workshop_level). A trade no building houses (the carpenter)
works from the start. A resident whose building doesn't stand yet waits,
and is seated at its workshop the moment it does.

Upgrades: experience unlocks a building's next level (its xp times the
level), and then it is built as a Production "build" job (Jeff's
default: experience unlocks, materials and time build): its cost times
the level from the stockpile, its steps times the level, taken by the
first free workshop of its builder's trade (the carpenter) ahead of the
tier's choice. The town chooses by itself (Jeff), on the world tick
before Production so the job is taken that tick, one build at a time:
walls when its tier is DEFEND, then the building a waiting resident
needs, then an inn when residents fill its room, then its lowest
building that houses a trade; whatever it can afford first, up to each
kind's max_level. Raids take residents captive, never kill them
(Jeff's default; step 6).

Also in this step: a crate or cart unloaded at the stockpile credits who
pushed it there (World keeps each cargo's last pusher from
entity_pushed until it is unloaded or gone).

## 242. A new server build is tried on staging ports before it replaces the live one; levels reload live

A deploy used to put a build nobody had run on the box straight in place
of the live server: an export that would not start, or a snapshot the new
code could not read, showed only when players were cut off. Now
`deploy.sh --staged` runs server/stage.sh between the export and the
countdown: it starts the new build from build/ as the deploying user on
UDP 7787 with its console on 7788 (never the live 7777/7778, nor the
box's Ollama on 11600), with a throwaway token and copies of the live
snapshot and edited levels, everything it writes (snapshot, mind log,
transcripts, Godot's user data) under a temp folder; a headless client on
the repo joins, walks and reports; `stop 0` must save and exit 0. A
failure, or a script error in either log, stops the deploy with the live
server untouched. It never reads /etc/psykinetic/env: the staged token is
random, and with no LLM settings the staged companions think scripted.

The same script prints the running server's build and protocol beside the
new one's first, so whoever deploys sees whether the clients must update
(decision 239). tools/deploy_box.ps1 is the coordinator's one command
after a release: that comparison against origin/main (and whether the
version is released yet, since self-updating clients need it published,
decision 241), then `deploy.sh --staged` over ssh, then what runs; it asks
nothing and exits non-zero on any failure.

Live reload: the console's `reload <zone>|all` reads a zone's level from
disk again and rebuilds it as builder mode already did (reload_zone: the
players stay, everyone there is sent the new terrain), without a restart.
`all` reloads each open zone whose level files changed since they were
read, by folder and md5 (mtimes are a second coarse); a zone whose level
is gone (a builder undo) is left as it is. Level data in the export
itself still changes only with a deploy; this is for the overlay.

## 265. A building is a record over the map's own walls, laid by a prefab

A building (art-kit's building.hut 3x3, house 4x6, shed 2x3) is a footprint
of ordinary floor whose walls and door are the map's own edges round it,
drawn in the layout like any wall, and a record in level.json
"buildings" ({slot, at: the footprint's top-left, facing: the side its
front is on}) that says where it stands. The record changes no rule:
walls, doors (with their rules, 255 and 256), paths, light and senses work
on the edges as they did. It says where the client draws the slot's roof,
inside floor and trim (art-kit's building.* slots are those parts only, no
walls: the walls are wall runs, 245, so they fade edge by edge as any
wall, 188), and what counts as inside (266). Level.BUILDINGS gives each
slot's footprint, across by deep facing north or south; Level.parse leaves
out a record whose footprint is not all floor of one height or overlaps
another, and warns of one whose outline has open edges but keeps it (a
shed may be open).

It is placed by stamping a prefab that carries both: levels/prefabs/
building_hut, building_house and building_shed (drawn by
tools/seed_prefabs.gd: the footprint, its walls, a door south, a ring of
dirt) each hold one record. Stamping (Prefab.stamp_changes) moves and
turns the record with the cells (LevelMap.moved_config carries
"buildings", a footprint by two opposite corners) and merges it into the
map's list, the map's buildings it lands on taken out, as it merges
places; so the editor and builder mode (BuilderSession.CONFIG_KEYS, its
prompt naming which prefabs are buildings) place buildings with no new
tool. The record reaches clients inside level.json in the "terrain"
message they already get: nothing replicates, the protocol is unchanged.

Rejected: a Building entity (replicated state that nothing changes, and a
second thing to keep in step with the walls); generating the walls from
the record (two sources for one wall, and an editor that could not touch
them up); and building slots that carry their own walls (they would
double the wall runs and fade as one block, not by the edge that hides the
player). A well, 1x1 with no inside, is not yet one of these: how its
cell stops walkers is its own question; it comes last, with its own
decision.

Amended (the well): building.well (1x1, art-kit's rim and posts, a
"roof" part over them) stands on a water cell, not floor (Level.ON_WATER):
the water is what stops walkers and lets sight pass, as is right for a
well, so the sim is unchanged. Level.parse asks for water under it; it has
no walls (no open-edge warning), no inside (its roof never goes) and no
plain outline. The client gives its cell to terrain's Client3D._dry_water,
so the water is drawn as the ground round it, not as a pond under the rim.
The kit's "well" prefab carries its record. Rejected: a new "well" cell
kind (a legend and sim change for what water already does) and walls on
its four edges (wall runs would draw stone round it).

## 257. Lore: prose in docs/lore/, data in levels/lore/, one entry format, shared ids

The world's facts (lore tree) are kept twice over. Prose for people goes in
docs/lore/ (primer.md, style.md, README.md for the format). Data for code goes
in levels/lore/*.json (world, factions, regions, materials, people, history,
knowers). It sits under levels/ because the server reads and live-reloads
levels/ and builds companions' prompts, and levels/*.json is in the export
filter (a subfolder matches). docs/ doesn't ship. Where the two disagree, the
data wins. Each file is {_about, entries}. An entry is {id, type, name,
status, source, summary, relations [{to, kind}], tags, facts}, with id unique
across the files. Ids are shared, not copied. A faction's id is its key in
levels/factions.json, and maps keeps the mechanical fields (colour, monsters,
hostile_to) there: lore adds no fields to that file and holds only the
meaning. A material names its Stockpile.RESOURCES resource, a place its
Level.PLACE_KINDS kind and its level, and a weapon its items.json id. A
material says in words what it does when worked, with effect tags. Economy
and items turn those into numbers, so lore never sets one. Facts are plain
statements of what is true, never lines to say (companions' rule).
tests/lore_test.gd checks it all. level_test and editor_test now skip
folders under levels/ with no layout.png, the rule Level.names() already
used. Rejected: lore fields inside levels/factions.json and items.json (two
trees writing one file), and data under docs/ (it doesn't ship).

## 258. Who knows what: common, rumour, secret, lived; only agreed lore is used

Lore is local. Each fact has a knowledge level. A common fact is known to
anyone who lives in, or knows, a region in its where (an empty where means
everyone). A rumour is told as hearsay where it is heard, and must say whether
it is true, so a false rumour can stand without the lore contradicting itself.
A secret is known only to its knowers. A lived fact is one person's own
experience, known only to its knowers and spoken of as memory.
levels/lore/knowers.json lists the knowers (groups such as townsfolk and a
scholar, and characters such as each companion and the smith), each with its
where and its tags. A knower knows the common facts and rumours of its where,
the common facts and rumours that share one of its tags wherever they are (a
scholar's history), and the secret and lived facts that name it. Every entry
and fact also has a status: agreed (Jeff or Dire decided it, or it is in the
game), draft, or asked (an open question for them, naming its question's
code). A fact without a status takes its entry's. Code uses a fact only when
it and its entry are both agreed, so drafts and open questions can sit in the
files without reaching a prompt. How a companion's prompt takes the facts is
the companions tree's business.

## 267. Every sound is a named slot, played from its takes, a fill, a fallback or a blip

Jeff's sound brief asks for sound slots like art's: everything the game
plays, or soon will, named by what it is for (sfx.door_wood_open,
sfx.footstep_grass_medium, amb.forest_night, ui.click), with where each
take came from, and a list of slots still on placeholder. The slots are
art/audio/slots.json, read by SoundKit (client3d/sound_kit.gd) the way
ArtKit reads art/kit/slots.json; Sfx now plays slots, not its own table of
file sets. A slot plays its own takes (art/audio/<category>/<slot>/,
<slot>.ogg, <slot>.2.ogg ...), else its fill (Kenney's two CC0 packs, the
files already in art/audio/sfx/, left where they are), else its fallback,
another slot (a footstep on grass sounds as the generic footstep until it
has takes), else a short generated blip, its pitch by bus, so a gap is
heard and not mistaken for a sound; a bed with nothing plays silence.
tools/sound_status.gd writes docs/sound_status.md and THIRD_PARTY.md's
sound block, and sound_kit_test fails while either is stale.

Each positional slot names the sim's noise kind it goes with (World.noise:
step, fight, door, ...), and how far it carries comes from that kind's
radius (SoundKit.NOISES, Senses' own constants; thud, rummage, break, latch and
door_rattle were provisional numbers until enemy-ai put them in Senses, and
now are Senses' too, a thud named by weight as thud_light or thud_heavy,
items' split at 5 kg): the one number sets how far monsters and players
hear it, so they can't drift.
A slot monsters don't hear (goblin chatter, picking an item up) says
"noise": null and gives a range; the status lists them. UI and ambience
beds are flat (positional false). Playback still uses Sfx's fixed
distance; matching the falloff to the radius is the next step (269).
Rejected: renaming Kenney's files into slot folders (churn, and their
SOURCES.txt already names each original), slots as a GDScript table
(the tools, the status and the art side all read JSON), and silence for
an empty slot (a missing sound goes unnoticed).

## 266. Inside is a cell of a footprint: the roof goes, its shadow stays, the near side fades

Whether a player is inside a building is asked by each client of its own
local player and their companion only (the same two the near-fade is
for, decision 188): inside is their cell being in a building's footprint
(265). Nothing is sent: what one screen leaves out is how that screen
draws, not a rule, so a player outside sees the roof over someone who is
in. Client3D._update_roofs and _inside_walls run with the fade
(_update_fade), from its focus points, footprint cells looked up in one
table, so a map of many buildings costs one lookup a point.

The roof. While they are inside, that building's "roof" part (art-kit's
building.* slots, 263: its pivot at the eaves, on the walls' tops) draws
only its shadow (SHADOWS_ONLY), so the room keeps the shade it had and
does not jump into sunlight; it comes back FADE_HOLD after they leave, as
a faded wall does, so stepping in and out of a doorway does not flicker
it. From outside, a roof between the camera and the player is one more
occluder and fades as a wall does.

The near side. While they are inside, the building's outline edges whose
outward side faces the camera (flat, by more than NEAR_SIDE, so in a
diamond view the two sides toward it and not the two it looks along),
with their runs, join what hides them (_hiding) and fade by 188's
see-through material, whether or not the line to the camera meets them:
in a corner of the room the wall beside the player hid them from the ray
test's three heights. They follow the camera as it turns and are held
FADE_HOLD as any faded wall. Faded, not cut away: Jeff's choice for now; a
cutaway to a low stub may come later. A building's outline is drawn plain
(terrain's Client3D._plain_walls, decision 252: level at WALL_HEIGHT,
never broken), so the roof sits on it.

Rejected: hiding by replicated state (who is inside where), which would
send what only one screen needs; hiding the roof's node outright, which
took its shadow with it and lit the inside as the open ground; hiding
every roof while the player is inside any, which opens the whole town;
and a second fade for buildings' walls beside 188's, which would fight it
over the same materials.

## 255. Doors: imps and sneaks open them with a reason, brutes break them, and a shut door hides you

Opening a door is no longer free to every creature. Players and companions
open any door they may (256); a monster opens one only if its kind does
(Monster.DOOR_OPENERS: imp, sneak; a monster of no kind, as before; a
level entry's "opens_doors" says otherwise) and only when it has a reason
(Monster.opens_doors_now): idling, going back and fighting are ordinary
movement and open doors; looking or hunting, it opens one only for
something real behind its lead, heard or seen there within
DOOR_FRESH_TICKS (4 s). A hunt's lead past where it last saw you is a
guess, and no reason. So a monster that comes to a shut door with nothing
heard or seen beyond it since it lost you goes to the door, looks round
and gives up: you can hide behind a shut door, quietly. A word behind it
(muffled, so heard half as far), or having been seen through it as it
shut, brings it in.

A monster that cannot open doors (the brute) breaks one when it has the
same reason: World.try_bash_door, a blow (its attack's cooldown) of
attack_damage times DOOR_FORCE (3 for HEAVY) at a wooden door's 20 hp, so
a brute is through in about 4 blows, with the door-struck noise each
time. It keeps at it till the door breaks or it gives up the hunt.

Ways: find_path takes opens_doors (default true). The memo of steps
(_path_step) is shared by every walker and says a door is passable, so
the parameter is asked at search time, on door steps only (PATH_STEP_DOOR
across a closed door, and the ASK steps). World.walk (the world tick)
passes the walker's own say, so a far brute does not walk through a door
either; walking into a closed door one may not open bumps it (_shift).
When no way without the door reaches its lead, the monster looks for the
first closed door on the way doors open (the same capped search; a
diagonal step's two straight ways both checked), and goes to it.

Rejected: brutes opening doors too (Jeff: they break them); monsters
opening every door they meet (a shut door would hide nothing).

## 256. Locks are a key id on the door; whether you hold the key is the items' to say

Door.lock is a key id ("" for none), replicated. A locked door does not
open for anyone who does not hold its key, by hand (try_toggle_door) or
walking into it; World.has_key asks World.key_check, a Callable the items
set (until then nobody holds any key). No level sets a lock yet, and the
level format for one waits for a level that needs it. Paths do not know
locks: a way through a locked door ends in a bump.

What a door shows is Door.state(), one of Door.STATES, the names agreed
with art-kit for door slots: "open", "closed", "locked", "broken", and
"barred" (shut from one side) kept for later.

## 271. Every sound the sim makes is a noise of a kind, and the sound plays as far as it carries

The sound worktree plays a positional sound as far as its noise carries
(Senses.NOISE_*, Chebyshev, half with no clear line, as World._hear): you
hear it where a monster would. So the kinds are named once, in Senses:
door_rattle 6 (a locked door tried, World.try_toggle_door), rummage 4 (a
chest's things taken or put, try_transfer), break 8 (a breakable that is
not a creature smashed, World.damage; a monster hunts it, as a fight),
latch 3 and thud 2 / 4 (light, heavy) for the items to make when locks
are worked and things dropped or land. A step carries by mass
(Senses.step_radius: mass / 27, 2 to 4; a player's and a companion's 3,
as before). Knockdowns, pain and deaths are a blow's "fight" already.
Goblin chatter, bandaging and the alert bark make no noise: chatter heard
would rouse a camp by itself; the bark becomes a call for help with the
groups (step 4).

## 273. A companion's voice is asked only when a player can hear her

Jeff's always-on world: companions in zones with no players nearby make
no voice calls. A zone with nobody in it already sleeps (World.step
steps only awake zones), so its companions make none. The gap was a
companion in an awake zone with nobody near: on the box logs 22 of 880
voice asks (her player offline 17, more than 10 cells off 5).

Companion.heard_by_anyone: her voice is asked only when a spawned player
in her zone is within HEARING_RANGE, or her own player has fallen and
waits to rise (still there, listening); otherwise the ask is logged "not
asked" with the reason. HEARING_RANGE is Senses.NOISE_SPEECH, so how far
speech carries for chat (Main.hearers), for the monsters' hearing and for
this is one constant. Stance asks are not gated: they come only in a
fight near her or her player. Town NPCs and companions left in town will
come under the same rule as the always-on world runs them.

## 276. The terrain's colours are art-kit's palette, read from its image

Jeff wants muted and earthy (stone, wood, moss, leather) with a few
saturated accents (docs/art_style.md), and the terrain's own colours were
the most saturated things on screen (the grass at saturation 0.67).
Client3D.swatch(row, column) reads art-kit's atlas, art/kit/palette.png (8
rows of 8 swatches), once, so a swatch Jeff repaints repaints what uses
it; the style guide's colours are the stand-in if the image cannot be
read. The ground's kinds (GROUND_SWATCHES: grass, dirt, stone floor,
sand), the cliffs' rock, the walls' stone (until material.wall has a
texture) and the scatter's colours are swatches; flowers are the accent
row's, the few saturated things on the ground. Water has no swatch yet:
its hues are muted by hand and its foam is the palette's bone. The forest
floor already was a swatch (foliage's darkest). Grass is now foliage
#5d7742 (#7a8f4a, the next lighter, read as dry khaki in the sun).

Dry water (for buildings-89, amending 236): a water cell in
Client3D._dry_water is drawn as the land beside it (a well's water, its
rim built round it): no surface, no sunk bed, no wet shore, no scatter, its
ground the neighbouring land's kind. The sim still has it as water
(unwalkable, sight passes). Whoever places it fills the set before the
room is built.

Amended: the water's shallow, deep and foam are art-kit's water row now
(palette row 8: columns 2, 4 and 0), read like the ground's, the same
colours as the hand-muted ones they replace.

## 284. A companion left in town works there as a resident

Jeff: companions left in town work a trade as residents. Economy's Towns
(note_companion_in / note_companion_out) seats her as a Production
worker; companions decides when she stays and when she goes.

She stays when her player goes from her without her, on ground of a
stockpile the town holds (Stockpile.place_at), and she has a trade:
- her player leaves the game while she stands there (Main._leave, where
  she already waits, idle); she stays in the world as before;
- her player travels to another zone while she was told to stay (HOLD,
  standing as their instruction: Companion.stays_put). Main.travel,
  shared, leaves her behind then: she is despawned as before but not
  brought along, and is not spawned beside them in the zone they go to.

Main._stay_in_town calls note_companion_in(place, name, trade) and keeps
{place, zone, trade} in her record as "resident" (saved, and read back by
PlayerRecord.from_dict). She goes when her player is back in her zone:
Main._join_companion, before anything else, calls note_companion_out and
clears it (her job waits with its materials), then she rejoins or spawns
where she worked; joined in any other zone while she is resident, no
companion is spawned. The name is her record's (her entity may be "Pip2"
after a respawn).

Her trade is levels/companions.json "trade" (Main.companion_trade) until
step 6's cards: placeholders Pip carpenter, Wren cook, Nix smith; no
trade, she does not stay. Her voice is told, as a fact in her now,
"While Jeff is away you stay in this town and work as its carpenter."
Not told to stay, or off the town's ground, she goes with her player as
before.

## 289. Lore is read by one class, Lore, and asked one thing: what a knower knows

`Lore` (`sim/lore.gd`) reads levels/lore/ once and keeps it (read on first use,
like Items), with `reload()` for live-reloaded data and `use()` for tests. Code
asks it one thing: `known_by(knower, least)`, the facts that knower knows under
decision 258's rule, each as {id, text, hearsay, memory}. A rumour comes as
hearsay and a lived fact as memory. Whether a rumour is true never leaves Lore,
so a prompt can't give it away. By default only agreed facts count (both the
fact and its entry, and the knower too). "draft" lets a tool preview drafts as
well, and an asked fact never counts. tools/lore_known.gd prints it for a knower.
How a companion's prompt uses the facts stays the companions tree's business.
Rejected: each reader filtering the JSON itself (the status gate and the truth
flag would be repeated, and one day missed).

## 280. Prices from value and need; players' own gold; trade at a shop counter, taxed for the town

Economy step 5 (sim/economy.gd, World.economy, saved as "economy").
Prices are worked out when asked, never stored, from the rules in
levels/economy.json: an item's value is its catalog "value" (items adds
the field; economy only reads it), else what it is made of ("value" per
resource, a thing at its own value) plus its work (made.steps / 600 x
"labour"), else its yield, else 1. The town's need scales it: how short
it is of what it wants (wants by tag, uneasy_extra too while its tier is
DEFEND; comfort for raws) takes it up to trade.max_factor (2) for none at
all, plenty down to min_factor (0.5). Deterministic: the same stores give
the same prices.

A player's gold is theirs (Jeff): kept by Economy by player id, saved,
never touched by death or anything else but buying. It is kept there
rather than on PlayerRecord so the sim pays it without Main;
World.add_gold(player_id, n, why) is the one way it changes (items' coin
purse "use" calls it), and World.gold_changed tells Main, which tells the
client.

Trade happens at a shop counter: a Chest with props {"shop": true} inside
a stockpile place the town holds (as a depot). A player beside it buys a
thing in the town's shop at its price: the sale tax goes to the treasury
(the stockpile's gold), the rest to the purse of the resident who made it
(Stockpile.stock_shop now keeps the maker's worker id, saved), or all of
it to the treasury if no one did; Production.note_sale is told. Putting a
thing into the counter sells it to the town, only if the town is short of
it, at trade.buy_ratio (0.5) of its own price, less the buy tax, which
stays in the treasury, and never below gold_floor: buying back and forth
always loses, so trade builds the town, not a player's fortune. A raw is
banked as its yield, gear goes into the shop to sell on; gold (a coin
purse) is given at the depot, not sold. Production.taxed moved to
Economy.taxed (Production's calls it).

Wire: client to server is the existing "command" ("shop" {shop, do: buy,
uid}, or no do to ask for the list; selling is the existing transfer);
server to client is a new message kind "shop" ({gold} alone, or {shop,
town, gold, goods [{uid, id, price}], offers {id: gold}, why}), sent only
to that player's peer. A protocol change (MESSAGE_KINDS). The client's
ShopPanel (render/shop_panel.gd) shows the gold over the pack and the
open shop's goods beside it, in PackPanel's look.

## 277. Saplings at the forest's edge

The forest's first ring is a tree on every void cell beside the land (so
the edge reads closed, and the sim's wall there is never mistaken for a
way in), which left the edge's trunks, and their shadows in the sun, in
a stair of cells (252). Now an edge cell has, often (SAPLING_CHANCE), a
sapling as well: tree.small at a third to three fifths of a tree's size
(SAPLING_SIZE), set off toward the land and sideways, still inside its
own void cell, leaning as trees do; faded as trees are when it hides the
player. Visual only. tools/map_bench takes --outdoor=1 to bench a forest
round its dungeon.

## 293. Who a companion is: traits rolled once, a card written from them

Jeff: trait tables rolled at creation, one model call writes the card, a
"how we met"; names rolled too ("Roll names"); no hand-written cards,
Pip, Wren and Nix included ("Rolled cards with lore that gets added
dynamically based on events and conversations": the growing part is its
own piece of work, designed separately).

levels/companion_traits.json holds a table per trait: name, pronoun,
birthplace, parentage, profession (its words and the trade she works in a
town she stays in, decision 284; empty for none), hobby, food,
temperament, fear, speech, how_we_met (a seed with {player} and
{pronoun}). Each entry is a few plain words. CompanionCard.roll rolls one
of each, seeded by her player's id (the same player rolls the same; a
name another record's companion has is rolled again), and Main keeps it
in her record ("traits", saved and read back by PlayerRecord).
COMPANION_NAMES, the authored cards and levels/companions.json are gone.

The legacy three (Jeff: "wren and nix stay in as legacy chars", "Keep
Pip too", "Pip is a young male, aspiring to be a squire"): the table's
"legacy" block names Pip, Wren and Nix, each with "fixed" facts the roll
keeps (Wren and Nix women; Pip a young man who wants to become a squire,
though no one has been knighted in ages: a wish the land no longer has),
the rest rolled round them; keys beyond the table's own ("who",
"aspiration") go into the plain card and the card call. A new roll never
gives their names; a record whose companion has one keeps it, and her
hand-written card goes. They rest in town between trips: when their
player leaves the game and she is not already on town ground (284), she
goes to the first stockpile the town holds, a resident there (working her
trade if she has one), despawned from where she was, until her player
comes to that zone; joining anywhere else, her player is told (a party
note: "Nix is resting in <town>. Go there to travel together again."), so
she does not read as lost. With no town stockpile anywhere, she waits
where she is as any companion. Any other companion goes on as 284 says.

Her card is first CompanionCard.plain_card: her traits said as plain
facts, so she is never without one. At her first spawn with a mind,
Companion.write_card asks her voice's model once, on its own channel
(OllamaMind "card": JSON, up to 320 tokens, 60 s, temperature 0.9, off
the tick like every ask), for a paragraph in the third person from her
traits and one sentence of how she and her player met. A paragraph of
80 characters or more with no speech in it is taken (card_by "model")
and written to her record; anything else, or no answer, leaves her plain
card and the call is made again at her next spawn. Her voice's system
message carries her card and "How you and Jeff met: ...", as facts;
nothing in it is a line to say. Her trade for 284 comes from her
profession. Lore will supply birthplaces and names per region once Jeff
agrees facts.

## 295. Raids on a town: one entry point, food and people only, damage repaired, captives kept until rescued

Economy step 6 (sim/towns.gd). A raid is a real group of raiders: maps
sends it out from a raider camp on the world tick and moves it along
its routes, and enemy-ai plays it as monsters wherever players are. The
town side has one entry point, Towns.raid_arrives(town, group) -> report,
called when a group ({id, faction, strength, from}) reaches the town's
stockpile ground. It is the same call whether the group got there on
maps' world tick or walked there in a played zone, so the town has one
path whether or not anyone watched. Fighting on the way lowers the
strength the caller passes; economy never rolls dice. The same group
against the same town gives the same report.

The town's defence is its walls (standing or being raised, by level) and
its residents in town, at the rules' raids.defence. Strength less defence
is what gets past (the margin). With none, the raid is fought off.
Otherwise:
- It takes the rules' raids.takes in order, each scaled by margin /
  strength: stockpile food, then food-tagged things from the shop and
  store. Food and people only (Jeff): never gold, ore, wood, cloth,
  experience or levels.
- Every loss is a ledger line by "raid:<faction>", which the town's
  safety already reads (DEFEND for a window).
- A taken thing stays in the item book, carried by "raid:<group id>",
  for whoever beats the group to drop.
- Past damage.margin, one standing building is DAMAGED, in damage.prefer
  order (walls first). It is never lost: its workshop stops, damaged walls
  defend nothing, and the town's tick orders a carpenter's
  "repair:<kind>" job before anything else. The repair costs repair.share
  (0.5) of the level's cost and time, and no experience.
- Past captives.margin, up to captives.count residents are carried off:
  the newest first, never a companion. Each one's Production worker is
  kept and set away (their work waits), and their record (trade, purse,
  origin, taken_at, by, held_by) is in Towns.captives(town).
- There is no clock (Jeff): a captive waits. Maps says where captives are
  held (captive_held: the camp, once the group is home). note_rescue
  brings a captive back as themselves, at their old work, with the
  rescue's experience.

The report ({town, group, faction, repelled, margin, took, damaged,
captives}) goes back to the caller and out on Towns.raided: what the
group carries off is maps' to move home with it.

Towns.threat (town) -> 0..1 is how threatened maps' camps make a town;
until maps sets it, it comes from the town's safety (raids.threat_default).
At walls_from and above, the town wants walls first. The raids numbers
in levels/economy.json (defence, takes, margins, repair share, threat,
the "goblins" raiders) are placeholders until the Blood Rot and their
faction are agreed.

Towns.building_changed(town, kind) is emitted whenever a building's state
or level changes (unlocked, built, raised, damaged, repaired), and
Towns.buildings_of(town) gives {kind: {state, level}}. They are what the
buildings worktree's views draw from (agreed with buildings): the state
lives only in Towns, never in level files.

## 296. Art slots are made once before a room is built; the forest is measured from its edge

A 256x256 outdoor map (the wilds) took 6 to 7 s to be ready, against
under 3 indoors. Timed phase by phase (tools/map_bench --outdoor=1), the
forest took 3.9 to 4.8 s of it, and of that the first tree 3.8 to 4.2 s,
the other 3,992 together 56 ms; and a rebuild spent 2.5 s freeing the old
room. A tree is not dear: made in a bare script it takes under 5 ms,
windowed or not. Split further, the 3.6 s was ArtKit freeing the sample
it measures a slot's height from ("fit"). Perf found why (Godot 4.7.2):
freeing any VisualInstance3D while the RenderingServer holds many newly
added instances that no drawn frame has taken in yet is pathologically
slow (100,000 added, one free: 36 s; the same free after two drawn
frames: 0.1 ms; headless, 1.8 ms). A room's build adds tens of thousands
in one frame, so a free during it pays; a free before it, or once a frame
has been drawn, does not.

Client3D._warm_art makes and lets go every mesh slot in WARM_CATEGORIES
(walls, doors, trees, rocks, buildings) once a process, before any room
is built: every slot's load and fit happen, and any free with them, while
there is nothing pending. Nothing in a build may free a 3D node until a
frame has been drawn (ArtKit's fit sample is the one there was; caching
its height from the scene's bounds would take the trap out of ArtKit
itself). The 2.5 s freeing the old room in map_bench's rebuild is the
same trap in the bench, which rebuilds with no frame drawn since the
first build; in play a frame has always been drawn by then. And _measure_forest walks from the land's outline only (a land
cell with void beside it), not from every land cell (65,536 at 256x256):
the land within is 0 by being land, and only the outline's 0 is read.

tools/map_bench, windowed, under the bench lock, alternately with main:
256x256 outdoors, ready 6.38 / 6.72 s to 3.02 / 2.89, 3D rebuild 3.96 /
4.06 s to 1.85 / 1.75; indoors, ready 2.97 to 2.77, rebuild 1.75 to 1.64;
frames and nodes unchanged. Rejected for now: trees by MultiMesh (the
forest builds in 140 ms now; it would save about 14,000 nodes, but the
near-fade swaps materials by node and would need per-instance alpha).

## 268. Sound takes the licence forbids sharing live outside the repo, synced in by hash

The repo is public, and the Sonniss #GameAudioGDC licence (v2.0, in
docs/licenses/) forbids supplying its sounds "as sound effects to any other
person ... whether unmodified, modified or re-designed": a file in the repo
is that, a trimmed take too. Its sounds inside the exported game are allowed.
So a sound source in art/audio/slots.json may be stored "external": its takes
are kept in the sound library, N:\assets\sound (the NAS; PSYK_SOUND_DIR
points elsewhere), as takes/<slot>/<slot>.ogg, .2.ogg ..., and
art/audio/takes.json (in the repo) lists each third-party take: its slot,
file, source, where in the source it was cut from, and its sha256.
tools/sound_sync.ps1 copies each listed external take into
art/audio/external/<slot>/ (git ignores it), checks its hash, removes what
is no longer listed and reimports. tools/release_client.ps1 runs it before
exporting and stops on any take missing or changed, so a release never
quietly ships placeholders; with no external take listed it doesn't look
for the library at all. The library is asked on a thread-pool thread with a
timeout (tools/sound_library.ps1), so a NAS that is down fails the sync in
seconds with a message instead of hanging. tools/sound_take.ps1 adds a take:
ffmpeg cuts it, trims a one-shot's silences, makes a positional slot's take
mono, encodes Ogg Vorbis, stores it (an external source's in the library,
another's in the repo at its source's path), and tools/sound_take.tscn lists
it and rewrites the status.

A slot plays its own takes, else its third-party takes that are there, else
its fill, else its fallback's, else the blip (267). The status and
THIRD_PARTY.md go by the lists, not the disk, so they read the same on every
machine, synced or not. The Linux Server export leaves art/audio/ out: a
dedicated server plays nothing, so the box never needs the library. The
sound tools run as scenes, not --script, because SoundKit reads Senses,
which needs the autoloads. Rejected: Git LFS or a private submodule (the
files would still be supplied to whoever can read it, and the repo is
public), downloading from Sonniss at build time (their server refuses
scripted downloads, and a release shouldn't depend on it), and leaving the
copies' hashes out (a changed or half-copied file would ship unnoticed).
## 290. The time of day is the world clock's, told to clients in a "sky" message

Jeff's environment worktree: a sun that rises in the east and sets in the
west on the world clock, a moon at night, a default day of 90 real
minutes, configurable, pausing with the server like the rest of the world.

The clock is the one there is: World.steps (10 a second, all zones
together, saved in the snapshot and resumed after a restart, so it already
stops while the server is down). DayNight (sim/day_night.gd, static) works
the hour out of it: the day's fraction is phase + (steps - anchor) /
day_steps, and the sun, the moon and the sky's light are functions of
that alone, the same on every peer. No per-frame state anywhere, nothing
counting on its own. A new world starts at noon. Setting the hour or the
day's length moves phase and anchor so the clock goes on from there (a
new day length keeps the hour); both are saved in the snapshot's "sky"
({day_steps, phase, anchor}). --hour and --day-minutes set them at boot
over the snapshot's; the console's `hour <h>` and `day_minutes <m>` set
them live, save, and tell every client.

Clients are not sent World.steps with the ticks (they get only their
zone's tick), and the light field runs on every peer, so the clock goes
to them: the "sky" message (Net.MESSAGE_KINDS) carries DayNight.to_dict()
and the server's World.steps, sent on entering a zone, every world tick
(30 s) to everyone, and at once when the console sets it. A client counts
on from the last one at the tick rate (DayNight.now). Its 30-s drift is a
few ticks at most, invisible on a day of 54 000 steps. Weather will ride in
the same message. Wire change: a new message kind, so PROTOCOL_REVISION
goes up.

## 291. Daylight in the light field: outdoors, out from under a roof, and zone kinds

The sim's light is ambient + sources (Fields.light_at). Outdoors, the
ambient term at a cell not under a roof is now the sky's, DayNight.light:
1 by day, DayNight.NIGHT (0.2) under the moon, smooth through twilight by
the sun's height (-6° to 12°). It is one number a tick, set by World.step
(a client's on each tick it is told), and looked up per cell, so nothing
is worked out again as the hour turns: Senses, which asks
light_at(cell, false) for every candidate each think, pays a dictionary
lookup more (enemy-ai's condition). Roofed means inside a building's
footprint (Level's buildings, decision 265). Those cells, and every cell of
a level that is not outdoors, keep the level's ambient light at any hour.

NIGHT 0.2 is agreed with enemy-ai: over Senses.GLIMPSE (0.15) and under
DARK (0.35). An unlit body outdoors at night is glimpsed, never seen (the
monster comes to look). A torch, fire or carried lantern lifts a cell over
DARK. Twilight crosses DARK with the sun just under the horizon, a
sneaking window.

level.json's "zone" names what kind of place a level is: outdoors,
indoors, cave or dungeon (Level.zone_of, DayNight.ZONES). The older
"outdoor": true reads as outdoors; with neither it is indoors; an unknown
one is warned of and read as indoors. Level's terrain keeps "outdoor"
(zone == outdoors) for what reads it and adds "zone" and "daylight"
(outdoors, and level.json sets no "ambient": a level that sets its light
outright keeps it). Each kind has a base ambient light
(DayNight.ZONE_AMBIENT; outdoors under a roof is lit as indoors), all 1
for now, as today; the ambient-lighting step tunes them. The view's floor
shading leaves the sky's term out (light_at's sky = false): the 3D sun
draws daylight, so the hour moves no per-cell bytes (terrain's rule).

## 292. One sun-or-moon light, moved a game minute at a time, for stable shadows

Outdoors, Client3D's one DirectionalLight3D is the sun by day and the
moon (opposite it) by night: never two shadow casters. It changes over at
1° under the horizon, where SKY_KEYS have its light at nothing, so the
swap does not show. The sky's top and horizon, the ambient light, the
sun's or moon's light and a thin haze (exponential fog) are blended
between SKY_KEYS by the sun's height: warm gold at dawn and dusk, neutral
by day, a cool blue under the moon. The sky colours are hand-picked for
now; art-kit's palette has no sky row.

Stable shadows: the light's direction moves only in steps of a game
minute (SKY_STEPS 1440 a day; 3.75 s apart at a 90-minute day), so
between steps nothing about the shadow map moves but the camera, which
Godot's directional shadows already snap to texels. It casts from at least
SHADOW_LOW (14°) up, so dawn and dusk shadows don't reach tens of metres
and crawl. Orthogonal shadow mode, fitted to the orthographic camera
(SHADOW_DISTANCE 70: the camera stands 40 m off), with a little blur.
Everything is set only when the step changes, not every frame. Indoors,
caves and dungeons keep the dark under-stone look with no sun.

## 297. A building is linked to its town's record; the town's records hold its state

A building in a level may say what it is to its town: level.json's
building entry gains "use" (one of the economy's buildings, levels/
economy.json "buildings": forge, kitchen, inn) and "town" (the key of a
stockpile place on that map; the town's id is "<area>/<key>", as
Holdings and Stockpile have it). Level.buildings_from checks the link
(Level._link) and leaves a building unlinked, standing as scenery, with a
warning, when the use is no economy building, the town no stockpile place
here, or the town already has a building of that use. Where it stands is not
checked: a stockpile place's radius is its banking yard (250), not the
town's extent, and a town's buildings stand round its store. A link moves and
turns with its building (it is part of the entry), so a stamped prefab
keeps it.

The state (planned, building, standing, damaged) and level are economy's
(Towns, the snapshot), never level files: a level is content, a raid is
game state. A building with no use, or whose town has no record of its
use yet, draws as standing, so levels without an economy look as they
did. How a client learns a linked building's state, and how each state
is drawn, is this decision's second stage, with economy's raids (#295):
Towns.building_changed(town, kind) on the server, a "town" message to
the peers, the slot's damaged state on the client.

Rejected: the state in level.json (game state in content, and the level
rewritten at every raid); a Building entity replicated per building
(state that only economy changes, and a second record of what Towns
already holds); and linking by the building's cell from Towns' side
(economy's rules need no map, and a map edited in the builder would leave
its records pointing at nothing).

The second stage, the state on every peer: the server connects
Towns.building_changed(town, kind) (economy's step 6, 295) when it makes
its Towns (Main._boot) and broadcasts a "town" message, {town: its id,
buildings: Towns.buildings_of(town)}, the whole town (a few kinds, so no
deltas); a peer coming into a zone is told each town there (Main.
_send_towns, beside "map" and "sky"); the server's own view takes Towns'
records as they are (_show_towns), as its player gets no greeting. Main
keeps what it was told (town_states) and hands it to the view
(Client3D.set_town), which keeps it across rebuilds: a town's state is
not the map's. Level.load_level gives a linked building its town id
("<level>/<town>"). A new message kind: the protocol changes with it.

How a state draws, on the client only: damaged, the slot's roof_damaged
in its roof's place and its state_damaged (rubble heaps in the outline's
band) shown (art-kit, 287); until a slot has a roof_damaged its roof sags
at its eaves (ROOF_SAG), caved in at a glance. The roof shown is the one
that goes while the player is inside (266) and fades from outside.
Planned, being built and standing draw standing for now. The walls of a
damaged building take terrain's "broken" wall state (Client3D.
_wall_states, 285): a third of its outline's walls by a hash of where
each is, the same on every peer, redrawn by rebuild_walls. Later:
whether a damaged roof lets daylight in (environment's 291 has every
footprint roofed); for now it stays roofed.

## 272. Bandaging: a kit, out of combat, then mending you can walk away from

Items step 4, first part (the roadmap's rule: right-click-hold on an
adjacent ally, out of combat, then regen starts and you can step away).
World.try_bandage(by, patient): by is a player or a companion, alive, not
stunned, carrying a bandaging kit (a thing whose catalog use is
"bandage"); the patient is by itself or a player or companion beside it,
hurt, not already being bandaged or mending; both out of combat (World.calm:
not hurt for BANDAGE_CALM_TICKS, 3 s, and no monster within BANDAGE_SAFE,
6 cells, the cells round looked at rather than every monster). It takes
BANDAGE_TICKS (2 s); the bandager moving, attacking or shoving, either of
them hurt, the patient out of reach, or a monster coming near breaks it off
with nothing lost. Done, the patient mends BANDAGE_HEAL (10) hp, one every
BANDAGE_REGEN_TICKS, wherever it goes, until it is hurt. The kit is gear:
not used up. World.bandage_changed(by, patient, state) tells companions,
the sound tree and the views (&"started", &"done", &"interrupted",
&"mended"); a player's and a companion's mending (0 none, 1 being
bandaged, 2 mending) replicates, so the protocol changes. GridEntity
keeps hurt_tick (World.damage) for the calm rule. Only bandaging under
way and the mending are looked at each tick.

Input: the right button held BANDAGE_HOLD_MSEC (0.5 s) on yourself or an
ally beside you sends "bandage"; a quicker click is what it always was
(a shove, a companion's pack). A companion calls try_bandage as a player's
command does.

Bandaging replaces passive regen (the roadmap's rule, Jeff's): players no
longer heal on their own out of combat (Main's _heal_players is gone;
companion_test says so). Companions drop theirs (Companion._heal) in their
step 4, with their bandage verb.

## 303. A level is parsed from its raw pixels, and the world map reads again only the levels that changed

The server stalled for 0.6 s each time the 256² wilds was built: a player
going there for the first time since a restart (611 ms worst tick on the
box), and every builder accept (652 ms), which snaps every client back.
Level.parse took about 300 ms for the wilds (a function call and a Color
for each of its half a million pixels, and an array made for each edge),
and an accept ran it twice: once reloading the zone and once in
WorldMap.build, which parsed every level again for Holdings.rebind and the
world map's checks.

Level.parse now reads the layout's bytes as RGBA8 (a copy when the image is
another format, so the level's own is left as it was), turns each colour
into a small integer code once per colour run, and works on packed arrays
of codes with a one-cell border of void, so the outline needs no bounds
check. Its output is the same, key for key and in the same order: checked
against the old parse for every level in the repo and the box's edited
wilds. The wilds parses in 55 ms instead of 300.

WorldMap keeps each area as it last read it, with an MD5 digest of its
layout and height bytes and its config; a build reads again only an area
whose digest changed, and gives each WorldMap its own copy of the area's
dictionary and of its ways. The digest is of the content, not of the files,
so an overlay written by an accept, a level moving between the overlay and
res://, a new area, an undo, a level registered in a test and the editor's
unsaved sources all count as changes without any stamps to keep. What is
kept is only read (WorldRoutes and Holdings copy what they take). An accept
now parses the edited level twice at 55 ms each instead of every level
twice; the wilds went from about 670 ms to about 180 ms on the desktop
(Ryzen 7 9700X), and a cold open from about 335 to 85.

Rejected for now: keying on file stamps (Main._level_stamp; it misses
levels registered in code and the editor's unsaved sources), sharing the
reload's own parse with WorldMap (Main keeps that level and could change
it), parsing on a thread (more moving parts than the remaining 180 ms
needs), and maps' incremental rebuild of only the edited area's cells,
which stays the next step if an accept must fit inside a tick.

## 305. Knockback threshold: an attack pushes only from World.knockback_min_force

Every melee blow carried half a shove's force and pushed with it, so the
lightest hits slid their targets: a player's punch moved an imp a tile, and
a fight was a string of slides. Now an attack's blow (after
ATTACK_FORCE_FACTOR) pushes only when that force is at least
`World.knockback_min_force` (exported, 1.5); a lighter one is set to 0 in
_try_hit, so it does damage and nothing else: no slide, no impact, no new
stun. Views flinch on the damage as they did (Client3D._on_struck), and
nothing is guessed on clients for an attack, so no client change.

With today's numbers: imp on player 0.15, brute on player 0.26, player on
brute 0.57, companion on imp 0.75, player on imp 1.0 hurt only; player on a
sneak 1.6 still knocks it back (2 tiles). An exhausted target counts half
its mass, so a tired one is knocked back sooner.

Not held to it: shoves and tosses (the push verb, paid in stamina), throws,
falls, door impacts and try_bash_door. No stagger state for blows under it
for now; Jeff can ask for one after the clip. Weapons as data (items step 5)
give the knockback verb by raising a blow's force over the line.

## 298. A town's wall is a ring of the map's walls, its look the town's walls level

A town wall is content, in the layout, like any wall: it blocks whatever
the town has built (Jeff: "rubble bank that still blocks"). level.json
"town_walls" names which ring of walls is a town's: {town: a stockpile
place's key, rect: the cells it encloses}; the ring is the rect's outline
(Level.outline, as a building's), its door edges the gates, ordinary
Doors under enemy-ai's rules. Level.town_walls_from leaves out a ring
whose town is no stockpile place here, already has a wall, or whose rect
is off the map, and warns of open edges on a ring or a place cell outside
it. A rect, not a disc round the place's radius: on the grid a disc is a
staircase of short runs, a rect four long sides. The ring moves with the
map (LevelMap.moved_config, by two corners) and is kept by builder mode
(CONFIG_KEYS); builder's town_wall tool lays the ring and the record
together. Linked by its town id ("<level>/<town>"), as buildings are (297).

Economy's walls level is the wall's strength (its defence) and here its
look, by the "town" message (297): level 0 (no "walls" record at all) a
low bank of rubble along the whole ring (terrain's "rubble" wall state);
1 a palisade (wall set wood); 2 stone; 3 stone with towers at its corners
and beside its gates (art-kit's wall.<set>.tower). Damaged, part of the
ring takes the "broken" state, never a gap: the sim keeps every wall.
Drawing waits on terrain's wall sets and states (#285) and art-kit's
towers (287); this is the record and its checks.

Rejected: walls that appear in the sim as the town builds them (live edge
changes, paths and fields reworked, for what reads as well as a rubble
bank that blocks); the ring written into the level as economy builds it
(game state in content); and a ring round the place's radius.

Drawn (with terrain's sets and states, 285, and art-kit's towers, 287):
Client3D._show_town_wall reads the town's "walls" record from the "town"
message. No record, or one only planned: level 0, every wall of the ring
in the "rubble" state. Level 1: wall set wood; 2: stone; 3: stone and
wall.stone.tower at the rect's four corners and at both ends of each
gate's edge (made once, shown only at level 3). Damaged: a third of the
ring "broken", by the same hash as a building's. Each change goes through
rebuild_walls with the ring's edges only; the entries are this view's own
(_state_walls, _town_wall_sets), taken out when the room is built again.

## 304. Each kind of place has its own light; the floor shows where you are seen

Jeff's environment step 3: how dark interiors, caves and night really are,
so torches and lanterns stand out and matter, but nothing is unplayably
black; one setting per zone type.

The sim's base light per zone kind (DayNight.ZONE_AMBIENT, decision 291's
kinds), placed against Senses' thresholds (GLIMPSE 0.15, DARK 0.35):
indoors 0.4, dim but over DARK, so a body there is seen (light through
doors and windows); a cave 0.2, the moon's light outdoors, so an unlit body
is only glimpsed; a dungeon 0.1, under GLIMPSE, so a monster is blind to
anyone without a light. Outdoors under a roof is lit as indoors. Every
player and companion carries a lantern, which lifts its own cell over DARK
even in a dungeon, so nothing is black to them. A level's "ambient" still
sets its light outright. test_room and sample name no zone and read as
indoors: their light goes from 1 to 0.4, still over DARK, so sight there
gives the same answers.

What the floor shows: brightness is no longer linear in the light. It
rises smoothly over 0.2 to 0.7 (Client3D.floor_brightness, FLOOR_LIGHT_LOW
and _HIGH), so ground where a body is seen reads plainly brighter than
ground where it is only glimpsed, and a torch's pool has an edge.
Outdoors, a cell's floor brightness (the ground's CUSTOM0 r) holds only its
sources' light (Fields.light_at with sky = false: nothing for the open
sky). The sky's light is one uniform on the ground's material, sky_floor,
set when the sky's step changes. The shader lights the floor to the
brighter of the two, so torch pools show at night and the hour still
rewrites no cell (terrain's rule, decision 292). Indoors sky_floor is 0.

Away from the sky the 3D view's ambient light has a colour and energy per
kind (Client3D.ZONE_LOOK), spread as the sim's values are: a room is dim
but all of it shows, warm-grey, the fire a warm patch; a cave is cool
moonlight, shapes with little colour, the fire the only warmth; a dungeon
is near black past the fire and the lanterns.
## 281. A monster's kind is a row of levels/monsters.json

What a kind is was spread over four tables in code (Level.MONSTER_TYPES,
Monster.TACTICS, IDLE_BY_KIND, DOOR_OPENERS and DOOR_FORCE). It is now one
row of levels/monsters.json per kind: "body" (the props a marker of that
kind spawns with: mass, hp, pace, blows), "tactic", "idle", "opens_doors",
"door_force", "leash" and "temperament" (weights). Monster.kinds() reads it
once, with a warning for a row or a field it cannot use (falling back to
a monster of no kind's); JSON's whole numbers come back as ints, but for
mass and move_ticks. Level.MONSTER_TYPES keeps its name and use (each
kind's body; a level's own "monsters" still add to it), now a static var
read from the table; sim/level.gd's only change. The editor asks
Monster.idle_of(kind). Imp, brute and sneak are its first rows, as they
were; the ranks of the lore draft (raiders, haulers, wardens...) would be
more rows.

## 282. Temperament: bold, cautious or cowardly, and a monster that breaks runs

Each monster of a kind is BOLD, CAUTIOUS or COWARDLY (Monster.Temper): its
level entry's "temperament", else drawn by its name from its kind's
weights (an imp mostly cautious, a brute mostly bold and never cowardly,
a sneak cautious or cowardly). Today's random boldness is drawn within
its temperament's span (BOLDNESS), so holding back follows it: a bold one
never does, a cautious one till one other is at its target, a coward till
two. A bold one's leash is half as long again.

It breaks below FLEE_BELOW of its hp (bold 15%, cautious 35%, cowardly
60%), or, a coward, alone against two or more within 3 tiles; a new alert,
FLEEING (shown " ~"; PROTOCOL_REVISION 10, as old clients would not know
it): it strikes no one and runs, to where it took up the chase if that
is away from the threat, else straight away (a capped search, the usual
back-off), till nobody has been within 4 tiles for FLEE_TICKS (6 s); then
a look about and back. Met again still hurt, it breaks again. The world
tick calms a runner like a hunter.

## 283. Calls for help and routs are noises its side hears

A cautious or cowardly monster that first sees someone calls (World.noise
"call", 12 tiles, at most every 10 s). Those of its side that hear it
(Factions.of_kind; with no factions, every monster of a kind) hunt whom
the caller fights: a real lead, so they open doors to it. Others only look.

One that breaks of itself (hurt or outnumbered) makes a "rout" (8 tiles):
of its side, a coward who hears it breaks, a cautious one under 70% of
its hp breaks, a bold one fights on. One broken by a rout does not rout
others again: routs echoing round a camp kept it breaking for ever. The
rout is read by a monster even mid-fight (its newest noises, each think),
where other noises are only heard with nobody in sight. Both are events:
no cost per tick. The call is the sound worktree's alert bark.

Amended: a client never sees World.noise, so a monster's call or rout is
also an event its viewers get (Monster.cried(kind), sent like winding),
for the view and sound to play; animals' cries (a herd bolting, a howl)
will use the same signal with their own kinds.

## 278. The suite runs its scenes at once, and a landing runs it beside net_test and state_test

A landing ran the suite's scenes one after another, then net_test, then
state_test: about 290 s on a quiet machine (the median of three, under the
bench lock: suite 150, net_test 107, state_test 38), much more on a busy
one, and every tree's landing waited on it. tests/run.sh and run.ps1 now
run the scenes at once: PSYKINETIC_TEST_JOBS, else half the cores less the
Godot processes already running (the machine is shared with other trees'
runs and benches), 2 to 8, and 2 while another tree holds the bench lock so
its timings stay true. The slowest start first by their last times
(.godot/test_durations.txt, per checkout), since view_test alone is some
30 s and sets the floor. Each scene writes its own log; a line prints as
each finishes, then the whole output of each that failed and a summary.
The rule is the one before: a non-zero exit, SCRIPT ERROR or ERROR:, or the
per-scene timeout fails the run; a timed-out scene is killed with the game
the Windows console build runs under it (found by a marker argument in
run.sh, by parent process in run.ps1), which the serial runner left
running. --serial / -Serial keeps the old way for reading a run as it goes.

Scenes running at once must not meet. Each test already had a base port of
its own, explicit in test_ports.gd's of(), and a per-scene offset would not
fit a checkout's 200-port window as tests grow, so ports stay explicit and
tests/suite_test reads every script under tests/ and fails, naming both
places, on two tests with one base port (the shell tests' "<base> +
PORT_OFFSET" and the ports counted from it included) or one scratch name,
or a test setting Net.port without test_ports.gd. Its first run found
net_test's console (base + 11) on controls_test's port; it is base + 1 now.
test_ports.gd's scratch() also puts the running scene's name (from
--scene) in the path, so two scenes cannot share a folder by accident.

tests/land.sh and land.ps1 run the suite (with two fewer jobs), net_test
and state_test together, with one summary and one exit code: what a
landing runs, and one of .sh or .ps1 is enough. Measured the same way,
medians of three under the bench lock: the suite alone 47 s (from 150), and
33 s once run.sh stopped starting a grep and a basename per scene (some 9 s
of process starts on Windows); a whole landing 111 s (from 290), net_test
now its long pole (decision 279 runs its phases at once).

## 299. A server goes cleanly: zones' entities are freed before their spawners leave, and the stdin thread is stopped and joined

The box's first staged deploy (decision 242) refused v0.1.141: its staged
server printed some 50 "Attempt to disconnect a nonexistent connection
from '<entity>' ... Signal: 'tree_exiting'" lines as it exited, one an
entity in its three zones (v0.1.140 the same). A MultiplayerSpawner tracks
each node it spawned through that signal, connected with the node's id
bound, and when the spawner itself leaves the tree with nodes still
tracked it disconnects them without the binding, which matches nothing.
The tree takes a node's children out last first, and each zone's spawner
was added to Main after $YSort (where the zone's entities live), so the
spawners left first, every entity still tracked. Now each spawner is moved
before $YSort as it is made: the entities leave first, each untracked by
its own tree_exiting, and a spawner leaves tracking nothing. That fixes
every way out (stop, restart, the test timer, a window closed), not only
the console's. The errors did not show on Windows, editor or export, so the
reasoning is the engine's code; the next staged deploy on the box is the
proof.

Looking for it found a crash too: a server stopped within 2 s of starting
crashed on its way out (exit 139), two runs in three. Its stdin thread,
which runs a method of Main, waits out 2 s of empty reads after stdin's
end before it returns, and Main's exit joined it only if it had already
ended, so Main was freed under it. Now _exit_tree sets _stdin_stop, which
the thread reads every 100 ms, waits half a second for it and joins it;
one held in a read by a live terminal is still left to die, as before.

net_test's restart phase checks both: the server it restarts holds three
zones (sample and castle opened on the console) and must go without an
ERROR line, and a fresh server told `stop 0` the moment its console is up
must exit 0.

Amended: the spawner order was not the cause, and the box still printed the
ERRORs with it (62, four zones). Godot 4.7 takes a node's children out of
the tree first to last, so before the change the spawners already left
after the entities, and after it before; neither order errors on Windows,
and both do on the box, where a debug build showed the ERRORs come as each
spawner leaves, one an entity still under its zone, their one-shot
connections still there: a spawner leaving the tree with nodes tracked
fails every disconnect on Linux. The fix is that no spawner leaves holding
any: _release_zones, before every quit (stop and restart, the test exits,
and a window closed or SIGTERM, Godot's close request), saves the world,
stops the sim and frees each zone's entities while their spawners are
still in the tree, so each one's leaving untracks it; Main's exit then
does not save again (it would write an empty world). The order change is
reverted. On the box, twice from one copy of the live world (50
entities, 6 player records, four zones), it stops with no ERROR and the
world comes back whole.

## 275. Item icons are rendered from each item's art slot, on demand, on the client

The pack panel showed each item's short name. Icons come from the item's
own art-kit slot (Items' "art"), so a new item, or new art for one, has an
icon with nothing drawn by hand. `ItemIcons` (client3d/item_icons.gd, Main's
`item_icons`) renders one the first time the panel asks for it, in a
SubViewport of its own world (an orthographic camera from the game's 3/4
angle, a light, a clear background, 128 px), one a frame, and keeps it;
`icon_ready(id)` says it is there. Rendering all of them at start-up was
the other way: it costs every item's model at load for icons most players
won't see that session.

Framing is a pure function, `ItemIcons.frame(bounds, view, place)`: the
model's bounds' eight corners, placed and seen along the camera, fitted
with a margin. A long thing (taller than LONG × its width) is rolled an
eighth of a turn about the line of sight to lie across the diagonal. The
framing is tested headless (items_test); the rendering is shown by the
`items_icons` clip.

Headless (servers, tests) nothing is rendered: `icon` gives null, and a
box with no icon shows the name in the middle as before; with one, the
name is a caption under it, and a drag carries the icon. Ground piles keep
their 3D art: icons are for the HUD only. Icons are kept by item and
whether placeholders are on; `forget(id)` (or `forget()`) draws again,
for when art-kit says an item's art changed (a signal of theirs, asked
for). Client only: nothing is sent, and the protocol is unchanged.

## 301. The town's store in builder mode: a prefab, a chest's use, and a check

Economy's pieces get into real levels through builder mode, not by hand
(Jeff lays out the starter town there).
- The town_store prefab (tools/seed_prefabs.gd, levels/prefabs) is an open
  7 x 5 yard of dirt. It has a depot chest and a shop counter on its back
  row, facing the yard with no wall near them, so neither a building's
  near-fade nor a wall hides them. Its config brings the store itself:
  place "store", kind stockpile, held by the town, radius 4, covering the
  yard. A stamp gives a working store in one call, and a second stamp's
  place becomes store_2 (Prefab.stamp_changes).
- The builder's place tool takes "use": "depot" | "shop" for a chest. It
  writes the prop Chest.depot / Chest.shop reads, faces the chest south
  unless told otherwise, and refuses use on anything else or alongside
  items (both chests keep nothing).
- Stockpile.check(config) -> Array[String] reads only a level's
  level.json. It warns about:
  - a depot or counter no town-held store covers;
  - a store held by someone else;
  - two stores that overlap;
  - a town-held store with no depot;
  - a depot or counter given items.
  The builder runs it after each tool call and shows Claude and the player
  what it says (builder-69's side), with the prompt text economy wrote.
Seeding Towns from the buildings a level places (buildings' "use" and
"town") follows once that lands.

## 269. A sound is heard where a monster there would hear its noise

Jeff's rule for sound: what you hear is what monsters hear. Sfx plays a
positional sound by the rule World._hear tells a monster a noise by, from
the listener's cell (the local player's; Client3D sets it as it follows
them): within the radius of the slot's sim noise (SoundKit.reach, Senses'
own radii; a footstep's is the body's, Senses.step_radius), counted in
cells, Chebyshev, and only half as far with no clear line
(World.has_clear_line, on the client's own copy of the map and doors).
Past that it isn't played at all. Within it, it is full loudness out to a
cell and falls in a straight line (in dB) to -24 dB at the edge, 4 dB less
and through a low-pass when muffled; Godot's own distance falloff is off,
its 3D player only pans. A sound on a cell edge (a door, a blow on a wall)
is heard from whichever cell beside it is heard best, since it faces both.
A test (view_test) makes every noise kind at every cell round a listener
by a door, through the sim and through Sfx.hearing, and they agree on
heard and muffled for all of them (1076 cases). Interest (36 cells) is
wider than the loudest noise (a shout, 20), so a sound you should hear is
never cut by it. Footsteps pick their slot by the ground (grass, dirt,
stone, sand, water) and the body (small under 50 kg, large from 100).

Buses: SFX, Voice, Ambience, UI and Music under Master, each with a
muffled twin (a low-pass at 900 Hz) sending to it, made by Sfx if the
project has none. Volumes are settings.cfg's master_volume=, sfx_volume=,
voice_volume=, ambience_volume=, ui_volume= and music_volume=, each 0..1;
Net.set_volume applies one (the volumes_changed signal) and writes it.
The game's first options screen is OptionsPanel (O, the coordinator's
ruling): a section per kind of option, Sound first with a slider each for
master, effects, voices, ambience and interface (music when there is
some); other trees add sections rather than keys. A slider applies as it
moves and writes the file when let go or when the panel is hidden.
Rejected: Godot's distance attenuation tuned per radius (Euclidean, and
never quite silent at the edge, so you would hear what a monster beside
you can't), the camera as the listener (the camera is up and back; a
monster hears from where it stands), and a server message per noise
(every step is a noise; the client already sees the events that make
them).

## 294. Her card grows: what she witnessed, and what became true in talk

Jeff: "Rolled cards with lore that gets added dynamically based on events
and conversations", and "if something is 'hallucinated' per se, that
actually becomes a card fact about that character". Her card (293) is not
frozen: CompanionFacts holds what has become true of her since, saved in
her record ("facts", "beliefs", and "talk" not yet read), per player's
companion. Every entry is a plain third-person sentence naming her, with
her player's id beside it (a rename does not strand it), never
transcript.

Facts from what she witnessed are written from templates, no model call,
only through her perception (Main tells her of a death only if she saw
it): an ally falling, a big monster killed, her own near-fall, the first
of a monster kind she has seen anywhere, what she found in a chest. The
same fact twice (Companion.near_repeat) is one.

Facts from talk: the lines between her and her player are kept; once at
least talk_lines (3) of her player's have been quiet for quiet_seconds
(60), one call on the voice's model (OllamaMind "facts", JSON, off the
tick) is shown her card, what is already true of her, what she believes,
and the stretch, and lists what is now true of her: what she said of
herself, or what her player said of her and she went along with ("went
along with" is the test; what she did not take up, jests and anything out
of the story are left out). The earliest fact stands: the call is told to
leave out what goes against what is listed, and her voice is told her
facts as true. Claims about the world (places, peoples, history) are her
beliefs, "You believe, though it may not be so", never written to
levels/lore: Lore owns the world. At most 4 of each a call.

Caps are data (companion_traits.json "growth"): facts_max 24, beliefs_max
8 (the oldest belief goes), prompt_chars 700. Over 24 facts, one merge
call folds the oldest of what she witnessed (all but the newest 6) into a
two- or three-sentence history fact; with no model to write it, they are
dropped oldest first. Talk facts are kept longest. Her voice's system
message, after her card and how they met: "Also true of you: <talk facts,
history, newest 6 witnessed>" within the budget, then her beliefs. Each
new fact goes to her transcript ("[Now true of her: ...]") and the mind
log (kind "fact", "facts"). The console's "companion facts <player>"
lists them by id, "companion forget <player> <id>" removes one.

## 302. A companion with no room to step aside changes places with her player

The box, tonight: her player walked into her in a one-wide corridor and
bounced back and forth ten times in five seconds. Bumped by her player
(Companion.bumped), she stepped aside to a free cell off their way; in a
corridor or a dead end there is none, and she stayed and said there was
no room. Now, with nowhere to step aside, she and her player change
places at once (World.swap_places: both creatures, side by side, nothing
between, no closed door; each slides as a step over her player's step
time, the grid updated for both together, entity_moved for each so a link
under her player still takes them). No voice call; she yields a moment so
she does not walk straight back into them. "There's no room for me to
move" is left for when even that cannot be (her player stunned, a wall
edge between).


## 311. Using things: keys by carrying them, a "use" verb, a thing's value, thuds

Items step 4b.

**Keys.** A door's lock (Door.lock, a string) is opened by whoever
carries a thing whose catalog `opens` is that lock, in the pack or a hand
(`World.holds_key`, which `World._ready` gives to enemy-ai's
`World.key_check` seam; tests may still set their own). A key is an
entry in the catalog, one per lock, not an instance with a lock of its
own: a key is data like everything else, the slot it sits in (which
replicates ids only) says which key it is, and there is no per-instance
state to save or send. The catalog has no keys yet (no content in real
levels); tests and the `items_use` clip add one with Items.add_for_test.
A key is never used up; it is not "used" either: carrying it is enough.

**Use.** `World.try_use(by, slot)` acts on the thing's catalog `use`:
"bandage" bandages oneself (try_bandage), "purse" opens a coin purse into
the player's gold (its yield's gold, through economy's `World.add_gold`,
"purse") and ends the instance ("opened"). Anything else is not usable
yet; buffs (decision 312) come in through it. The input is a right click
on a thing in your own pack row (PackPanel.use, Main.use_slot, the
command "use" with the slot): a command like the others, so no new RPC.

**Value.** The catalog's optional `value` (gold, an int 0 or more;
anything else is warned about at load and is 0): `Items.value_of`, for
economy's prices.

**Thuds.** A thing put down (try_drop) or landing from a throw makes a
noise of kind "thud" (Senses.NOISE_THUD_LIGHT, or _HEAVY from
THUD_HEAVY_KG 5 kg), so monsters hear a dropped sack. Things laid down by
the world (restores, spills) make none.

## 279. net_test's phases run at once

After decision 278, net_test was a landing's long pole: its phases ran one
after another, some 100 s of a 111 s landing. Its phases are independent
but for 2, which loads 1's snapshot, so each group now runs at once on
ports of its own (base 17760 for the checkout; 1 and 2 on it, 3 + 1, 4 + 2,
the restart phase + 3 with its console on + 4, and in net_test.ps1 the zones
phase + 5 and the chest phase + 6), and the checks read every log once all
are done, as before. net_test.sh runs each group in a subshell of its own
(its instances and helpers' state its own); net_test.ps1 runs itself once a
group (-Phase <group> -Logs <folder>), since a PowerShell process cannot
run its functions side by side. What a check needs from a group (the
restart's exit code, the console's reply) goes through a file. The
condition-based waits of the earlier fix carry over unchanged, so a loaded
machine still only makes it slower. net_test.sh went from about 100 s to
70, net_test.ps1 from about 100 to 48.

Found on the way: net_test.ps1's zones phase had failed since decision 293
made companions' names a roll from their player's id (Jo and Kim had
random ids, and the check named Pip and Nix); it reads their names from the
server's log now. land.sh runs net_test.sh, which has no zones phase, so it
went unseen.

## 320. Companions bandage, and heal only by being bandaged

Companions step 4's last verb. Items' bandaging (#272: World.try_bandage,
a kit, out of combat, then mending) left companions healing on their own
(Companion._heal: a point every 10 ticks after 50 calm). That is gone: a
companion heals only by being bandaged, by her player or by herself, and
a reset still brings her back whole. With a bandaging kit, out of combat
(World.calm for her and the patient), Companion.can_do offers "bandage
your own wounds" and, with her player in sight, "bandage <player>'s
wounds", for each who is hurt and neither being bandaged nor mending.
Chosen ([DO: n], or one promise naming it: "I'll bandage you" is her
player, "my own wounds" herself; "give you my bandages" stays a give),
she walks beside her patient, calls World.try_bandage, and waits on the
patient's mending: 2 is done (her voice tells it), 0 is broken off.
Bandaging herself, low, with nothing next to her, she keeps at it rather
than the retreat reflex ending it. Her voice is told the facts, never
what to say: whose wounds are being bandaged or mending, and for open
wounds whether she carries a kit (or her player does, or neither) and
whether it is safe to bandage now. Her world text says wounds do not
close on their own. No protocol change: mending is already replicated.

## 300. Where a new player starts is data: levels/world_map.json's start zone

New players went to Level.DEFAULT_MAP (test_room) unless the server ran with
--map, and the box runs without it; Jeff wants the town to be where
everyone begins. A server flag would be one more thing to keep right in the
unit and in every deploy, and the world's shape is the levels' business, so
the start is data: levels/world_map.json, {"start": {"zone": <level>}}, the
cells the level's own "starts". Main.default_zone() takes --map first (it
stays, for tests and a host), then the start zone, then DEFAULT_MAP when
neither names a level, so a world with no world_map.json plays as before.
A player with a record still goes back to their own zone.

The world map is measured from the start zone (WorldMap.root()): problems()
flags what it cannot reach or what has no way back to it, a start zone that
is not a level, and one with no start cells of its own (Level.parse stands
its first floor cell in, which is no place for everyone to begin); the world
map view lays out from it and marks it. A file rather than a key in a level:
one place, so two levels cannot both claim to be the start. It is set to the
wilds, where the town is, once the town is in that level.
## 306. Towns are seeded from the buildings the maps already have

A town's buildings live only in Towns (decision 297), but a map can put a
forge or kitchen down already standing: the starter town in the wilds,
or one the builder links with set_building. Towns.seed_from(world_map)
squares the two. Each building a level links to a town ("use" one of the
economy rules' buildings, "town" a stockpile place there, as
Level._link allows) stands in that town at level 1 when the town has no
record of that kind yet: logged, building_changed emitted (so the views
and the "town" message follow), and residents waiting for it seated.
A record the town already has is left alone: never lowered, nor its
damage mended, nor a level a map can't show taken away; a building
unlinked or removed from the map takes nothing from the town either (the
record outlives the scenery, as it would a fire). The building's art does
not set its level: Towns does, and the views draw it so.
- Main._boot builds the WorldMap once, gives it to Holdings and, after
  Towns is made, to seed_from.
- BuilderHost._save_and_reload seeds again after each accept (beside
  Holdings.rebind), so a building linked live stands at once.
- WorldMap's areas carry Level's "buildings" (with use and town) for it.
Server only; protocol unchanged; tests/towns_seed_test.

## 310. A turn fades only what changes, and the fade looks near the line

Turning the camera ran `_set_yaw` into `_classify_walls`, which forced every
piece that can fade to be set again (its materials and shadow) on every
frame of the turn, and the test of which pieces hide the player went
through all of them. Outdoors that is every tree: the wilds have 6,676
such pieces, and turning there (A or D held, 180 degrees a second) cost
40 ms of script a frame plus 24 ms of the renderer catching up, 14 fps
against 439 with nothing to fade (Jeff: "camera rotation gets laggy in the
wilds"). A turn now calls `_update_fade()` as a step does, setting only the
pieces whose fade changes. The pieces are also indexed by 8-unit squares,
flat (`_occluder_chunks`), and the lines from the camera to the player are
tested only against those in the squares a line crosses below the highest
top of any piece: a few dozen, not thousands. The same turn now costs
0.06 ms, and frames match a run with the fade left out (about 750 fps
here). view_test checks the index finds exactly what testing every piece
finds, from every floor cell of the test room at four turns and three
tilts. Rejected: capping the swaps per frame with hysteresis, which would
still pay for the test and leave a tree in front of the player late; and
fading by chunk, which would fade trees nowhere near the line.
`tools/map_bench` gains `--map=`, `--spin=`, `--walk=` and `--fade=0` to
measure it on a real level.

## 312. Buffs: a thing with effects is consumed into a temporary raise, on the entity

Items step 4c. A thing whose catalog `effects` are non-empty (food, a
draught, a charm) is consumed when used (World.try_use, whatever its
`use` is called), and each effect goes on the user as a buff:
`World.add_buff(entity, kind, amount, ticks)`. Gear (no effects) is never
consumed; buffs are, as the roadmap's rule has it.

Kinds are the roadmap's upkeep buffs (Items.BUFF_KINDS): **mass** (food,
in kg: added in World._weigh, so a fed player is heavier and harder to
shove; the travel ration, +10 kg for three minutes, is the catalog's
one), **aura** (magic items) and **wits** (social time). Aura and wits
have no reader yet: `World.buff(entity, kind)` is the hook for whatever
comes to use them (psionics, talk), so nothing here guesses what they do.

Never below baseline: an effect with an amount or ticks of 0 or less, or
an unknown kind, is warned about and left out at load, and add_buff
refuses them. Buffs of a kind don't add up: a second one keeps the larger
amount and the later end, so eating three rations is not three times as
heavy (no stacking treadmill).

The buffs live on the entity, `GridEntity.buffs` (kind -> [amount, the
tick it fades]), reassigned whole on each change; a player's and a
companion's replicate (SUBCLASS_REPLICATED "buffs"), and the HUD's top
line shows each with its seconds left ("Fed +10 175s"). World._fade_buffs
looks only at entities with one on (_buffed), in the zone ticking.
`World.buff_changed(entity, kind, state)` (&"started", &"renewed",
&"faded") is for companions to mention a fade, once, and the views. Buffs
are not saved: a restart drops them, as it drops bandaging under way.

## 322. decisions.md and CHANGELOG.md merge by keeping both sides

Every landing appends to `docs/decisions.md` and adds bullets under
`## Unreleased` in `CHANGELOG.md`, so any two trees landing close together
conflicted in those two files on the second one's rebase, and the landing
stopped while it held the lock (art-kit lost its turn twice). Both files are
append-only, so `.gitattributes` gives them git's built-in `merge=union`
driver: a merge or rebase keeps both sides' lines, in order, and only a real
conflict elsewhere stops a landing. The cost: two edits to the same line are
both kept, so a landing that amends an older entry, or a release cut that
renames `## Unreleased`, checks the file reads right after its rebase (the
release session checks the changelog's top on every cut). Rejected: each
tree resolving by hand (the conflicts were never real) and a custom merge
driver (needs setup in every clone; union is built into git).
## 287. Walls in sets by setting

Jeff, looking at the first wall candidates: they read as castle walls, and a
home, a crypt and a cave should not all be one castle. The wall slots are
now sets by setting, each a full module list where it makes sense:
wall.castle.* (outdoor fortifications: today's flat wall.* renamed, the
Kenney fills with them, every module in 1 m, 3 m and 4.5 m), wall.wood.*
(homes: planks between timber posts, 0.3 m thick, one storey), wall.stone.*
(dungeons and crypts: dressed blocks, 3 m and 4.5 m with a few 1 m ledges)
and wall.cave (natural rock: a profile and an end, a pillar, a rockfall).
Each set has its own wall.<set>.profile for terrain's sweep (no cap_y for
the cave), material.wall.<set> for the runs' texture (material.wall became
material.wall.castle), and floor.<set> for the ground inside such a place
(cobbles, planks, flagstones, rock; textures as ground.*, which stays for
the outdoors). A profile carries a "variation" block terrain's sweep reads,
so Jeff can tune it without code: sway, broken, gap, lean, jitter, sag;
castle sways 10 %, is broken 0.1 and breached 0.05; wood leans up to 2° a
run and sags 3 cm post to post; stone and cave are all zero (terrain's
sweep makes the cave's faces). Towers (wall.<set>.tower for castle, stone,
wood) stand at a vertex, taller than the wall, for a town's walls. Doors
stay set-free for now.

Buildings (decision 263) lose their floor part, since terrain draws the
inside as ground in the building's floor_set (one lit surface, no double
floor at the door), and say their wall_set and floor_set (wood for the
hut, house and shed), read through ArtKit.spec. A building's damaged state
is a roof_damaged part, shown in place of roof with the same pivot, and a
state_damaged part of rubble at the walls' feet: a state node can only add,
and a caved-in roof needs the whole one gone.

Until terrain passes a set in (decisions 285, 286), client3d draws every
wall in the castle set, so nothing changes on screen.

## 288. Monster AI stays in GDScript: C# measured, not adopted

Jeff asked for real numbers on moving monster AI, starting with
pathfinding, from GDScript to C#. World.find_path (the grid A*, its step
memo, doors, occupancy, heat and held ground) and line of sight were ported
to C# in a throwaway worktree on main at 9cbeb51 (enemy-ai step 4), using
Godot 4.7.2 .NET and the .NET 8 SDK. The C# side read a mirror of the
zone's terrain, doors and occupancy, kept current by hooks in world.gd. It
matched GDScript exactly: 1,468 paths compared in play and 20,000 lines of
sight, no difference. Every timing was taken on the 256² castle-density
map_bench under the bench lock on the desktop (Ryzen 7 9700X), with
--settle=300 and 600-tick blocks. The GDScript baseline is the standard
Godot build of the same commit. The throwaway code is deleted; nothing
landed in the game.

| | GDScript (standard Godot) | GDScript (.NET Godot) | C# find_path (.NET Godot) |
|---|---|---|---|
| tick median, 1 / 4 / 9 players | 3.2 / 7.1 / 13.8 ms | 2.9 / 7.1 / 13.7 ms | 2.6 / 6.8 / 12.4 ms |
| worst tick, 1 / 4 / 9 players | 21 / 26 / 58 ms | 10 / 36 / 61 ms | 8 / 24 / 62 ms |
| time in find_path, 4 / 9 players | 1.07 / 1.97 ms a tick | | 0.08 / 0.15 ms a tick |
| one path in play (glue included) | 360-410 µs | | 28-32 µs |
| a monster's path (capped at 400 tiles) | 527 µs | | 24 µs |
| a path corner to corner across 256² | 100-220 ms | | 2.3-4.0 ms |
| a line of sight | 15.7 µs | | 1.1 µs (0.4 batched) |
| a call (no args / two Vector2i) | 110 / 141 ns | | 455 / 775 ns into C# |
| peak working set, 4 players | 696 MB | 719 MB | 719 MB (C# heap 5 MB) |
| server export | 78.8 MB, 2 files | | 158.8 MB, 189 files |
| client export | 115.2 MB, 2 files | | 195.4 MB, 189 files |
| server start (Windows, to listening) | 625-660 ms | | 709-737 ms |

The tick medians move by 1-3 ms between runs, so the direct measure is
the one to trust. C# makes pathfinding 13-20 times faster, but that saves
only 1-1.8 ms of the 9-player tick, about 13%. Worst ticks did not move.
The other ~10 ms of the tick is spread over hundreds of short monster
calls (idle steps, patrols, looks, refreshes). Most are a few µs, and that
is about what one call into C# costs.

Costs:
- **Dev (Windows):** a second Godot binary (the .NET editor), the .NET 8
  SDK, and the .NET templates (1.2 GB download, 1.9 GB unpacked). Every
  tool, worktree and GODOT_PATH would move to the .NET editor. The repo
  needs a .csproj and .sln at its root.
- **Builds before runs:** a headless run uses whatever assembly was built
  last. tests/run.sh, net_test, state_test, map_bench and every tool would
  need `dotnet build` first, or they test stale C#.
- **Export time and hangs:** an export takes about a minute. But MSBuild's
  reused nodes held the pipe for another ~9 minutes, so scripts would need
  MSBUILDDISABLENODEREUSE=1.
- **The box:** server/deploy.sh builds the server on the box with the Linux
  Godot, and the box has no .NET. Either the .NET Linux editor, the .NET 8
  SDK and the .NET templates go on the box, or the server is exported on
  the desktop and shipped. The server carries its own runtime (a 77 MB
  data_Psykinetic_linuxbsd_x86_64 folder), so nothing runs system-wide, but
  deploy.sh's install step must copy that folder too.
- **Support dates:** .NET 8's support ends in November 2026, so an upgrade
  would follow soon after adopting it.
- **Moving only the pathfinder:** about 240 lines of GDScript become about
  330 of C#, plus about 135 lines of GDScript glue. The glue keeps a second
  copy of terrain, doors and occupancy in step through hooks in spawn,
  despawn, relocate, doors, zone switches and terrain resets. That is a new
  class of bug: the mirror disagreeing with the sim.
- **Moving the monster loop:** GDScript and C# cannot extend each other's
  classes. Monster in C# drags GridEntity and its five subclasses, Senses
  and World's queries with it: in effect all of sim/ (34 files, about
  16,000 lines). The 33 test files are written against GDScript members,
  six of them against a monster's own state.
- **Tooling:** C# changes need a rebuild. There is no reload into a running
  game, and the GDScript debugger does not step into C# (Visual Studio or
  Rider attach for that). The GDScript editor and builder tools are
  unaffected.
- **Parallel worktrees:** each worktree builds its own assembly on the
  shared CPU.

Alternatives:
- **Further GDScript work on the same code:** the cost is the searches
  themselves. A search that cannot reach its goal looks at all 400 tiles,
  and the door check and retries repeat searches. Reachability regions
  (cells joined with the doors as they are, so an unreachable goal fails at
  once), path reuse within a chase or pack, and fewer retries cost no
  toolchain. They should take most of the 1-2 ms, but this has not been
  measured.
- **The hot function alone in C#:** measured above, 1-1.8 ms at 9 players
  for all the costs listed.
- **A GDExtension (C++):** at least C#'s speed, with cheaper calls and no
  runtime (a 1-3 MB library per platform). But it needs a C++ toolchain and
  godot-cpp for Windows and Linux (the box builds on the box), a crash
  takes the server down, and it needs the same mirror glue. Not measured.

Decision: stay in GDScript, and move no monster AI. Pathfinding is the one
piece that ports cleanly, and it is only a seventh of the tick. The rest
cannot move without all of sim/, and the toolchain, deploy and test costs
fall on every tree. The measurements are kept here for later. If long
walks (100-220 ms corner to corner today, on world-tick walks or
click-to-move across a big map) or pathfinding grow into the stall, first
do the GDScript work above. Only then move find_path alone, as a
GDExtension or C#, with these numbers as the bar.

## 307. Weather is a function of the world clock and each region's climate

Jeff's environment step 4: clear, overcast, rain, fog, wind and storms,
changing on the world clock with gradual transitions, chosen per region by
a simple climate.

Weather (sim/weather.gd, static, beside DayNight) works it out the way the
hour is worked out: the day is cut into spells (a climate's "spell", a
quarter day by default), each spell's kind is picked from the region's
climate weights by a hash of (region, spell), and the change from one
spell's kind to the next is blended over the climate's "change" (a tenth
of a spell by default). Each kind is an amount of cloud, rain, fog and wind
(Weather.KINDS), and the blend is of those, so a fog bank rolls in and out
over the change. The wind blows a way of its own per spell, turned through
the change. Nothing is stepped or saved, and every peer gets the same
weather from the clock it already has.

The climates are data, levels/climates.json, keyed by lore region id (only
entries of type "region" in levels/lore/regions.json; lore gives words,
this file the numbers), with a "default". Every number in it is a
placeholder until lore and Jeff agree each region's character: the Blood
Rot's land weighted to fog and overcast is environment's guess. A level
names its region in level.json "region" (Level.region_of; none is
town_lands, and an id that is no lore region is warned of and read as
town_lands); Level's terrain carries it.

The one state is the console's override, `weather <kind>|auto|reload
[<minutes>] [<region>|all]` (30 minutes by default): {kind, from, until}
per region, in and out over a change, saved in the snapshot's "sky" while
it runs. The "sky" message (decision 290) now also carries the overrides
and the server's climates, so a client of another build works out the same
weather, and a reloaded climates.json reaches everyone with the next sky
message. That changes what the message carries: PROTOCOL_REVISION goes up.

## 308. What weather does in play: outdoors only, one lookup a zone a tick

Fields.update_weather, called by World.step for each awake zone (a
client's on each tick it is told), keeps that zone's Weather.at and what
it does. Only outdoors, out from under a roof (Fields.under_sky): rooms,
huts, caves and dungeons are untouched, even in a world whose other zones
have a storm.

- Light: cloud takes up to CLOUD_DIM (a quarter) of the sky's light over
  the night's (a storm's noon is about 0.8, well over Senses.DARK).
- Sight: World.weather_sight_at(cell), 1 − 0.55·fog − 0.25·rain (thick
  fog: about half), scales a looker's sight range at its own cell in
  Senses.sees, glimpses and sees_cell alike. Adjacent (NOTICE_ALWAYS) is
  not scaled, and a body carrying a light is seen at full range: a lantern
  shows in fog.
- Hearing: World.weather_hearing_at(cell), 1 − 0.3·rain − 0.25·wind (a
  storm: under half), scales a noise's radius at its cell in World.noise,
  before anyone is asked, so muffling halves the scaled reach. Speech is
  not scaled: World.noise carries chat and whispers between players too.

Hook points agreed with enemy-ai (who owns Senses and World.noise's
rules). Wind does not move heat or fire in the sim yet; that needs a
go-ahead.
## 323. Weapons are verbs, as catalog data: Items.VERBS, verb_of, World.wielded and guard

Items step 5. The roadmap's weapons (hammer, sword, shield, giant axe,
spear, dagger, bow) are catalog entries with a `verb`: a kind and its
numbers, never a damage tier. Each kind's numbers and their defaults are
`Items.VERBS`; every verb also has `Items.COMMON`'s speed (a multiple of
the wielder's attack time), damage and force (multiples of its blow):

- knockback (hammer): force 3, slower (speed 1.3);
- block (sword: arc 0, absorbs half a blow; shield: arc 1, the three
  cells in front, a whole blow, no damage of its own): stamina per blow
  taken, breaks_at (a blow that strong breaks the guard);
- knockdown (giant axe, two hands): arc 1 (three cells), down 15 ticks,
  slow (speed 2), damage 1.5;
- reach (spear): two cells, brace (stops a charge);
- backstab (dagger): quick (0.6), half damage, twice from behind;
- ranged (bow, two hands): 8 cells, draw_min 5 and draw_full 20 ticks.

The numbers are a starting point to tune in play. `Items.verb_from`
fills a verb in at load: an unknown kind is no verb, a number that isn't
one (or is under 0) its default, an unknown key left out, each with a
warning. `Items.verb_of(id)` gives it ({} for anything not a weapon: a
knife is a tool and a shop's weapon, with no verb).

What an entity fights with is `World.wielded(entity)`: the right hand's
weapon, else the left's, a guard only when nothing else is held; its
guard is `World.guard(entity)`: the block verb with the larger absorb in
either hand (a shield over a sword). Combat (the roadmap's "weapons as
verbs", a later step) reads these; nothing here changes an attack yet, so
the knockback threshold (decision 305) still decides today's pushes.

Every weapon is made by the smith (the only item trade with a workshop),
from ore, wood and, for the bow, cloth, so the town's "weapon" and
"shield" wants are met. Blocking and drawing need a button: that is Jeff's
choice between layouts (the coordinator has it), landed separately.
## 319. Creatures are art slots: a rigged body and a named clip set

Jeff's hunting and wildlife (enemy-ai leads) needs deer, rabbits, boar and
wolves drawn. Each is an art slot of a new kind, "creature": creature.deer
(the doe), creature.stag (the antlered male), creature.wolf, creature.boar
and creature.rabbit, sized as the animal stands, with a budget (a rabbit
1,200 triangles to a stag 4,000) and a "clips" list: each clip a name the
game asks for (idle, walk, trot, run, graze, alert, hit, death; attack,
charge, howl where the animal has them), the names it may have in the art
(the Quaternius pack's Gallop is a run, its Eating a graze), and either
"required" (the behaviour reads wrong without it) or a "fallback" (what the
game shows instead: trot is walk faster, a wolf's howl idle with a head-up
tween). ArtCheck holds a creature's own art to it: an armature, every
required clip (an error when missing), the fallbacks named in warnings.
Names match in any case, after any library or armature prefix. A grey box
has no rig, so the check asks none of it (ArtKit marks grey instances).

The deer, stag and wolf come from Quaternius's Ultimate Animated Animal
Pack (CC0; its own License.txt still to be read before use), the boar is
an art-gen mesh on the Quaternius Pig's rig and clips (pc-character), and
the rabbit an art-gen mesh on a small rig of pc-character's. A pack's flat
materials move onto palette swatches when its art drops in, as any piece's.
## 313. Raids are real monsters in a played zone, handed back to maps when it sleeps

maps moves raid groups on the world tick (WorldRaids). When a group's
route crosses into an area whose zone is awake, maps calls
World.raids.enter(group, area, arrival[, goal]) and leaves the group alone
(its state "present") till Raids hands it back by one of three signals:
raid_left(id, strength, area, cell, carries) when the zone sleeps or is
reset with raiders alive, or they reach their goal when it is not the town
(an exit on their way), or are home again after the raid; raid_done(id,
report) when the first raider stands on the town's stockpile ground (Towns
.raid_arrives with the strength left; what it took the group now carries,
and the raiders turn back the way they came), followed by one of the other
two; raid_beaten(id, area, cell) when every raider is dead or running at
once (a rout), what it carried left on the ground there. One owner at a
time: maps never moves a present group, Raids never keeps one asleep.

The group's strength is spread over raiders of its faction's kinds
(Factions "monsters" with a "strength" in levels/monsters.json: imp 1,
brute 3, sneak 1), drawn by the group's id, each holding a share, so its
strength is what its living raiders hold and no fraction is lost. They
march (Idle.MARCH: a route of waypoints, one every 6 steps of a single
capped search when they enter, else straight at the goal) and fight
whoever they notice like any monster, going back to the march after; far
from everyone, the world tick walks them on (World.walk). World.spawn_spec
puts them in as a level's monsters are (Main's _spawn); zone_slept says a
zone fell asleep. No cost when there are no groups (Raids.step returns at
once). tools/clip.gd scenario raid.

## 314. Raiders kill players; companions and residents they beat down are taken

Raiders kill players, like any monster; residents and companions they beat
down in a raid are taken captive, never killed (the town rule: raids take
food and people). Companions can still die in ordinary fights, and are
brought back later by a medicine man or temple (economy, companions).
World.damage asks World.spared(target, source, cause) before a blow kills:
unset it kills as ever; Raids sets it, and answers the group's id when the
source is one of its raiders and the target a Companion (a resident is
one). Then the target stays at 1 hp, entity_died is not emitted (no death
lines, no "alive": false) and World.entity_taken(target, by) is: Main takes
her off the map and keeps her record "taken" (companions' side), and the
group carries "companion:<keeper id>" among its captives, the origin Towns
names her by. entity_damaged is emitted first as ever, so the blow is seen.
## 285. Walls and floors are drawn in sets

The map says which set its walls and floors are drawn in (level.json
`"walls"` and `"floors"`: castle, wood, stone or cave, art-kit's sets of
decision 287; castle when not given or not a set, so every map today looks
as it did). A building's outline and inside are drawn in its slot's
`wall_set` and `floor_set` (wood for the hut, house and shed), whatever the
map's are. Drawing only: the sim's walls, floors and every rule are the
same in any set.

Walls: `Client3D._wall_sets` (edge to set, filled for buildings at build
time, open to others) replaces `_plain_walls`. A run is one set; its sweep
reads the set's `wall.<set>.profile` (points, cap_y, none for the cave: all
body) and its `variation`, so Jeff tunes a set without code: sway (the
body's rise and fall, of cap_y), broken (a share of edges' tops broken
off), gap (a share of breaches of rubble), lean (degrees a run leans at
most, its base on its line), sag (metres the top dips between the run's
ends) and jitter (metres its points are pushed, the same push where a
point is shared so no seam opens). Castle's 0.1, 0.1 and 0.05 are the
constants it had, so it is unchanged; a home's wood leans up to 2 degrees
and sags 3 cm, nothing broken, under its roof. Its thickness is the
profile's, in what hides the player too (`_edge_bounds`: castle 0.5 m,
wood 0.3). Its material is `material.wall.<set>` once it has a texture,
else courses made here in a swatch of the set's (wood's are long planks).
A post is the set's `wall.<set>.post` (`.end` for the cave), a column of
the set's own stone while that slot is only a grey box, and stands where
two sets meet on a line as well as at turns and ends.

`Client3D._wall_states` (edge to "broken" or "rubble", for buildings: a
town's walls by their level) draws an edge broken, a ragged stub never
under 0.45 of the cap, or as rubble, a bank 0.9 to 1.15 m high and wider
than the wall, never a way through; `wall.<set>.straight_ruined` and
`wall.<set>.rubble` stand there instead once they have art. The sim's wall
stays either way. `Client3D.rebuild_walls(edges)` draws again only the runs
on those edges' lines and their posts, and indexes what can fade again;
the old runs are hidden at once and freed two frames later, so a call
right after a build never frees a 3D node before a frame is drawn (296).

Floors: the ground stays one mesh and one shader (decision 216). A second
texture, a byte a cell read cell by cell (so a floor ends at the walls'
line, not along the ragged border kinds have), says each cell's floor set:
0 the ground's own look, then wood (planks), stone (flagstones) and cave
(rock), each in a palette swatch, or its `floor.<set>` texture (4 m a tile)
once it has one. `Client3D._floor_sets` (cell to set) holds the
buildings' insides; the map's floor set is drawn on its stone ground,
grass, dirt and sand left as they are. Buildings keep no floor of their own
(287): no double floor at the door, one lit surface.

Rejected: a set a building or region paints per cell in the editor (later,
if Jeff asks); a mesh per floor set over the ground, which would double the
ground's draws and light it twice; and keeping plain walls as a flag beside
the sets, which the wood set's own variation now says.

## 324. A release cut keeps `## Unreleased` and puts the version under it

Cutting v0.1.141 and v0.1.142 renamed `## Unreleased` to `## vX.Y.Z` and then
added an empty `## Unreleased` above it in a second commit. A tree that
rebased after the cut had its bullet, written right under the old
`## Unreleased` line, carried by git to the renamed line: it landed under the
released version (terrain caught it twice by hand; decision 322's union merge
does not help, since there is no conflict). Now a cut leaves the
`## Unreleased` line untouched and inserts `## vX.Y.Z` (and a blank line)
below it, above the bullets, in the one CHANGELOG commit: the line every
tree's bullets hang from never moves, so a rebase keeps them under it.
`tools/release_client.ps1` takes the release notes from the `## v<version>`
section when there is one (the top section only when there is none), so the
empty Unreleased section above it is not the notes. Rejected: asking every
tree to check after a rebase (they did; it still slipped twice).

Companions' side (Main._on_entity_taken): the companions who saw it are
told it as a fact ("<name> saw <her> carried off by raiders in <place>")
and in their exchange; she gets one ("<name> was beaten down and carried
off by raiders in <place>"); her record is kept as at a journey's end (her
pack, facts) and marked "taken": {by, zone, at} (Main.companion_taken; a
resident leaves her town's work); her player is told; she leaves the map
as one who travels, not one who dies. While taken she is not spawned, and
her player, joining, is told she is held. Main.companion_freed(player_id,
place) frees her: with a stockpile place she rests in that town as a
resident (as Wren and Nix do between trips) till her player comes, without
one (her captors beaten in the field) she comes back beside her player,
at once if they are in that zone; a fact either way. Towns calls
companion_taken for a resident taken in a raid on a town nobody is in, and
companion_freed on a rescue.
## 321. A minimap from the zone's Level data: a corner map always, the big map on M

The 256-cell wilds are too big to find your way by the view alone (Jeff:
"we'll need a minimap"). render/minimap.gd (Minimap) draws the zone the
client is in from the Level data Main already holds for it, one pixel a
cell into a texture made again on a change of zone or a builder's edit
(27.6 ms for the wilds, once): the ground in its kind's palette swatch,
height a shade lighter or darker, water blue, a wall darkening the floor
either side (the walls Level puts round the border are the frame's edge
instead), nothing where there is no floor. Over it each frame: you, a
pointer turned where the camera looks; your companion; the other players in
their tints; doors; the start cells; the ways out (links at their marker,
neighbours at their side's middle), named for where they go; and the
level's places. No monsters: finding them is the game. North-up, as the
grid is. It reads Level and World only, so terrain's border glimpses never
appear on it, and nothing new goes over the wire.

The corner map is always on, top right below the compass (the pack and the
gold have the bottom), centred on you at a cell a pixel and never showing
past the zone's edge; a small zone is scaled up to fill it. M opens the big
map, the whole zone fitted to 72% of the screen with its name, the wheel
zooming it in steps (x1, x2, x4) round you and Esc or M closing it. Tab and
Alt were taken (the talk log, every HP bar), and Jeff chose M. Sizes are for
a 1080-line screen and scale with a taller one, as the rest of the HUD does.
The whole zone shows for now; fog of war (what each player has seen, saved
per player, a wire change) and "known" places come later.

Found on the way: decision 299's _release_zones also runs on a host's exit,
where its 3D view answered each freed entity at once and read the rest
(a SCRIPT ERROR in Fields.any_carried_heat); it now pauses the tree and frees
the 3D view before the entities.
## 286. Cave walls are rock, not a swept profile

A map or edge in the cave set (decision 285) is drawn as rock, the way the
cliffs are (decision 226): flat facets in the cliffs' swatch, each its own
shade, darker toward the foot, one mesh a run. A run is columns a quarter
metre apart along it, each CAVE_ROWS points up either side and a ragged
ridge on top. Its width at a height is wall.cave.profile's (wide at the
foot, narrowing up), times a thickness that wanders along the line (0.6 to
0.9 m at the foot); its top wanders 2.4 to 3.4 m; its points are pushed up
to 0.1 m. All of it is read from where the point is in the world (the
line, the place along it, the height), so two runs on a line meet on the
same points with no seam. Nothing reaches more than 0.45 m from the edge's
line, so a walkable cell keeps half a metre clear. The profile has no
cap_y and nothing on top is kept level. A broken edge stands about half as
tall, rubble as low as the other sets' rubble, still rock and still a
wall to the sim. Posts at turns and ends are wall.cave.end once it has
art, until then a lump of the same rock, eight sides round. No texture:
material.wall.cave and material.rock can replace the swatch later, as
they can on the cliffs. Rejected: sweeping the profile with jitter (its
long flat faces read as masonry, not rock), and a separate rock mesh per
cell edge (seams at every metre).

## 270. Ambience: beds weighed from the zone, the roof, the clock and the weather

Jeff's brief asks for beds per zone, time of day and weather (wind on the
field, birds at dawn, crickets at night, a fire's crackle, the town's
noise), crossfading as you move. Ambience (client3d/ambience.gd, under the
3D view) plays each amb.* slot as a looping, flat bed on the Ambience bus.
Four times a second it weighs every bed 0..1 (Ambience.weights, a pure
function the tests read): outdoors (the level's zone, Level.zone_of) the
forest's dawn, day and night beds by the clock (DayNight's light; dawn a
bell round 6.2 o'clock), the wind, rain and storm beds by the zone's
weather (World.fields.weather, environment's), rain hushing the birds and
crickets; under stone (cave, dungeon) the dungeon's bed; a town's day or
night bed near a building that serves a town. Under a roof
(World.fields.under_sky false at the listener) the outdoor beds are
quieter and muffled (the Ambience bus's low-pass twin). Each bed eases
toward its weight over about two seconds, so beds cross-fade, and a bed
below 1% is stopped. A bed starts at a random point along its loop.

Fire is a point, not a bed: the crackle (amb.torch_fire, a mono loop)
plays from the nearest fire or torch the listener hears, by the same rule
as every positional sound (Sfx.hearing, its slot's range, 4). Beds are cut
by tools/sound_take.ps1 as seamless loops: the take's last two seconds
fade out over its first fading in, and it ends where that overlap began;
flat takes are folded to stereo (some sources are quad or ambisonic).

Sfx.hearing now also shortens a noise's reach in rain and wind under the
sky, as World.noise does (World.weather_hearing_at; never speech), so the
rule that you hear what monsters hear holds in weather too. Rejected:
switching beds outright at thresholds (an audible cut at dusk), the
server choosing beds (it knows nothing a client doesn't, and a client
moves between ticks), and one long recording per zone (no crossfade with
the clock or weather).

## 325. Where a way out's target lies against an area: WorldMap.ways_out

Terrain draws the wilds' edges as borders with a glimpse of the linked level
beyond (the castle's wall past the trees), and needs to know where each
target's cells lie in ours. If terrain worked that out itself, the glimpse
and where a crossing actually lands (WorldMap.arrival, maps') could
disagree, so the world map gives it: ways_out(area, gap), one entry a way
whose target is a level, with its kind, target, our marker or side, where a
link arrives, the direction away from our land, a Transform2D taking the
target's cells into ours, and whether anything leads back (a glimpse of a
drop or a trapdoor can be skipped). A neighbour abuts as arrival() has it:
the same row or column, the target's opposite edge against ours. A link's
target is turned to face us by the edge its arrival is nearest (the castle's
from_wilds is on its south row, so it lies north of the wilds), that edge
gap cells past our land and the arrival across from our marker. Only
translations today: arrival() ignores the levels' "north", and so does this,
so a quarter turn waits until a crossing turns too. world_map_test checks
an edge against arrival(), a link's placement, a one-way link, and the
wilds' castle lying north with its arrival across from the link.

Amended: a link's target goes gap cells past where our land ends going out
from the marker, not past the map's edge (what terrain's design asked; the
wilds' rows 0 to 15 above the castle link are void, now terrain's canopy,
which put the castle some 20 cells out of view from the road). The land's
end is the last floor cell walking out from the marker. Edges are as they
were: a crossing lands at the map's edge, so the glimpse does too.
## 315. Animals are monsters of side "wild"

A wild animal is a row of levels/monsters.json with "side": "wild" (rabbit,
deer, stag, boar, wolf so far), spawned as Animal (sim/animal.gd, a
Monster; Level gives a wild kind's spec that script). It is of no faction:
monsters never hunt it (they look for players and companions, as ever) and
never count it of their side (Monster._same_side), and its own side is its
herd (a row's "herd": a stag runs with the deer). Its row's "role" is what
it does with what it notices:
- prey (rabbit, deer, stag) never fights: anyone it sees, glimpses or
  smells, a predator's step, or anything loud (a fight, a call, a door)
  and it bolts (FLEEING, its rout cry), and the herd hears the rout and
  bolts with it (step 4's rout: prey are cowards). Another's step only
  brings its head up, turned to it, a moment (SUSPICIOUS, " ?"): you can
  creep up on a herd that does not see you, not walk up on one;
- game (boar) bolts the same, but struck, or cornered with the threat
  near, it charges (its row's HEAVY blow) for CHARGE_TICKS, crying
  "charge", then runs;
- predator (wolf) hunts its row's "diet" in sight (looked over every 10
  ticks, not every think), and players only when bold: by night (the sky's
  light under 0.35, and 2 cells more sight), with 3 of its pack about, or
  just struck. Its call for help is the pack's howl (the "call" cry; sound
  picks the slot by kind).
Idling it wanders about its home and grazes between strolls (Pose.SIT,
which a view of an animal plays as its graze: no new pose on the wire),
seeing 3 cells less with its head down. Animals keep Monster's tiers, so a
herd nobody is near costs what a far monster does. The pose and the alert
it shows are the replicated ones there were; the protocol is unchanged.

## 316. Scent goes with the wind

Senses.smells(entity): an animal smells someone downwind of them, the wind
(Weather's, the zone's fields: wind 0..1 and wind_dir) blowing from them
toward it within a cosine of 0.6, up to 12 cells in a full wind and less
in a lighter one, through walls; never in still air or out of the sky.
One dot product per candidate, after the range check. Animals smell (a
prey's look is sight, glimpse or scent); monsters do not, for now. So the
way to a herd is upwind and quiet: downwind, it is gone before you see it.
## 326. Past the forest, outdoors: a canopy, hills and a far floor

Jeff: "the wilds needs zone borders on the edges". Outdoors, the real trees
stood only FOREST_REACH (8) cells off the land, and past them the view,
which reaches about 22 cells and pans 10 more, showed the sky's colour
under the map: a drop into nothing. `TerrainBorder` (client3d/border.gd),
under the room, now draws what lies past the forest. A canopy: one sheet
at crown height from 6 cells off the land, where the real trees thin out,
rising out of the forest floor among them, to 34 cells, further than the
view and its pan reach from anywhere on the land. Noise rolls it into
crowns and points them, each facet a foliage colour, darker in a hollow
and further off. Its colours are the trees' own: the Kenney fill's greens
while the trees are that fill, the palette's foliage once they are
art-kit's. Hills: where the land's edge stands high, the canopy beyond it
stands as high (the height of the land each cell was reached from). And a
far floor in the forest floor's colour, 200 m past the map, under the
canopy, so no tilt or peek finds a void.

Drawing only: the sim, paths, picks and the minimap never see it, and no
rule changes at the map's edge. Its cost is kept off the room's build: the
walk out from the land (eight ways, from the land's outline) and the
meshes' arrays are made on a worker thread, and the meshes are added when
it is done. The land set it reads is made new each build, never cleared
under it. One mesh a 16-cell chunk, flat facets, no shadows: 228 chunks for
a 256-cell map, a few in view. map_bench at 256 outdoors: frames and ready
time as before, within the spread. level.json `"border": "none"` leaves it
out. Openings at a map's ways out, and a glimpse of the level beyond, come
with decision 327.

Rejected: more real trees out to the view's reach (tens of thousands of
nodes on a 256-cell map), and fog, which would have hidden the land's own
far side too.

## 309. What weather looks like: drawn round the view, eased to the sim's

The 3D view draws the zone's weather (World.fields.weather, decision 308)
outdoors only, with one WeatherView node (client3d/weather_view.gd) that
moves with the camera's target. It eases the drawn amounts toward the
sim's (the sim's already change over a climate's change; this only
smooths its ticks). Nothing here is in the sim or on the wire.

- Sky and light (Client3D.weathered_look, over the hour's sky_look): cloud
  greys the sky, ambient and sun, and takes up to CLOUD_SUN (three
  quarters) of the sun's or moon's light. The ambient is kept, so a storm's
  noon is grey, not dark, and its shadows fade with the sun. The floor's
  sky_floor follows the sim's light, the day's less Weather.CLOUD_DIM of
  cloud. The sky's look is still set once a game minute, plus whenever the
  eased weather changes.
- Fog: the Environment's exponential fog thickens (FOG_DENSITY at full
  fog, a little for rain), plus height fog up to FOG_HEIGHT. Over it, three
  unshaded noise layers near the ground drift with the wind, so thin fog
  shows as wisps and a bank rolls in and fills them. Sized against the
  sim's sight: full fog halves sight, so the view's own few cells stay
  readable.
- Rain: one GPUParticles3D of streaks in a box over the view, its
  amount_ratio the rain, slanted downwind. The drops hide on a
  GPUParticlesCollisionHeightField3D that follows the camera and is redrawn
  only when the view moves, so rain stops on roofs and never falls inside.
  The drops are on their own visual layer, which the heightfield leaves out.
- Cloud shadow: one Decal of seamless noise, tiled 2×2, drifting with the
  wind and jumping a period at a time so the jump never shows. Strongest
  in broken cloud, none in overcast, storm or fog, by day only.
- Wind: one global shader uniform, `wind` (project.godot [shader_globals]:
  xy the way it blows in the view's xz, z its strength), set each frame.
  Ground fire stretches downwind (fire.gdshader), torch flames lean
  (flame.gdshader, one mesh for all), and tufts, flowers and reeds bend in
  rolling gusts (scatter.gdshader, their own material; stones and roots
  keep the plain one; no shadows, so no shadow-map redraw). Trees and
  saplings wait: their near-fade swaps in see-through copies of their
  materials, which would need the same vertex code (agreed with terrain).
- `--weather=<kind>` (and map_bench's) starts every region already in a
  weather, for clips, shots and benches.
## 327. A glimpse of the level past a way out

Jeff: "maybe the castle gets a little area where you can see it just beyond
the map edge". Past each of an outdoor level's ways out (WorldMap.ways_out,
decision 325), the client draws a piece of the level it leads to: from the
wilds' castle road the castle's south wall and gate stand past a band of
trees, and from the castle the wilds' road runs on south. Drawing only:
nothing in it is walked, picked, faded, lit by its own torches or on the
minimap, and no entity, item or fire of it is shown.

What is drawn: the target's cells within GLIMPSE_DEPTH (18) of the side it
shows us and GLIMPSE_WIDE (20) either side of the way, moved into our cells
by ways_out's to_ours, its heights lifted so the way's ends stand level.
ways_out puts the target's map GLIMPSE_GAP (3) cells past where our land
ends; where the target's own land starts in from its map's edge (the
wilds' starts 16 rows in), it is slid in by that much, so land faces land
across the gap, and its depth is counted from its land. No cell of it comes
within the gap of our land (a ragged edge would touch it otherwise). A lane
of the marker's ground, three wide, runs from our land to it. Its cells and
the lane count as land to our forest (`_wooded`): the trees and the border's
canopy (326) grow round them and stand in the gap either side of the lane.
A way with no way back, or into a level not outdoors (a door down into a
dungeon), shows nothing.

How: a second `Client3D` under the room, never processing, draws it with
the same builders (`_draw_glimpse`: ground, water, ledges, walls in its own
sets, doorways shut and without picks, posts), its ground lit by our sky
alone (`sky_floor`, passed on from ours each hour). The target is read with
`Level.load_level`, kept by WorldMap's digest of it, so a rebuild reads it
again only if it changed: the castle's rebuild 40 ms to about 105 (the
wilds' first read 55 ms more), the wilds' within the spread, frames as
before. Rejected: drawing it from WorldMap's areas, which keep no ground
kinds or water; and making its cells walkable void with a rule that they
are not, which every path and pick would have to know.
## 328. Raid groups travel the world map; camps make a town's threat; off until switched on

Jeff: raids are "real raiders on the world tick": a group sets out from a
raider camp, travels the routes and reaches the town. Economy owns what
happens at the town (Towns.raid_arrives) and enemy-ai the raiders in a
played zone (World.raids); this is the part between, sim/world_raids.gd
(WorldRaids, World.raid_groups), server only, on the world tick, saved in
the snapshot as "raid_groups".

The camps are Holdings places of kind "camp" a faction holds; the towns a
camp raids are Towns' towns whose place a faction hostile to it holds
(factions.json). A town's threat (Towns.threat, which economy left for
this) is one less the chance no camp comes: each hostile camp pulls by its
worth (full at size_full) and less the further its route (halved at
threat_tiles steps). A camp with no group out sends one at its most
threatened town with send_chance times that threat a world tick, one group
a camp and a town at a time; its strength is the camp's worth times
strength_per_size; its id "raid:<camp>:<step>". It walks the route on its
faction's layer (WorldRoutes), steps_per_world_tick a world tick, so held
ground is physical: it goes round another's ground, and where there is no
way round it stops there and turns back. At a town nobody is watching it
raids by the numbers: Towns.raid_arrives, whose report's took and captives
are what it carries home, where each captive is held at the camp
(Towns.captive_held). Walking into an area whose zone is awake it is handed
to World.raids (enter, marching on the town if it is there, else for the
cell its route leaves by) and stands still on the world map until
raid_left hands it back where and as strong as it is, carrying what it
carries (it does not walk straight back into the area it left), or
raid_beaten ends it; raid_done marks the town as hit. A group in play when
the server stopped (raiders are not saved) goes on from where it was last.
The rules are levels/economy.json raids.groups, with defaults in the code.

It is off until switched on (--raids, or the console's raids on, kept in
the snapshot): the box has Jeff's town being built, and no real level has a
camp yet, so raids stay a test until he says. While off nothing is sent,
nothing moves, and the towns keep economy's own threat. The console's
raids lists the groups, and raids send <camp> <town> sends one at once.
tests/raid_groups_test plays it on two fixture areas, the hand-over through
a stand-in World.raids.
