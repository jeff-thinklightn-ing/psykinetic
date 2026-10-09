# Changelog

Newest first. `tools/release_client.ps1` uses the top section as the release
notes.

## v0.1.70

Companions. Server.

- A server can give companions' voices a model of their own, on another
  machine (`PSYKINETIC_VOICE_URL`, `PSYKINETIC_VOICE_MODEL`), while their
  quick decisions stay where they are.
- Asked about something she hasn't seen, she is reminded that a flat "no"
  would claim she knows.

The server must be updated to v0.1.70 too, as it refuses any other version.

## v0.1.69

Companions. Server.

- **Questions don't change what she does**: only something you actually ask
  her to do (stay close, hold, attack, guard, fall back) changes her
  stance. Questions, remarks and things she can't do with her hands don't.
- Asked about something she hasn't seen, she is left to find out what you
  mean in her own words.

The server must be updated to v0.1.69 too, as it refuses any other version.

## v0.1.68

Companions. Server.

- Ask about something she hasn't seen and she asks back ("What door?")
  instead of telling you there isn't one.

The server must be updated to v0.1.68 too, as it refuses any other version.

## v0.1.67

Companions. Server and client.

- **She knows what she has seen**: ask about a door, fire, water or a
  crate and she answers from what she can see, what she saw earlier, or
  what she can feel; if she hasn't seen one, she says so instead of making
  it up.
- **Talks to you, not about you**: she calls you "you", never repeats your
  instructions back or describes herself, and says distances as "close by",
  "a few paces", "some way off".
- **Names matter**: a line naming someone else isn't for her; a line
  naming no one, she answers only if she has something useful.
- The controls list has a darker backing, easier to read.

The server must be updated to v0.1.67 too, as it refuses any other version.

## v0.1.66

Companions. Server.

- **Companions hear everyone nearby**: what any player (or companion) says
  within earshot reaches every companion there, who knows who said it.
- **She knows when it isn't for her**: talk to the other player and your
  companion keeps quiet; say her name, or speak to her with no one else
  around, and she answers.
- She knows who else is around, and where.
- A fallen player still hears what is said nearby.

The server must be updated to v0.1.66 too, as it refuses any other version.

## v0.1.65

Chat. Server and client.

- **Speech carries, but not far**: what you say, and what companions say,
  is heard only by players on the same map within about ten steps. Your
  companion hears you only from that close too.
- **Party chat**: start a line with `/p` to reach every player on the
  server, on any map. It shows in green in the talk panel, and companions
  never hear it.

The server must be updated to v0.1.65 too, as it refuses any other version.

## v0.1.64

HUD. Client.

- **A proper compass**: bigger, with a ring of ticks that turns with the
  camera and N, E, S, W that stay upright (N in red).
- **Controls list**: the controls are now a tidy list down the left side.
  Press H to hide or show it; the game remembers.
- The top line shows just who you are, your HP and the tick.

The server must be updated to v0.1.64 too, as it refuses any other version.

## v0.1.63

Companions. Server.

- **Quick phrases always work**: 1 With me!, 2 Stay back!, 3 Get them!,
  4 Fall back! change what your companion does at once, and she still
  answers you.
- **Calm, she follows**: with nothing hostile near and nothing asked of
  her, she keeps with you; she only weighs up what to do in a fight.
- She only holds a spot when you ask her to.
- **Smoother following**: she lets you get a couple of steps ahead, then
  catches up, instead of stepping at your heel.

The server must be updated to v0.1.63 too, as it refuses any other version.

## v0.1.62

Zones. Server and client.

- **Many maps at once**: every map is its own place on the server, with
  its own monsters and things, and stays as you left it.
- **Links take you, not everyone**: step on a link and you and your
  companion go to the other map; the others stay where they are. The test
  room has a link in its top-left corner to the sample map, and back.
- You see only the map you are on. A map nobody is on sleeps until
  someone arrives.
- The server remembers which map you were on, and puts you back there.

The server must be updated to v0.1.62 too, as it refuses any other version.

## v0.1.61

Light, heat and directions. Server and client.

- **Heat and light**: fires, torches, lanterns and the lantern everyone
  carries give off light and heat that fall off with distance and stop at
  walls and closed doors. Standing in fire, or hemmed in by it, burns. In
  3D the floor glows warm around fires, and dark levels get darker away
  from the lights.
