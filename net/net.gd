extends Node
## Launch mode and ENet setup (autoload "Net").
##
##   --host                       listen server: runs the sim, has a local player (default)
##   --server                     dedicated: runs the sim, no local player, fine with --headless
##   --client --address=<ip>      connects to a server; runs no sim
##   --port=<n>                   default 7777
##   --bind=<ip>                  server/host: listen on this address only (game and status ports;
##                                default every address); tests' servers take 127.0.0.1, which
##                                Windows' firewall doesn't ask about
##   --token=<string>             server: required; a peer must send it (Net.authenticate)
##                                within 5 s or it is disconnected. host: optional; without
##                                it anyone may join (local play). client: sent on connect
##   --state=<path>               server/host: JSON snapshot of entity state, written every
##                                30 ticks and on clean shutdown, loaded on start if present
##   --admin-port=<n>             server/host: accept console commands on 127.0.0.1:<n> (TCP)
##   --status-port=<n>            server: answer status queries on UDP <n> (decision 431; the box's unit gives the game port + 2,
##                                which is where clients ask; none without it, so tests' servers never take a neighbour's port)
##   --max-players=<n>            server/host: players at once (default 16)
##   --no-interest                server/host: send every client everything in its zone, not only
##                                what is near its player (decision 217)
##   --console                    read console commands from stdin (--server does this anyway)
##   --no-companions              server/host: players get no companion
##   --no-player-reset            server/host: R from a client does not rebuild the room
##   --map=<name>                 server/host: new players start in zone levels/<name> (default test_room)
##   --day-minutes=<m>            server/host: a day on the world clock takes this many real minutes
##                                (default 90, or as last saved); see DayNight
##   --hour=<h>                   server/host: start at this hour of the day, 0..24 (clips, tests)
##   --season=<name>              server/host: start in the middle of this season (spring, summer,
##                                autumn, winter); see Season
##   --season-days=<n>            server/host: a season lasts this many days (default 7, or as saved)
##   --weather=<kind>             server/host: start in this weather everywhere, already in (clips;
##                                as the console's `weather <kind>`, for 10 hours); see Weather
##   --edit=<name>                the level editor on levels/<name>/layout.png (made if there is none;
##   --edit-size=<w>x<h>          a new one this many cells, default 32x24); no game, no network
##   --world-map                  the world map editor: every level and its links as a node map
##   --mind-log=<path>            server/host: write the companion minds' decisions here, a JSON line
##                                each (a dedicated server: /var/lib/psykinetic/mind.log when it can)
##   --transcripts=<dir>          server/host: keep what is said to and by each companion here, a
##                                text file each a day (a dedicated server:
##                                /var/lib/psykinetic/transcripts when it can); see Transcript
##   --voice-url=<url>            her voice on this endpoint instead (stances and the check stay on
##   --voice-model=<m>            --llm-url); and this model (or PSYKINETIC_VOICE_URL / _MODEL)
##   --builders=<id,id>           server/host: these player ids may use builder mode (B) besides a
##                                host's own player (or PSYKINETIC_BUILDERS); it asks Claude with
##                                ANTHROPIC_API_KEY from the environment, never from a client
##   --builder-stub               builder mode answers from a script, no key (tests, trying the UI)
##   --builder-model=<m>          and --builder-effort=<e>, --builder-max-cost=<dollars a request>
##   --mind-why                   ask the minds for a short "why" with each answer, for the log
##                                (or PSYKINETIC_MIND_WHY=1)
##   --perception=list|grid|both  what the minds are told she sees around her: a list of the
##                                nearest things with where each is (default), a map of the
##                                cells around her, or the map then the list (or
##                                PSYKINETIC_PERCEPTION); see Companion.perception
##   --llm-model=<m>              companion minds ask this model...
##   --llm-url=<url>              ...at this endpoint (default: local Ollama /api/chat;
##                                a URL ending /chat/completions is spoken to OpenAI-style)
##   --settings=<path>            client settings file to use instead of the one next to the exe
##   --renderer=2d|3d             client view: the 3D one (client3d/, default) or the 2D isometric one;
##                                overrides the settings file's renderer=
##   --controls=click|wasd        click to move (default), or WASD to walk and the mouse to aim;
##                                overrides the settings file's controls=
##   --player-id=<id> --name=<s>  client: identity to present instead of the settings file's
##
## With no mode argument: an exported build reads settings.cfg (address=,
## port=, token=, player_id=, name=) next to the exe and joins as a client,
## or asks for those once if the file is missing; a run from the project is
## a host. display_delay_ms= (default 150) sets how far in the past other
## entities are drawn; it is only ever written by hand. player_id is a UUID made on first run; the server remembers each
## player by it. A host run from the project uses a fixed dev id.
## window_width=, window_height= and window_mode= (windowed, fullscreen)
## are the window as it was last left; F11 toggles fullscreen. camera_yaw=
## is the 3D view's diamond as last left, camera_zoom= its wheel zoom. renderer=2d picks the 2D view;
## anything else, or no line, is the 3D one. It is read whatever the mode,
## and kept as written when the file is rewritten. controls=wasd is WASD
## with the mouse aiming; anything else, or no line, is click-to-move;
## read and kept the same way. hp_bars=0 turns the 3D view's HP bars off;
## master_volume=, sfx_volume=, voice_volume=, ambience_volume=, ui_volume=
## and music_volume= (0..1, default 1) set the sound (the options panel, O,
## writes them back). ui_scale= (0.5..2, default 1) sizes the whole interface,
## text_scale= the text alone, colours=normal|distinct picks the meaning
## colours' set (decision 453; the Options write them back). key_<action>=<key>
## rebinds an action (Keys.DEFAULTS; the Controls section writes them back).
## antialias=off|fxaa|smaa|msaa4 (default smaa) smooths
## the 3D view's edges (the options panel's Video section writes it back).
## camera=low is the low-horizon camera trial (decision 623: outdoors a
## perspective view 22 degrees up, seeing the sky); anything else, or no
## line, the ortho view (the Video section writes it back).
## phrase1= ... phrase4= are the quick phrases keys 1-4 say (written back,
## the defaults where there is none). Any line
## the game does not write itself (these, and keys it does not know) is
## kept as written when it rewrites the file.
##
## The game version comes from version.txt at the project root. A client
## sends it with its token and protocol; a server rejects another protocol
## (decision 239).
##
## Test hooks (used by tests/net_test):
##   --test-move=<dx>,<dy>        once the local player exists, order it to move by this offset
##   --test-contest=<x>,<y>,<tick> at that server tick, order the local player to tile (x, y)
##   --test-reset=<tick>          at that server tick, ask for a room reset as the R key does
##   --test-exit-after=<seconds>  quit after this long
##   --test-exit-on=<path>        quit once that file exists (a client in the game sees 20 more ticks first)
##   --test-wait-players=<n>      server: the sim waits until n players are in (60 s at most)
##   --test-hold=<tick>,<n>       server: the sim waits at that tick until n peers have ordered (20 s at most)
##   --test-herds=<n>             server: n herds of wild animals in each outdoor zone built (perf's benches; Main._test_herds)
##   --screenshot=<path>          save the window as PNG when --test-exit-after quits
##   --test-minimap               open the big map at the start (for screenshots)
##   --menu                       start at the main menu, as an exported client does (for screenshots)
##   --test-ui-cost               print the interface's per-frame cost at exit (UiCost; ui's measure)
##   --test-show=<a,b>            open these on the HUD once the player is in (for the ui tree's screenshots):
##                                hints, options, pack, talk, chat, debug, say (a speech bubble), shop (the nearest counter's),
##                                game_menu, menu, setup (the connect screen's fields), connect, failed (its states), over the game;
##                                tip (a sample named dagger's tip over the pack: nothing in play is named yet),
##                                hint (the cursor's hint on the nearest crate or chest, as if the cursor were on it),
##                                converse (the conversation panel on the nearest town's person, sample offers),
##                                credits (the Options with its Credits list open), counter (the counter screen, sample work),
##                                world (the world map), controls (the Options scrolled to its key rows, one waiting for a key)
##   --raids                      raid groups on from the start (decision 328; else the console's raids on)
##   --regenerate                 the shifting levels laid again on this server (decision 542; else the console's regenerate on)
##   --test-hover=<x>,<y>         keep the cursor over that cell (for screenshots)
##   --test-click=<seconds>       after this long, left-click where the cursor is
##   --test-fullscreen=<seconds>  after this long, toggle fullscreen as F11 does
##   --test-azimuth=<degrees>     start with the view turned by this (for screenshots)
##   --test-yaw=<degrees>         3D: start with the camera yawed by this (for screenshots)
##   --test-door=<tick>           at that server tick, open or close the door the local player stands beside
##   --test-chest=take|put        walk to the nearest chest and drag its first item into the player's slots (take),
##                                or the player's first item into it (put)
##   --print-protocol             print this build's version and protocol (PROTOCOL v<x.y.z> <id>) and quit
##   --test-version=<x.y.z>       client: claim this version instead of the real one
##   --test-protocol=<s>          client: claim this build fingerprint instead of the real one
##   --test-lag=<seconds>         client: hold every order this long before sending it
##   --test-steer=<seconds>       hold-to-move with a cursor that swings a quarter turn this often
##   --test-fight=<seconds>       strike at the nearest monster this often (closing in on it), between steering
##   --test-chase=<seconds>       hold-to-move on the nearest animal as drawn (a deer first) for this long, as a
##                                cursor kept on a fleeing deer does (tools/net_chase.sh)
##   --test-walk=<keys:secs,...>  WASD: hold these keys (e.g. w:1.5,wd:1) in turn, then let go
##   --test-smooth                count jumps and back steps in what is drawn, frame by frame (60 fps), and report
##                                them at exit (net/smooth_meter.gd; tools/net_smooth.sh)
##
## Options are read from both the engine argument list and the user arguments
## after "--". Use the --name=value form: a bare value before "--" would be
## taken by Godot as a scene path.

enum Mode { HOST, SERVER, CLIENT }

const DEFAULT_PORT := 7777
## ENet connections, including ones still waiting to authenticate.
const MAX_CLIENTS := 8
## Authenticated peers at once by default; later ones are refused.
const MAX_PLAYERS := 16
## Seconds a connected peer has to send the token.
const AUTH_TIMEOUT := 5.0
## Seconds between telling a peer why it is rejected and disconnecting it.
const REJECT_GRACE := 0.25

## Server: a peer is gone, once per peer, before anything else is sent.
signal peer_left(peer: int)
## The Options' low-horizon camera toggle (decision 623) changed: the 3D
## view applies it at once.
signal camera_low_changed(low: bool)
## A peer has sent a good hello and may be given a player. Main spawns
## players on this, never on peer_connected.
signal peer_authenticated(peer: int, player_id: String, player_name: String)
## Client: the server turned this peer away and said why, just before
## disconnecting it.
signal join_rejected(reason: String, server_version: String)

