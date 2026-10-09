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

## 115. What she sees is a switch: list, grid or both

Whether a small model understands a scene better from a list of things
with their relations already worked out, or from a map it has to read
itself, is a question for the model, not for us. So the "around you"
block has three forms behind one flag (`--perception`, and live on the
console), the same in the voice's ask and the stance's, and an eval that
asks the real model. The list is the default: it is what the voice had
before, in a richer form, and the cheapest in tokens.

## 116. The list says where things are, so the model need not work it out

Supersedes 111's "a sentence or two". Up to five things within six paces,
each with paces, her bearing, and its relation to her and Jeff ("between
you and Jeff", "behind Jeff", "on the ledge above you") computed by the
server. A small model cannot do geometry from coordinates, but it can
repeat a relation it is given. Monsters are chosen before ground: a ledge
and a stair at her feet must not push the sneak next to Jeff off the end.
Torches are left out, as they are of the grid's key.

## 117. The grid draws walls and doors on cells

The sim's walls and doors are thin, on the edges between cells; a
character map has only cells. Drawing at double resolution would be a
25 x 25 map, twice the tokens. Instead an unseen cell whose face she can
see across a wall is drawn "#", and a door on its doorway, the cell beyond
it from her ("D" closed, "d" open). Behind a wall she cannot see anyway,
so nothing she could see is hidden; and the characters are spaced so
each is its own token, or "....." reads as one.

## 118. The perception eval scores against the sim, by keyword

The truth for each question (what is next to her, where the nearest
fire is, whether the nearest door is open, what is near Jeff) is worked
out from the scene with the prompt's own line of sight, not written by
hand, so a scene can be moved without its answers going stale. Keyword
scoring is crude, but it is cheap, repeatable and needs no second model;
an answer that names a thing as next to her when it is not fails, so
reciting the whole list does not pass. It runs on the dev machine against
the box's Ollama through a tunnel, so testing never means deploying.