- **Compass**: every map has a north. A small compass on the screen shows
  it, turning with the camera; F3 shows which way the camera faces.
- **Companions speak in compass directions**: "the fire is two paces to
  the north", never "to my left". She also says when she feels heat, or
  when it's dark past a door.
- Levels can set their light (`ambient`) and north, and hang lanterns.

The server must be updated to v0.1.61 too, as it refuses any other version.

## v0.1.60

Companions. Server.

- **She answers when asked**: a question to a companion always gets words
  back, never silence; "..." is only for moments nobody spoke to her.
- **Sharper sense of what is around her**: she is told what she can see as
  a short list, each thing with how far it is and where (beside you,
  between you and Jeff, behind Jeff, up on the ledge): monsters, anything
  within two paces, and whatever you just asked about.
- **Perception is a setting**: `--perception=list|grid|both` (or
  `perception` on the console) can give her a small map of what she sees
  instead of, or as well as, the list. The list stays the default; see
  docs/perception_eval.md for how the three compare.

The server must be updated to v0.1.60 too, as it refuses any other version.

## v0.1.59

Companions. Server.

- A companion stops going on about the same fire or crate: she mentions
  her surroundings when something there is new, or when you ask about them,
  and knows what she has already talked about.
- While you are down she still knows your name (the transcript no longer
  calls you "the one you travel with").
- Rebuilt transcripts no longer repeat the stretch around a fall.

The server must be updated to v0.1.59 too, as it refuses any other version.

## v0.1.58

Server.

- Rebuilt transcripts no longer repeat stretches of the conversation, and
  their times run in order.

The server must be updated to v0.1.58 too, as it refuses any other version.

## v0.1.57

Companions. Server.

- **Monsters by kind**: companions now speak of "an imp" or "the brute",
  never "Imp2".
- **Fewer kill calls**: a companion comments on a monster's death only if
  it was a brute or bigger, it fell next to you, or it was the last one
  of the fight. An ally falling always gets a word.
- **Transcripts rebuilt**: the server can rebuild past conversations from
  its log, your lines included (`transcript rebuild` on the console).

The server must be updated to v0.1.57 too, as it refuses any other version.

## v0.1.56

Server.

- The console finds a companion's transcript by name in any case, even while
  she is not in the world.

The server must be updated to v0.1.56 too, as it refuses any other version.

## v0.1.55

Companions. Server.

- **Transcripts**: the server keeps a day-by-day text record of everything
  said to each companion and by her, with what happened in between, for
  30 days.