## A server's status asked with query_status (decision 431), once a query:
## {ok: true, version, protocol, players, accepting, compatible (the same
## protocol, or a newer server this client could update to)}, or {ok:
## false, why} ("no answer" within 2 s).
signal status_received(address: String, port: int, result: Dictionary)

## What decides whether a client may join is protocol(), not the build
## (decision 239): a client and a server of different builds play together
## as long as what goes over the wire is the same. protocol() sees by itself:
## the RPC methods of RPC_SCRIPTS and their arguments' names; the properties
## entities, doors and ground piles replicate (GridEntity.REPLICATED,
## Door.REPLICATED, GroundPile.REPLICATED, SUBCLASS_REPLICATED); the message
## kinds (MESSAGE_KINDS); the spawn spec format (EntityFactory.SPEC_VERSION).
## Bump PROTOCOL_REVISION for a wire change it cannot see: a message's or an
## RPC's fields or their meaning, a replicated value's meaning or units, a
## spawn spec key, the order of anything sent. Not for a new spawn spec key
## or message field that older peers ignore and whose absence means today's
## behaviour (an "art" key, drawn as today's shape without it); one whose
## presence or absence changes play needs it. tests/protocol_test checks
## that every message kind, RPC script and replicated property is listed
## here. 7: a carrier's slots are 6, the pack and two hands (decision 247).
## 8: crates and carts are Cargo, their slots replicated (decision 259).
## 9: the "sky" message, the world clock; the sim's light outdoors follows
## the hour on every peer (decisions 290, 291).
## 10: a monster's alert can be FLEEING (decision 282).
## 11: the "sky" message carries the weather's overrides and climates, and
## the sim's sight, hearing and light follow the weather (decisions 307, 308).
## 12: the "sky" message carries the year (season_days, year_phase,
## year_anchor), and the sun's path, the sim's daylight and the weather's
## snow follow the season (decision 362).
## 13: "winding" is any body's, not only a monster's (moved to GridEntity),
## and its 0 ticks means a wind-up given up (decision 392).
## 14: the "counter" command (look, order, collect) rides the command RPC,
## answered by the "counter" message (decision 438).
## 15: the "offers" and "offer" verbs on the command RPC (a resident's
## offers asked for and one accepted) and the "offers" message (decision 435).
## 16: monsters and animals replicate raised and raised_tick, as players do
## (decision 455): their synchronizer's layout, unseen by the names above.
## 17: the "town" message's field entry carries the crop's look ("crop":
## sown, growing, ripe, flattened or "", decision 457).
## 18: the "map" message carries "generation", the regenerating level's
## generation the client is sent (decision 465).
## 19: a level carries fords (the "ford" legend kind, walked as floor at
## half pace) and bridges (building slot "bridge", floor over water), in the
## "terrain" message's files and the levels served (decision 505).
## 20: a level carries tall grass (the "tall_grass" legend kind, grass that
## hides, slows and is trampled), and the "grass" message tells a zone's
## trampled cells (decision 508).
## 21: a level carries slopes and rocks (the "slope" and "rock" legend
## kinds: a ramp walked as a stair, a cell walled round) in the "terrain"
## message's files and the levels served (decision 513); the "world"
## message's trade caravans carry "days", the days still to go (504 amended).
## 22: a level may carry relief.png, its ground's elevation in metres (in
## the "terrain" message's files and the levels served), and steps are
## walked by slope, uphill slower, sight over relief in metres (decision 525).
## 23: the "offers" message carries "standing" {id, title}, the offer standing
## for that player, absent if none (decision 536).
## 24: a blessed body at 0 HP is downed until downed_until, not gone; a
## channeler carries channel_of and channel_until (decision 544).
## 25: a draugr spawns from sim/draugr.gd (Draugr), and the "offers"
## message's "standing" may name a monster that talks, not only a resident
## (decision 548, and npc's side of it).
## 26: a building kind may be SOLID (building.mound): its footprint is no
## floor but its door, carried as terrain "solid" in the "terrain"
## message's files and the levels served (decision 550).
## 27: the "speech" message carries "aside", one clause of how a resident
## said the words, "" when none (336 amended).
## 28: a player carries led_by, the name of the companion leading them,
## "" when none, and led_to, where she leads them (a place id or an area);
## while led the server walks their body (decision 551 and amended); a
## companion carries bond_step, her bond's step word, and bond_why, its
## newest reason as her player reads it (decision 555).
## 29: a level may carry "waters" and "roads", curves its water and road
## cells are rasterised from on load (Curves) and the views draw from, in
## the "terrain" message's files and the levels served (decision 559).
## 29 (566, economy's side): the "town" message's buildings carry
## "progress" (0..1) while a job builds, raises or repairs one and
## "walls" (Towns.walls_up), and the message carries "awake" {map building
## code: bool}.
## 29 (562, items' side): a body's buffs may carry "speed", a share its
## steps are quicker by, which World.step_ticks reads on both sides.
## 29 (566, maps' side): a town building's wall edges stand only once its
## "walls" are up; below that its outline is open, on the server and in a
## client's prediction alike (World._open_walls).
## 29 (567): a level may carry the landmark slots (building.great_tree,
## .cairn, .standing_stone, .waystone), solid with no door, and a building's
## "variant" and "yaw", in the "terrain" message's files and the levels
## served.
## 29 (562, economy's side): the "barter" message and the "barter"/"trade"
## commands carry "resident", a maker's path, in place of "shop" for a
## barter with that maker.
## 29 (505 amended): a level's terrain "relief" keeps the water under a
## bridge, its deck's height apart in terrain "decks"; Level.walk_relief
## lays the decks back for walking, on the server and in a client alike.
## 30: a player carries charges, the resurrection charges they hold, and
## charge_room, the most they may hold (decision 573).
## 30 (566 amended, npc's side): a level may carry the work props
## (building.chopping_block, building.woodpile), solid with no door, that a
## woodcutter stands beside, in the "terrain" message's files and the levels
## served.
## 30 (576): the "world" message carries "capabilities" {companion, held:
## [{id, words, teacher}]}, what the player's companion has learned; a level
## link sealed by a mark opens for the companion's mark too (Main.party_has).
## 31 (577): the "world" message carries "focus" {companion, fight, magic,
## stealth}, the player's companion's focus in whole numbers.
## 31 (579, maps' side): building.mound is 12 x 12 (was 5 x 5): what is solid
## round it, and its door, differ on both sides.
## 31 (593): the "swing" command may carry "at" (a ground point) in place of
## "dir", and strikes whoever stands that way; new commands "signature"
## {at} and "apply_item" {slot, target}; "stance" may carry "at".
## 31 (597): every entity replicates "winded"; a winded body's steps take
## World.winded_move_scale times the ticks (levels/combat.json).
## 31 (606): GridEntity's _net_hurled RPC (World.hurl, a thing thrown down a
## line): its Items id and the cell it came down on, for the views' flight.
## 31 (602): the "telegraph" message, to a zone: {id, source, kind, shape,
## cells, from_tick, lands_tick, zone} shown, {id, landed} over.
## 32 (611): new command "make_way" {target}: your own companion beside you steps aside.
## 32 (585): level.json "ledges", terrain["ledges"] (each {curve: {points,
## tangents, tops, feet, length}, up, closed}) the views draw faces along;
## the hills' and the wilds' faces wander, so their relief differs.
## 32 (586): the "barter" message gains "fence" ("" | "day" | "night"): the
## counter's fence state, Snagfin's by day or by night (World.fence_state).
## 32 (587, economy's side): the "return" message gains "near_death" (a
## player back at once) and {all_fallen: seconds} (0 calls the wait off).
## 32 (584 amended): the "barter" message from a medicine man carries
## "care" {gold, herbs, antlers, in_care, by}; new command "retain"
## {resident, pay: "gold" | "herbs" | "antlers"}.
## 32 (591, economy's side): the "town" message gains "stage" (hamlet,
## village, town, city).
## 32 (594): place kinds "fishing" and "fort" (Level.PLACE_KINDS); a counter
## in a fort place naming its town is that town's shop.
## 32 (587, companions' side): a player carries heart, its beats a minute while
## downed (0 up); the "slow_heart" {held} and "bleed_out" commands; every
## player at 0 hp lies downed (the unblessed their last moments); a revive
## starts only when it is calm.
## 32 (601 amended): GroundPile replicates "gold" (whole gold lying on the
## cell, a count, never a thing; a pile may hold gold alone); the coin_purse
## item is gone from the catalog.
## 32 (583, items' side): the "loose" command carries "angle" (radians on
## the grid; "at" still read as a fallback); GridEntity._net_shot carries
## the point an arrow stopped at (Vector2, cell units) and what stopped it
## (&"body", &"wood", &"stone", &"ground"); a bow's verb has steps and
## damage_at; walking drawn keeps the draw at half pace.
## 32 (599, items' side): a "search" command {target: a cache chest's
## path}; a Chest carries cache and cache_place (from its props).
## 32 (488 amended, two kinds): a level may carry the "forge" and "butchery"
## kinds, and a kind's "open" outline edges, no wall and no door, which both
## sides read from the kinds file as walkable.
## 32 (591, buildings' side): a level may carry the "market" kind, open all
## round, and the set piece's "tower_room"; each kind's "stage" and "plot",
## read alike on both sides.
## 32 (589): terrain["link_cues"] [{tile, cue, facing, variant}] the views
## place a piece by, and each level link's "cue" (the big map's mark).
## 32 (591): message "clearing" {zone, whole?, cells: [[x, y, stage]]} (a
## felled cell's stage, "trunk" grown back), sent before "map" whole, and
## terrain["clearing"] (cell -> stage) the views draw.
## 33 (614): new command "give_gold" {to: a player's or your companion's path,
## amount} or {from: your companion's path, amount}: gold from purse to purse.
## 33 (614, companions' side): the world message carries "companion_gold"
## {companion, gold}: what is in her purse, for her keeper's card.
## 33 (562 amended (4)): a Resident replicates trade and person (SUBCLASS_REPLICATED),
## so a joined client's talk bar and card know who they are.
## 33 (584 amended (2)): the "barter" message's "care" gains "given" {herbs, antlers},
## the player's tally toward that hut; "retain" with herbs or antlers takes what is held.
## 33 (619): slot stacks: replicated slot_counts on Player, Companion, Chest and
## Cargo (empty while no slot holds more than one); "transfer" and "drop" take
## an optional "count"; the barter message's pack entries carry "uids" and "count".
## 34 (620): a bow's verb has spread, spread_floor and spread_settle (the
## cone of flight, Items.spread_at), read alike by a client's cone and the
## server's roll; the arrow flies a line rolled in it, not the aim.
## 34 (622): a seventh carried slot, the armour worn (Items.ARMOUR = 6, CARRIED 7):
## Player's and Companion's slots replicate seven; Player.worn and Companion.worn
## (SUBCLASS_REPLICATED), the armour's id.
## 35 (580 step 3, dungeon's side): building.burial_table, building.crypt_pillar,
## building.round_table and building.broken_table are solid (Level.SOLID): a client
## without them would walk through their cells.
## 35 (613 amended, dungeon's side): building.dwarven_forge and building.weapon_rack
## are solid and doorless (Level.SOLID, DOORLESS): both sides take their footprints
## out of the floor.
## 35 (624, economy's side): new command "town_sheet" {town}, answered by the
## new "town_sheet" message (Main.town_sheet's keys, or {town, why}).
## 35 (640, economy's side): the "folds" message {counts: {place id: sheep}}, a
## herder's fold's sheep at home, to the zone on a change and to a peer arriving.
## 35 (622, step 2): a drawn bow's step and draw time read the armour worn
## (range_steps caps the step, draw scales the ticks), alike on client and server.
## 35 (642): buffs may hold "steady", which narrows the cone (World.spread_of)
## on client and server alike.
## 35 (626): a player and a companion replicate tending (SUBCLASS_REPLICATED):
## the name of the body it is bandaging, "" when not, for the views' kneel and ruffle.
## 35 (591 amended): the "clearing" message gains "plots" [{town, kind, use,
## rect: [x, y, w, h], facing: [dx, dy], size}] (a town's laid plots), and
## terrain["plots"] the views raise each kind on.
## 35 (621 amended): Companion.asleep (SUBCLASS_REPLICATED), true while she
## sleeps on her player's watch (Intent.SLEEP); her body lies down by it.
## 35 (629): the "greet" command takes a talking monster's path, the "offer"
## command routes his deal id to him, and the "offers" request answers for him
## (his deals in the existing "offers" message); no new kind, key or RPC.
## 35 (648, npc's side): Monster.peaceable (SUBCLASS_REPLICATED), true while a
## talking monster sits unprovoked (the draugr sets it); a client's click or E
## talks to him then and strikes otherwise.
## 35 (649, maps' side): the "clearing" message gains "gone" [plots, as
## "plots" carries them, without size]: a town's plots dropped, their
## buildings and edges taken off.
## 35 (649, economy's side): a town's stage may be "settlement" and may fall; a
## building's state in the towns' buildings may be "disrepair", "ruin" or "gone";
## the "town_sheet" message carries strain {days, of, why}.
## 35 (649, terrain's side): a "clearing" cell's "trunk" may stand on the level's
## own floor (a ruin's ground grown back), so a client keeps it and makes the cell
## void on a reload; one that forgot it would show floor there.
## 35 (649, buildings' side): a level may carry the "camp" kind, open all round
## and roofless, read alike on both sides.
## 35 (643): new message "notes" {zone, notes: [{tile: [x, y], text}]}: the
## sought's door notes of a zone, whole, with the map and when they change;
## the client reads one with E on the cell outside the door.
## 35 (490 amended, npc's side): a resident's look spec may carry "hat=<word>"
## (the bard's "bard"), a piece on pc-character's head socket; a client that does
## not know the word wears nothing new.
## 36 (661): new command "view_ready" {zone}, a client's view of the zone built
## (Main.tell_view_ready); the server ends that player's arrival shelter. An old
## client never sends it, and the shelter runs its 6 s.
## 36 (548 amended): the "offers" message may carry a talking monster's free deal
## (kind "deal", cost 0, no what.steps: the draugr's "again" for one who paid);
## an old client's panel skips it, and only the typed yes reaches it.
const PROTOCOL_REVISION := 36
## The scripts whose RPCs are part of the wire.
const RPC_SCRIPTS: Array[String] = ["res://net/net.gd", "res://sim/world.gd", "res://sim/grid_entity.gd", "res://sim/monster.gd"]
## Every kind of message (message, message_to, broadcast, broadcast_to).
const MESSAGE_KINDS: Array[String] = ["barter", "builder", "chat", "clearing", "counter", "death", "folds", "grass", "map", "notes", "offers", "party", "return", "roofs", "shop", "sky", "speech", "telegraph", "terrain", "town", "town_sheet", "world"]
## Properties entity subclasses add with replicate().
const SUBCLASS_REPLICATED: Array[String] = ["activity", "addressing", "ailing", "ailments", "alert", "asleep", "body", "bond_step", "bond_why", "buffs", "channel_of", "channel_until", "charge_room", "charges", "down_until", "downed_until", "emit_light", "hands", "heart", "keeper_peer", "led_by", "led_to", "mending", "move_ticks", "peaceable", "person", "pose", "raised", "raised_tick", "slot_counts", "slot_notes", "slots", "tending", "trade", "worn"]
const SETTINGS_FILE := "settings.cfg"
## First launch: half the 3840x2160 base, windowed.
const DEFAULT_WINDOW_SIZE := Vector2i(1920, 1080)
const WINDOW_SAVE_DELAY := 0.5
const UNKNOWN_VERSION := "0.0.0"
## The identity a host run from the project uses, so its state persists too.
const DEV_PLAYER_ID := "dev-host"
const DEFAULT_NAME := "Player"
const MAX_NAME_LENGTH := 24
## The bodies a player or companion may wear (decision 388), the first the default.
const BODIES: Array[StringName] = [&"male", &"female"]
## The longest look a player's settings may carry (tidy_look).
const MAX_LOOK_LENGTH := 160

## From version.txt at the project root. Sent on join; must match the server.
var version := UNKNOWN_VERSION

var mode := Mode.HOST
var address := "127.0.0.1"
var port := DEFAULT_PORT
## The address a server or host listens on (--bind), or "" for every one.
var bind_address := ""
## Snapshot file for the authority, or "" for none.
var state_path := ""
## Localhost TCP port for console commands, or 0 for none.
var admin_port := 0
## UDP status port (decision 431): a server answers there only when given
## (--status-port); a client asks there (--status-port, settings
## status_port=), else at the game port + 2 (ServerStatus.port_for).
var status_port := 0
var _status_responder: ServerStatus.Responder
## [ServerStatus.Query, game port] waiting for an answer.
var _status_queries: Array[Array] = []
## Read console commands from stdin. Always on for --server.
var console := false
## OpenAI-compatible chat endpoint and model for companion minds, from
## --llm-url / --llm-model or PSYKINETIC_LLM_URL / PSYKINETIC_LLM_MODEL.
## The URL defaults to a local Ollama's native endpoint; a model must be
## named for the language-model mind to be used at all.
const DEFAULT_LLM_URL := "http://127.0.0.1:11434/api/chat"
var llm_url := DEFAULT_LLM_URL
var llm_model := ""
## Her voice on an endpoint and model of its own (a bigger model on a
## bigger card, say), from --voice-url / --voice-model or
## PSYKINETIC_VOICE_URL / PSYKINETIC_VOICE_MODEL; "" for the same as
## --llm-url / --llm-model. Stances and the instruction check stay there.
var voice_url := ""
var voice_model := ""
## The mind log's file ("" for none); see MindLog. A dedicated server
## writes /var/lib/psykinetic/mind.log by default when that directory is
## there. --mind-why asks the minds for their reason as well.
const DEFAULT_MIND_LOG := "/var/lib/psykinetic/mind.log"
var mind_log_path := ""
## --map=<name>: the zone new players start in ("" for the default map).
var map_name := ""
## --day-minutes=<m>, --hour=<h>: the world clock's day length and hour,
## set at boot over the snapshot's (DayNight); 0 and -1 keep it.
var day_minutes := 0.0
var start_hour := -1.0
## --weather=<kind>: the weather every region starts in ("" for the clock's).
var start_weather := ""
## --season=<name>, --season-days=<n>: the season to start in ("" for the
## clock's) and a season's length (0 keeps it).
var start_season := ""
var season_days := 0
## --edit=<name>: run the level editor on that map instead of the game.
var edit_map := ""
## --world-map: the world map editor (editor/world_map_view) instead of the game.
var world_map := false
## --edit-size=<w>x<h>: a new map's size in cells.
var edit_size := LevelMap.NEW_SIZE
## Builder mode (BuilderHost), server/host: --builders=<id,id> (or
## PSYKINETIC_BUILDERS) the player ids allowed to build besides a host's
## own player; --builder-stub answers with StubClaude instead of the API
## (no key needed); --builder-model, --builder-effort, --builder-max-cost
## (dollars per request) for Claude. It needs ANTHROPIC_API_KEY or the stub.
var builders: PackedStringArray = []
var builder_stub := false
## The lawspeaker (decision 448), server only: --lawspeaker=<haiku|sonnet|opus|off>
## (or PSYKINETIC_LAWSPEAKER) turns his daily rulings on through the Claude
## API (ANTHROPIC_API_KEY, as the builder); off by default, and the box stays
## off unless Jeff turns it on. --lawspeaker-players lets players' words into
## his requests (an outside API).
var lawspeaker := "off"
var lawspeaker_players := false
## Where the server writes the proposals list for Jeff (decision 458) after a
## round that proposes: --proposed=<path>; the box's default when its folder
## is there; "" writes nothing (clients, tests).
const DEFAULT_PROPOSED := "/var/lib/psykinetic/proposed.md"
var proposed_path := ""
var _proposed_given := false
var builder_model := ClaudeClient.DEFAULT_MODEL
var builder_effort := "medium"
var builder_max_cost := 1.0
var _mind_log_given := false
## Where the companions' transcripts go ("" for none); see Transcript.
const DEFAULT_TRANSCRIPTS := "/var/lib/psykinetic/transcripts"
var transcripts_dir := ""
var _transcripts_given := false
var mind_why := false
## --perception: "list", "grid" or "both" (Companion.perception).
const PERCEPTIONS: Array[String] = ["list", "grid", "both"]
var perception := "list"
## --no-companions: players get no companion (tests of other things, or ops).
var companions := true
## --still-monsters: no monster idles or notices anyone (they stand where
## they are and leave the players be), for tests that stage what they need in
## a real level (Monster.idling, Monster.noticing): without it, test_room's
## imps hunted net_test's players under load.
var still_monsters := false
## --no-player-reset turns this off: any player may rebuild the room with R.
## On while the game is only being tested; the console's reset always works.
var player_reset := true