- **She sees what is around her**: fire, water, doors, crates, boulders,
  carts, ledges and torches nearby, and she can say where they are ("Fire
  is burning two paces to your left").
- She says so when she doesn't know what something is.

The server must be updated to v0.1.55 too, as it refuses any other version.

## v0.1.54

Packaging. Client.

- The client no longer carries development scratch files it never used.

The server must be updated to v0.1.54 too, as it refuses any other version.

## v0.1.53

Levels from pixel maps. Server and client.

- **Maps are pictures now**: a level is a folder with a painted map, an
  optional height map and a short settings file. The test room is the same
  room as before, now drawn this way.
- **New ground**: grass, dirt, water, stairs, torches, carts, and brutes and
  sneaks besides imps.
- **Heights**: raised ground with cliffs, climbed by stairs. Shove someone
  off a ledge and they fall and get hurt; nobody can be pushed up a step.
  From higher ground you see over lower walls.
- **Level links**: step onto one and the whole party goes to the next map.
- A sample level shows all of it.

The server must be updated to v0.1.53 too, as it refuses any other version.

## v0.1.52

Healing and instructions. Server.

- **You heal out of combat** now too, at your companion's rate: a point a
  second after five calm seconds.
- **Only real requests stick**: your companion takes your words as an
  instruction only when she understands them as asking something of her;
  a warning or a shout is just talk.
- Her sense of the world now includes the land outside the old stone
  places.

The server must be updated to v0.1.52 too, as it refuses any other version.

## v0.1.51

Companion voice, rewritten. Server.

- **She talks like someone in the dungeon with you**: her voice is told
  only her world and what is happening, never about a game, and sees your
  recent exchange as a conversation.
- She answers when you talk to her, keeps quiet when there is nothing to
  say, and only changes what she is doing when you have asked her to.
- Long lines end at a sentence instead of being cut off mid-word.

The server must be updated to v0.1.51 too, as it refuses any other version.

## v0.1.50

Companion fixes. Server.

- **Death and respawn**: your companion reacts to your death when it
  happens, and to your return as a separate moment.
- **"In danger"** now means a monster within 2 cells; low HP with nothing
  near is "badly hurt".
- **Instructions lapse** when either of you drops below 30% HP.
- **Her voice** only changes her stance when you are the one talking.
- **R reset** also brings you back to full HP and stamina.

The server must be updated to v0.1.50 too, as it refuses any other version.

## v0.1.49

Companion voice. Server.

- **She talks about what is happening**: her voice knows her stance, what
  she is doing and what just happened.
- **Characters**: each companion's personality is a paragraph, written per
  companion (Pip and Wren first).
- **Fewer repeats**: she remembers her last 20 lines across sessions and
  does not say them again; her lines are livelier.
- **When you are in real danger** (below 30% HP) your last instruction
  lapses, she decides afresh, and if she changes course she tells you why.

The server must be updated to v0.1.49 too, as it refuses any other version.

## v0.1.48

Companions: hands and voice. Server and client.

- **She acts at once**: a scripted tactical layer runs her every tick from
  a stance (stay close, hold, press, guard, pull back); her mind only
  picks the stance when the fight changes, in a few hundred ms.
- **She speaks for herself, separately**: when you talk to her, someone
  dies, someone's HP crosses a threshold, or after a fight goes quiet.
  When you tell her something, her answer can change her stance.
- **Retreating means getting out of danger**: she steps clear of the
  monsters, near you if she can, and fights back when cornered.
- **She heals** out of combat, a point a second; a reset heals her fully.
- **No parroting**: quick phrases reach her as what you mean, and she never
  says your words or her own last lines back.
- She is told who she is and who you are, by name.
- The test runner fails a scene that hangs instead of waiting forever.

The server must be updated to v0.1.48 too, as it refuses any other version.

## v0.1.47

Companions keep their heads in a fight; speech bubbles. Server and client.

- **Speech bubbles** for everyone: a small dark bubble over the speaker,
  wrapped, readable through walls, scaled with the zoom; a new line
  replaces the speaker's last, and two speakers' bubbles move apart.
- **No dithering mid-fight**: in a fight your companion is only asked
  again when the fight changes (a new monster next to either of you, an
  HP threshold, her target dead), and never leaves a live target in reach
  for a routine rethink.
- **She does what you ask**: an instruction (typed or a quick phrase)
  stands for a minute or until you say another, and she goes against it
  only to save a life, saying why.
- **She talks less**: only when spoken to, at a death, or when someone's
  HP crosses a threshold, and she does not repeat herself.
- **Reflex**: badly hurt with a monster next to her, she always retreats.
- Her mind now gets the situation in plain sentences first.

The server must be updated to v0.1.47 too, as it refuses any other version.

## v0.1.46

Quick phrases; companions are companions. Server and client.

- **Keys 1-4 say quick phrases** instead of giving orders: "With me!",
  "Stay back!", "Get them!", "Fall back!". They go exactly as typed chat
  does: over your head, to every player, into the party log, and to your
  companion as something you said. Edit them in settings.cfg
  (`phrase1=` ... `phrase4=`). The HUD shows them.
- **Typed chat** now shows over the speaker's head too.
- **The old orders are gone**: what your companion does about what you
  say is up to her.
- **No more "owner"**: her mind is told your name and that you travel
  together by choice; the console lists companions as "Wren, with Jeff".

The server must be updated to v0.1.46 too, as it refuses any other version.

## v0.1.45

Companion mind follow-ups. Server.

- **Fewer second thoughts in a fight**: a blow on her or her owner asks
  her mind again at most once per 30 ticks, and only if the fight changed
  (a new monster next to either of you, either's hp crossing 50% or 30%,
  her target gone). Otherwise her decision holds.
- **A shorter, sharper context**: only objects within 2 cells, monsters
  within 4 or coming for her or her owner, six entries at most, nearest
  first; repeated log lines collapse ("Brute hit Player for 1 ×6.").
- **The mind log rotates** at 5 MB, keeping one older file.

The server must be updated to v0.1.45 too, as it refuses any other version.

## v0.1.44

Companion mind, talking, speech history, housekeeping. Server and client.

- **Talk to your companion**: Enter opens a line (Esc cancels). It goes to
  every player as chat and to the party log, and your companion answers
  and decides on it at once. At most 200 characters, one line per 2 s.
- **Tab** shows the last 20 things said this session: speech, last words
  and chat, with who and when.
- **Every speech line** goes to the server log and the party log; a
  companion's last words are always said.
- **Companion decisions hold**: a language-model mind's choice stands until
  its next, instead of the scripted mind's answer cutting in between.
- **Reflexes**: below 30% hp with a monster next to her, a companion only
  retreats, steps aside or holds, whatever her mind says.
- **She knows about the fight**: the hp of everyone near her and the
  recent blows on her and her owner are in what her mind is told, and the
  reason she is asked (it was always blank before). Players are named as
  the party log names them.
- **Mind log**: every decision, with the full prompt and raw reply, one
  JSON line each, to /var/lib/psykinetic/mind.log on the server
  (`--mind-log=`; `--mind-why` asks for a reason too). Console: `mind log
  on|off`, `mind last <name>`.
- **Sounds** now come from art/audio/sfx/, files named for what they do;
  the audio packs are no longer in the repo or the client.
- `tools/ship.ps1` stops and lists untracked files unless given
  `-IncludeUntracked`.

The server must be updated to v0.1.44 too, as it refuses any other version.

## v0.1.43

Mouse wheel zoom. Client (the server only for the version).

- The mouse wheel zooms the 3D camera in small eased steps, between 0.8×
  and 1.4× of the usual size, centred on your character, in both schemes.
  It stays where you leave it and is saved.
- A middle click (no drag) puts the zoom back to 1×.
- Nothing else about the camera changes.

The server must be updated to v0.1.43 too, as it refuses any other version.

## v0.1.42

Camera: free turn, lock on a diamond. Client (the server only for the version).

- **A/D** (click scheme) turn the 3D camera freely, all the way round.
  Let go and it locks on the next diagonal view the way you were turning,
  or goes back if you turned less than 10°, and stays there. That view is
  saved again.
- **WASD scheme:** the sideways middle drag does the same.
- **W/S** tilt while held and spring back to 50°. No zoom; Q/E do nothing.
- The camera no longer turns by itself to follow your character.

The server must be updated to v0.1.42 too, as it refuses any other version.

## v0.1.41

The camera follows the character. Client (the server only for the version).

- **Click scheme:** the 3D camera turns by itself to the diagonal view
  that puts the way you are walking toward the top of the screen. It
  waits until you have kept a new heading for 0.7 s, turns over a second,
  never turns while you stand still, and never twice within 1.5 s.
- **A/D** look round up to a quarter turn either way and spring back when
  let go. **W/S** tilt and spring back, as before.
- Your character is always the middle of the screen.
- The camera's view is no longer saved.
- **WASD scheme:** the middle-drag turn is no longer limited to a quarter
  turn; otherwise unchanged.

The server must be updated to v0.1.41 too, as it refuses any other version.

## v0.1.40

Camera simplification. Client (the server only for the version).

- **A/D** (click scheme) turn the 3D camera up to a quarter turn either
  side of its home view and settle on one of the three diagonal views in
  that range. The WASD scheme's middle drag is held to the same range.
- **W/S** (click scheme) tilt while held and spring back to 50° when let go.
- **Zoom is gone**; Q/E and the middle click do nothing in the click scheme.
- A saved view outside the range comes back as the nearest one in it; the
  old saved tilt and zoom are dropped.

The server must be updated to v0.1.40 too, as it refuses any other version.

## v0.1.39

Click scheme camera keys swapped. Client (the server only for the version).

- **W/S** tilt the 3D camera (W toward top-down, S toward level).
- **Q/E** zoom (Q out, E in).
- Everything else is as it was.

The server must be updated to v0.1.39 too, as it refuses any other version.

## v0.1.38

Combat readability (3D view). Server and client.

- **HP bars** over creatures, longer for more max hp, green, amber below
  half, red below a quarter. They show while a creature is hurt or has
  been fighting in the last 4 s, and fade out otherwise; hold Alt to see
  them all. `hp_bars=0` in `settings.cfg` turns them off.
- **Deaths**: the body tips onto its side with a little bounce, flashes,
  drops its lantern, lies for 8 s and sinks into the floor. Corpses never
  block anything. A companion says a last line. When you die the camera
  pulls back and the colour drains until you are back.
- **Sounds**, placed where they happen: swings, blows, impacts against
  walls, wood and bodies, crates breaking, deaths, doors, and quiet
  footsteps, all from Kenney's CC0 Impact Sounds and RPG Audio packs.
  `master_volume=` and `sfx_volume=` (0 to 1) in `settings.cfg`.
- Lines you add to `settings.cfg` by hand are kept when the game rewrites it.

The server must be updated to v0.1.38 too, as it refuses any other version.

## v0.1.37

Click scheme camera keys, remapped. Client (the server only for the version).

- **W/S** zoom in and out on your character while held (1.5× a second),
  between 0.6× and 2×, slowing into either end. The zoom stays where you
  leave it and is saved.
- **Q/E** tilt the camera while held (E up toward top-down, Q down),
  between 40° and 85°, sticky and saved. Tilting no longer zooms out on
  its own.
- **A/D** turn as before.
- **A middle click** resets both tilt and zoom over 250 ms.
- The Q/E 90° step and "look left/right" are gone.
- The WASD scheme is unchanged.

The server must be updated to v0.1.37 too, as it refuses any other version.

## v0.1.36

Q/E relative to the character. Client (the server only for the version).

- In the click scheme Q now means "look to my left" and E "look to my
  right", left and right of where your character is heading (the way it
  is walking, or last moved). The camera steps 90° to the diagonal view
  that brings that side toward the top of the screen, so at a corner the
  passage on that side comes into view, whatever view you started from.