## Server-to-everyone notices that are not sim state: ("speech", {entity, text}).
signal message_received(kind: String, data: Dictionary)
## Join token. Never written anywhere in the repo; see server/env.example.
var token := ""
## Who this client says it is. From settings.cfg, --player-id/--name, or
## for a project host the dev id.
var player_id := ""
var player_name := DEFAULT_NAME
## The body this client's player wears (BODIES; decision 388): settings.cfg
## "body", chosen in the options panel, sent with the join, so a change shows
## from the next join.
var player_body: StringName = &"male"
## Server only: the body each player id asked for when it joined.
var _bodies: Dictionary[String, StringName] = {}
## The look this client's player chose beside their body (PersonLook's
## words, tidy_look; decision 439): settings.cfg "look", chosen in the
## options panel's Character section, sent with the join like the body.
var player_look := ""
## Server only: the look each player id asked for when it joined.
var _looks: Dictionary[String, String] = {}
## Server only: peers told to go that have not yet gone.
var _leaving: Dictionary[int, bool] = {}
## Server only: peers dropped early (see _drop) whose ENet disconnect event
## is still to come.
var _dropped: Dictionary[int, bool] = {}
## Server only: authenticated peer -> its player_id.
var _authenticated: Dictionary[int, String] = {}
## True when an exported build has no settings file and must ask for one.
var needs_setup := false
## Which client view Main shows: "2d" or "3d". Nothing on a server.
var renderer := "3d"
## --renderer was on the command line; it wins over the settings file.
var _renderer_given := false
## The settings file's renderer= as written ("" for no line), written back
## as it was so that a --renderer run does not change the file.
var _settings_renderer := ""
## How the local player is driven, and which keys and buttons do anything:
## "click" (click to move, Q/E turn) or "wasd" (WASD walks, the mouse aims,
## a middle drag turns). Like renderer: settings controls=, --controls.
var controls := "click"
var _controls_given := false
var _settings_controls := ""
## The window as the settings file has it: its windowed size and whether it
## is fullscreen. Applied at start, kept up to date, saved with the rest.
var window_size := DEFAULT_WINDOW_SIZE
var fullscreen := false
## The 3D camera's diamond in degrees (a multiple of Client3D.ORBIT_STEP,
## 0..360), kept with the window settings; --test-yaw for a run.
var camera_yaw := 0.0
## The 3D camera's wheel zoom, a factor on its default size, kept with the
## yaw.
var camera_zoom := 1.0
## The low-horizon camera trial (decision 623): settings.cfg camera=low.
var camera_low := false
## The HUD's list of controls shown (H toggles it); settings.cfg hints=on|off,
## off by default since the context hint (ui's step 3) says what the keys do.
var hints := false
## settings.cfg hp_bars= (0 turns them off), and the volumes, 0..1, each a
## bus's (Sfx.VOLUME_SETTINGS) but master's: master_volume=, sfx_volume=,
## voice_volume=, ambience_volume=, ui_volume=, music_volume=.
var hp_bars := true
var master_volume := 1.0
var sfx_volume := 1.0
var voice_volume := 1.0
var ambience_volume := 1.0
var ui_volume := 1.0
var music_volume := 1.0
## A volume changed (set_volume): Sfx sets the buses again.
signal volumes_changed
## The 3D view's anti-aliasing (decision 385): settings.cfg antialias=,
## one of ANTIALIAS, on the root viewport (set_antialias). SMAA by default:
## at 1080p it takes the steps off every edge, textures' too, where MSAA 2x
## leaves them, for nothing measured on the desktop; MSAA 4x is there for
## thin limbs, FXAA for a weak card.
const ANTIALIAS: Array[String] = ["off", "fxaa", "smaa", "msaa4"]
var antialias := "smaa"
## The interface's size (the root's content scale, ui_scale=), the text size
## (the theme's font sizes, text_scale=) and the colour set (colours=,
## "normal" or "distinct"; UiTheme.COLOUR_SETS), the Options' accessibility
## rows (decision 453).
var ui_scale := 1.0
var text_scale := 1.0
var colours := "normal"
## The first-time talk hint was shown (hinted_talk=on).
var hinted_talk := false
## settings.cfg screenshot_dir=: where F12's screenshots go (decision 538; Jeff's
## NAS folder), "" for the game's own user://screenshots. Kept as any
## unknown key is.
var screenshot_dir := ""
## The first screenshot's hint (the folder) has been shown (hinted_shot=on).
var hinted_shot := false
## How far round the player a grown forest's crowns are seen through
## (GrownTrees, decision 467; Jeff: "larger circle, probably even most of
## visible screen"): a share of the view's half-height, to the middle of its
## soft edge. settings.cfg see_through= (0.2 to 1.5), read only, so it is
## tried without a build; the file keeps it.
var see_through := 0.8
const VOLUME_SETTINGS: Array[String] = ["master_volume", "sfx_volume", "voice_volume", "ambience_volume", "ui_volume", "music_volume"]
## The quick phrases, keys 1-4; settings.cfg phrase1= ... phrase4=.
const DEFAULT_PHRASES: Array[String] = ["With me!", "Stay back!", "Get them!", "Fall back!"]
var phrases: Array[String] = DEFAULT_PHRASES.duplicate()
## Lines of the settings file that save_settings does not write itself,
## key -> value as read, written back as they were.
var _settings_kept: Dictionary = {}
## The keys save_settings writes; everything else in the file is kept.
## camera_pitch was written by older builds and is no longer: listed so
## that a rewrite drops it.
const WRITTEN_SETTINGS: Array[String] = ["address", "port", "token", "player_id", "name", "display_delay",
	"window_width", "window_height", "window_mode", "camera_yaw", "camera_pitch", "camera_zoom",
	"renderer", "controls", "phrase1", "phrase2", "phrase3", "phrase4", "hints", "body", "look"]
## Saves the window settings a moment after the last resize, not on each.
var _window_save: SceneTreeTimer
var _mode_given := false
var _settings_override := ""
var _test_version := ""
## --print-protocol: print this build's version and protocol and quit (the
## release flow compares them with the box's: decision 239).
var print_protocol := false
## Client: the build the server runs, as its "map" message says ("" until
## then). It may differ from this one's with the same protocol (decision 239).
var server_version := ""
var _test_protocol := ""
var _protocol := ""
## True once an ENet peer is in place. False means offline single-player.
var online := false

## This peer's id: 1 on the server, host and offline; ENet's id on a client.
## Cached because a closed ENet peer can no longer be asked.
var local_id := 1

var test_move := Vector2i.ZERO
var test_contest_tile := Vector2i.ZERO
var test_contest_tick := 0
var test_reset_tick := 0
## --test-builder=<x>,<y>,<w>,<h>:<request>: once the local player is in,
## builder mode asks that for that area (for screenshots of the ghost).
var test_builder := ""
var test_exit_after := 0.0
var test_exit_on := ""
var test_minimap := false
## --test-ui-cost: the interface's per-frame cost printed at exit (UiCost).
var test_ui_cost := false
## --menu: the main menu first, whatever the mode (MainMenu).
var show_menu := false
## --test-show: HUD panels opened once the local player is in (Main._run_test_show).
var test_show: PackedStringArray = []
## --raids: raid groups on from the start (World.raid_groups; the console can too).
var raids := false
## --regenerate: the shifting levels regenerate on this server (Regen, decision
## 542; the console can too). Off, a marked level stays as it is: tests, and
## any server not asked, never write a generation.
var regenerate := false
var test_wait_players := 0
## --test-herds=<n>: n mixed herds (deer, rabbits, boar, wolves) put in each
## outdoor zone the server builds, for benches with wildlife before economy's
## herds place any (Main._test_herds). 0: none.
var test_herds := 0
var test_hold_tick := 0
var test_hold_orders := 0
## Players admitted since start, for --test-wait-players.
var _admitted_ever := 0
## The peers that ordered on --test-hold's tick.
var _hold_senders := {}
## When the sim began to wait for a test hold (msec), -1 when it is not.
var _hold_since := -1
var screenshot_path := ""
var test_hover_tile := Vector2i(-1, -1)
var test_click_after := 0.0
var test_fullscreen_after := 0.0
var test_azimuth := 0.0
var test_yaw := 0.0
var _test_yaw_given := false
var test_door_tick := 0
var test_chest := ""
var test_lag := 0.0
## Server: how often the tick clock goes to clients, 10 (each tick) or 20
## (each half tick too); --tick-send-hz. The sim stays at 10 Hz.
var tick_send_hz := 10
var test_steer := 0.0
## --test-fight: seconds between strikes at the nearest monster.
var test_fight := 0.0
## --test-chase: seconds of chasing the nearest animal as drawn.
var test_chase := 0.0
## --test-smooth: Main measures what it draws (net/smooth_meter.gd).
var test_smooth := false
## --test-walk: [{"keys": "wd", "seconds": 1.0}, ...]
var test_walk: Array[Dictionary] = []

var mispredicts_total := 0
## Tick times, bandwidth, corrections: see NetStats.
var stats := NetStats.new()
## --max-players=<n>: authenticated peers at once (MAX_PLAYERS unless said);
## twice as many connections may wait to authenticate.
var max_players := MAX_PLAYERS
## Server: what each client is sent, by nearness to its player (Interest).
var interest := Interest.new()
var _traffic_at_msec := 0
var snaps_total := 0
## Times (msec) of snaps in the last minute.
var _snap_times: Array[int] = []
## Times (msec) of mispredictions in the last minute.
var _mispredict_times: Array[int] = []


func _enter_tree() -> void:
	version = _read_version()
	if OS.get_environment("PSYKINETIC_LLM_URL") != "":
		llm_url = OS.get_environment("PSYKINETIC_LLM_URL")
	llm_model = OS.get_environment("PSYKINETIC_LLM_MODEL")
	voice_url = OS.get_environment("PSYKINETIC_VOICE_URL")
	voice_model = OS.get_environment("PSYKINETIC_VOICE_MODEL")
	if OS.get_environment("PSYKINETIC_LAWSPEAKER") != "":
		lawspeaker = OS.get_environment("PSYKINETIC_LAWSPEAKER").strip_edges().to_lower()
	if OS.get_environment("PSYKINETIC_BUILDERS") != "":
		_set_option("--builders", OS.get_environment("PSYKINETIC_BUILDERS"))
	if OS.get_environment("PSYKINETIC_MIND_WHY") in ["1", "true", "on", "yes"]:
		mind_why = true
	if OS.get_environment("PSYKINETIC_PERCEPTION") != "":
		_set_option("--perception", OS.get_environment("PSYKINETIC_PERCEPTION"))
	_parse_args()
	if print_protocol:
		print("PROTOCOL v%s %s" % [version, protocol()])
		get_tree().quit.call_deferred()
		return
	if not _mode_given:
		_apply_settings()
	_apply_renderer_setting()
	set_antialias(antialias, false)  # The default, with no settings file.
	_apply_window_settings()
	if mode == Mode.SERVER and not _mind_log_given and DirAccess.dir_exists_absolute(DEFAULT_MIND_LOG.get_base_dir()):
		mind_log_path = DEFAULT_MIND_LOG
	if mode == Mode.SERVER and not _transcripts_given and DirAccess.dir_exists_absolute(DEFAULT_TRANSCRIPTS.get_base_dir()):
		transcripts_dir = DEFAULT_TRANSCRIPTS
	if mode == Mode.SERVER and not _proposed_given and DirAccess.dir_exists_absolute(DEFAULT_PROPOSED.get_base_dir()):
		proposed_path = DEFAULT_PROPOSED
	if player_id.is_empty():
		# A client run from the command line gets a throwaway id; a host or
		# server run from the project is always the same dev player.
		player_id = new_uuid() if mode == Mode.CLIENT else DEV_PLAYER_ID
	player_name = tidy_name(player_name)


## A random UUID v4, as a player identity.
static func new_uuid() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() & 0xFF
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func tidy_name(raw: String) -> String:
	var tidy := raw.strip_edges().substr(0, MAX_NAME_LENGTH)
	return tidy if not tidy.is_empty() else DEFAULT_NAME


## A body as BODIES has it: anything but "female" is male (an older client
## sends none).
static func tidy_body(raw: Variant) -> StringName:
	return &"female" if str(raw).strip_edges().to_lower() == "female" else &"male"


## A player's look as the game keeps it (decision 439; it comes from any
## client and goes to every other): only the words a player may choose
## (PersonLook.PLAYER_CHOICES), each once, with a value it knows (a seed
## a whole number in range), at most MAX_LOOK_LENGTH long; the rest dropped.
static func tidy_look(raw: Variant) -> String:
	var kept: Array[String] = []
	var said := {}
	for word in str(raw).substr(0, MAX_LOOK_LENGTH * 2).split(" ", false):
		var pair := word.split("=")
		if pair.size() != 2 or said.has(pair[0]) or not PersonLook.PLAYER_CHOICES.has(pair[0]):
			continue
		var choices: Array = PersonLook.PLAYER_CHOICES[pair[0]]
		var known := pair[1] in choices if not choices.is_empty() else (pair[1].is_valid_int() and pair[1].length() <= 10 and int(pair[1]) >= 0)
		if known:
			said[pair[0]] = true
			kept.append(pair[0] + "=" + pair[1])
	return " ".join(kept).substr(0, MAX_LOOK_LENGTH)


## Server side: the look [param id] asked for when it joined this run (this
## host's own player: its setting); "" if none.
func asked_look(id: String) -> String:
	if _looks.has(id):
		return _looks[id]
	return player_look if id == player_id else ""


## Server side: the body [param id] asked for when it joined this run (this
## host's own player: its setting); &"" if it has not joined since the server
## started, so its record keeps the one it had.
func asked_body(id: String) -> StringName:
	if _bodies.has(id):
		return _bodies[id]
	return player_body if id == player_id else &""


## Server side: the player_id an authenticated peer presented, or "".
func player_of(peer: int) -> String:
	return _authenticated.get(peer, "")


func _read_version() -> String:
	var text := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	if text.is_empty():
		push_warning("[net] version.txt missing; reporting %s" % UNKNOWN_VERSION)
		return UNKNOWN_VERSION
	return text


## Where the client settings file lives: next to the exe in an exported
## build, wherever --settings points, or nowhere ("") in a project run.
func settings_path() -> String:
	if _settings_override != "":
		return _settings_override
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(SETTINGS_FILE)
	return ""


## No mode on the command line: join from settings.cfg if there is one, ask
## for one in an exported build, otherwise host.
func _apply_settings() -> void:
	var path := settings_path()
	if path == "":
		return
	if not FileAccess.file_exists(path):
		needs_setup = true
		mode = Mode.CLIENT
		return
	var settings := _read_settings(path)
	configure_client(settings.get("address", address), int(settings.get("port", str(port))),
			settings.get("token", ""))
	player_name = tidy_name(settings.get("name", DEFAULT_NAME))
	player_body = tidy_body(settings.get("body", ""))
	player_look = tidy_look(settings.get("look", ""))
	# display_delay (ticks) was written by older builds, always, so a new
	# default could never reach anyone: it is dropped, and only a hand-written
	# display_delay_ms (kept as it is, never written) counts.
	var delay := str(settings.get("display_delay_ms", ""))
	if delay.is_valid_float():
		World.display_delay_ticks = clampf(delay.to_float() / 1000.0 * World.TICK_RATE, 0.0, 10.0)
	player_id = str(settings.get("player_id", "")).strip_edges()
	if player_id.is_empty():
		# First run with a hand-written file: give it an identity and keep it.
		player_id = new_uuid()
		save_settings(address, port, token, player_name)
		print("[net] gave %s a new player id" % path)
	print("[net] using %s" % path)


## renderer= and controls= from the settings file, unless given on the
## command line: only "2d" picks the 2D view, only "wasd" WASD. Also
## hp_bars=, master_volume= and sfx_volume=, and every line the game does
## not write itself, to keep.
func _apply_renderer_setting() -> void:
	var path := settings_path()
	if path != "" and FileAccess.file_exists(path):
		var settings := _read_settings(path)
		_settings_renderer = str(settings.get("renderer", ""))
		if not _renderer_given and _settings_renderer != "":
			renderer = renderer_from(_settings_renderer)
		_settings_controls = str(settings.get("controls", ""))
		if not _controls_given and _settings_controls != "":
			controls = controls_from(_settings_controls)
		if status_port == 0 and str(settings.get("status_port", "")).is_valid_int():
			status_port = str(settings["status_port"]).to_int()
		apply_view_options(settings)


## hp_bars=, the volumes (VOLUME_SETTINGS), art_placeholders= and
## art_labels= (ArtKit) from [param settings], and the lines to keep. A
## volume is held to 0..1; a bad one keeps the default.
func apply_view_options(settings: Dictionary) -> void:
	hp_bars = str(settings.get("hp_bars", "1")).strip_edges().to_lower() not in ["0", "false", "off", "no"]
	ArtKit.show_placeholders = _setting_on(settings, "art_placeholders")
	ArtKit.show_labels = _setting_on(settings, "art_labels")
	for key in VOLUME_SETTINGS:
		set(key, _volume(settings.get(key, ""), float(get(key))))
	set_antialias(str(settings.get("antialias", antialias)).strip_edges().to_lower(), false)
	phrases = phrases_from(settings)
	_settings_kept.clear()
	for key: String in settings:
		if key not in WRITTEN_SETTINGS:
			_settings_kept[key] = settings[key]


## A yes-or-no line of [param settings], off unless it says so.
static func _setting_on(settings: Dictionary, key: String) -> bool:
	return str(settings.get(key, "0")).strip_edges().to_lower() in ["1", "true", "on", "yes"]


## phrase1= ... phrase4= from [param settings], each cut to a chat line's
## length; a missing or empty one is its default.
static func phrases_from(settings: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for i in DEFAULT_PHRASES.size():
		var text := str(settings.get("phrase%d" % (i + 1), "")).strip_edges().left(200)
		out.append(text if not text.is_empty() else DEFAULT_PHRASES[i])
	return out


static func _volume(text: Variant, otherwise: float) -> float:
	var value := str(text).strip_edges()
	return clampf(value.to_float(), 0.0, 1.0) if value.is_valid_float() else otherwise


## "wasd" is WASD; anything else is click-to-move.
static func controls_from(value: String) -> String:
	return "wasd" if value.strip_edges().to_lower() == "wasd" else "click"


## "2d" is the 2D view; anything else is the 3D one.
static func renderer_from(value: String) -> String:
	return "2d" if value.strip_edges().to_lower() == "2d" else "3d"


## The window as the settings file last saw it, applied before the first
## frame; the defaults where there is no file. Nothing on a server or in
## tests (headless). Resizes and F11 from then on are saved back.
func _apply_window_settings() -> void:
	if DisplayServer.get_name() == "headless" or mode == Mode.SERVER:
		return
	var path := settings_path()
	if path != "" and FileAccess.file_exists(path):
		var settings := _read_settings(path)
		var width := str(settings.get("window_width", ""))
		var height := str(settings.get("window_height", ""))
		if width.is_valid_int() and height.is_valid_int() and width.to_int() > 0 and height.to_int() > 0:
			window_size = Vector2i(width.to_int(), height.to_int())
		fullscreen = str(settings.get("window_mode", "")) == "fullscreen"
		camera_yaw = saved_yaw(str(settings.get("camera_yaw", "")), camera_yaw)
		camera_zoom = saved_zoom(str(settings.get("camera_zoom", "")), camera_zoom)
		var see := str(settings.get("see_through", ""))
		if see.is_valid_float():
			see_through = clampf(see.to_float(), 0.2, 1.5)
		hints = str(settings.get("hints", "off")) == "on"
	if _test_yaw_given:
		camera_yaw = test_yaw
	var window := get_window()
	window.size = window_size
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.move_to_center()
	window.size_changed.connect(_on_window_size_changed)
	_apply_access_settings()


## ui_scale=, text_scale= and colours= from the settings file, applied
## before the first frame (the colours before any panel loads).
func _apply_access_settings() -> void:
	var path := settings_path()
	if path != "" and FileAccess.file_exists(path):
		var settings := _read_settings(path)
		var scale := str(settings.get("ui_scale", ""))
		if scale.is_valid_float():
			ui_scale = clampf(scale.to_float(), 0.5, 2.0)
		var text := str(settings.get("text_scale", ""))
		if text.is_valid_float():
			text_scale = clampf(text.to_float(), 0.5, 2.0)
		var set := str(settings.get("colours", "normal"))
		if UiTheme.COLOUR_SETS.has(set):
			colours = set
		camera_low = str(settings.get("camera", "")).strip_edges() == "low"
		hinted_talk = str(settings.get("hinted_talk", "off")) == "on"
		screenshot_dir = str(settings.get("screenshot_dir", "")).strip_edges()
		hinted_shot = str(settings.get("hinted_shot", "off")) == "on"
		Keys.read(settings)  # key_<action>= (decision 453).
	set_ui_scale(ui_scale, false)
	set_text_scale(text_scale, false)
	set_colours(colours, false)


## The Options' Interface size: the root's content scale (every panel is laid
## out in canvas units, so one number sizes them all).
func set_ui_scale(value: float, save := true) -> void:
	ui_scale = clampf(value, 0.5, 2.0)
	if DisplayServer.get_name() != "headless" and get_tree() != null and get_tree().root != null:
		get_tree().root.content_scale_factor = ui_scale
	if save:
		_settings_kept["ui_scale"] = "%.2f" % ui_scale
		save_view_settings()


## The Options' Text size: the theme's font sizes (UiTheme.apply_text_scale).
func set_text_scale(value: float, save := true) -> void:
	text_scale = clampf(value, 0.5, 2.0)
	UiTheme.apply_text_scale(text_scale)
	if save:
		_settings_kept["text_scale"] = "%.2f" % text_scale
		save_view_settings()


## The one-time talk hint shown (Main), remembered.
func set_hinted_talk(value: bool) -> void:
	hinted_talk = value
	save_view_settings()


## The first screenshot's hint shown (decision 538), kept in settings.cfg.
func set_hinted_shot(value: bool) -> void:
	hinted_shot = value
	_settings_kept["hinted_shot"] = "on" if value else "off"
	save_view_settings()


## A key rebound in the Options (Keys.bind) and the bindings saved.
func set_key(action: String, keycode: int) -> void:
	Keys.bind(action, keycode)
	save_view_settings()


## The Options' Colours: the meaning colours' set (UiTheme.apply_colours;
## shown in full from the next start).
func set_colours(value: String, save := true) -> void:
	if not UiTheme.COLOUR_SETS.has(value):
		return
	colours = value
	UiTheme.apply_colours(value)
	if save:
		_settings_kept["colours"] = value
		save_view_settings()


## The Options' Camera: the low-horizon trial (decision 623) on or off,
## applied to the 3D view at once (camera_low_changed) and written as
## camera=low or camera=high.
func set_camera_low(value: bool, save := true) -> void:
	var changed := value != camera_low
	camera_low = value
	if changed:
		camera_low_changed.emit(value)
	if save:
		_settings_kept["camera"] = "low" if value else "high"
		save_view_settings()


## camera_yaw= as read from the settings file: only a diamond view is a
## resting yaw, so an older file's axis-aligned one (a 45° step) goes to
## the nearest diamond. [param otherwise] for a missing or bad value.
static func saved_yaw(text: String, otherwise: float) -> float:
	if not text.strip_edges().is_valid_float():
		return otherwise
	return fposmod(Client3D.nearest_diamond(text.to_float()), 360.0)


## camera_zoom= as read from the settings file: held to the wheel's range
## (an older build's wider zoom comes back at its nearer end).
## [param otherwise] for a missing or bad value.
static func saved_zoom(text: String, otherwise: float) -> float:
	if not text.strip_edges().is_valid_float():
		return otherwise
	return clampf(text.to_float(), Client3D.ZOOM_MIN, Client3D.ZOOM_MAX)


## F11: borderless fullscreen at the monitor's native size, or back to the
## window as it was.
func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = window_size
		window.move_to_center()
	_save_window_settings()


## Remembers the windowed size (fullscreen is the monitor's, not a choice)
## and saves it once the resizing settles.
func _on_window_size_changed() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED or window.size == window_size:
		return
	window_size = window.size
	if _window_save != null and _window_save.time_left > 0.0:
		return
	_window_save = get_tree().create_timer(WINDOW_SAVE_DELAY)
	_window_save.timeout.connect(_save_window_settings)


## Rewrites the settings file with the window and the view as they are,
## where there is one (never before the setup screen has written it).
func save_view_settings() -> void:
	_save_window_settings()


func _save_window_settings() -> void:
	var path := settings_path()
	if path != "" and FileAccess.file_exists(path):
		save_settings(address, port, token, player_name)


## Plain key=value lines; blank lines, comments and [sections] are ignored.
func _read_settings(path: String) -> Dictionary:
	var settings := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";") or line.begins_with("["):
			continue
		var equals := line.find("=")
		if equals > 0:
			settings[line.substr(0, equals).strip_edges()] = line.substr(equals + 1).strip_edges()
	return settings