- A/D still turn the camera in the screen's sense, for free sweeping.

The server must be updated to v0.1.36 too, as it refuses any other version.

## v0.1.35

A/D feel; Q/E back. Client (the server only for the version).

- **Q/E** step 90° to the next diagonal view again in the click scheme
  (400 ms), alongside A/D.
- **A/D** turn at 180° a second while held.
- **Letting go of A/D** carries on to the next diagonal view the way you
  were turning if you went more than 10° past the last one, and goes back
  otherwise. The settle starts at the speed you were turning and slows to
  a stop, so the camera never halts and starts again on release.
- The WASD scheme is unchanged; its up/down middle drag still springs back.

The server must be updated to v0.1.35 too, as it refuses any other version.

## v0.1.34

Click scheme camera on WASD. Client (the server only for the version).

- **W/S** tilt the 3D camera while held, between 40° and 85° (near
  top-down), slowing into either end. It stays where you leave it and is
  saved; the camera pulls back a little as it tilts up.
- **A/D** turn the camera while held; let go and it eases onto the
  nearest diagonal view over 250 ms (the saved view is always one of
  those).
- **A middle click** levels the tilt back to 50°.
- Q/E and middle-button drags do nothing in the click scheme now.
- The WASD scheme is unchanged.

The server must be updated to v0.1.34 too, as it refuses any other version.

## v0.1.33

Pitch peek. Client (the server only for the version).

- Hold the middle button and drag up or down to tilt the 3D camera from
  its usual 50° toward top-down (85°), further the further you drag (all
  of it over 300 px), while it pulls back a little to show more round you.
  Let go and it springs back over 250 ms. The camera's turn never changes.
- The click scheme's sideways middle-drag peek is gone; Q/E still turn.
- In the WASD scheme a middle drag turns the camera if it first moves
  sideways and tilts it if it first moves up or down.
- Near walls stay see-through while tilted. F3 shows the pitch.

The server must be updated to v0.1.33 too, as it refuses any other version.

## v0.1.32

Peek in the click scheme. Client (the server only for the version).

- Hold the middle button and drag sideways to turn the 3D camera up to
  45° either way from the view it rests on; let go and it springs back to
  that view over 200 ms. The saved view never changes. Q/E still step
  between views, even mid-peek.
- The WASD scheme is unchanged.

The server must be updated to v0.1.32 too, as it refuses any other version.

## v0.1.31

The 3D camera rests only on diagonal views. Client (the server only for
the version).

- The four resting yaws are the diamond views: the default and each 90°
  from it.
- Q/E step 90° from one to the next in one smooth 400 ms ease, through
  the axis-aligned view without stopping there.
- In the WASD scheme a middle drag still turns freely while held, and on
  release settles on the nearest diamond.