## The volume [param key] (one of VOLUME_SETTINGS) at [param value], held
## to 0..1 and applied to the buses; with [param save], written to the
## settings file (kept as any line the game does not write itself), else
## only when the next save comes (a slider writes when let go).
func set_volume(key: String, value: float, save := true) -> void:
	if key not in VOLUME_SETTINGS:
		return
	set(key, clampf(value, 0.0, 1.0))
	_settings_kept[key] = "%.2f" % float(get(key))
	volumes_changed.emit()
	if save:
		save_view_settings()


## The 3D view's anti-aliasing at [param value] (one of ANTIALIAS; another
## keeps what it is), on the root viewport: off, FXAA or SMAA (screen space,
## a pass over the frame) or MSAA 4x. With [param save], written to the
## settings file (kept as any line the game does not write itself).
func set_antialias(value: String, save := true) -> void:
	if value not in ANTIALIAS:
		return
	antialias = value
	var viewport := get_viewport()
	if viewport != null:
		viewport.msaa_3d = Viewport.MSAA_4X if value == "msaa4" else Viewport.MSAA_DISABLED
		viewport.screen_space_aa = {"fxaa": Viewport.SCREEN_SPACE_AA_FXAA,
			"smaa": Viewport.SCREEN_SPACE_AA_SMAA}.get(value, Viewport.SCREEN_SPACE_AA_DISABLED)
	if save:
		_settings_kept["antialias"] = value
		save_view_settings()


## The options' Controls section: click-to-move or WASD, written to
## settings.cfg as controls= (read again at the next start as before).
func set_controls(value: String, save := true) -> void:
	controls = controls_from(value)
	_settings_controls = controls
	if save:
		save_view_settings()


## The options' controls list on or off (as H does), written as hints=.
func set_hints(shown: bool, save := true) -> void:
	hints = shown
	if save:
		save_view_settings()


## The options' Window choice: fullscreen or windowed, as F11 toggles.
func set_fullscreen(value: bool) -> void:
	if value != fullscreen:
		toggle_fullscreen()


## The options' Resolution choice: the windowed size, applied now when the
## window is windowed, and remembered as the size fullscreen comes back to.
func set_window_size(size: Vector2i) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	window_size = size
	var window := get_window()
	if window != null and not fullscreen and DisplayServer.get_name() != "headless":
		window.size = size
		window.move_to_center()
	_save_window_settings()


## Writes the settings file, keeping (or minting) this client's player id.
## False if it cannot.
func save_settings(new_address: String, new_port: int, new_token: String,
		new_name: String) -> bool:
	var path := settings_path()
	if path == "":
		return false
	if player_id.is_empty():
		player_id = new_uuid()
	player_name = tidy_name(new_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[net] cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(("address=%s\nport=%d\ntoken=%s\nplayer_id=%s\nname=%s\n"
			+ "window_width=%d\nwindow_height=%d\nwindow_mode=%s\ncamera_yaw=%d\ncamera_zoom=%.3f\n") % [
		new_address, new_port, new_token, player_id, player_name,
		window_size.x, window_size.y, "fullscreen" if fullscreen else "windowed", roundi(camera_yaw), camera_zoom])
	if _settings_renderer != "":
		file.store_string("renderer=%s\n" % _settings_renderer)
	if _settings_controls != "":
		file.store_string("controls=%s\n" % _settings_controls)
	for i in phrases.size():
		file.store_string("phrase%d=%s\n" % [i + 1, phrases[i]])
	file.store_string("hints=%s\n" % ("on" if hints else "off"))
	file.store_string("body=%s\n" % player_body)
	if hinted_talk:
		file.store_string("hinted_talk=on\n")
	for line: String in Keys.lines():
		file.store_string(line + "\n")
	if player_look != "":
		file.store_string("look=%s\n" % player_look)
	for key: String in _settings_kept:
		file.store_string("%s=%s\n" % [key, _settings_kept[key]])
	file.close()
	return true


func configure_client(new_address: String, new_port: int, new_token: String) -> void:
	mode = Mode.CLIENT
	address = new_address
	port = new_port
	token = new_token
	needs_setup = false


## Round trip time to the server in milliseconds, as measured by ENet.
## 0 on the server, the host, offline, and before a client has connected.
func rtt_ms() -> float:
	if mode != Mode.CLIENT or not online:
		return 0.0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0.0
	var server := enet.get_peer(1)
	if server == null:
		return 0.0
	return server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)


## The same in sim ticks, capped so a bad reading cannot stall reconciliation.
func rtt_ticks() -> float:
	# --test-lag stands in for a longer way to the server, so it counts.
	return minf((rtt_ms() / 1000.0 + test_lag) * World.TICK_RATE, 10.0)


func record_mispredict() -> void:
	mispredicts_total += 1
	_mispredict_times.append(Time.get_ticks_msec())


## Mispredictions in the last 60 seconds.
func record_snap() -> void:
	snaps_total += 1
	_snap_times.append(Time.get_ticks_msec())


## Snaps (mispredictions too big to blend) in the last 60 seconds.
func snaps_per_minute() -> int:
	var cutoff := Time.get_ticks_msec() - 60000
	while not _snap_times.is_empty() and _snap_times[0] < cutoff:
		_snap_times.pop_front()
	return _snap_times.size()


func mispredicts_per_minute() -> int:
	var cutoff := Time.get_ticks_msec() - 60000
	while not _mispredict_times.is_empty() and _mispredict_times[0] < cutoff:
		_mispredict_times.pop_front()
	return _mispredict_times.size()


## Server: polls the network itself, so that a peer whose ENet link is
## already closing is dropped from the multiplayer before the replication
## pass of the same frame. ENet frees a peer's channels the moment either
## side starts a disconnect (its reset_queues), up to a round trip before
## Godot's disconnect event; a send in that window logs "Unable to send
## packet on channel 0, max channels: 0". The tree's own poll is off on
## the authority (see start) and done here: the ENet poll first, then any
## listed peer with no channels is told to the multiplayer as gone, which
## sends nothing, then the multiplayer's poll (packets, replication).
## Net's _process runs before every other node's, so the RPCs sent this
## frame never see the peer either.
func _process(_delta: float) -> void:
	_poll_status()
	if online and mode == Mode.CLIENT and stats.log_due():
		print("[net] client: rtt %d ms, %s" % [roundi(rtt_ms()), stats.client_text()])
	if not online or not is_authority():
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	stats.record_frame(roundi(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0))
	var now := Time.get_ticks_msec()
	if now - _traffic_at_msec >= 1000 and enet.host != null:
		_traffic_at_msec = now
		stats.record_traffic(roundi(enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)),
				roundi(enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)))
	if not multiplayer.get_peers().is_empty() and stats.log_due():
		print("[net] server: %d peers; %s" % [multiplayer.get_peers().size(), stats.server_text()])
	enet.poll()
	for peer in multiplayer.get_peers():
		var link := enet.get_peer(peer)
		if link == null or link.get_channels() == 0:
			_drop(peer)
	multiplayer.poll()


## Server: forgets [param peer] at the multiplayer level before ENet
## reports it gone, by raising the peer's disconnect itself; the real
## event later is swallowed (see _on_peer_disconnected).
func _drop(peer: int) -> void:
	multiplayer.multiplayer_peer.emit_signal("peer_disconnected", peer)
	_dropped[peer] = true


func _notification(what: int) -> void:
	# Leave cleanly when the window is closed so the other side sees it at once.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


## The authority gate used by every mutation: multiplayer.is_server(), except
## that a process started as a client is never the authority. That matters
## before it connects and after its connection closes, when is_server() would
## either say yes (offline peer) or fail (closed ENet peer), and a mirror must
## never start simulating.
func is_authority() -> bool:
	if mode == Mode.CLIENT:
		return false
	# A server or host whose peer is closed (shutting down, or never opened)
	# is simply offline: still the only authority there is. A closed ENet peer
	# cannot even be asked is_server(), so settle it here.
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return true
	return multiplayer.is_server()


## Server side: has [param peer] sent the right token? The authority itself
## always has.
func is_peer_authenticated(peer: int) -> bool:
	return peer == local_id or _authenticated.has(peer)