- The saved yaw is always a diamond; an axis yaw saved by an older build
  is read as the nearest diamond.

The server must be updated to v0.1.31 too, as it refuses any other version.

## v0.1.30

Deploys. Tooling only; no game change.

- `deploy.sh` removes untracked `.uid` and `.import` files before it
  pulls, and runs the headless import after the pull, never before. The
  v0.1.29 deploy stopped on a `.uid` the box had generated itself.
- `ship.ps1` cleans the same way before its own pull on the box, and
  before committing imports headless and refuses a script that has no
  `.uid`, so each `.uid` goes in with its script.

The server must be updated to v0.1.30 too, as it refuses any other version.

## v0.1.29

Control schemes as complete packages. Client (the server only for the
version).

- **Click is the default again** (`controls=click`, or no line): click
  and hold-to-move, Q/E turn the 3D camera a step, the verbs land on what
  you click. WASD and the middle button do nothing, and the camera just
  follows you, with no lean toward the cursor.
- **WASD** (`controls=wasd`): WASD walks relative to the camera, the mouse
  aims, a middle-button drag turns the 3D camera freely and settles on the
  nearest 45° step when you let go (eased over 250 ms). Q/E do nothing.
- **The camera never turns under a held movement key**: a drag made while
  you walk applies when you let go of the keys.
- **The WASD lean** now comes from where the cursor is on the screen: past
  a dead zone of 15% round the middle it leans up to 3 cells toward that
  side, settling in about 300 ms. The camera moving cannot change it.
- **The hover and the click always agree**: the cell under the cursor is
  picked once a frame after the camera has moved, and a click goes to the
  cell the square showed.
- The HUD shows only the active scheme's controls.

The server must be updated to v0.1.29 too, as it refuses any other version.

## v0.1.28

Controls pass. Server and client.

- **Two control schemes.** `controls=wasd` (the default) or
  `controls=click` in `settings.cfg`; `--controls=` overrides it for a run.
- **WASD** walks relative to the camera (W is up the screen at the current
  yaw), eight directions from key combinations; letting go stops on the
  cell being entered. Clicking a far cell walks there until a key is
  pressed.
- **The mouse aims** in WASD: standing still you face the cursor; a left
  click attacks whoever is next to you that way, or swings at air; a
  right click grabs whoever is next to you that way, and a drag tosses. A
  click on a sprite still goes to that sprite.
- **Continuous motion.** The player walks at 4 cells a second, steadily,
  with no pause at cell boundaries; monsters and companions are drawn the
  same way. A refused step eases to a stop. Facing turns smoothly (about
  100 ms) toward where you are going, or toward the cursor.
- **The camera leads toward the cursor**, up to 3 cells, and settles back
  on you when the cursor comes back near you. The middle-button peek and
  nudge are gone: Q/E is the only camera rotation.
- **Bumping your companion** makes her step aside at once (YIELD), or say
  there is no room; it goes in the party log. A language-model mind gets
  one decision window to do it before the scripted answer applies.
  Clicking her walks into her rather than attacking her.
- **3D:** the hover is a square cell outline; the toss aim is an arrow on
  the floor; speech shows for 4 seconds from the speech message itself;
  lanterns are warm white; creatures have a nose that shows their facing
  and lunge when they swing.
- **Mispredicts fixed.** A move order sent while a step was showing could
  reach the server before it had taken that step, and the server would set
  off from the tile before and go another way. Steering with the button
  held did this constantly in 3D, where the following camera gives a new
  target every few frames. Orders now carry the steps already shown and
  the server walks those first: a steered walk with 50-200 ms of delay
  went from about two mispredictions in ten seconds to none, and a WASD
  walk round a corner shows none at 0, 120 and 200 ms.
- A companion no longer steps aside onto fire.

The server must be updated to v0.1.28 too, as it refuses any other version.

## v0.1.27

The 3D view is the default. Client.

- A client now starts in the 3D view. `--renderer=2d`, or a line
  `renderer=2d` in `settings.cfg`, picks the 2D view; anything else, or
  nothing, is 3D.
- `renderer=` in `settings.cfg` is now honoured (it was ignored, and wiped
  when the file was rewritten on a resize). The command line overrides it
  for that run without changing the file.

The server must be updated to v0.1.27 too, as it refuses any other version.

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