## The hello a client sends right after it connects: {token, version,
## player_id, name, protocol}. On the server, the same protocol (whatever
## the build: decision 239), the right token (if one is required) and an id
## nobody else is using let the peer in; anything else gets it told why and
## disconnected. A different protocol is "client out of date" when the
## server's build is newer, "server out of date" when the client's is, and
## "build mismatch" when they claim the same build.
@rpc("any_peer", "call_remote", "reliable")
func authenticate(hello: Dictionary) -> void:
	if not is_authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0 or _authenticated.has(peer):
		return
	var offered := str(hello.get("token", ""))
	var client_version := str(hello.get("version", ""))
	var client_protocol := str(hello.get("protocol", ""))
	var id := str(hello.get("player_id", "")).strip_edges()
	var player_name_given := tidy_name(str(hello.get("name", "")))
	var why := "client v%s protocol %s, server v%s protocol %s" % [
		client_version, client_protocol if client_protocol != "" else "none", version, protocol()]
	if client_protocol != protocol() and newer_version(version, client_version):
		_reject(peer, "client out of date", why)
	elif client_protocol != protocol() and newer_version(client_version, version):
		_reject(peer, "server out of date", why)
	elif client_protocol != protocol():
		# Same version number, different build: what goes over the wire differs.
		_reject(peer, "build mismatch: this client and the server are different builds of v%s" % version, why)
	elif token != "" and offered != token:
		_reject(peer, "authentication failed", "empty token" if offered == "" else "wrong token")
	elif id.is_empty() or id.length() > 64:
		_reject(peer, "authentication failed", "bad player id")
	elif id in _authenticated.values():
		_reject(peer, "already connected", "already connected as %s" % id.left(8))
	elif _authenticated.size() >= max_players:
		_reject(peer, "server full")
	else:
		if client_version != version:
			print("[net] peer %d is v%s, the server v%s: the same protocol %s, so it plays" % [
				peer, client_version, version, protocol()])
		_bodies[id] = tidy_body(hello.get("body", ""))
		_looks[id] = tidy_look(hello.get("look", ""))
		_admit(peer, id, player_name_given)


func _on_peer_connected(peer: int) -> void:
	if _authenticated.size() >= max_players:
		_reject(peer, "server full")
	else:
		# Even without a token the peer must say hello, so its version is checked.
		get_tree().create_timer(AUTH_TIMEOUT).timeout.connect(_on_auth_timeout.bind(peer))


func _on_auth_timeout(peer: int) -> void:
	if online and peer in multiplayer.get_peers() and not _authenticated.has(peer):
		_reject(peer, "authentication failed", "nothing sent in %d s" % roundi(AUTH_TIMEOUT))


func _on_peer_disconnected(peer: int) -> void:
	if _dropped.has(peer):
		# ENet's own event for a peer already dropped early.
		_dropped.erase(peer)
		return
	_authenticated.erase(peer)
	_leaving.erase(peer)
	peer_left.emit(peer)


func _admit(peer: int, id: String, player_name_given: String) -> void:
	_authenticated[peer] = id
	_admitted_ever += 1
	print("[net] peer %d authenticated as %s (%s) (%d of %d)" % [
		peer, player_name_given, id.left(8), _authenticated.size(), max_players])
	peer_authenticated.emit(peer, id, player_name_given)


## Server, tests only: whether the sim waits this frame. --test-wait-players
## starts the clock when the test's players are all in, and --test-hold keeps
## [param tick] until every contestant's order is in, so a test counts in
## ticks from the same start and a contest's orders land on one tick, however
## slowly each process starts on a loaded machine. Each gives up after a while.
func test_holds(tick: int) -> bool:
	if test_wait_players > 0 and _admitted_ever < test_wait_players:
		if _held("for %d players" % test_wait_players, 60000):
			return true
		test_wait_players = 0
	elif test_hold_tick > 0 and tick == test_hold_tick and _hold_senders.size() < test_hold_orders:
		if _held("at tick %d for %d orders" % [test_hold_tick, test_hold_orders], 20000):
			return true
		test_hold_tick = 0
	elif _hold_since >= 0:
		print("[test] the sim goes on at tick %d" % tick)
		_hold_since = -1
	return false


## Whether a test hold waits on: false once it has waited [param max_msec].
func _held(what: String, max_msec: int) -> bool:
	if _hold_since < 0:
		_hold_since = Time.get_ticks_msec()
		print("[test] the sim waits %s" % what)
	if Time.get_ticks_msec() - _hold_since < max_msec:
		return true
	print("[test] gave up waiting %s" % what)
	_hold_since = -1
	return false


## Server: [param peer] ordered its player on [param tick] (for --test-hold).
func test_note_order(peer: int, tick: int) -> void:
	if test_hold_tick > 0 and tick == test_hold_tick:
		_hold_senders[peer] = true


## [param reason] is what the player sees; [param detail] is for the log.
func _reject(peer: int, reason: String, detail := "") -> void:
	print("[net] rejected peer %d from %s (%s)" % [
		peer, _peer_address(peer), reason if detail == "" else detail])
	# Tell it why first. Disconnecting at once would drop that packet, so
	# give the message a moment to go out, then disconnect gracefully (an
	# outright cut leaves the peer in the multiplayer list for good). From
	# the disconnect on the peer is listed but cannot be sent to; it is
	# marked as leaving so sends this frame skip it (sendable_peers), and
	# the next frame's poll drops it (see _process).
	rejected.rpc_id(peer, reason, version)
	get_tree().create_timer(REJECT_GRACE).timeout.connect(func() -> void:
		if online and peer in multiplayer.get_peers():
			_leaving[peer] = true
			multiplayer.multiplayer_peer.disconnect_peer(peer))


## Server: is [param peer] being disconnected (still listed, not sendable)?
func is_leaving(peer: int) -> bool:
	return _leaving.has(peer)


## Server: the peers an RPC may go to now: every connected peer whose
## link is whole and that is not being disconnected. Broadcasts go peer
## by peer through this.
func sendable_peers() -> Array[int]:
	var peers: Array[int] = []
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for peer in multiplayer.get_peers():
		if _leaving.has(peer):
			continue
		if enet != null:
			var link := enet.get_peer(peer)
			if link == null or link.get_channels() == 0:
				continue
		peers.append(peer)
	return peers


@rpc("authority", "call_remote", "reliable")
func rejected(reason: String, server_version: String) -> void:
	print("[net] %s (server %s, this client %s)" % [reason, server_version, claimed_version()])
	join_rejected.emit(reason, server_version)


## A fingerprint of everything that goes over the wire: the replicated
## properties, the RPC methods, the spawn spec format, and a hand-bumped
## revision. Two builds with the same version.txt but different fingerprints
## cannot talk to each other, and the server says so instead of letting the
## client fall over on the first packet it does not understand.
func protocol() -> String:
	if _protocol.is_empty():
		var parts: Array[String] = [
			"rev%d" % PROTOCOL_REVISION, "spec%d" % EntityFactory.SPEC_VERSION]
		parts.append_array(GridEntity.REPLICATED)
		parts.append_array(Door.REPLICATED)
		parts.append_array(GroundPile.REPLICATED)
		parts.append_array(SUBCLASS_REPLICATED)
		parts.append_array(MESSAGE_KINDS)
		for path in RPC_SCRIPTS:
			parts.append_array(rpc_signatures(load(path) as Script))
		_protocol = "|".join(parts).sha256_text().left(12)
	return _protocol


## [param script]'s RPC methods, each with its arguments' names
## ("_net_tick(tick)"), sorted: what protocol() takes of it.
static func rpc_signatures(script: Script) -> Array[String]:
	var out: Array[String] = []
	var config: Variant = script.get_rpc_config()
	if not config is Dictionary:
		return out
	var args := {}
	for method: Dictionary in script.get_script_method_list():
		var names: Array[String] = []
		for arg: Dictionary in method.get("args", []):
			names.append(str(arg.get("name", "")))
		args[str(method["name"])] = ",".join(names)
	for method: Variant in config.keys():
		out.append("%s(%s)" % [method, args.get(str(method), "")])
	out.sort()
	return out


## Whether version [param a] ("0.1.140") is newer than [param b]; one that
## does not read as numbers is older than any that does.
static func newer_version(a: String, b: String) -> bool:
	var left := a.split(".")
	var right := b.split(".")
	for i in maxi(left.size(), right.size()):
		var x := int(left[i]) if i < left.size() and left[i].is_valid_int() else -1
		var y := int(right[i]) if i < right.size() and right[i].is_valid_int() else -1
		if x != y:
			return x > y
	return false


## What this client tells the server it is: the real version, unless a test
## hook says otherwise.
func claimed_version() -> String:
	return _test_version if _test_version != "" else version


func _peer_address(peer: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return "?"
	var packet_peer := enet.get_peer(peer)
	return packet_peer.get_remote_address() if packet_peer != null else "?"


## Server: tells every peer (and itself) something that is not sim state.
func broadcast(kind: String, data: Dictionary) -> void:
	if kind not in MESSAGE_KINDS:
		push_error("[net] message kind %s is not in Net.MESSAGE_KINDS: add it there (and so to protocol())" % kind)
	message_received.emit(kind, data)
	if online:
		for peer in sendable_peers():
			message.rpc_id(peer, kind, data)


## Server: tells only [param peers] (a zone's, World.peers_in); itself
## too when its own player is among them.
func broadcast_to(peers: Array[int], kind: String, data: Dictionary) -> void:
	if kind not in MESSAGE_KINDS:
		push_error("[net] message kind %s is not in Net.MESSAGE_KINDS: add it there (and so to protocol())" % kind)
	if local_id in peers:
		message_received.emit(kind, data)
	if online:
		var sendable := sendable_peers()
		for peer in peers:
			if peer in sendable:
				message.rpc_id(peer, kind, data)


## Server: tells one [param peer] (itself, for its own player).
func message_to(peer: int, kind: String, data: Dictionary) -> void:
	broadcast_to([peer], kind, data)


@rpc("authority", "call_remote", "reliable")
func message(kind: String, data: Dictionary) -> void:
	message_received.emit(kind, data)


## Closes the connection, if any. Safe to call more than once.
func shutdown() -> void:
	if _status_responder != null:
		_status_responder.close()
		_status_responder = null
	if online:
		online = false
		get_tree().multiplayer_poll = true
		multiplayer.multiplayer_peer.close()


## Asks the server at [param at_address] (its game [param at_port]) how it
## is: answered through status_received (decision 431). Needs no
## connection, so the menu can ask before joining.
func query_status(at_address: String, at_port: int) -> void:
	var query := ServerStatus.Query.new()
	query.send(at_address, ServerStatus.port_for(at_port, status_port))
	_status_queries.append([query, at_port])


## The status responder on --status-port; a port that cannot be had is
## said and left (the game plays on without it).
func _listen_status() -> void:
	var at := status_port
	_status_responder = ServerStatus.Responder.new()
	_status_responder.info = func() -> Dictionary:
		return {"version": claimed_version(), "protocol": protocol(), "players": _authenticated.size(),
			"accepting": _authenticated.size() < max_players}
	var error := _status_responder.listen(at, bind_address if bind_address != "" else "*")
	if error != OK:
		print("[net] status port %d unavailable (%s): no status answers" % [at, error_string(error)])
		_status_responder = null
	else:
		print("[net] answering status on UDP %d" % at)


func _poll_status() -> void:
	if _status_responder != null:
		_status_responder.poll()
	for i in range(_status_queries.size() - 1, -1, -1):
		var query: ServerStatus.Query = _status_queries[i][0]
		var game_port: int = _status_queries[i][1]
		var result := query.poll()
		if result.is_empty():
			continue
		_status_queries.remove_at(i)
		if result.get("ok", false):
			result["compatible"] = result["protocol"] == protocol() or newer_version(str(result["version"]), claimed_version())
		status_received.emit(query.address, game_port, result)


## Creates the ENet peer for the chosen mode. Called once by Main, after its
## MultiplayerSpawner is ready to receive.
func start() -> void:
	if online:
		return
	var peer := ENetMultiplayerPeer.new()
	if mode == Mode.CLIENT:
		var error := peer.create_client(address, port)
		if error != OK:
			push_error("[net] cannot connect to %s:%d (%s)" % [address, port, error_string(error)])
			return
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(
				func() -> void: print("[net] connection to %s:%d failed" % [address, port]))
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		print("[net] client connecting to %s:%d" % [address, port])
	else:
		if mode == Mode.SERVER and token == "":
			push_error("[net] --server needs --token=<string>: refusing to run an open server")
			get_tree().quit(1)
			return
		# No relay: clients talk to the server only, so the server never
		# forwards packets or announces one peer's coming and going to the
		# others. Those announcements were the main sender into a closing
		# link (two clients leaving in one poll: the second, already without
		# channels, was told about the first).
		(multiplayer as SceneMultiplayer).server_relay = false
		if bind_address != "":
			peer.set_bind_ip(bind_address)
		var error := peer.create_server(port, maxi(MAX_CLIENTS, max_players * 2))
		if error != OK:
			if mode == Mode.SERVER:
				push_error("[net] cannot listen on port %d (%s)" % [port, error_string(error)])
				get_tree().quit(1)
			else:
				# Single-player must keep working when the port is taken.
				print("[net] port %d unavailable (%s); running offline" % [port, error_string(error)])
			return
		print("[net] %s listening on port %d%s" % [
			"server" if mode == Mode.SERVER else "host", port,
			", token required" if token != "" else ", no token: open to anyone"])
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if mode == Mode.SERVER and status_port > 0:
			_listen_status()
		# The authority polls the network itself; see _process.
		get_tree().multiplayer_poll = false
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()
	online = true


## Client: connects to the same server again, after it went away (a
## restart, decision 240), with the same player id, so the server puts the
## player back where it saved them. False if no connection could be begun.
func reconnect() -> bool:
	shutdown()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		print("[net] cannot connect to %s:%d (%s)" % [address, port, error_string(error)])
		return false
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()
	online = true
	return true


func _on_connected_to_server() -> void:
	print("[net] connected as peer %d" % multiplayer.get_unique_id())
	authenticate.rpc_id(1, {
		"token": token, "version": claimed_version(), "player_id": player_id, "name": player_name,
		"body": String(player_body), "look": player_look, "protocol": _test_protocol if _test_protocol != "" else protocol()})


func _on_server_disconnected() -> void:
	online = false
	print("[net] server disconnected")


func _parse_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key := args[i]
		var value := ""
		var has_value := false
		var equals := key.find("=")
		if equals != -1:
			value = key.substr(equals + 1)
			key = key.substr(0, equals)
			has_value = true
		match key:
			"--host":
				mode = Mode.HOST
				_mode_given = true
			"--server":
				mode = Mode.SERVER
				_mode_given = true
			"--client":
				mode = Mode.CLIENT
				_mode_given = true
			"--console":
				console = true
			"--no-companions":
				companions = false
			"--still-monsters":
				still_monsters = true
				Monster.idling = false
				Monster.noticing = false
			"--no-player-reset":
				player_reset = false
			"--mind-why":
				mind_why = true
			"--no-interest":
				interest.enabled = false
			"--print-protocol":
				print_protocol = true
			"--test-minimap":
				test_minimap = true
			"--menu":
				show_menu = true
			"--test-ui-cost":
				test_ui_cost = true
			"--raids":
				raids = true
			"--regenerate":
				regenerate = true
			"--test-smooth":
				test_smooth = true
			"--world-map":
				world_map = true
			"--builder-stub":
				builder_stub = true
			"--lawspeaker-players":
				lawspeaker_players = true
			"--address", "--port", "--bind", "--state", "--admin-port", "--status-port", "--max-players", "--token", "--settings", "--player-id", "--name", "--renderer", "--controls", \
					"--llm-url", "--llm-model", "--voice-url", "--voice-model", "--perception", "--mind-log", "--map", "--day-minutes", "--hour", "--weather", "--season", "--season-days", "--edit", "--edit-size", "--transcripts", \
					"--builders", "--builder-model", "--builder-effort", "--builder-max-cost", "--lawspeaker", "--proposed", \
					"--test-move", "--test-contest", "--test-reset", "--test-builder", "--test-exit-after", "--test-exit-on", "--test-wait-players", "--test-herds", "--test-hold", "--test-version", "--test-protocol", \
					"--screenshot", "--test-show", "--test-hover", "--test-door", "--test-chest", "--test-click", "--test-fullscreen", "--test-azimuth", "--test-yaw", \
					"--test-lag", "--test-steer", "--test-fight", "--test-chase", "--test-walk", "--tick-send-hz":
				if not has_value and i + 1 < args.size():
					i += 1
					value = args[i]
				_set_option(key, value)
		i += 1


func _set_option(key: String, value: String) -> void:
	match key:
		"--address":
			address = value
		"--port":
			if value.is_valid_int():
				port = value.to_int()
		"--bind":
			bind_address = value
		"--state":
			state_path = value
		"--token":
			token = value
		"--settings":
			_settings_override = value
		"--renderer":
			renderer = renderer_from(value)
			_renderer_given = true
		"--controls":
			controls = controls_from(value)
			_controls_given = true
		"--tick-send-hz":
			tick_send_hz = clampi(value.to_int(), 10, 20)
		"--test-lag":
			test_lag = maxf(value.to_float(), 0.0)
		"--test-steer":
			test_steer = maxf(value.to_float(), 0.0)
		"--test-fight":
			test_fight = maxf(value.to_float(), 0.0)
		"--test-chase":
			test_chase = maxf(value.to_float(), 0.0)
		"--test-walk":
			test_walk.clear()
			for part in value.split(","):
				var pieces := part.split(":")
				if pieces.size() == 2 and pieces[1].is_valid_float():
					test_walk.append({"keys": pieces[0].to_lower(), "seconds": pieces[1].to_float()})
		"--player-id":
			player_id = value.strip_edges()
		"--name":
			player_name = value
		"--admin-port":
			if value.is_valid_int():
				admin_port = value.to_int()
		"--status-port":
			if value.is_valid_int():
				status_port = value.to_int()
		"--max-players":
			if value.is_valid_int():
				max_players = clampi(value.to_int(), 1, 64)
		"--llm-url":
			llm_url = value
		"--llm-model":
			llm_model = value
		"--voice-url":
			voice_url = value
		"--voice-model":
			voice_model = value
		"--perception":
			if value.to_lower() in PERCEPTIONS:
				perception = value.to_lower()
			else:
				print("[net] --perception=%s: not one of %s; keeping %s" % [value, "|".join(PERCEPTIONS), perception])
		"--map":
			map_name = value
		"--day-minutes":
			if value.is_valid_float() and value.to_float() > 0.0:
				day_minutes = value.to_float()
		"--hour":
			if value.is_valid_float():
				start_hour = fposmod(value.to_float(), 24.0)
		"--season":
			if value.to_lower() in Season.NAMES:
				start_season = value.to_lower()
			else:
				print("[net] --season=%s: not one of %s" % [value, "|".join(Season.NAMES)])
		"--season-days":
			if value.is_valid_int() and value.to_int() > 0:
				season_days = value.to_int()
		"--weather":
			if Weather.KINDS.has(value.to_lower()):
				start_weather = value.to_lower()
			else:
				print("[net] --weather=%s: not one of %s" % [value, "|".join(Weather.KINDS.keys())])
		"--builders":
			builders = PackedStringArray(Array(value.split(",", false)).map(func(id: String) -> String: return id.strip_edges()))
		"--builder-model":
			builder_model = value.strip_edges()
		"--builder-effort":
			if value in ["low", "medium", "high", "xhigh", "max"]:
				builder_effort = value
		"--builder-max-cost":
			if value.is_valid_float():
				builder_max_cost = maxf(0.01, value.to_float())
		"--lawspeaker":
			lawspeaker = value.strip_edges().to_lower()
		"--proposed":
			proposed_path = value.strip_edges()
			_proposed_given = true
		"--edit":
			edit_map = value.strip_edges()
		"--edit-size":
			var parts := value.to_lower().split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				edit_size = Vector2i(clampi(parts[0].to_int(), 2, 256), clampi(parts[1].to_int(), 2, 256))
		"--mind-log":
			mind_log_path = value
			_mind_log_given = true
		"--transcripts":
			transcripts_dir = value
			_transcripts_given = true
		"--test-version":
			_test_version = value
		"--test-protocol":
			_test_protocol = value
		"--test-move":
			var parts := value.split(",")
			if parts.size() == 2:
				test_move = Vector2i(parts[0].to_int(), parts[1].to_int())
		"--test-contest":
			var parts := value.split(",")
			if parts.size() == 3:
				test_contest_tile = Vector2i(parts[0].to_int(), parts[1].to_int())
				test_contest_tick = parts[2].to_int()
		"--test-reset":
			test_reset_tick = value.to_int()
		"--test-builder":
			test_builder = value
		"--test-exit-after":
			test_exit_after = value.to_float()
		"--test-exit-on":
			test_exit_on = value
		"--test-wait-players":
			test_wait_players = value.to_int()
		"--test-herds":
			test_herds = maxi(0, value.to_int())
		"--test-hold":
			var hold := value.split(",")
			if hold.size() == 2:
				test_hold_tick = hold[0].to_int()
				test_hold_orders = hold[1].to_int()
		"--screenshot":
			screenshot_path = value
		"--test-show":
			test_show = value.split(",", false)
		"--test-door":
			test_door_tick = value.to_int()
		"--test-chest":
			test_chest = value
		"--test-click":
			test_click_after = value.to_float()
		"--test-fullscreen":
			test_fullscreen_after = value.to_float()
		"--test-azimuth":
			test_azimuth = value.to_float()
		"--test-yaw":
			test_yaw = value.to_float()
			_test_yaw_given = true
		"--test-hover":
			var parts := value.split(",")
			if parts.size() == 2:
				test_hover_tile = Vector2i(parts[0].to_int(), parts[1].to_int())
