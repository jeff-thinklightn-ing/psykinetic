class_name Main
extends Node2D
## Builds the test room, starts networking, and turns clicks into orders.
## This is view/input glue plus level setup: on the server it asks World and
## the MultiplayerSpawner to create entities; it never touches entity state.

const FLOOR_SOURCE := 0
const FIRE_SOURCE := 2
const DOOR := "res://sim/door.gd"
## --test-herds: a set of herds, each about a cell of its own (Main._test_herds).
const TEST_HERDS := [["deer", "deer", "deer", "deer", "stag"], ["rabbit", "rabbit", "rabbit"], ["boar", "boar"],
	["wolf", "wolf", "wolf"]]
const PILE := "res://sim/ground_pile.gd"
## Keys for things, in both schemes: F picks up (your cell, the one under the
## cursor, or one beside), G puts down what is in your hand, T throws it at
## the cursor.
## The item actions a key tap orders (Keys: pick_up, drop, throw).
const ITEM_ACTIONS: Array[String] = ["pick_up", "drop", "throw"]
const BANDAGE_HOLD_MSEC := 500
## The one grey every wall face is drawn in, 0..1: darker than the floor,
## a few steps above the void, the same whichever way the face points.
const WALL_VALUE := 0.18
## Alpha of the near walls (the south and east edges of walkable cells,
## facing the camera), drawn as one layer so they never stack up opaque.
const NEAR_WALL_ALPHA := 0.3
## WASD only: the camera leans toward where the cursor is on the screen.
## The cursor's offset from the middle, each axis over half the screen
## (so -1..1), counts from the edge of a dead zone CAMERA_LEAN_DEADZONE
## across (15% of the screen) out to the screen's edge, which leans
## CAMERA_LEAN_CELLS; eased with a time constant of CAMERA_LEAN_EASE
## (about 300 ms to settle).
const CAMERA_LEAN_DEADZONE := 0.15
const CAMERA_LEAN_CELLS := 3.0
const CAMERA_LEAN_EASE := 0.1
## WASD, 3D: degrees of yaw per screen pixel of horizontal middle drag.
const DRAG_DEGREES_PER_PX := 0.25
## 3D, WASD: a middle drag is a turn or a pitch peek by whichever axis it
## first moves this far on, and stays that for the rest of the drag.
const DRAG_AXIS_PX := 6.0
## WASD: the facing sent for a player standing still changes at most this
## often (seconds).
const FACE_SEND_INTERVAL := 0.15
## WASD into someone who will not move: the step (a bump) is sent at most
## this often, and one into a wall not at all.
const BUMP_SEND_INTERVAL := 0.25
## 555, ui's side: how long the HUD says her step dropped, and the words per
## cold step (Companion.bond_step); a warm step says nothing on the HUD.
const BOND_HINT_SECONDS := 8.0
const BOND_WORDS := {"cooling": "%s is quiet", "wary": "%s keeps her distance", "sullen": "%s hangs back", "apart": "%s walks apart"}
## Camera: the fraction of the remaining distance to the player closed per
## second, as an exponential rate. Higher is tighter.
const CAMERA_FOLLOW_RATE := 6.0
## Where the camera starts (and stays on a dedicated server): the chamber.
## What is drawn where there is no map: near-black, so walls along the void
## stand apart from it.
const VOID := Color(0.05, 0.05, 0.06)
## The 2D view's void outdoors: the forest floor.
const FOREST_VOID := Color(0.1, 0.17, 0.09)
const MONSTER := "res://sim/monster.gd"
const PUSHABLE := "res://sim/pushable.gd"
const PLAYER := "res://sim/player.gd"
const COMPANION := "res://sim/companion.gd"
const RESIDENT := "res://sim/resident.gd"
## Residents' bodies (decision 333): at most so many in a zone, its towns'
## residents looked over every so many ticks (_sync_residents).
const RESIDENTS_MAX := 12
const RESIDENT_SYNC_TICKS := 30
## Residents' voices (decision 336): a line goes to a resident within so
## many cells of its speaker (or one it names); an ask waits for the
## resident mind at most so many ticks, then is dropped.
const RESIDENT_EARSHOT := 2
## How near a friend a left click walks before talk opens (decision 454).
const TALK_REACH := RESIDENT_EARSHOT
## How long a talk walk waits to arrive before it is forgotten.
const TALK_WAIT_MSEC := 15000
const RESIDENT_ASK_TICKS := 150
## How often residents look for a player to hail (decision 554): every second.
const HAIL_CHECK_TICKS := 10
## How often the bodies' work is read from the sim (decision 566): every second.
const WORK_CHECK_TICKS := 10
## The work props a level stands (566 amended: a chopping block in the
## woodlot, a log pile by the store; 567-style doorless solid buildings,
## maps' to place, art-kit's slots): a body stands beside one, facing it,
## so the stroke lands on it.
const CHOPPING_BLOCK := "building.chopping_block"
const WOODPILE := "building.woodpile"
## How far from the store's cell its woodpile may stand, in cells.
const WOODPILE_REACH := 4
## The walk home from a site is reckoned this much over the route's cells at
## the body's pace (grass, slopes and diagonals slow it), so it is home
## when the yield lands (521 amended).
const WALK_HOME_SLACK := 1.3
## Steps a shepherd or herder stands at one spot of the ground before the next
## (566 amended, phase 2: a slow round of the pasture or the fold).
const HERD_DWELL := 60
## The seasons the flock is sheared in (economy's _flock_turn: once each).
const SHEARING_SEASONS: Array[String] = ["spring", "autumn"]
## A town's homes: the map's huts and houses linked to nothing within so
## many cells of its store, each with room for so many.
const HOME_TILES := 24
const HOME_ROOM := {"building.hut": 2, "building.house": 3}
## The level in play (Level.load_level): its entities, spawned by the
## server in this order, which is also entity id order (each spec built by
## EntityFactory on every peer); the starts, a joining peer's player taking
## the first free one; where the camera first looks.
var level: Dictionary = {}
var level_entities: Array[Dictionary] = []
var player_starts: Array[Vector2i] = []
var level_centre := Vector2i.ZERO
var map_name := ""
## Indexed by join order.
const PLAYER_TINTS: Array[Color] = [
	Color(0.35, 0.65, 1.0), Color(0.4, 0.9, 0.45), Color(1.0, 0.85, 0.3), Color(0.95, 0.5, 0.9),
	Color(0.4, 0.9, 0.9), Color(1.0, 0.6, 0.3), Color(0.75, 0.75, 0.8), Color(0.7, 0.55, 1.0),
]

## World pixels the cursor must travel with the right button held before a
## shove becomes an aimed toss.
const TOSS_DRAG_MIN := 10.0
const TOSS_AIM_LENGTH := 26.0
## A move click off the floor goes to the nearest walkable cell within this
## many tiles of the click point (Euclidean on the ground plane), or nowhere.
const SNAP_RANGE := 3.0
const COMPANION_TINT := Color(0.45, 0.95, 0.85)
## What a companion says as she falls.
const COMPANION_DEATH_LINES: Array[String] = ["Go on... without me.", "I'm sorry.", "Tell them I tried.", "Keep... going."]
## Ticks between a player dying and reappearing at a start tile.
const RESPAWN_TICKS := 20
## Ticks between looks at who stands at a temple counter (decision 434).
const TEMPLE_COUNTER_TICKS := 5
## Whether the fallen are brought back at a temple or a healer's hut
## (decision 396); off, every death respawns as before (tests of the old
## respawn turn it off).
var returns := true
## A player is not put down (on respawn or on coming back) with a hostile
## this close to the intended tile; it goes to the safest start tile instead.
## A companion waiting farther than this from where her player comes back
## (a start tile, a town) is put beside them (decision 705).
const REJOIN_NEAR := 8
const SPAWN_SAFE_DISTANCE := 5
## Ticks a newly spawned player is ignored by monsters, unless it moves or
## attacks first.
const SPAWN_GRACE_TICKS := 30
## A player arriving through a link or over an edge is sheltered this long at
## most (decision 661): no monster targets them and nothing harms them till
## their client's "view_ready", an act of theirs, or this.
const ARRIVAL_SHELTER_TICKS := 60
## A player sheltered on arriving is not sheltered again for this long
## (decision 661): crossing back and forth gets spawn grace alone.
const SHELTER_COOLDOWN_MSEC := 30000
## Commands that keep an arrival's shelter (decision 661): talk and looking.
## Any other ends it at once, so nobody stands untouchable doing things.
## Levels' named rooms read for a zone not open (_rooms_of), by zone.
var _rooms_read := {}
## By peer: when their companion's whereabouts were last told
## (_tell_whereabouts), msec.
var _where_told := {}
## How long a view's build or a call for her goes before the line is said
## again.
const WHERE_AGAIN_MS := 2000
const SHELTER_KEEPS: Array[String] = ["say", "party", "face", "greet", "town_sheet", "view_ready"]
## A client that loses the server it played on tries again this often, for
## this long (decision 240).
const RECONNECT_EVERY := 2.0
const RECONNECT_FOR := 180.0
## The console's restart: what a dedicated server exits with, which the
## systemd unit (Restart=on-failure) starts again; and the seconds left at
## which players are told again, after the first word.
const RESTART_EXIT_CODE := 75
const RESTART_WARNINGS: Array[int] = [10, 3]
## --test-exit-on: the ticks a client in the game sees after the file appears.
const TEST_EXIT_SETTLE_TICKS := 20
## With --state, the server writes its snapshot this often.
const SNAPSHOT_EVERY_TICKS := 30
## A dead level entity (monster killed, crate broken) comes back at its spawn
## tile once this many ticks have passed since it died...
const RESPAWN_DELAY_TICKS := 600
## ...and no player is within this many tiles of that spawn tile.
const RESPAWN_MIN_DISTANCE := 6
## At most one comes back in a zone this often, the one farthest from every
## player first, so a zone opened after a long sleep (or cleared and left)
## does not bring every due one back at once (decision 382).
const RESPAWN_STAGGER_TICKS := 60
## For RESPAWN_ARRIVAL_TICKS (60 s; 10 s before 382 amended (2)) after a
## player joins or comes into the zone, nothing comes back within this many
## tiles of them, nor in their line of sight.
const RESPAWN_JOIN_DISTANCE := 12
const RESPAWN_ARRIVAL_TICKS := 600
## A camp falls (decision 429) when for CAMP_FALL_TICKS (10 s) no living
## monster of its holder's side stands within its radius + CAMP_DEFEND_MARGIN
## and a player stands within its radius; looked at every CAMP_CHECK_TICKS.
const CAMP_FALL_TICKS := 100
const CAMP_DEFEND_MARGIN := 2
const CAMP_CHECK_TICKS := 10
## The far tier hands over to records (decision 352): a monster FAR from
## every player and companion for RETIRE_AFTER_TICKS, more than
## retire_tiles from all of them, calm and with nowhere the world tick
## would walk it (Monster._world_tick moves only one going back or on a
## march), is kept as a record on its Zone instead of a node (_retire); it
## is made again, as it was, once someone comes within recall_tiles
## (_recall). Both are past what a client is sent (Interest leaves at about
## 44 cells), so nobody sees one go or come. Looked at every
## RETIRE_EVERY_TICKS: records within recall_tiles are made again nearest
## first for RECALL_BUDGET_USEC at most (the rest on the next pass), but
## all within RECALL_NOW_TILES (where Interest would already show it: only
## after a jump, a join or a travel) at once; then monsters are retired
## for RETIRE_BUDGET_USEC at most.
@export var retire_tiles := 80
@export var recall_tiles := 70
const RECALL_NOW_TILES := 44
## A player joining: the records within RECALL_JOIN_NOW_TILES of where they
## come in are made again at once (spawn safety looks for hostiles there),
## the rest within recall_tiles nearest first over the next ticks, for
## RECALL_BUDGET_USEC a tick (_recall_due), while their client loads the
## map: one join's hundred or two do not land on one tick.
const RECALL_JOIN_NOW_TILES := 12
const RETIRE_AFTER_TICKS := 300
const RETIRE_EVERY_TICKS := 10
const RETIRE_BUDGET_USEC := 2000
const RECALL_BUDGET_USEC := 4000

## Server only: peer id -> that peer's player entity.
var _players: Dictionary[int, Player] = {}
## Server only: peer id -> the player_id it joined with.
var _peer_ids: Dictionary[int, String] = {}
## Builder mode on this server or host (null when it is off: no key, no stub).
var _builder: BuilderHost
## Builder mode on this client (K): selecting, asking, the ghost.
var _builder_ui: BuilderUI
## Server only: everyone who has ever joined, by player_id. Saved in the
## snapshot, so a player comes back where they left off, in their colour.
var _records: Dictionary[String, PlayerRecord] = {}
## Server only: peer id -> tick at which its dead player comes back.
var _respawn_at: Dictionary[int, int] = {}
## Server only: player_id -> that player's live companion.
## The world map the towns' buildings are read from (_sync_residents).
var _world_map: WorldMap
## Server: each regenerating level's state (decision 465), area ->
## {generation (0 until its first), at_step (the world step of it)}; saved
## as the snapshot's "regen".
var _regen: Dictionary = {}
## A level-placed captive (decision 518): camp place id -> the worker ids it
## holds from the level, placed once; saved ("placed_captives").
var _placed_captives: Dictionary = {}
## The sought's bands (613, enemy-ai's side): sought id -> {place (the place
## it was placed at), stood (its band stood there for that placing)}; saved
## ("sought_bands"), so a band killed is not stood again on a restart.
var _sought_bands: Dictionary = {}
## How far beyond a sought's place its band may stand (cells): the place's
## radius and this, inside the place's room (_stand_band).
const BAND_REACH := 2
## The alms runs (decision 546, npc's side): town -> {who, gold, started,
## at_altar, back_at, rolled, lost}, Pip's run down with the altar's gold;
## saved ("alms_runs"). And the players who have learned Aldous's secret
## ("crypt_told"): only then may a run go wrong.
var _alms_runs: Dictionary = {}
var _crypt_told: Dictionary = {}
## The runners away by this hand (a run, or a companion of his name out
## with a player), so only this hand brings them back ("runner_out").
var _runner_out: Dictionary = {}
var _runs_day: Dictionary = {}
## A client: the generation of the regenerating level its player is in, as
## the "map" message said (0: a level that does not regenerate).
var map_generation := 0
## Residents' voices (decision 336): one mind for them all, made on first
## use; the asks waiting for it ({body: instance id, ask, at: tick}), one per
## resident; the ask out, by serial.
var _resident_mind: CompanionMind
var _resident_asks: Array[Dictionary] = []
## Residents speaking unprompted (decision 554): the msec of the last hail
## in each player's hearing, the tick of each player's last blow given
## (_hail_struck), how many ticks the resident mind took over its last
## answer (a slow mind: no hails), and when each resident last found
## nothing to say to a player (worker id + player id -> tick).
var _hail_at: Dictionary = {}
var _blow_at: Dictionary = {}
var _mind_last_ticks := 0
var _hail_tried: Dictionary = {}
var _resident_fight_at: Dictionary = {}  # worker id -> the last tick a hostile was near them or their listener (675, npc's side)
var _hail_heard: Dictionary = {}  # player id -> {cue text: day}: no two residents tell one player the same thing in a day
var _hail_greetings: Dictionary = {}  # player id -> {day, n}: greetings by standing a player heard today, capped at hail.greetings_a_day
var _notes: Dictionary = {}  # zone -> the "notes" list last sent (decision 643): the sought's door notes.
var _rumour_said: Dictionary = {}  # "town|player id|day" -> true: the sought rumour told on a greeting (decision 643).
var _greet_at: Dictionary = {}  # "worker id|player id" -> msec of the last click greeting (560): one a greet.again_seconds
## Visible work (decision 566): a site's spot for a body (site id -> {cell, face}),
## what was last told of each house's waking ("town id|code" -> bool), and
## the tests' stand-ins for economy's trip and build (worker id -> ...).
var _site_spots: Dictionary = {}
var _awake_sent: Dictionary = {}
var _trip_stub: Dictionary = {}
var _build_stub: Dictionary = {}
## The tests' stand-in for economy's Towns.field_work (566 amended, phase 2):
## town -> whether the farmer's field work counts now.
var _field_work_stub: Dictionary = {}
## The farmer's one sack a harvest (566 amended, phase 2): worker id -> the
## crop stage it was carried for ("harvested"); gone when the stage turns.
var _sacks: Dictionary = {}
## The hoeing's place along the field's rows: worker id -> the index of the
## cell worked next (_row_cells).
var _rows: Dictionary = {}
## Talk with no panel (decision 536): the offer standing for each player,
## player id -> {worker, id, title, at, zone}: what a resident last spoke to
## them, taken by a yes, a name or an amount said back; one per player, not
## saved (a restart forgets it as it forgets a conversation).
var _standing: Dictionary = {}
var _resident_out: Dictionary[int, Dictionary] = {}
## Server only: claims asks waiting (decision 378), each {body, worker,
## person, from, line, at}, one per resident; those out, by serial; when
## each resident was last asked.
var _claims_asks: Array[Dictionary] = []
var _claims_out: Dictionary[int, Dictionary] = {}
var _claims_at: Dictionary[String, int] = {}
var _resident_serial := 0
## Serial -> worker id: a resident's card asked of the model (decision 398),
## once, the first time they are spoken to; the plain card stands until then.
var _resident_cards_out: Dictionary = {}
var _companions: Dictionary[String, Companion] = {}
## Each player's companion's walk leading them (decision 551), by player id:
## kept across the zones it crosses, and stopped, to be taken up again.
var _guides: Dictionary[String, Guide] = {}
## What she refused to lead each player to (551 phase 2), by player id ->
## goal key -> {day, reason, as_far}: refused again the rest of that day
## (talking her round waits); and the place she offered to go as far as,
## by player id ({day, to}), taken by "lead on".
var _guide_refused: Dictionary[String, Dictionary] = {}
var _guide_offers: Dictionary[String, Dictionary] = {}
## Server only: the companions whose voice is on the Claude API (decision
## 363, the console's `mind claude`), by player id -> model id; for this
## session only, so a companion who comes back is wrapped again.
var _claude_voices: Dictionary[String, String] = {}
## Server only: the companions the last room rebuild brought back, by name.
var _revived: Array[String] = []
## Server only: what happened, in words, for companion minds and the log.
var party_log := PartyLog.new()
## Speech carries this far (cells, in its own zone): chat and a companion's
## lines reach the players within it, and a companion hears her player's
## words only from this close.
const HEARING_RANGE := Companion.HEARING_RANGE
## A talking monster's words for a yes or a sum said with no offer standing
## (629 amended; Jeff: "yes didn't do anything"): asked for the sum, and with
## nothing to offer (a pact on).
const YES_TO_WHAT := "Yes to what? Name your gold."
const NOTHING_STANDS := "There is nothing between us to say yes to."
## The draugr's zone before the barrow's redesign -> after (548 amended;
## dungeon's barrow_two_depths.md: he stands in barrow_deep, barrow_lair
## retires): a paid deal is keyed by the zone after, whichever he stands in.
const PAID_ZONE_MOVED := {"barrow_lair": "barrow_deep"}
## A chat line that starts with this is party chat: to every player on the
## server, whatever their zone; no companion hears it.
const PARTY_PREFIX := "/p "
## "/w words": a whisper, heard only WHISPER_RANGE off (Senses.NOISE_WHISPER).
const WHISPER_PREFIX := "/w "
const WHISPER_RANGE := Senses.NOISE_WHISPER
## Which mind new decisions use: "scripted" or "ollama" (console: mind ...).
var mind_kind := "scripted"
## Server only: level_entities index -> the entity holding that slot now.
var _alive_slots: Dictionary[int, GridEntity] = {}
## The towns whose residents have bodies now, by place id (_town_near).
var _towns_near := {}
## The herds registered as a keeper (decision 367), so a second boot swaps it.
var _herds_kept: Object = null
## Server only: level_entities index -> tick its entity died or broke.
var _dead_since: Dictionary[int, int] = {}
## Zone name -> the tick its last respawn came back (RESPAWN_STAGGER_TICKS).
var _respawned_at: Dictionary[String, int] = {}
## Zone names woken since their last respawn check: their dead are spaced
## out on it (_space_after_wake, decision 382 amended (2)).
var _woken: Dictionary[String, bool] = {}
## Peer -> the tick its player was last put down (a join, a zone entered, a
## respawn): the wider no-respawn radius while RESPAWN_ARRIVAL_TICKS last.
var _arrived_at: Dictionary[int, int] = {}
## Server: when (Time.get_ticks_msec) each player id was last sheltered on
## arriving (decision 661); zones' ticks differ, so the clock is the machine's.
var _sheltered_at: Dictionary[String, int] = {}
## Camp place id -> the tick it was first seen undefended with a player in
## it (decision 429); not saved, so a restart starts the clock again.
var _camp_clear_since: Dictionary[String, int] = {}
## Peer -> the closed link (decision 463) it was last told of, so stepping
## about on it says so once.
var _told_closed: Dictionary[int, Vector2i] = {}
## Peer -> the burial niche's edge it last pressed on (608), so pressing
## on at it says "Only the dead lie here." once.
var _told_niche: Dictionary[int, Vector3i] = {}
## "<player id>@<zone>" -> the generation the draft line was said to them in
## (608 amended, _tell_draft): once a generation; a restart says it again.
var _draft_told: Dictionary[String, int] = {}
# Server console: lines from stdin (read on a thread) and from --admin-port.
var _stdin_thread: Thread
var _stdin_mutex := Mutex.new()
var _stdin_lines: Array[String] = []
## Set on exit: the stdin thread stops at its next look (decision 299).
var _stdin_stop := false
## The zones' entities are gone, the world saved before they went (decision 299).
var _released := false
var _admin: TCPServer
var _admin_clients: Array[StreamPeerTCP] = []
var _test_target := Vector2i.ZERO
## --test-fight: when the last strike was ordered (msec).
var _test_fight_at := -100000
var _test_ordered := false
var _test_arrived := false
var _test_contested := false
var _test_contest_reached := false
var _test_exiting := false
var _test_reset_sent := false
var _test_door_sent := false
## Everything said this session (speech, last words, chat), shown with Tab.
var talk: TalkPanel
## Speech bubbles over the speakers, in either view.
var bubbles: SpeechBubbles
## 2D: a bubble's tail this many world px over an entity (above its name).
const BUBBLE_OVER_2D := 40.0
## The chat box (Enter opens it, Esc cancels); while it is open the game's
## keys do nothing.
var _chat_box: LineEdit
## When this peer last sent a chat line (msec), and, on the server, when
## each player last did (tick).
var _chat_sent_at := -100000
var _chat_tick: Dictionary[int, int] = {}
## A chat line: at most this long, at most one per this many seconds.
const CHAT_MAX_CHARS := 200
const CHAT_INTERVAL := 2.0
## Client: whether this peer has ever had a player, to tell a rejected join
## from a later disconnect.
var _had_player := false
## Client: the server said why it turned us away; keep that message up.
var _rejected := false
## Client: trying to get back to the server (decision 240).
var _reconnecting := false
## "already connected" refusals tried again in a row (721: an older server
## holding this player's dropped link), at most ALREADY_TRIES, each after
## ALREADY_RETRY_SECONDS.
var _already_tries := 0
const ALREADY_TRIES := 12
const ALREADY_RETRY_SECONDS := 5.0
## While reload_zone rebuilds a zone: the players in it were standing there,
## so they stay, monsters near or not (no spawn safety's start tile).
var _reloading := false
## Each level's files as last read (_level_stamp), for the console's reload.
var _level_stamps: Dictionary[String, String] = {}
## Client: told once that the server runs a newer build of the same protocol.
var _told_newer := false
## Server: when the console's restart is due (msec), -1 when none is, and
## what the server exits with then (RESTART_EXIT_CODE, or 0 for stop).
var _restart_at := -1
var _restart_exit := RESTART_EXIT_CODE
var _restart_why := ""
## RESTART_WARNINGS already given (or longer than the countdown).
var _restart_told: Array[int] = []
## Right button held on this entity: released without a drag it is a shove,
## dragged it is a toss in the dragged direction.
var _toss_target: GridEntity
## E held (decision 329): bandaging once held BANDAGE_HOLD_MSEC (the one
## under the cursor beside you, else yourself: World.try_bandage); let go
## sooner, a tap: what was under the cursor opens (_tap_e).
var _e_held := false
var _e_since := 0
var _e_target: GridEntity
var _e_door: Door
## The off hand raised with the right button (World.off_hand): "block",
## "draw", or "" (the button shoves and tosses).
var _stance := ""
## Said when a player reaches for a boss's thrown axe (603 amended, a draft
## for Jeff: it is bound to him till the pact is won).
const BOUND_AXE_WORDS := "The axe will not leave his hall."
## The thing on the cursor (decision 593): {kind: "bandage", slot}; while
## set, a left click applies it and never attacks. {} for none.
var _cursor_item := {}
var _toss_from := Vector2.ZERO
## WASD: the camera's lean toward the cursor, in grid units (see
## CAMERA_LEAN_*).
var _lead := Vector2.ZERO
## The ground point under the cursor this frame, picked once after the
## camera has moved (see _update_pick): the hover shows it and every
## click this frame uses it, so the two always agree.
var _pick_grid := Vector2(NAN, NAN)
## 3D: the screen point a middle drag went down at (x NAN when none), and
## what it is: UNDECIDED until it has moved (let go so, it does nothing),
## then TURN or PITCH (WASD) or PAN (click).
enum Drag { UNDECIDED, TURN, PITCH, PAN }
var _drag_from := Vector2(NAN, NAN)
var _drag := Drag.UNDECIDED
## The middle drag began with Ctrl held: a pan (671 amended).
var _drag_pan := false
## Click scheme, 3D: W/S or A/D were held last frame (their release
## springs the tilt back and settles the turn).
var _tilting := false
var _turning := false
## WASD: when the facing and the last bump were sent, in msec.
var _face_sent_at := 0
var _bump_sent_at := 0
## --test-walk: which entry is held, and when it started (msec); samples
## of the local player's shown position, [msec, grid], for the report.
var _walk_index := -1
var _walk_since := 0
## --test-walk-on-wind: when the local player's own wind-up began (msec), or -1.
var _wind_at := -1
## The local player's own wind-up as the client last heard it: until (msec)
## and the way to its target (_wind_up_held).
var _own_wind := {"until": 0, "way": Vector2.ZERO}
var _walk_samples: Array[Array] = []
## --test-smooth's meter (net/smooth_meter.gd), made with the first frame.
var _smooth_meter: RefCounted = null
var _smooth_camera: RefCounted = preload("res://client3d/camera_ease.gd").new()
## Every wall face, far and near, for turning the view.
var _walls: Array[WallEdge] = []
## Left button held after a move click: the cell it last sent the player
## to. Moving the cursor to another cell retargets; NONE when not held.
const NONE := Vector2i(-1, -1)
var _held_target := NONE
## 683: the hold has steered the walk since its click (a step or a new
## cell sent): letting go then ends the walk at the step under way.
var _held_steered := false
## Decision 678: the held walk's line (a key, or the button held near the
## body): where it is anchored and its way (grid units); INF for none.
var _walk_origin := Vector2.INF
var _walk_along := Vector2.ZERO
## Off the line by more than this (cells; the DDA keeps within half), the
## line is anchored again where the walk is.
const LINE_OFF := 0.75
## 678 amended: a change of the held way under this goes on from the walk's
## point on the line it was on, rather than a new line from the walk's end
## cell: from the cell, the line's first pick is the straight step every
## time, and a way that shifts each frame (a hand on the mouse, the camera
## following) walked straight, never taking the diagonals.
const LINE_TURN := deg_to_rad(20.0)
## The left button held with the cursor this near the body (cells) steers:
## a walk the cursor's way on 678's line, one steady run, never a cell
## reached and set off from again (Jeff: "placing the cursor to move on a
## diagonal 1 square in front of me ... the run camera stutter").
const STEER_CELLS := 2.5
## 678 amended: held farther, the walk is planned again when the cursor's
## way drifts HELD_DRIFT off the last plan's, or fewer than HELD_PLAN_LEFT
## of its steps are left (each plan is a straight line from where it starts,
## walked a few steps, so it keeps its slope: planned again every step, it
## took only each line's first step, the straight one, and never the
## diagonals), a straight step's time apart at most; at once on a turn
## (held_turns).
const HELD_DRIFT := deg_to_rad(12.0)
const HELD_PLAN_LEFT := 3
## When the held button last sent a new walk (Time msec): one a step's
## time at most (the jitter fix; Jeff: "movement with the mouse and left
## click seems slightly jumpy").
var _held_sent_at := 0

## The 3D view (the default; see Net.renderer); the 2D nodes are hidden.
var _client3d: Client3D
## Town id -> {kind: {state, level}}: the towns' buildings as the server
## last told ("town", decision 297), for the view's buildings.
var town_states := {}
## Town id -> {map building code: awake} as the server last told ("town"
## "awake", decision 566), for the window light; the view's set_awake.
var town_awake := {}
## Holdings place id -> the sheep its fold holds, as the server last told
## (economy's "folds" message, 640), for the beasts the view draws there.
var fold_counts := {}
## The telegraphs showing on this client (decision 602): id -> their data.
var telegraphs := {}
## Each level's damaged roofs (their indices) as this client was last told
## ("roofs", decision 383), for the view.
var roof_states := {}
@onready var ground: TileMapLayer = $Ground
## The node the zone World is in keeps its entities under (one per zone,
## under $YSort/Entities, named for it), and its spawner: both per zone.
var entities: Node2D
@onready var near_walls: CanvasGroup = $NearWalls
var spawner: MultiplayerSpawner
## The zone the views draw (a host's own player's), and the travel under way
## (a despawn that is no death).
var _view_zone := ""
## Decision 660: clearings held while the view's ground fields read the
## terrain on a worker, and their redraws while its room is being built.
var _held_clearings: Array[Callable] = []
var _held_redraws: Array[Callable] = []
var _travelling := false
## Where each fallen player fell (peer -> cell), till they rise: they hear
## from there.
var _fell_at: Dictionary[int, Vector2i] = {}
@onready var cursor: Polygon2D = $Cursor
@onready var ripple: ClickRipple = $Ripple
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $HUD/Label
@onready var debug_overlay: Label = $HUD/Debug
## The HUD's compass (top right), turned so N is the level's north on screen.
var compass: HudCompass
## The controls, down the left (H shows and hides them).
var hint_panel: HintPanel
## The options (O): sound volumes; other trees add their sections.
var options_panel: OptionsPanel
## The options' own canvas layer, above the HUD (layer 1) and the main menu.
var _options_layer: CanvasLayer
const OPTIONS_LAYER := 30  # Above the main menu's own layer (20) as well as the HUD's.
## The options were opened from the main menu, which comes back when they close.
var _options_from_menu := false
## Esc's menu (GameMenu; the game never pauses), the main menu (MainMenu) while it shows, and
## the join flow's screen (ConnectScreen) while it shows; null otherwise.
var game_menu: GameMenu
var main_menu: MainMenu
var connect_screen: ConnectScreen
## The title screen's music while the main menu shows (656), let go on Play; null otherwise.
const TitleMusic := preload("res://client3d/title_music.gd")
const FreeNet := preload("res://net/free_net.gd")
var title_music: TitleMusic
## _go_online was called (Play once; Change server reconnects instead).
var _went_online := false
## The connect screen shows the join in progress: it goes once the player is in.
var _connect_joining := false
## The last tick this view saw, for F3.
var _hud_tick := 0
## The hint over what the cursor is on ("E  open"), outlined, by the cursor.
var _context_hint: Label
## The hint's inputs at its last working-out (ui's perf pass): the picks and
## the entity loop run again only when the cursor moved, the world ticked,
## or what is under the cursor or the typing state changed.
var _hint_mouse := Vector2(-1.0, -1.0)
var _hint_tick := -1
var _hint_under_id := 0
var _hint_typing := false
var _hint_words := ""
## The compass's place, worked out again when the player's cell or the tick changes.
var _place_tile := Vector2i(-100000, -100000)
var _place_tick := -1
var _place_words := ""
## What the counter panel was last placed from (the pack's rect, the shop's box, its own size).
var _counter_placed_from: Array = []
## --test-show=hint: the thing the hint is shown on, as if the cursor were on it.
var _test_hint_thing: GridEntity
## --test-show=herbs: the cell whose pile the hint is shown for (NONE: none).
var _test_hint_cell := Vector2i(-100000, -100000)
## --test-show=counter: the pack panel, for the counter screen's sample.
var _test_counter_shown: Node
## The aim ring and outline wear the draw's look (Client3D.draw_look): reset once it ends.
var _draw_shown := false
## The one-time line the first time a townsperson is near (Net.hinted_talk), and when it goes.
var _talk_hint: Label
## Where F12's screenshots go unless settings.cfg says (decision 538).
const DEFAULT_SCREENSHOT_DIR := "user://screenshots"
## The last screenshot saved (F12), "" for none or a failure.
var last_screenshot := ""
## Where the local player last stood and since which tick, for the cover
## cue (decision 515): stillness is this view's own count, since
## last_step_tick is stamped on the server alone.
var _still_tile := Vector2i(-100000, -100000)
var _still_since := 0
## Her bond's step as last seen, per companion name (555, ui's side), so a
## drop is told once; the hint's words and until when (seconds on the ticks clock).
var _bond_seen: Dictionary = {}
var _bond_hint := ""
var _bond_hint_until := 0.0
var _talk_hint_until := 0.0
## A town's read-out ("party" lines from "Town": the dole, 353) by the area
## the player was in when it came: shown on the big map's area box, not in
## the talk log (Jeff's castle F12, 2026-10-22).
var town_notes: Dictionary = {}
## Economy's "return" message while the local player lies dead (396
## amended, ui's side): {by, where, seconds}, and the client's clock when it
## came, for the countdown; {} once they are back.
var _return_told: Dictionary = {}
var _return_at := 0.0
## The down screen (587, ui's side) and everyone's wait as the return
## message last said it ({all_fallen: seconds}; 0 calls it off), with the
## client's clock when it came.
var down_screen: DownScreen
## The zone arrival card (660, ui's side): perf's phased arrival calls
## begin(zone_display_name()) as a crossing starts and finish() when the
## rebuild is done.
var arrival_card: ArrivalCard
## The named room the local player's shown cell is in (665, ui's side;
## Level.room_at), and when each room was last left (msec), so stepping
## out and back within ROOM_AGAIN_MSEC says nothing.
var _room_here := ""
var _room_left_at: Dictionary = {}
const ROOM_AGAIN_MSEC := 10000
var _fallen_wait := 0
var _fallen_wait_at := 0.0
## The bow's aim while drawn (the archery aim, ui's side): the angle from
## the archer to the mouse on the grid (radians, Vector2.angle(), x as 0),
## set every frame while aim_drawn; pc-character turns the body from them.
var aim_angle := 0.0
var aim_drawn := false
## The cell on the arc the aim points at (sent as "at" beside the angle).
var _aim_mark_cell := Vector2i.ZERO
## A fixed aim point on the grid for a shot (--test-show=aim); NAN for the mouse.
var _aim_fixed := Vector2(NAN, NAN)
## When the arc first showed, for its fade-in (msec).
var _aim_since := 0
## The 2D view's arc, made on first use.
var _aim_line: Line2D
## Talking with a town's person (536, ui's side: no panel; the say line, their speech, the HUD).
## Channels this view has seen (544, ui's side): channeler instance id ->
## [the tick first seen, its channel_until], so the ring's course runs from
## when it was first seen to its end.
var _channel_seen: Dictionary = {}
## The offer that stands with a resident for this player (npc's 536: the
## "offers" message's "standing" title, "" for none): said on the HUD
## line, taken by "yes" (Y, or typed).
var standing_title := ""
## The world map (WorldMapPanel; ui's step 5), M after the zone's big map.
var world_map_panel: WorldMapPanel
## Her card page (618, ui's side): C; what she has learned and how she fights, from world_state.
var card_page: CardPage
## The town status sheet (624, ui's side), and economy's "town_sheet"
## messages by town id (624, economy's side; {} for a town till one comes).
var town_panel: TownSheet
var town_sheets: Dictionary = {}
## When (msec) each town's rows were last asked for (_ask_town_sheet).
var _town_sheet_asked: Dictionary = {}
## A talking monster's deals as buttons (629, ui's side): opened by his
## "offers" message after E on him, watched by _update_deal.
var deal_panel: DealPanel
## The admin panel (672): F10 for an admin (admin_allowed); is_admin is the
## server's word ("admin" after the join); _admin_refused counts the
## server's refusals (logged as a count, never who).
var admin_panel: AdminPanel
## Feel tuning's window (673, ui's side): F7 in a local host.
var tuning_panel: TuningPanel
var is_admin := false
var _admin_refused := 0
## The notes pinned to doors (643, ui's side; npc's "notes" message): by
## zone id, {tile: text}; a zone's list arrives whole and an empty one
## clears it. The sheet one is read on, and the word at the cursor over
## a note's cell.
var zone_notes: Dictionary = {}
var note_sheet: NoteSheet
var _note_hover: Label
## A town's rows are asked for again no sooner than this after the last ask (ms).
const TOWN_SHEET_ASK_MSEC := 5000
## Each town's stage as its "town" message last said (591; "" before).
var town_stages: Dictionary = {}
## The counter screen beside the pack (CounterPanel; economy's job, 438).
var counter_panel: CounterPanel
## The player's pack, and an open chest or companion's pack (I; a right
## click on a chest or your companion).
var pack_panel: PackPanel
## The map of the zone you are in: a corner one always, the big one on M (decision 321).
var minimap: Minimap
## Items' icons for the pack panel (none drawn headless).
var item_icons: ItemIcons
## An open shop's goods, and the player's gold over the pack (ShopPanel).
var shop_panel: ShopPanel
## The barter window beside the pack (BarterPanel, 560, ui's side).
var barter_panel: BarterPanel
## The menus' sounds (UiSounds).
var ui_sounds: UiSounds
## The local player's gold, as the server last said ("shop" messages).
var gold := 0
## The last "counter" message, for ui's counter screen (decision 438).
var counter_data := {}
signal counter_told(data: Dictionary)
## The barter window's last "barter" message (decision 560), for ui's window.
var barter_data := {}
signal barter_told(data: Dictionary)
## Client: the world map's server data (decision 446, WorldNews.merge):
## {holdings: {place_id: [faction, strength]}, known_areas, known_places,
## party: [{name, area, kind}]}; world_changed after each "world" message.
var world_state := {}
signal world_changed
## A danger area shown on the ground (decision 602; the "telegraph" message):
## [param data] {id, source, kind, shape, cells, from_tick, lands_tick,
## zone}; ended, landed or given up. For the views (ui's decal) and sounds.
signal telegraph_started(id: int, data: Dictionary)
## F7 in a local host (decision 673): the tuning panel (ui's) shown or hidden.
signal tuning_panel_toggled
signal telegraph_ended(id: int, landed: bool)
## Server: what each player's world map is told (WorldNews), and the tick
## it was last looked at.
var _world_news: WorldNews
var _news_tick := -1
## A chest or companion right-clicked from afar: opened once in reach.
var _pack_wanted: GridEntity
## A friend left-clicked from afar (decision 454): talk opens once within
## TALK_REACH, if before _talk_until (msec).
var _talk_wanted: GridEntity
var _talk_until := 0
## 560, ui's side: the resident last greeted by a click (their bubble opens
## the talk bar), the bar itself (their name, Talk, Barter) and who it is for.
var _greeted_by_click: GridEntity
var _bar: PanelContainer
var _bar_name: Label
var _bar_barter: Button
var _bar_for: GridEntity
## The pack sounds asked for, "set entity" each, newest last (tests).
var sounds: Array[String] = []
var _test_chest_done := false
var _test_show_done := false
var _test_chest_walking := false
@onready var toss_aim: Line2D = $TossAim
## The map as parsed once at start: floor, fire, edges (see Terrain).
var _terrain: Dictionary = {}


func _ready() -> void:
	if not Net.edit_map.is_empty():
		# --edit: the level editor instead of the game; nothing goes online.
		get_tree().change_scene_to_file.call_deferred("res://editor/level_editor.tscn")
		return
	if Net.world_map:
		# --world-map: the world map editor instead of the game.
		get_tree().change_scene_to_file.call_deferred("res://editor/world_map_view.tscn")
		return
	# After every other node: see _process.
	process_priority = 10
	var probe := Vector2i(3, 5)
	if not ground.map_to_local(probe).is_equal_approx(Iso.tile_to_local(probe)):
		push_error("Iso math disagrees with the TileSet: %s vs %s" % [
			Iso.tile_to_local(probe), ground.map_to_local(probe)])

	near_walls.self_modulate.a = NEAR_WALL_ALPHA
	World.zone_switched.connect(_on_zone_switched)
	_build_talk()
	if Net.mode != Net.Mode.SERVER:
		_builder_ui = BuilderUI.new()
		_builder_ui.name = "BuilderUI"
		_builder_ui.main = self
		add_child(_builder_ui)
	if "hidden" in Net.test_show:
		_register_test_meadow()  # --test-show=hidden: a meadow of tall grass and nobody in it (decision 515's shot).
	_load_level(Net.map_name if not Net.map_name.is_empty() else Level.DEFAULT_MAP)
	if Net.renderer == "3d" and Net.mode != Net.Mode.SERVER and DisplayServer.get_name() != "headless":
		_show_3d()
	GridEntity.draws_2d = _draws_2d()
	_paint_level()
	# The minimap was made (_build_talk) before there was a level, and a
	# host's boot draws this map no more (_view_zone): drawn here.
	_door_marks_at = -1  # A new level: its doors.
	minimap.rebuild(level)
	Iso.set_azimuth(Net.test_azimuth)
	_apply_azimuth()
	camera.position = Iso.tile_to_local(level_centre)
	RenderingServer.set_default_clear_color(FOREST_VOID if _terrain.get("outdoor", false) else VOID)

	World.ticked.connect(_on_world_ticked)
	World.stepped.connect(_on_world_stepped)
	# A zone asleep is not synced: its towns are near no more, till its first
	# sync awake says (decision 355).
	World.zone_slept.connect(func(each: Zone) -> void:
		for place_id: String in _towns_near.keys():
			if str(World.holdings.place(place_id).get("area", "")) == each.name:
				_towns_near.erase(place_id)
		_retire_sleeping(each))
	World.zone_woke.connect(func(each: Zone) -> void: _woken[each.name] = true)
	if Net.test_exit_after > 0.0:
		get_tree().create_timer(Net.test_exit_after).timeout.connect(_on_test_exit)
	if Net.test_exit_on != "":
		_exit_on_file()
	if Net.test_click_after > 0.0:
		get_tree().create_timer(Net.test_click_after).timeout.connect(_test_click)
	if Net.test_fullscreen_after > 0.0:
		get_tree().create_timer(Net.test_fullscreen_after).timeout.connect(Net.toggle_fullscreen)

	# An exported client starts at the menu (--menu: anyone, for screenshots);
	# a host, a server and a project run go straight in.
	if Net.show_menu or OS.has_feature("template") and Net.mode == Net.Mode.CLIENT:
		_show_menu()
		return
	_play()


## Feel tuning's keys (decision 673), fixed (not the Options' to rebind)
## and only in a local host (Tuning.allowed; a joined client's do nothing):
## F7 the panel, F8 the next time scale, F9 pause, "." one tick on while
## paused. Whether [param key] was one.
func tuning_key(key: InputEventKey) -> bool:
	if key == null or not key.pressed or key.echo or not Tuning.allowed():
		return false
	match key.keycode:
		KEY_F7:
			tuning_panel_toggled.emit()
		KEY_F8:
			talk.add_line("Tuning", "time x%s" % Tuning.cycle_scale(), true, true)
		KEY_F9:
			talk.add_line("Tuning", "paused: \".\" steps one tick" if Tuning.toggle_pause() else "time runs", true, true)
		KEY_PERIOD:
			if not Tuning.paused:
				return false
			Tuning.step_once()
		_:
			return false
	return true


## Feel tuning's "camera" fields (decision 673): the view's own, on Client3D
## while it runs (camera.<var>): combat's draw pull, and (step 2, ui's) the
## view's eases and pulls, whose repo values are art/kit/feel.json's
## "camera" section (Client3D.load_camera_feel). Each with its range.
const CAMERA_FIELDS := {"draw_pull_margin": [0.0, 5.0], "draw_pull_most": [1.0, 3.0], "draw_pull_rate": [1.0, 30.0],
	"zoom_rate": [1.0, 40.0], "peek_pull_back": [1.0, 2.0], "peek_return_seconds": [0.05, 1.0],
	"mourn_pull_back": [1.0, 2.5], "mourn_seconds": [0.5, 8.0], "mourn_return_seconds": [0.1, 2.0],
	"reach_ease": [0.05, 2.0], "aim_lead_cells": [0.0, 8.0], "aim_cone_ease_ticks": [0.25, 6.0],
	"telegraph_flash": [0.0, 1.0], "telegraph_flash_msec": [50, 1000], "flash_seconds": [0.02, 0.6],
	"overhead_pitch": [60.0, 89.0], "pitch_ease_seconds": [0.05, 1.0],
	"inside_pitch": [60.0, 89.5], "inside_ease_seconds": [0.05, 1.0], "inside_leave_hold": [0.0, 2.0]}
## The camera fields combat's 673 added; the rest are ui's (673 step 2).
const COMBAT_CAMERA_FIELDS: Array[String] = ["draw_pull_margin", "draw_pull_most", "draw_pull_rate"]


static func camera_fields() -> Array:
	var out := []
	for key: String in CAMERA_FIELDS:
		out.append({"path": "camera." + key, "group": "Camera", "min": CAMERA_FIELDS[key][0], "max": CAMERA_FIELDS[key][1],
			"owner": "combat" if key in COMBAT_CAMERA_FIELDS else "ui"})
	return out


func _camera_value(path: String) -> Variant:
	var key := path.get_slice(".", 1)
	return _client3d.get(key) if _client3d != null and CAMERA_FIELDS.has(key) else null


func _set_camera_value(path: String, value: Variant) -> bool:
	var key := path.get_slice(".", 1)
	if _client3d == null or not CAMERA_FIELDS.has(key):
		return false
	_client3d.set(key, value)
	return true


## The tuning panel's Reset the hall (673, ui's side): the zone laid again
## from its map, as the console's "zone reset", the tuning kept.
func _reset_hall() -> void:
	if Tuning.allowed():
		talk.add_line("Tuning", admin_command("zone reset %s" % World.zone.name), true, true)


## The practice hall's dummies (decision 673, Tuning.spawn_dummy), one at
## each of its level.json spawn_points named dummy...; the arena's others
## gone with the room.
func place_dummies() -> void:
	Tuning.clear()
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/%s/level.json" % Net.PRACTICE_MAP))
	var points: Variant = config.get("spawn_points", {}) if config is Dictionary else {}
	if points is not Dictionary:
		return
	for point: String in points:
		var at: Variant = points[point]
		if point.begins_with("dummy") and at is Array and (at as Array).size() == 2:
			Tuning.spawn_dummy(Vector2i(int(at[0]), int(at[1])))


## The practice hall (decision 673): a host of its own (--practice) started
## beside this one and this one closed, so the menu's Practice never mixes
## with the box; an exported game runs itself again, a project run Godot
## on the project.
func start_practice() -> void:
	var args := PackedStringArray(["--practice"])
	if not OS.has_feature("template"):
		args = PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--", "--practice"])
	if OS.create_process(OS.get_executable_path(), args) > 0:
		_quit_game()


## Play: online, by way of the connect screen for a client (the first run
## fills in the server's details first).
func _play() -> void:
	if main_menu != null:
		main_menu.visible = false
	if Net.is_authority():
		_end_title_music()  # A host's world is already here; a client's waits for its "map".
	$HUD.visible = true
	if Net.needs_setup:
		# An exported client with no settings.cfg yet: ask once, then join.
		_connect_screen().edit()
		return
	_ask_server_status()
	if Net.mode == Net.Mode.CLIENT:
		_connect_status("connecting to %s:%d" % [Net.address, Net.port])
	if not _went_online:
		_went_online = true
		_go_online()


## The title screen's music faded out and let go (656): on Play for a host, on its first
## "map" for a client, so it plays on through the connect screen until the world loads.
func _end_title_music() -> void:
	if title_music != null:
		title_music.stop()
		title_music = null


## The main menu over everything (MainMenu), made the first time.
func _show_menu() -> void:
	if main_menu == null:
		main_menu = MainMenu.new()
		main_menu.play_pressed.connect(_play)
		main_menu.practice_pressed.connect(start_practice)
		main_menu.options_pressed.connect(_menu_options)
		main_menu.quit_pressed.connect(_quit_game)
		add_child(main_menu)
	main_menu.visible = true
	if title_music == null:
		title_music = TitleMusic.new()
		add_child(title_music)
	$HUD.visible = false
	if connect_screen != null:
		connect_screen.visible = false
	_ask_server_status()


## The server's status for the menu and the connect screen (maps' Net.query_status
## and status_received, once they exist): "online, v0.1.150, 3 players", "no
## answer", with "out of date: updates when you join" when the build would not fit.
func _ask_server_status() -> void:
	if not Net.has_method("query_status") or Net.address.is_empty():
		return
	if not Net.is_connected("status_received", _on_server_status):
		Net.connect("status_received", _on_server_status)
	Net.call("query_status", Net.address, Net.port)


func _on_server_status(address: String, port: int, result: Dictionary) -> void:
	if address != Net.address or port != Net.port:
		return
	var words := server_status_words(result)
	if main_menu != null:
		main_menu.set_status(words)
	if connect_screen != null:
		connect_screen.set_status(words)


## [param result] (maps' shape: ok, version, players, accepting, compatible;
## or ok false with why) in words, the parts set off by middle dots.
static func server_status_words(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		# No answer is no verdict (older servers never answer; maps): unknown.
		var why := str(result.get("why", "no answer"))
		return "status unknown" if why == "no answer" else why
	var players := int(result.get("players", 0))
	var parts: Array[String] = ["online", "v%s" % str(result.get("version", "?")),
		"%d player%s" % [players, "" if players == 1 else "s"]]
	if not bool(result.get("accepting", true)):
		parts.append("not taking players now")
	if not bool(result.get("compatible", true)):
		parts.append("out of date: updates when you join")
	return " · ".join(parts)


## The join flow's screen (ConnectScreen), made the first time.
func _connect_screen() -> ConnectScreen:
	if connect_screen == null:
		connect_screen = ConnectScreen.new()
		connect_screen.has_menu = main_menu != null
		connect_screen.submitted.connect(_on_setup_submitted)
		connect_screen.retry_pressed.connect(_retry_connect)
		connect_screen.back_pressed.connect(_show_menu)
		add_child(connect_screen)
	return connect_screen


## What the connection is doing, on the connect screen when there is one
## (a client), else the HUD line (a host's rare messages).
func _connect_status(text: String, is_failed := false) -> void:
	if connect_screen != null or Net.mode == Net.Mode.CLIENT and not Net.online:
		_connect_screen().set_state(text, is_failed)
		_connect_joining = true
	else:
		hud.text = text


## Retry after a failed connection: the same server again.
func _retry_connect() -> void:
	_connect_status("connecting to %s:%d" % [Net.address, Net.port])
	_rejected = false
	if not Net.reconnect():
		_connect_status("could not start a connection to %s:%d" % [Net.address, Net.port], true)


## Leave: back to the menu, which for an exported game is the game started
## again (the world here is let go); a project run quits.
func _leave_game() -> void:
	if OS.has_feature("template"):
		# With the arguments it was started with (a renderer, --controls, a
		# settings path), less any test hook.
		var args: PackedStringArray = []
		for arg: String in OS.get_cmdline_args():
			if not arg.begins_with("--test-"):
				args.append(arg)
		OS.create_process(OS.get_executable_path(), args)
	_quit_game()


func _quit_game() -> void:
	_release_zones()
	Net.shutdown()
	get_tree().quit()


func _on_setup_submitted(address: String, port: int, token: String, player_name: String) -> void:
	if not Net.save_settings(address, port, token, player_name):
		print("[net] could not write %s" % Net.settings_path())
	Net.configure_client(address, port, token)
	_connect_status("connecting to %s:%d" % [address, port])
	if _went_online:
		_retry_connect()
		return
	_went_online = true
	_go_online()


## Starts networking in whatever mode Net settled on, and sets this peer up
## as the authority or as a mirror accordingly.
func _go_online() -> void:
	Net.start()
	if Net.is_authority():
		# Players are spawned for authenticated peers only.
		Net.peer_authenticated.connect(_on_peer_authenticated)
		Net.peer_left.connect(_on_peer_disconnected)
		World.entity_despawned.connect(_on_entity_despawned)
		# What each client is sent follows its player (decision 217).
		if not World.entity_moved.is_connected(Net.interest.moved):
			World.entity_moved.connect(Net.interest.moved)
			World.entity_despawned.connect(Net.interest.remove)
		World.entity_pushed.connect(_narrate_push)
		World.entity_damaged.connect(_narrate_damage)
		World.guard_met.connect(_narrate_guard)
		World.knocked_down.connect(_narrate_down)
		World.draw_given_up.connect(_tell_arms_gave)
		World.braced_against.connect(_narrate_brace)
		World.item_named.connect(_narrate_named)
		World.item_kept.connect(_narrate_kept)
		World.item_grew.connect(_narrate_grew)
		# Her named things and gifts are facts of her card (293 amended).
		World.item_named.connect(_card_named)
		World.item_kept.connect(_card_kept)
		World.item_given.connect(_card_given)
		World.item_grew.connect(_card_grew)
		# Her bond with her player (decision 444).
		World.bandage_changed.connect(_bond_bandaged)
		World.bandage_changed.connect(_tell_bandage_broke)  # decision 625.
		World.entity_died.connect(_bond_stood_by)
		World.entity_damaged.connect(_bond_blow)  # Fights won together (decision 621).
		World.entity_died.connect(_bond_won)
		World.bundle_swapped.connect(_narrate_swap)
		World.shield_bashed.connect(_narrate_bash)
		World.entity_bumped.connect(_on_bumped)
		World.entity_died.connect(_on_entity_died)
		World.entity_died.connect(_robber_fell)  # The grave robbers' gold (580, economy's side).
		World.entity_taken.connect(_on_entity_taken)
		World.telegraph_started.connect(_tell_telegraph)  # Decision 602.
		World.telegraph_ended_in.connect(_tell_telegraph_ended)
		# The draugr's blessed, downed and brought back (decision 544).
		World.downed = _downed
		World.entity_downed.connect(_on_downed)
		# What she lives through is a danger of the place (decision 551).
		World.entity_downed.connect(_roads_downed)
		World.entity_taken.connect(_roads_taken)
		World.entity_died.connect(_roads_fell)
		World.entity_damaged.connect(_roads_struck)
		# What her player did that moves her bond (555 amended).
		World.entity_downed.connect(_bond_left_down)
		World.entity_died.connect(_bond_fell)
		road_heard = _road_heard  # The road's news she hears (551 phase 2).
		World.entity_damaged.connect(_hail_struck)  # A blow given (decision 554).
		# Her focus grows by what she does (decision 577).
		World.entity_damaged.connect(_focus_struck)
		World.loosed.connect(_focus_shot)
		World.buff_changed.connect(_focus_ate)
		World.channel_changed.connect(_on_channel)
		World.command_received.connect(_on_command)
		World.slots_changed.connect(_on_slots_changed)
		World.ground_changed.connect(_on_ground_changed)
		World.gold_changed.connect(_on_gold_changed)
		World.traded.connect(_on_traded)
		World.slot_refused.connect(_on_slot_refused)
		BuilderHost.warn_overlays()
		if BuilderHost.available():
			_builder = BuilderHost.new()
			_builder.main = self
			add_child(_builder)
		if Net.llm_url != "" and Net.llm_model != "":
			mind_kind = "ollama"
		if Net.mode == Net.Mode.SERVER:
			World.entity_moved.connect(_log_player_move)
		World.entity_moved.connect(_on_entity_moved)
		World.link_bumped.connect(_on_link_bumped)
		World.niche_pressed.connect(_on_niche_pressed)  # The hidden door (608).
		World.walked_off.connect(_on_walked_off)
		var drawn := map_name
		_boot()
		if World.home().name == drawn:
			# The views drew this map above: not again (a big map's 3D view
			# takes seconds to build).
			_view_zone = drawn
		_start_console()
	else:
		# Terrain is static level data, not replicated state. The zone's
		# entities arrive through its spawner; the server says which zone.
		_zone_nodes(map_name)
		World.mirror_reset()
		World.mirror_terrain(_terrain)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		multiplayer.connection_failed.connect(
				func() -> void: _connect_status("the server at %s:%d did not answer" % [Net.address, Net.port], true))
		Net.join_rejected.connect(_on_join_rejected)
	Net.message_received.connect(_on_message)


## Main processes after everything else (process_priority, set in
## _ready): the entities have placed themselves and the 3D view has moved
## its camera, so the pick below is made against the frame as drawn.
func _process(delta: float) -> void:
	UiCost.frame()
	_measure_smoothness(delta)
	_show_home_zone()
	_follow_player(delta)
	if _client3d != null and DisplayServer.get_name() != "headless":
		# Alt shows every HP bar; the view only reads it.
		_client3d.show_all_bars = Input.is_key_pressed(KEY_ALT)
	_drag_yaw()
	_drive_camera_keys(delta)
	_update_pick()
	_run_test_hold_near()
	_run_test_latency()
	_run_test_kicks()
	_test_hover()
	drive_stand_draw(Keys.held("stand") and not is_typing() and _cursor_item.is_empty(), Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if not _free_drive(delta):
		_drive_wasd()
	if not _stance.is_empty() and Net.controls != "wasd" and _local_player() != null:
		_aim_at_cursor(_local_player())  # A raised shield or a drawn bow turns to the cursor.
	_check_bandage_hold()
	_run_test_steer()
	_run_test_chase()
	# Hover is the floor cell under the cursor, on the ground plane alone:
	# nothing standing on the map intercepts it. In 3D a monster a click
	# would attack is outlined instead, and the cell is not shown.
	var tile := _mouse_tile()
	var player := _local_player()
	# One pick of the body under the cursor a frame, for the target and the hint both.
	var under_mouse := _entity_under_mouse()
	var lobbing := player != null and player.raised == "draw" and player.lobbing
	var drawing := player != null and player.raised == "draw" and not lobbing
	_show_lob(player, lobbing)
	_update_aim(player, drawing)
	# The archery aim: the shot goes the aim's way to the arc's cell; the
	# marker is the aim, so the hover square shows only without one.
	var aim_tile := _aim_mark_cell if drawing and aim_drawn else tile
	var aim: Dictionary = {}
	if drawing:
		# Items' 583 shot_aim takes the angle and the range ({end, cell, hit,
		# struck}); before it lands, the cell ({end, hit}). Called by name, so
		# either side lands first.
		if World.has_method("draw_step"):
			var steps := range_steps(player)
			var reach := range_now(player)
			var angle := aim_angle if aim_drawn else Vector2(aim_tile - player.tile).angle()
			aim = World.call("shot_aim", player, angle, reach if reach > 0 else int(steps[0]) if not steps.is_empty() else 1)
		else:
			aim = World.call("shot_aim", player, aim_tile)
	if _client3d != null and drawing:
		# A bow drawn: the body the shot would strike is outlined (475), the
		# arc and its marker say how far (the archery aim).
		var hit: GridEntity = aim.get("hit")
		var lands: Vector2i = aim.get("cell", aim.get("end", aim_tile)) if aim.get("cell", aim.get("end")) is Vector2i else aim_tile
		_client3d.target(hit)
		_client3d.hover(lands, not aim_drawn and hit == null)
		_client3d.draw_look(World.draw_of(player))
		_client3d.stand_ring(Vector2i.ZERO, false)
		_draw_shown = true
	elif _client3d != null:
		if _draw_shown:
			_draw_shown = false
			_client3d.draw_look(-1.0)
		var foe: GridEntity = under_mouse if player != null and under_mouse is Monster and World.can_target(player, under_mouse) else null
		_client3d.target(foe)
		# The hover square only where a cell is the answer: building (Jeff:
		# "it highlights a tile which is unneeded"); in play the cursor is enough.
		_client3d.hover(tile, foe == null and World.is_walkable(tile) and _building())
		_show_stand_ring(player)
	else:
		cursor.visible = World.is_walkable(tile) and not drawing and _building()
		cursor.position = Iso.tile_to_local(tile)
		cursor.polygon = PackedVector2Array([Iso.project(Vector2(-0.5, 0.5)), Iso.project(Vector2(-0.5, -0.5)),
				Iso.project(Vector2(0.5, -0.5)), Iso.project(Vector2(0.5, 0.5))])
	_retarget_held()
	_show_channel_ring()
	if _client3d != null:
		_client3d.telegraph_tick(World.tick)  # 602, ui's side: the telegraphs' fill.
	_update_pack()
	_update_talk()
	_update_deal()
	_update_note()
	_update_room()
	_update_bar()
	var hud_began := Time.get_ticks_usec()
	if compass != null:
		compass.north_on_screen = screen_north()
		if minimap != null:
			minimap.north_on_screen = compass.north_on_screen  # The map turns as the compass does (535).
		var standing := player.tile if player != null else NONE
		if standing != _place_tile or _hud_tick != _place_tick:
			_place_tile = standing
			_place_tick = _hud_tick
			_place_words = place_text(player)
		compass.place = _place_words
	if counter_panel != null and pack_panel != null:
		var at_counter := pack_panel.visible and is_instance_valid(pack_panel.other) \
				and not World.counter_kind(pack_panel.other).is_empty() or is_instance_valid(_test_counter_shown)
		counter_panel.visible = at_counter
		if at_counter:
			var rect := pack_panel.get_global_rect()
			var shop_box := shop_panel.box_rect() if shop_panel != null else Rect2()
			var placed_from := [rect, shop_box, counter_panel.get_combined_minimum_size()]
			if placed_from != _counter_placed_from:
				_counter_placed_from = placed_from
				counter_panel.reset_size()
				var bottom := shop_box.position.y - ShopPanel.GAP if shop_box.size.y > 0.0 else rect.end.y
				counter_panel.global_position = Vector2(rect.position.x - counter_panel.size.x - ShopPanel.GAP, bottom - counter_panel.size.y)
	if _context_hint != null:
		var at := get_viewport().get_mouse_position()
		var typing := is_typing()
		var under_id := under_mouse.get_instance_id() if under_mouse != null else 0
		if at != _hint_mouse or _hud_tick != _hint_tick or under_id != _hint_under_id or typing != _hint_typing:
			_hint_mouse = at
			_hint_tick = _hud_tick
			_hint_under_id = under_id
			_hint_typing = typing
			_hint_words = ""
			if not typing and DisplayServer.get_name() != "headless":
				_hint_words = context_hint_for(under_mouse)
				if _hint_words.is_empty():
					_hint_words = context_hint_for(_door_under_mouse())
				if _hint_words.is_empty():
					# A prop on the cell under the cursor (the pick ray finds bodies, not chests).
					for entity in World.get_entities():
						if entity.spawned and entity.tile == tile and (entity is Chest or entity is Cargo or entity is Companion):
							_hint_words = context_hint_for(entity)
							break
				if _hint_words.is_empty() and Net.hints and player != null and (not World.ground_at(tile).is_empty() or World.ground_gold(tile) > 0):
					_hint_words = "%s  pick up %s" % [Keys.name_of("pick_up"), pile_words(World.ground_at(tile), World.ground_gold(tile))]  # Behind hints=on (Jeff, 2026-10-22).
				if _hint_words.is_empty() and tile != NONE:
					# The building under the cursor (decision 537) and how far its town has
					# built it (566): "H3 house, being built 40%" in builder mode, else a
					# town's building by its plain name, "house, being built 40%".
					var building := BuilderUI.building_at(level.get("buildings", []), tile)
					if not building.is_empty():
						_hint_words = BuilderUI.hint_words(building, town_states, _builder_ui != null and _builder_ui.active)
		var words := _hint_words
		if is_instance_valid(_test_hint_thing) and _client3d != null:
			# --test-show=hint: the hint as the cursor on that thing would show it.
			words = context_hint_for(_test_hint_thing)
			at = _client3d.screen_of_tile(_test_hint_thing.tile)
		elif _test_hint_cell != Vector2i(-100000, -100000) and _client3d != null and Net.hints \
				and (not World.ground_at(_test_hint_cell).is_empty() or World.ground_gold(_test_hint_cell) > 0):
			# --test-show=herbs: the pile's hint, as the cursor on it would show it (decision 515).
			words = "%s  pick up %s" % [Keys.name_of("pick_up"), pile_words(World.ground_at(_test_hint_cell), World.ground_gold(_test_hint_cell))]
			at = _client3d.screen_of_tile(_test_hint_cell)
		_context_hint.visible = not words.is_empty()
		if not words.is_empty():
			if _context_hint.text != words:
				_context_hint.text = words
				_context_hint.reset_size()
			_context_hint.position = at + Vector2(28.0, 28.0)
	UiCost.add("hud", Time.get_ticks_usec() - hud_began)
	if debug_overlay.visible:
		debug_overlay.text = _debug_text()
	_update_toss_aim()
	_poll_console()
	_count_down_restart()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if is_typing():
		return
	if _arriving():
		return
	if _builder_ui != null and _builder_ui.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if Keys.pressed(event, "talk_log"):
		talk.toggle_pin()
		return
	if minimap != null and Keys.pressed(event, "map"):
		press_m()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and minimap != null and key.keycode == KEY_ESCAPE and minimap.big:
		minimap.toggle()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE and not _cursor_item.is_empty():
		_cursor_item = {}  # Esc puts the cursor's thing back first (decision 593).
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		escape()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F10 and admin_allowed():
		open_admin()  # 672: the admin panel, for an admin only.
		get_viewport().set_input_as_handled()
		return
	if Keys.pressed(event, "talk"):
		_open_chat()
		return
	if Keys.pressed(event, "debug"):
		debug_overlay.visible = not debug_overlay.visible
		return
	if tuning_key(key):
		get_viewport().set_input_as_handled()
		return
	if Keys.pressed(event, "fullscreen"):
		Net.toggle_fullscreen()
		return
	if Keys.pressed(event, "screenshot"):
		take_screenshot()
		return
	if Keys.pressed(event, "yes") and not standing_title.is_empty() and not is_typing():
		_send_chat("yes")  # 536: the word, said; the server takes it.
		return
	if Keys.pressed(event, "hints"):
		toggle_hints()
		return
	if Keys.pressed(event, "options"):
		toggle_options()
		return
	if Keys.pressed(event, "pack"):
		toggle_pack()
		return
	if Keys.pressed(event, "card"):
		toggle_card()  # 618, ui's side: her card page.
		return
	if Keys.pressed(event, "town"):
		toggle_town()  # 624, ui's side: the town sheet.
		return
	if Keys.pressed(event, "reset"):
		# A command like any other, so it works from a client too; the
		# authority decides. With no player to send it for (dead, respawning)
		# only the authority's own window can still do it.
		var me := _local_player()
		if me != null:
			World.command(me, "reset", {})
		elif Net.is_authority():
			_start_level()
		return
	if Keys.pressed(event, "bandage"):
		press_bandage()
		return
	if Keys.pressed(event, "lantern"):
		var holder := _local_player()
		if holder != null:
			World.command(holder, "lantern", {})
		return
	if key != null and not key.echo and Keys.matches(key.keycode, "open"):
		if key.pressed:
			_press_e()
		elif _e_held:
			_release_e()
		return
	if key != null and key.pressed and not key.echo and not _item_action_of(key.keycode).is_empty():
		item_key(_item_action_of(key.keycode))
		return
	if key != null and key.pressed and not key.echo and _phrase_of(key.keycode) > 0:
		say_phrase(_phrase_of(key.keycode))
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
	if click.button_index == MOUSE_BUTTON_LEFT and click.pressed and tuning_panel != null and not tuning_panel.picking.is_empty():
		var cell := _mouse_tile()
		if cell != NONE:
			tuning_panel.place(cell)  # 673, ui's side: the arena's spawn at the cell clicked.
		get_viewport().set_input_as_handled()
		return
	if click.button_index == MOUSE_BUTTON_LEFT and click.pressed and _bar != null and _bar.visible:
		_close_bar()  # Any click closes the talk bar and goes on: a bubble takes none (560 amended).
	if click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and minimap != null and minimap.big:
		# The big map open: the wheel zooms it instead.
		if click.pressed:
			minimap.zoom(1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		return
	if click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# 3D, both schemes: the wheel zooms, up nearer.
		if _client3d != null and click.pressed:
			_client3d.zoom_by(1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		return
	if click.button_index == MOUSE_BUTTON_MIDDLE:
		# 3D only: a pitch peek, or in WASD a horizontal drag turns.
		if _client3d != null:
			if click.pressed:
				_begin_middle_drag(Vector2(DisplayServer.mouse_get_position()), click.ctrl_pressed)
			elif not is_nan(_drag_from.x):
				_end_middle_drag()
		return
	var player := _local_player()
	if player == null:
		_toss_target = null
		_held_target = NONE
		return
	if not _cursor_item.is_empty() and click.pressed and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_click_cursor_item(player, click.button_index)
		get_viewport().set_input_as_handled()
		return
	if click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		if _stance == "block" or _stance == "lob":
			_lower_off_hand(player)  # The draw is the left button's (Jeff, 2026-10-22); the lob the right's (677).
		_release_toss(player)
		return
	if click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		_held_target = NONE
		if _stance == "draw" and World.off_hand(player) == "draw":
			_lower_off_hand(player)  # 583 amended (2): the release looses (Jeff: "release left click no longer fires").
		return
	if not click.pressed:
		return
	# A sprite under the cursor is the target whatever cell is under those
	# pixels; otherwise the click resolves on the ground plane, to the floor
	# cell under the cursor and whatever stands on it. The right button also
	# takes a door face.
	var target := _entity_under_mouse()
	var on_sprite := target != null
	var tile := target.tile if target != null else _mouse_tile()
	if target == null:
		target = World.get_entity_at(tile)
	if target == null:
		target = remains_at(tile)  # A gone draugr's remains: a click talks to him (573 amended (4)).
	# A bow in hand (583 amended; Jeff: "the point of shift is to stand
	# firm and start nocking"): Shift (the stand key) held draws and stands
	# the body firm (drive_stand_draw), a left release while drawn looses
	# (583 amended (2); the press does nothing), and letting go of Shift
	# with the left button up lowers it, the arrow kept; a press with Shift
	# down before the draw is up draws too. A plain left click never attacks with a bow: it walks (a
	# monster as the ground), talks to a friend or opens a chest
	# (_click_with_bow; the coordinator's ruling). The right button with a
	# bow is the lob (decision 677; Jeff: "right click hold and release to
	# fire"): held, the bow aimed at the sky and drawn, the body firm; let
	# go, loosed at the cursor (_lower_off_hand); one draw at a time. Right
	# otherwise: the off hand (decision 329): a shield raised while held;
	# empty-handed it shoves and tosses (below). Opening and bandaging are
	# E's (_press_e). Left: a chest is walked to.
	if World.off_hand(player) == "draw":
		if click.button_index == MOUSE_BUTTON_RIGHT and _stance.is_empty():
			_raise_lob(player)
		elif click.button_index == MOUSE_BUTTON_LEFT and _stance == "lob":
			pass  # 677: lobbing, the left button waits.
		elif click.button_index == MOUSE_BUTTON_LEFT:
			if _stance == "draw":
				pass  # 583 amended (2): drawn, the press waits; its release looses.
			elif Keys.held_in(click, "stand"):
				_raise_off_hand(player)  # The bow is the weapon: Shift draws, no stand swing.
			else:
				_click_with_bow(player)
		return
	if click.button_index == MOUSE_BUTTON_RIGHT and _raise_off_hand(player):
		return
	# Ctrl: the held weapon's signature move; Shift: a swing where you
	# stand, toward the cursor, at whatever is there (decision 593).
	if click.button_index == MOUSE_BUTTON_LEFT and Keys.held_in(click, "signature"):
		_send_at(player, "signature")
		return
	if click.button_index == MOUSE_BUTTON_LEFT and Keys.held_in(click, "stand"):
		_talk_wanted = null
		_send_at(player, "swing")
		return
	if click.button_index == MOUSE_BUTTON_LEFT and target is Chest:
		_walk_to_chest(player, target)
		return
	var targetable := target != null and target != player and World.can_target(player, target)
	# Left on a friend (a resident, a companion, another player) or a
	# peaceable monster that talks, both schemes: talk, never an attack
	# (decisions 454, 648); Shift's swing (above) strikes one.
	if click.button_index == MOUSE_BUTTON_LEFT and target != player and talks_on_click(target):
		_talk_to(player, target)
		return
	if Net.controls == "wasd" and not on_sprite:
		_wasd_click(player, click.button_index)
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			# A creature (a monster: friends are above): go to it and
			# attack. Anything else: walk there (and push), to the nearest
			# floor if the click was off it.
			if targetable and target.is_creature():
				World.command_attack(player, target)
				_free_chase_start(player, target)
			else:
				_move_click(player, tile if target != null else _snap_to_floor(_mouse_grid()))
		MOUSE_BUTTON_RIGHT:
			# Any entity: go to it and shove. Sent on release, so that
			# dragging first can aim it.
			if targetable:
				_toss_target = target
				_toss_from = get_global_mouse_position()


## A plain left click with a bow in hand: never an attack (Jeff: "mouse to
## move only"): a chest is walked to, a friend talked to, anything else,
## a monster as the ground, walked toward; Shift with the button is the
## only shot.
func _click_with_bow(player: Player) -> void:
	var target := _entity_under_mouse()
	var on_sprite := target != null
	var tile := target.tile if target != null else _mouse_tile()
	if target == null:
		target = World.get_entity_at(tile)
	if target == null:
		target = remains_at(tile)
	if target is Chest:
		_walk_to_chest(player, target)
	elif target != null and target != player and talks_on_click(target):
		_talk_to(player, target)
	elif Net.controls == "wasd" and not on_sprite:
		_wasd_click(player, MOUSE_BUTTON_LEFT)
	else:
		_move_click(player, tile if target != null else _snap_to_floor(_mouse_grid()))


## Whether [param entity] is a friend (decision 454): a town's resident, a
## companion (anyone's) or a player. A left click talks to one; only
## Shift+click attacks.
func is_friend(entity: GridEntity) -> bool:
	return entity is Resident or entity is Companion or entity is Player


## Whether a plain left click on [param entity] talks rather than strikes
## (decision 648; Jeff: "earlier i struck the draugr because left
## clicking attacked"): a friend, or a monster that talks and is peaceable
## now (Monster.peaceable, the server's, replicated: the draugr seated and
## unprovoked; false on a kind that never sets it).
## Shift's swing and the signature still strike it; once it fights, a click
## attacks as ever.
func talks_on_click(entity: GridEntity) -> bool:
	return is_friend(entity) or entity is Monster and (entity as Monster).talks and (entity as Monster).peaceable


## A left click on [param friend] (decision 454): within TALK_REACH, talk
## opens at once (_open_talk); from afar the player walks beside them and
## it opens on arrival (_update_talk). Holding the button does not steer
## this walk away.
func _talk_to(player: Player, friend: GridEntity) -> void:
	# Your own companion beside you: she makes way (the hands, as a bump;
	# the server's "make_way"). Jeff on v0.1.166, body-blocked by Pip.
	if _is_own_companion(friend) and World.can_melee(player.tile, friend.tile):
		World.command(player, "make_way", {"target": str(friend.get_path())})
		return
	if World.distance(player.tile, talk_cell(friend)) <= TALK_REACH:
		_open_talk(friend)
		return
	var beside := _beside(talk_cell(friend), player.tile)
	if beside == NONE and _is_own_companion(friend):
		beside = friend.tile  # A corridor: walk at her, and the bump swaps you.
	if beside == NONE:
		return
	_move_click(player, beside)
	_held_target = NONE
	_talk_wanted = friend
	_talk_until = Time.get_ticks_msec() + TALK_WAIT_MSEC


## Talk with [param friend] (decision 454): a resident's conversation panel
## (the E path); for a companion the chat box addressed to her ("Wren, "),
## for a player the chat box.
func _open_talk(friend: GridEntity) -> void:
	_talk_wanted = null
	if friend is Resident:
		_greet(friend)  # 560, ui's side: the click greets; the bar's Talk opens the say line.
		_open_bar(friend)
	elif talks_peaceably(friend):
		_greet(friend)  # 629, ui's side: the greet speaks his deal; his "offers" message opens the deal window.
	elif is_friend(friend) and friend != _local_player():
		# A player or a companion (Jeff on v0.1.165: "click player still pulls up the
		# chat window with their name"): no window, only the talk bar under them,
		# Talk (560 amended: the bubbles take no clicks, so the person's click opens it).
		_open_bar(friend)


## The resident nearest [param player] in this zone, or null (560's shots).
func _nearest_resident(player: Player) -> GridEntity:
	var who: GridEntity = null
	var nearest := 1000000
	if player == null:
		return null
	for entity in World.townsfolk():  # The town's people, as the first-talk hint reads them.
		if entity is Resident and entity.spawned:
			var distance := World.distance(player.tile, entity.tile)
			if distance < nearest:
				nearest = distance
				who = entity
	return who


## --test-show=greet's sample (560, ui's side): once a resident is in the
## world, the player beside them, a greeting bubble over them and the talk
## bar under it; tried once a second for a while, as the town's people
## spawn after the level.
const GREET_SHOT_TRIES := 8


func _greet_sample(player: Player, tried: int) -> void:
	var who := _nearest_resident(player)
	if who == null or bubbles == null:
		if tried < GREET_SHOT_TRIES and is_instance_valid(player):
			get_tree().create_timer(1.0).timeout.connect(_greet_sample.bind(player, tried + 1))
		return
	if Net.is_authority() and _beside(who.tile, player.tile) != NONE:
		World._relocate(player, _beside(who.tile, player.tile))  # In the shot, beside them.
	bubbles.show_line(who.get_instance_id(), "Wares, if you have coin.")
	_greeted_by_click = who
	_open_bar(who)


## A click on [param resident] in reach (560, ui's side; Jeff: "the npc
## stops, faces you, and addresses you"): npc's "greet" command, sent by
## name (the resident stops, turns and speaks one line through the spoken
## path; npc's rules and cooldown); _open_talk opens the talk bar under
## them. The standing-offer read (536) is asked as before.
func _greet(resident: GridEntity) -> void:
	var player := _local_player()
	if player == null or not is_instance_valid(resident):
		return
	_greeted_by_click = resident
	World.command(player, "greet", {"resident": str(resident.get_path())})
	ask_offers(resident)


## The talk bar (560, ui's side): the resident's name and two options,
## Talk (536's say line addressed to them) and Barter (the window, a
## merchant's), under their bubble, else under them, while in hearing.
func _open_bar(resident: GridEntity) -> void:
	if _bar == null:
		return
	_bar_for = resident
	var person := str(resident.get("person")) if resident.get("person") != null else ""
	_bar_name.text = person if not person.is_empty() else _display_name(resident)
	_bar_barter.visible = _barters(resident)
	_bar.visible = true
	_update_bar()


func _close_bar() -> void:
	if _bar != null:
		_bar.visible = false
	_bar_for = null


## Each frame: the bar follows its person's bubble, or with none the point
## a bubble would hang from; it goes when they are off screen or out of hearing.
func _update_bar() -> void:
	if _bar == null or not _bar.visible:
		return
	if not is_instance_valid(_bar_for) or bubbles == null:
		_close_bar()
		return
	var player := _local_player()
	if player != null and World.distance(player.tile, _bar_for.tile) > HEARING_RANGE:
		_close_bar()
		return
	var rect := bubbles.rect_of(_bar_for.get_instance_id())
	if rect.size.y <= 0.0:
		var at: Variant = _bubble_anchor(_bar_for.get_instance_id())
		if not at is Vector2:
			_close_bar()
			return
		rect = Rect2(at, Vector2.ZERO)
	_bar.reset_size()
	_bar.global_position = Vector2(rect.position.x + rect.size.x * 0.5 - _bar.size.x * 0.5, rect.end.y + 8.0)


## The bar's Talk: the say line addressed to them, as the click did before 560.
func _bar_talk_pressed() -> void:
	var resident := _bar_for
	_close_bar()
	if not is_instance_valid(resident):
		return
	_open_chat()
	if _chat_box.visible:
		var person := str(resident.get("person")) if resident.get("person") != null else ""
		_chat_box.text = "%s, " % (person if not person.is_empty() else _display_name(resident))
		_chat_box.caret_column = _chat_box.text.length()


## Whether [param resident] has a barter to offer: the merchant fronts the
## town's shop (560, a counter near), a maker trades their own make in
## person (562; economy's rule: a trade in Items.TRADES, the medicine man
## too).
func _barters(resident: GridEntity) -> bool:
	var trade := str(resident.get("trade")) if resident.get("trade") != null else ""
	if trade == "merchant":
		return _shop_counter_near(resident) != null
	return trade in Items.TRADES or trade == "medicine_man"


## The bar's Barter: the window for the shop the merchant fronts (the shop
## counter nearest them, economy's "barter" {shop}), or for a maker's own
## goods in person ("barter" {resident}, 562).
func _bar_barter_pressed() -> void:
	var resident := _bar_for
	_close_bar()
	if is_instance_valid(resident):
		_open_barter_with(resident)


func _open_barter_with(resident: GridEntity) -> void:
	var player := _local_player()
	if player == null or barter_panel == null or not _barters(resident):
		return
	var person := str(resident.get("person")) if resident.get("person") != null else ""
	if str(resident.get("trade")) == "merchant":
		var counter := _shop_counter_near(resident)
		barter_panel.open(counter, person)
		World.command(player, "barter", {"shop": str(counter.get_path())})
	else:
		barter_panel.open(resident, person)
		World.command(player, "barter", {"resident": str(resident.get_path())})


## The shop counter nearest [param near] in this zone (a Chest that is a
## shop), or null.
func _shop_counter_near(near: GridEntity) -> GridEntity:
	var best: GridEntity = null
	var best_distance := 1000000
	for entity in World.get_entities():
		if entity is Chest and (entity as Chest).shop and entity.spawned:
			var distance := World.distance(near.tile, entity.tile)
			if distance < best_distance:
				best_distance = distance
				best = entity
	return best


## The window's care row (economy's healer's care): the "retain" command
## for the healer in person; the answer is the barter message again.
func _retain(with: GridEntity, pay := "gold") -> void:
	var player := _local_player()
	if player != null and is_instance_valid(with) and with is Resident and with.is_inside_tree():
		World.command(player, "retain", {"resident": str(with.get_path()), "pay": pay})  # 584 amended: gold, herbs or antlers.


## The window's Confirm: economy's "trade" command, by name, naming the
## counter ({shop}) or the maker in person ({resident}, 562).
func _trade(with: GridEntity, give: Array, take: Array, gold_balance: int) -> void:
	var player := _local_player()
	if player != null and is_instance_valid(with):
		var key := "resident" if with is Resident else "shop"
		World.command(player, "trade", {key: str(with.get_path()), "give": give, "take": take, "gold": gold_balance})


## Economy's barter message (Main.barter_told, 560, economy's side): the
## window redrawn, the purse read.
func _on_barter_told(data: Dictionary) -> void:
	if data.has("gold"):
		gold = int(data["gold"])
		if shop_panel != null:
			shop_panel.gold = gold
	if barter_panel != null:
		barter_panel.show_barter(data)


## Each frame: a friend walked to opens talk once within TALK_REACH; gone,
## or not reached in TALK_WAIT_MSEC, it is forgotten.
func _update_talk() -> void:
	if _talk_wanted == null:
		return
	var player := _local_player()
	if player == null or not is_instance_valid(_talk_wanted) or not _talk_wanted.spawned \
			or Time.get_ticks_msec() > _talk_until:
		_talk_wanted = null
		return
	if World.distance(player.tile, talk_cell(_talk_wanted)) <= TALK_REACH:
		_open_talk(_talk_wanted)


## The right button pressed: what the off hand holds is raised (a
## "stance" command: a shield's block, a bow's draw), true; false with
## nothing for it, and the press shoves as ever.
func _raise_off_hand(player: Player) -> bool:
	_stance = World.off_hand(player)
	if _stance.is_empty():
		return false
	_toss_target = null
	var at := _mouse_grid()
	World.command(player, "stance", {"kind": _stance} if is_nan(at.x) else {"kind": _stance, "at": [at.x, at.y]})
	return true


## The right button pressed with a bow (decision 677): the lob, a draw aimed
## at the sky (a "stance" command with "lob").
func _raise_lob(player: Player) -> void:
	_stance = "lob"
	_toss_target = null
	World.command(player, "stance", {"kind": "draw", "lob": true})


## The lob's aim each frame while [param player] lobs (decision 677): the
## brass arc from its nocked arrow to the cell under the cursor drawn in to
## its reach (World.lob_aim), the ring of its circle (lob_radius), red where
## it cannot come down (lob_open); hidden otherwise.
func _show_lob(player: Player, lobbing: bool) -> void:
	if _client3d == null:
		return
	if not lobbing:
		_client3d.lob_aim(Vector3.ZERO, Vector2i.ZERO, 0.0, false, 0.0, false)
		return
	var cell := World.lob_aim(player, _mouse_tile())
	var radius := World.lob_radius(player)
	var puppet: Node3D = _client3d._puppets.get(player.get_instance_id())
	var from: Vector3 = _client3d._bow_tip(puppet) if puppet != null else Vector3(player.tile.x, 1.1, player.tile.y)
	var apex := float(Items.verb_of(World.drawn_with(player)).get("lob_apex", 0.25))
	_client3d.lob_aim(from, cell, radius, World.lob_open(cell), apex, radius >= 0.0 and cell != player.tile)


## [param command_name] ("swing", "signature") toward the ground point under
## the cursor (decision 593); the server picks who is struck.
func _send_at(player: Player, command_name: String) -> void:
	var at := _mouse_grid()
	if is_nan(at.x):
		return
	World.command(player, command_name, {"at": [at.x, at.y]})


## B (decision 593): a bandage on the cursor from the kit carried, or put
## back if one is on it already. No kit, nothing.
func press_bandage() -> void:
	var player := _local_player()
	if not _cursor_item.is_empty() or player == null:
		_cursor_item = {}
		return
	var slot := World.bandage_kit(player)
	if slot >= 0:
		_cursor_item = {"kind": "bandage", "slot": slot}


## A click with the cursor's thing on it (decision 593): the left button
## applies it to whoever is under the cursor (yourself, an ally; the server
## says whether it can), the right puts it back. Either way it leaves the
## cursor, and no attack is made.
func _click_cursor_item(player: Player, button: MouseButton) -> void:
	var item := _cursor_item
	_cursor_item = {}
	if button != MOUSE_BUTTON_LEFT:
		return
	var on := _entity_under_mouse()
	if on == null:
		on = World.get_entity_at(_mouse_tile())
	if on != null and (on is Player or on is Companion):
		World.command(player, "apply_item", {"slot": int(item["slot"]), "target": str(on.get_path())})


## The right button released: a drawn bow is loosed the aim's way ("loose"
## with the angle, and the arc's cell as "at" for the old shot), a raised
## shield lowered.
func _lower_off_hand(player: Player) -> void:
	if _stance == "draw":
		var at := _aim_mark_cell if aim_drawn else _mouse_tile()
		World.command(player, "loose", loose_args(aim_angle if aim_drawn else NAN, at))
	elif _stance == "lob":
		var at := _mouse_tile()
		World.command(player, "lob", {"at": [at.x, at.y]})  # 677: the server draws it in to the reach.
	elif _stance == "block":
		World.command(player, "stance", {"kind": ""})
	_stance = ""


## E pressed: what is under the cursor (an entity, a door face) is kept
## for the tap or the hold.
func _press_e() -> void:
	_e_held = _local_player() != null
	_e_since = Time.get_ticks_msec()
	_e_target = _entity_under_mouse()
	if _e_target == null:
		_e_target = World.get_entity_at(_mouse_tile())
	if _e_target == null:
		_e_target = remains_at(_mouse_tile())
	_e_door = _door_under_mouse()


## E released before the hold bandaged: a tap.
func _release_e() -> void:
	_e_held = false
	var player := _local_player()
	if player != null and Time.get_ticks_msec() - _e_since < BANDAGE_HOLD_MSEC:
		_tap_e(player)


## A tap of E: a chest, a crate or a cart, or your own companion's pack
## opens (from afar you walk to it: _open_pack); else a door face beside
## you opens or closes.
func _tap_e(player: Player) -> void:
	var target := _e_target
	if is_instance_valid(target) and target.spawned \
			and (target is Chest or target is Cargo or _is_own_companion(target)):
		_open_pack(player, target)
		return
	if is_instance_valid(target) and target.spawned and (target is Resident or talks_peaceably(target)) \
			and World.distance(player.tile, talk_cell(target)) <= HEARING_RANGE:
		_open_talk(target)  # A resident (560), or a peaceable talking monster (629, ui's side).
		return
	var door := _e_door
	if is_instance_valid(door) and player.tile in Terrain.edge_cells(door.key):
		World.command(player, "door", {"edge": [door.key.x, door.key.y, door.key.z]})
		return
	# 643, ui's side: a note on the door, from its cell or the cell faced.
	var at := note_cell_by(player)
	if at != NONE and note_sheet != null:
		note_sheet.show_note(at, note_at(at))


## 643, ui's side: the cell with a note that [param player] stands on, else
## the one it faces, else NONE.
func note_cell_by(player: Player) -> Vector2i:
	if not note_at(player.tile).is_empty():
		return player.tile
	if not note_at(player.tile + player.facing).is_empty():
		return player.tile + player.facing
	return NONE


## 643, ui's side: the note pinned at [param tile] in this zone, "" for none.
func note_at(tile: Vector2i) -> String:
	var notes: Variant = zone_notes.get(zone_name_here(), {})
	return str(notes.get(tile, "")) if notes is Dictionary else ""


## npc's "notes" message (643): a zone's notes, whole; empty clears.
func _on_notes_message(data: Dictionary) -> void:
	var zone := str(data.get("zone", ""))
	if zone.is_empty():
		return
	var notes: Dictionary = {}
	if data.get("notes") is Array:
		for each: Variant in data["notes"]:
			if each is Dictionary and each.get("tile") is Array and (each["tile"] as Array).size() == 2:
				var text := str(each.get("text", ""))
				if not text.is_empty():
					notes[Vector2i(int(each["tile"][0]), int(each["tile"][1]))] = text
	if notes.is_empty():
		zone_notes.erase(zone)
	else:
		zone_notes[zone] = notes


## 665, ui's side, each frame: the local player's shown cell entering a
## named room it has not just left says the room's name mid-screen
## (ArrivalCard.say: after the zone's name on a crossing, never over it).
func _update_room() -> void:
	if arrival_card == null:
		return
	var player := _local_player()
	if player == null:
		return
	var key := Level.room_at(level, player.shown_tile())
	if key == _room_here:
		return
	var now := Time.get_ticks_msec()
	if not _room_here.is_empty():
		_room_left_at[_room_here] = now
	_room_here = key
	if not key.is_empty() and now - int(_room_left_at.get(key, -ROOM_AGAIN_MSEC)) >= ROOM_AGAIN_MSEC:
		arrival_card.say(str(level["rooms"][key]["name"]))


## 643, ui's side, each frame: the sheet closes when its note is taken
## down or the player is neither on its cell nor facing it; the word at
## the cursor shows over a note's cell.
func _update_note() -> void:
	if note_sheet == null:
		return
	var player := _local_player()
	if note_sheet.visible:
		if player == null or note_at(note_sheet.tile) != note_sheet.text \
				or (player.tile != note_sheet.tile and player.tile + player.facing != note_sheet.tile):
			note_sheet.close()
	if _note_hover == null:
		return
	var over := _mouse_tile() if player != null and not zone_notes.is_empty() else NONE
	_note_hover.visible = over != NONE and not note_at(over).is_empty()
	if _note_hover.visible:
		_note_hover.position = get_viewport().get_mouse_position() + Vector2(16.0, 18.0)


## E held BANDAGE_HOLD_MSEC: a bandage command, on the player or companion
## under the cursor (within reach, or the server says why: 713), else on yourself.
func _check_bandage_hold() -> void:
	if not _e_held or Time.get_ticks_msec() - _e_since < BANDAGE_HOLD_MSEC:
		return
	_e_held = false
	var player := _local_player()
	if player == null:
		return
	var patient: GridEntity = player
	var target := _e_target
	if is_instance_valid(target) and (target is Player or target is Companion):
		patient = target  # Out of reach, the server says so (713), never yourself instead.
	bandage(player, patient)


## Asks the server to have [param player] bandage [param patient].
func bandage(player: Player, patient: GridEntity) -> void:
	World.command(player, "bandage", {"target": str(patient.get_path())})


## The 3D view (unless renderer is 2d) takes over drawing and picking; the 2D
## ground, walls, entities (still the replicated state, just unseen),
## cursor, ripple and toss arrow are hidden. The HUD stays. Input is
## handled here as for the 2D view, with the picks and the hover and
## ripple drawing routed to the view (see _mouse_grid,
## _entity_under_mouse, _door_under_mouse).
func _show_3d() -> void:
	for node in [ground, near_walls, $YSort, cursor, ripple, toss_aim]:
		node.visible = false
	_client3d = preload("res://client3d/client3d.tscn").instantiate()
	add_child(_client3d)
	_client3d.room_built.connect(_on_room_built)
	_client3d.fields_done.connect(_replay.bind(_held_clearings))
	_client3d.room_filled.connect(_replay.bind(_held_redraws))
	_client3d.setup(_terrain, level_centre)
	_client3d.bubbles = bubbles
	_show_towns()
	if Tuning.allowed():
		Tuning.register_source("camera", _camera_value, _set_camera_value, camera_fields)  # 673.
		Tuning.register_source("monsters", Monster.tuning_value, Monster.set_tuning_value, Monster.tuning_fields)  # 673 step 2.
		Tuning.register_source("feel", ArtKit.feel_value, ArtKit.set_feel_value, ArtKit.feel_fields)  # 673 step 2: art/kit/feel.json.
		Tuning.register_source("effects", Items.effect_value, Items.set_effect_value, Items.effect_fields)  # 682: the remedy's heal.
		Tuning.register_source("companions", CompanionCard.tuning_value, CompanionCard.set_tuning_value, CompanionCard.tuning_fields)  # 706: her holds.
		Tuning.register_source("named", NamedEnemy.tuning_value, NamedEnemy.set_tuning_value, NamedEnemy.tuning_fields)  # 716: days dead.


# --- WASD ---------------------------------------------------------------------------

## The grid direction WASD keys point at a camera yaw: [param keys] is
## (D - A, W - S); W is up the screen, D to its right. Eight directions;
## ZERO for none. At yaw 0, the 2D view's, W is (-1, -1).
static func wasd_direction(keys: Vector2, yaw_degrees: float) -> Vector2i:
	return grid_direction(wasd_vector(keys, yaw_degrees))


## The way [param keys] point on the ground at [param yaw_degrees], exact
## (grid units, not rounded to the eight; decision 678's line).
static func wasd_vector(keys: Vector2, yaw_degrees: float) -> Vector2:
	var yaw := deg_to_rad(yaw_degrees)
	# Up the screen is away from the camera along the ground; see
	# Client3D._camera_offset, which puts the camera on the +x +z side.
	var up := Vector3(-1, 0, -1).rotated(Vector3.UP, yaw)
	var right := Vector3(1, 0, -1).rotated(Vector3.UP, yaw)
	var along := up * keys.y + right * keys.x
	return Vector2(along.x, along.z)


## Decision 678 (Jeff: "walking still wants to be on a diagonal and it
## doesn't fit with the new camera"): the two of the eight steps either
## side of [param along] from [param from], the one that leaves the body
## nearer the line through [param origin] first (a DDA: over a few steps
## the walk goes where it is pushed, not on the nearest diagonal); the
## nearer to the way first on a tie. ZERO for no way.
static func line_steps(from: Vector2i, origin: Vector2, along: Vector2) -> Array[Vector2i]:
	if along.length() < 0.01:
		var none: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
		return none
	var unit := along.normalized()
	var octant := unit.angle() / (PI / 4.0)
	var near_k := roundf(octant)
	var other_k := floorf(octant) + 1.0 if near_k == floorf(octant) else floorf(octant)
	var nearest := Vector2i(roundi(cos(near_k * PI / 4.0)), roundi(sin(near_k * PI / 4.0)))
	var other := Vector2i(roundi(cos(other_k * PI / 4.0)), roundi(sin(other_k * PI / 4.0)))
	var off_nearest := absf(unit.cross(Vector2(from + nearest) - origin))
	var off_other := absf(unit.cross(Vector2(from + other) - origin))
	var picks: Array[Vector2i] = [nearest, other]
	if off_other < off_nearest - 0.0001:
		picks = [other, nearest]
	return picks


## The held walk's next step along [param along] (decision 678): from the
## walk's end, the line's pick, or the other where the pick's step is
## walled. The line is anchored where the walk is when the way changes (a
## key, the yaw) or the body is off it (a push, a walled pick taken round).
func _line_step(player: Player, along: Vector2) -> Vector2i:
	var from := player.walk_end()
	var line := line_anchor(_walk_origin, _walk_along, from, along)
	_walk_origin = line[0]
	_walk_along = line[1]
	player.hint_line(_walk_origin, _walk_along)
	var picks := line_steps(from, _walk_origin, _walk_along)
	if World._terrain_blocks_step(from, picks[0], true) and not World._terrain_blocks_step(from, picks[1], true):
		return picks[1]
	return picks[0]


## The held walk's line [origin, unit way] for the way [param along], from
## the line it was on ([param origin], [param way]; INF none) and the walk's
## end [param from]: a new one from that cell when there was none, the way
## turned LINE_TURN or more, or the walk is LINE_OFF off it (a push, a
## walled pick taken round); a smaller change of way goes on from the walk's
## point on the old line (678 amended).
static func line_anchor(origin: Vector2, way: Vector2, from: Vector2i, along: Vector2) -> Array:
	var unit := along.normalized()
	if origin == Vector2.INF or unit.dot(way) < cos(LINE_TURN) or absf(way.cross(Vector2(from) - origin)) > LINE_OFF:
		return [Vector2(from), unit]
	if unit.dot(way) < 0.9999:
		return [origin + way * way.dot(Vector2(from) - origin), unit]
	return [origin, way]


## The nearest of the eight directions to [param vector] (grid units),
## or ZERO for a vector too short to point anywhere.
static func grid_direction(vector: Vector2) -> Vector2i:
	if vector.length() < 0.01:
		return Vector2i.ZERO
	var angle := snappedf(vector.angle(), PI / 4.0)
	return Vector2i(roundi(cos(angle)), roundi(sin(angle)))


## The walk keys held, as the letters the walk reads ("wd"), from the
## keyboard through the bound keys (Keys.walk_held, 453 amended: arrows
## or ZQSD once bound in the Options) or from --test-walk while it runs
## (which names the letters).
func _held_key_names() -> String:
	if Net.test_latency > 0:
		return _lat_keys
	if not Net.test_walk.is_empty():
		return _test_walk_keys()
	if is_typing():
		return ""
	if DisplayServer.get_name() == "headless":
		return ""
	return Keys.walk_held()


## (D - A, W - S) for [param keys] as _held_key_names gives them.
static func key_vector(keys: String) -> Vector2:
	return Vector2(float("d" in keys) - float("a" in keys), float("w" in keys) - float("s" in keys))


## 3D: while the middle button is held the drag tilts or turns the
## camera, and a missed release (the button let go outside the window)
## ends it.
func _drag_yaw() -> void:
	if _client3d == null or is_nan(_drag_from.x):
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_end_middle_drag()
		return
	_middle_drag(Vector2(DisplayServer.mouse_get_position()) - _drag_from)


## The middle button went down at [param at] (screen px). With Ctrl
## ([param pan]) it pans; otherwise what it is waits on which way, if any,
## it moves.
func _begin_middle_drag(at: Vector2, pan := false) -> void:
	_drag_from = at
	_drag = Drag.UNDECIDED
	_drag_pan = pan


## The drag is [param offset] (screen px) from where it went down. With
## Ctrl it pans the view, which springs back onto the player when let go;
## otherwise, in either scheme (671 amended), it is a free turn or a pitch
## peek by the axis it first moves on.
func _middle_drag(offset: Vector2) -> void:
	if _drag == Drag.PAN:
		_client3d.pan_by(offset)
		return
	if _drag == Drag.UNDECIDED:
		if absf(offset.x) < DRAG_AXIS_PX and absf(offset.y) < DRAG_AXIS_PX:
			return
		if _drag_pan:
			_drag = Drag.PAN
			_client3d.begin_pan()
			_client3d.pan_by(offset)
			return
		if absf(offset.x) >= absf(offset.y):
			_drag = Drag.TURN
			_client3d.begin_drag()
		else:
			_drag = Drag.PITCH
			_client3d.begin_pitch_peek()
	if _drag == Drag.TURN:
		_client3d.drag(offset.x * DRAG_DEGREES_PER_PX)
	else:
		_client3d.pitch_peek(offset.y)


func _end_middle_drag() -> void:
	_drag_from = Vector2(NAN, NAN)
	match _drag:
		Drag.TURN:
			_client3d.end_drag()
		Drag.PITCH:
			_client3d.end_pitch_peek()
		Drag.PAN:
			_client3d.end_pan()
	_drag = Drag.UNDECIDED


## Click scheme, 3D: the walk's forward key puts the camera overhead and
## back puts it to the normal pitch, to stay (671, Client3D.set_overhead;
## saved), and left/right turn it while held (W/S and A/D by default, the
## Options' bindings); letting go settles the turn on one of the eight
## views (saved). The keys do nothing else in this scheme (and nothing at
## all in 2D).
func _drive_camera_keys(delta: float) -> void:
	if _client3d == null or Net.controls != "click":
		return
	var keys := _held_key_names()
	var tilt := float("w" in keys) - float("s" in keys)
	var turn := float("d" in keys) - float("a" in keys)
	if tilt != 0.0 and not _tilting:
		_client3d.set_overhead(tilt > 0.0)  # 671: on the press, to stay.
	_tilting = tilt != 0.0
	if turn != 0.0:
		_client3d.turn(turn, delta)
		_turning = true
	elif _turning:
		_turning = false
		_client3d.end_turn()


func _view_yaw() -> float:
	return _client3d.yaw if _client3d != null else 0.0


## The stand key with a bow, each frame (583 amended; Jeff: "holding down
## shift while running allows you to move while aiming - the point of
## shift is to stand firm and start nocking"): [param held] (Shift down,
## not typing, nothing on the cursor) and nothing raised draws at once,
## the server standing the body firm (World.stand_firm: its walk, route
## and queued steps dropped); let go while drawn, the bow is lowered, the
## arrow kept, nothing loosed, unless [param left_down]: then the left
## button's release looses (583 amended (2)). After a shot with Shift still down the next
## draw starts. Nothing without a bow and arrows in hand.
func drive_stand_draw(held: bool, left_down := false) -> void:
	var player := _local_player()
	if player == null or World.off_hand(player) != "draw":
		return
	if held and _stance.is_empty():
		_raise_off_hand(player)
	elif not held and not left_down and _stance == "draw":
		World.command(player, "stance", {"kind": ""})
		_stance = ""


## WASD each frame: while a direction is held, the next step goes as the
## one on screen ends (and any click walk is dropped); standing still,
## the body faces the cursor.
func _drive_wasd() -> void:
	var player := _local_player()
	if player == null or Net.controls != "wasd" or _arriving():
		if _client3d != null:
			_client3d.set_frozen(false)
		if player != null:
			player.aim = Vector2.ZERO
		return
	# Before the first step: a step sent before prediction is on would be
	# taken by the server and never shown.
	player.enable_prediction()
	var keys := _held_key_names()
	# The camera holds still under a held key, so a direction never turns
	# under the hand; a middle drag meanwhile applies when they let go.
	if _client3d != null:
		_client3d.set_frozen(not keys.is_empty())
	var along := wasd_vector(key_vector(keys), _view_yaw())
	var direction := Vector2i.ZERO
	if along.length() < 0.01:
		_walk_origin = Vector2.INF
		player.hint_line(Vector2.INF, Vector2.ZERO)
	else:
		direction = _line_step(player, along)  # 678: on the line, not the nearest of the eight.
	_record_walk(player)
	if _stance == "draw" or _stance == "lob" or player.raised == "draw":
		# 583 amended: drawn, the body stands firm; a walk key only turns it (a lob too, 677).
		player.hint_step(Vector2i.ZERO)
		player.aim = Vector2.ZERO
		if direction == Vector2i.ZERO:
			_aim_at_cursor(player)
		else:
			face_toward(player, direction)
		return
	player.hint_step(direction)  # 655 amended: the walk shown bends toward the step to come.
	if direction == Vector2i.ZERO:
		_aim_at_cursor(player)
		return
	player.aim = Vector2.ZERO
	_held_target = NONE
	_send_held_step(player, direction)


## A held walk's step [param direction] (a key, or the button steering,
## 678), sent as the one on screen ends.
func _send_held_step(player: Player, direction: Vector2i) -> void:
	if not player.ready_for_step():
		return
	if Net.is_authority() and (not player.queued_steps.is_empty() or World.tick + 1 < player.next_move_tick):
		return  # The authority queues and times steps itself; one ahead at most.
	var from := player.walk_end()
	if World._terrain_blocks_step(from, direction, true):
		_aim_at_cursor(player)
		return
	var ahead := World.get_entity_at(from + direction)
	if ahead != null and ahead != player and ahead.is_creature():
		if Time.get_ticks_msec() - _bump_sent_at < BUMP_SEND_INTERVAL * 1000.0:
			return
		_bump_sent_at = Time.get_ticks_msec()
	if _test_holding:
		_test_hold_counts["steps"] += 1
	World.command_step(player, direction)


## WASD, standing still: the body turns to the cursor on this screen at
## once, and the facing others see follows, a few times a second at most.
## The archery aim, each frame (ui's side; Jeff, 2026-10-22: "for aiming
## bow and drawning back movement mouse disappears and the game draws a
## semi circle for distance... use a circle which the aim can move along at
## many degrees"): while the bow is drawn the cursor hides, the aim's angle
## is read from the mouse on the grid, the arc drawn at the current range
## step round the archer with the marker at the angle and the step's pips;
## let go, it all goes and the cursor is back.
func _update_aim(player: Player, drawing: bool) -> void:
	if not drawing:
		if aim_drawn:
			aim_drawn = false
			_aim_since = 0
			_show_cursor(true)
			if _client3d != null:
				_client3d.aim_arc(Vector2.ZERO, 0.0, 0.0, 0.0, 0, false)
				_client3d.aim_lead(Vector2.ZERO, false)  # 617: the view eases back onto the archer.
				_client3d.aim_reach(0.0, Vector2.ZERO)  # 669: and back to the player's own zoom.
			if _aim_line != null:
				_aim_line.visible = false
		return
	var origin := Iso.local_to_grid(player.position)
	var toward_point := _aim_fixed if is_finite(_aim_fixed.x) else _mouse_grid()
	if is_nan(toward_point.x):
		return
	if not aim_drawn:
		aim_drawn = true
		_show_cursor(false)
	var toward := toward_point - origin
	if toward.length() > 0.05:
		aim_angle = toward.angle()
	var radius := range_now(player)
	if radius <= 0:
		_aim_since = 0
	elif _aim_since == 0:
		_aim_since = Time.get_ticks_msec()
	var alpha := aim_fade(Time.get_ticks_msec() - _aim_since) if _aim_since > 0 else 0.0
	var point := aim_point(origin, aim_angle, float(radius))
	_aim_mark_cell = Vector2i(point.round())
	var pips := aim_pips(Items.verb_of(World.drawn_with(player)), World.draw_step(player), radius)
	if _client3d != null:
		_client3d.aim_arc(origin, aim_angle, float(radius), alpha, pips, radius > 0, spread_now(player),
				float(World.full_range_of(player)))
		_client3d.aim_lead(Vector2.from_angle(aim_angle), true)  # 617: the view leads toward the aim while drawn.
		_client3d.aim_reach(float(radius), Vector2.from_angle(aim_angle))  # 669: and widens to keep the reach on screen.
	else:
		_update_aim_line(origin, float(radius), alpha)


## The current range step in cells: items' World.range_of by name (0 before
## draw_min), else the verb's one range once the draw counts.
static func range_now(player: GridEntity) -> int:
	if World.has_method("range_of"):
		return int(World.call("range_of", player))
	var verb := Items.verb_of(World.drawn_with(player))
	return int(verb.get("cells", 0)) if World.draw_of(player) > 0.0 else 0


## The cone of flight's half-angle now (radians): the sim's World.spread_of
## by name (combat's design: the server rolls the line inside it; -1 while
## not drawing), -1 before it lands or for a bow with none (the arc alone).
static func spread_now(player: GridEntity) -> float:
	if World.has_method("spread_of"):
		return float(World.call("spread_of", player))
	return -1.0


## The verb's range steps in cells, shortest first (items' "range_steps";
## [] when the verb has none).
static func range_steps(player: GridEntity) -> Array:
	var verb := Items.verb_of(World.drawn_with(player))
	var steps: Variant = verb.get("range_steps", verb.get("steps", []))
	return steps if steps is Array else []


## The pips beside the marker (decision 669): the shot's strength at the
## aim's reach, [param radius] cells, from a bow of [param verb] drawn to
## [param step], in AIM_PIPS (full strength all of them; 2, 3, 4 up to
## full draw, then 3, 2, 1 in the bands past it); none before the draw counts.
const AIM_PIPS := 4
static func aim_pips(verb: Dictionary, step: int, radius: int) -> int:
	var damage_at: Array = verb.get("damage_at", [])
	if step < 0 or radius <= 0 or damage_at.is_empty():
		return 0
	var most := float(damage_at.max())
	return clampi(roundi(AIM_PIPS * Items.damage_for(verb, step, radius) / maxf(most, 0.001)), 1, AIM_PIPS)


## Where the aim lands on the arc: [param origin] plus [param radius] the
## way of [param angle].
static func aim_point(origin: Vector2, angle: float, radius: float) -> Vector2:
	return origin + Vector2.from_angle(angle) * radius


## The arc's fade-in over AIM_FADE_MSEC from the step's first show.
const AIM_FADE_MSEC := 200.0
static func aim_fade(msec: int) -> float:
	return clampf(float(msec) / AIM_FADE_MSEC, 0.0, 1.0)


## The "loose" command's arguments: the angle (radians, NAN for none: the
## old aim) beside the cell the aim lands on, for either server.
static func loose_args(angle: float, at: Vector2i) -> Dictionary:
	var args := {"at": [at.x, at.y]}
	if not is_nan(angle):
		args["angle"] = angle
	return args


## The OS cursor shown or hidden (hidden while the bow is drawn; the
## mouse still moves the aim).
func _show_cursor(show: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show else Input.MOUSE_MODE_HIDDEN


## The 2D view's arc: a Line2D through the semicircle's points, projected.
func _update_aim_line(origin: Vector2, radius: float, alpha: float) -> void:
	if _aim_line == null:
		_aim_line = Line2D.new()
		_aim_line.width = 3.0
		_aim_line.default_color = UiTheme.color("brass_bright")
		cursor.get_parent().add_child(_aim_line)
	_aim_line.visible = radius > 0.0
	if not _aim_line.visible:
		return
	var points := PackedVector2Array()
	for i in 33:
		var a := aim_angle - PI * 0.5 + PI * i / 32.0
		points.append(Iso.grid_to_local(origin + Vector2.from_angle(a) * radius))
	_aim_line.points = points
	_aim_line.modulate.a = alpha


func _aim_at_cursor(player: Player) -> void:
	var cursor := _mouse_grid()
	if is_nan(cursor.x) or DisplayServer.get_name() == "headless":
		player.aim = Vector2.ZERO
		return
	player.aim = cursor - Iso.local_to_grid(player.position)
	var direction := grid_direction(player.aim)
	if direction == Vector2i.ZERO or direction == player.facing or not player.ready_for_step():
		return
	if Time.get_ticks_msec() - _face_sent_at < FACE_SEND_INTERVAL * 1000.0:
		return
	_face_sent_at = Time.get_ticks_msec()
	World.command(player, "face", {"dir": [direction.x, direction.y]})


## The body turned [param direction]'s way (a walk key while drawn, 583
## amended), as the cursor's turn is sent: a few times a second at most.
func face_toward(player: Player, direction: Vector2i) -> void:
	if direction == Vector2i.ZERO or direction == player.facing:
		return
	if Time.get_ticks_msec() - _face_sent_at < FACE_SEND_INTERVAL * 1000.0:
		return
	_face_sent_at = Time.get_ticks_msec()
	World.command(player, "face", {"dir": [direction.x, direction.y]})


## WASD, a click not on a sprite. Left: a far cell is walked to (until a
## key is pressed); otherwise it is an attack the cursor's way, on whoever
## stands next to the player there, or a swing at air. Right: grab whoever
## stands next to the player the cursor's way; dragging tosses, as ever.
func _wasd_click(player: Player, button: MouseButton) -> void:
	var cursor := _mouse_grid()
	if is_nan(cursor.x):
		return
	var at := player.shown_tile()
	var direction := grid_direction(cursor - Iso.local_to_grid(player.position))
	if direction == Vector2i.ZERO:
		return
	var next := World.get_entity_at(at + direction)
	var reachable := next != null and next != player and World.can_target(player, next) \
			and World.can_melee(at, at + direction)
	if button == MOUSE_BUTTON_LEFT:
		var tile := _snap_to_floor(cursor)
		if tile != NONE and World.distance(at, tile) > 1:
			_move_click(player, tile)
			_held_target = NONE  # No hold-to-move in WASD: the keys steer.
		elif reachable and is_friend(next) and not Keys.held("stand"):
			_talk_to(player, next)  # Decision 454: a friend beside you is talked to, not hit.
		elif reachable and next.is_creature() and not _is_own_companion(next):
			World.command_attack(player, next)
		else:
			World.command(player, "swing", {"dir": [direction.x, direction.y]})
	elif button == MOUSE_BUTTON_RIGHT and reachable:
		_toss_target = next
		_toss_from = get_global_mouse_position()


## The monster a left click now would attack (the one under the cursor,
## see _entity_under_mouse), or null.
func _foe_under_mouse() -> GridEntity:
	var player := _local_player()
	if player == null:
		return null
	var entity := _entity_under_mouse()
	return entity if entity is Monster and World.can_target(player, entity) else null


## A companion that belongs to this peer's player.
func _is_own_companion(entity: GridEntity) -> bool:
	return entity is Companion and entity.keeper_peer != 0 and entity.keeper_peer == Net.local_id


## Turns everything on the ground to the current azimuth: the floor layer
## (laid out at azimuth 0 by its TileSet, so it gets the change of
## projection as a transform), the walls, with their near/far layer, and
## the doors. Entities place themselves each frame.
func _apply_azimuth() -> void:
	ground.transform = Iso.ground_transform() * Transform2D(Vector2(Iso.HALF.x, Iso.HALF.y),
			Vector2(-Iso.HALF.x, Iso.HALF.y), Vector2.ZERO).affine_inverse()
	var floor_at := _floor_test() if not _walls.is_empty() else Callable()
	for wall in _walls:
		var layer: Node = near_walls if WallEdge.is_near(wall.key, floor_at) else $YSort
		if wall.get_parent() != layer:
			wall.reparent(layer, false)
		wall.refresh()
	for door in World.get_doors():
		door.refresh()


## A move click: sends the player to [param tile] (NONE: nowhere near the
## floor, ignored) and ripples there. Holding the button keeps retargeting
## from _process as the cursor moves to other cells.
func _move_click(player: Player, tile: Vector2i, ripple_it := true) -> void:
	_pack_wanted = null
	_talk_wanted = null
	if _free_own(player) != null:
		_free_route(player, tile)
		if ripple_it and tile != NONE:
			if _client3d != null:
				_client3d.ripple(tile)
			else:
				ripple.start(Iso.tile_to_local(tile))
		return
	_held_target = tile
	_held_steered = false
	if tile == NONE:
		return
	World.command_move(player, tile)
	_held_sent_at = Time.get_ticks_msec()
	if _test_holding:
		_test_hold_counts["orders"] += 1
	if not ripple_it:
		return
	if _client3d != null:
		_client3d.ripple(tile)
	else:
		ripple.start(Iso.tile_to_local(tile))


## Free movement, the own body (decision 689): each frame the way meant
## (the keys', the held button's toward the cursor, or a click's route,
## World.walk_path's cells steered along) goes to the own body's view
## (FreeNet.Own), which shows it at once and closes a command every
## FreeNet.SEND_SECONDS; those go to the server (World.request_free; a
## host's straight to World.take_free).
var _free := {"path": [], "held": false, "at": 0, "chase": null}
## How long the button is held after a click before it steers to the
## cursor rather than walking the click's route.
const FREE_HOLD_SECONDS := 0.25
## 724: a click route whose next step another body has stood in the way
## of for FREE_BLOCKED_SECONDS (of the sim's ticks) steps to its own right, if that cell is
## open, and plans again round the body as a wall; with its right shut it
## waits, as the other, coming the other way, has its right open. Past
## FREE_GIVE_UP_SECONDS blocked, the route is given up.
const FREE_BLOCKED_SECONDS := 0.25
const FREE_GIVE_UP_SECONDS := 2.0
## Blocked means stood still against another: past this far (cells) from
## where the block began, it got on, and the count starts again.
const FREE_BLOCKED_MOVED := 0.15
## How far along its route a free body looks for a cell in clear line
## (_free_pull, 689 amended (5)): a few line checks a frame at most.
const FREE_PULL_CELLS := 12
## How often a chase sends its attack order again while out of reach (697).
const FREE_CHASE_RESEND_MS := 1000


## The own body's view while it is a free body, else null: a client's from
## the server's first state of it, a host's made here.
func _free_own(player: Player) -> FreeNet.Own:
	if player == null:
		return null
	if player.free_view is FreeNet.Own:
		return player.free_view
	if Net.is_authority() and World.free_body(player):
		player.free_view = FreeNet.Own.new()
		return player.free_view
	if not player.free_state.is_empty():
		# Its state heard before it was known for its own (a body rebuilt by a
		# reset, its spawn bringing the state): heard again, as its own.
		player._free_heard()
		if player.free_view is FreeNet.Own:
			return player.free_view
	return null


## Each frame: true when the own body is free (the grid's drive skipped).
func _free_drive(delta: float) -> bool:
	var player := _local_player()
	var own := _free_own(player)
	if own == null:
		_free["path"] = []
		return false
	var intent := _wind_up_held(player, _free_intent(player, own))
	_record_walk(player)
	if intent != Vector2.ZERO:
		player.aim = Vector2.ZERO
	elif Net.controls == "wasd" and (_free["path"] as Array).is_empty():
		_aim_at_cursor(player)
	var commands := own.hold(player, intent, minf(delta, 0.1))
	if commands.is_empty():
		return true
	if Net.is_authority():
		World.take_free(player, commands)
	else:
		World._to_server(&"request_free", [player.get_path(), FreeNet.pack_commands(commands)])
	return true


## [param intent], or ZERO while the local player's own heavy blow winds up
## and the server would hold it (392 amended (2): under
## World.WIND_UP_LEAVE_INTENT, or strictly within World.WIND_UP_KEEP_ANGLE
## of the way to its target), so the view stands as the server does; any
## other way goes, and the server gives the wind-up up.
func _wind_up_held(player: Player, intent: Vector2) -> Vector2:
	if not player.winding.is_connected(_on_own_winding):
		player.winding.connect(_on_own_winding)
	if Time.get_ticks_msec() >= int(_own_wind["until"]):
		return intent
	var way: Vector2 = _own_wind["way"]
	if intent.length() < World.WIND_UP_LEAVE_INTENT 			or (way.length() > 0.001 and intent.normalized().dot(way.normalized()) > cos(deg_to_rad(World.WIND_UP_KEEP_ANGLE))):
		return Vector2.ZERO
	_own_wind["until"] = 0  # Left: the server's give-up follows.
	return intent


## The local player's own wind-up begun ([param ticks] > 0, towards
## [param direction]) or given up (0), for _wind_up_held.
func _on_own_winding(direction: Vector2i, ticks: int) -> void:
	_own_wind["way"] = Vector2(direction)
	_own_wind["until"] = Time.get_ticks_msec() + int(ticks * World.TICK_DT * 1000.0) if ticks > 0 else 0


## The way the player means to go this frame, a unit vector or ZERO.
func _free_intent(player: Player, own: FreeNet.Own) -> Vector2:
	if is_typing():
		return Vector2.ZERO
	var at := own.shown(player)
	if Net.controls == "wasd":
		var along := wasd_vector(key_vector(_held_key_names()), _view_yaw())
		if along.length() > 0.01:
			_free_taken_over(player)
			_free["path"] = []
			return along.normalized()
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _test_holding
	if not held:
		_free["held"] = false
	# A click walks its route; the button still held past FREE_HOLD_SECONDS
	# steers to the cursor instead (Jeff: "wasn't one click enough before?").
	var steering: bool = _free["held"] and Time.get_ticks_msec() - int(_free["at"]) > FREE_HOLD_SECONDS * 1000.0
	if steering and Net.controls != "wasd":
		_free_taken_over(player)
		var cursor := _mouse_grid()
		if not is_nan(cursor.x):
			var way := cursor - at
			var from := World.free_cell(player, at)
			var goal := Vector2i(cursor.round())
			if from == goal or World._line_clear(from, goal, goal, player):
				_free["path"] = []  # In the open: straight at the cursor.
				return way.normalized() if way.length() > 0.25 else Vector2.ZERO
			# Something in the way (a tree, a wall): round it, as a held walk
			# on the grid went, planned again as the cursor moves.
			var now := Time.get_ticks_msec()
			if goal != _free.get("goal", NONE) or now - int(_free.get("planned", 0)) > 300:
				_free["goal"] = goal
				_free["planned"] = now
				var route: Array = []
				for cell: Vector2i in World.walk_path(from, goal, player):
					route.append(cell)
				_free["path"] = route
			if (_free["path"] as Array).is_empty():
				return way.normalized() if way.length() > 0.25 else Vector2.ZERO
	_free_chase(player, at)
	var path: Array = _free["path"]
	_free_pull(player, path, at)
	while not path.is_empty():
		var next := Vector2(path[0])
		var near := 0.05 if path.size() == 1 else 0.45
		if at.distance_to(next) > near:
			var way := next - at
			if _free_blocked(player, at, way, path):
				return Vector2.ZERO if (_free["path"] as Array).is_empty() else (Vector2(_free["path"][0]) - at).normalized()
			# The last cell: slower as it comes, so it stops on the centre.
			return way.normalized() * (clampf(way.length() * 4.0, 0.2, 1.0) if path.size() == 1 else 1.0)
		if path.size() == 1 and not own.pending.is_empty():
			# 689 amended (6): the last cell is kept till the server has every step: one
			# it dropped (a stall past FREE_BANK_TICKS) puts the body back
			# short, and the route walks on from there instead of ending.
			return Vector2.ZERO
		path.pop_front()
	return Vector2.ZERO


## 724: where [param entity] stands now, as this peer last heard: another's
## free body its mirror's newest state (not drawn display_delay_ticks
## behind, nor its tile, which lags: physics' test saw a phantom at a
## start long left), anyone else its tile.
static func _free_stands(entity: GridEntity) -> Vector2:
	if entity is Player and (entity as Player).free_view is FreeNet.Mirror:
		var samples: Array = ((entity as Player).free_view as FreeNet.Mirror).samples
		if not samples.is_empty():
			return samples.back()[1]
	return Vector2(entity.tile)


## 724: the body (not [param player]) against [param at] ahead along
## [param heading]: its centre (_free_stands) within two FREE_RADIUS and a
## little, less than 60 degrees off the way.
func _free_body_ahead(player: Player, at: Vector2, heading: Vector2) -> GridEntity:
	var best: GridEntity = null
	var nearest := World.FREE_RADIUS * 2.0 + 0.2
	for entity in World.get_entities():
		if entity == player or not is_instance_valid(entity) or not entity.spawned:
			continue
		var off := _free_stands(entity) - at
		if off.length() < nearest and off.length() > 0.001 and off.normalized().dot(heading) > 0.5:
			nearest = off.length()
			best = entity
	return best


## 724 (physics: two click routes met head-on in the two-wide passage and
## stood face to face for good; the server stops each body a radius off the
## other and steers neither): whether another body stands in the route's
## way at [param at], heading [param way]. Blocked FREE_BLOCKED_SECONDS, the
## route steps to the body's own right (two coming head-on pick opposite
## sides) if that cell is walkable and empty, then goes round the other as
## a wall to the route's end; with the right shut it waits for the other
## to step aside. Blocked FREE_GIVE_UP_SECONDS, the route is given up.
## True when [member _free]'s path was changed (or emptied).
func _free_blocked(player: Player, at: Vector2, way: Vector2, path: Array) -> bool:
	var other := _free_body_ahead(player, at, way.normalized())
	# Counted in the sim's ticks, not the wall's: a server that stalls (a
	# test's hold, a long frame) stops the clock with the bodies.
	var now := World.tick
	if not is_same(_free.get("blocked_route"), path):
		# Another route (a new click): its own count, from nothing.
		_free["blocked_route"] = path
		_free.erase("blocked_since")
		_free.erase("blocked_at")
		_free.erase("sidestepped")
	if other == null or at.distance_to(_free.get("blocked_at", at)) > FREE_BLOCKED_MOVED:
		# Nobody against it, or it got on (a body passing beside, the other
		# stepping aside): not blocked.
		_free.erase("blocked_since")
		_free.erase("blocked_at")
		_free.erase("sidestepped")
		return false
	var since: int = _free.get("blocked_since", now)
	_free["blocked_since"] = since
	_free["blocked_at"] = _free.get("blocked_at", at)
	var blocked := float(now - since) / World.TICK_RATE
	if blocked >= FREE_GIVE_UP_SECONDS:
		print("[free] %s's route given up at %s: %s at %s in the way %.1f s (tick %d)" % [player.name, at, other.name, _free_stands(other), blocked, now])
		_free["path"] = []
		_free.erase("blocked_since")
		_free.erase("blocked_at")
		_free.erase("sidestepped")
		return true
	if blocked < FREE_BLOCKED_SECONDS or _free.get("sidestepped", false):
		return false
	var heading := way.normalized()
	var from := World.free_cell(player, at)
	var side := from + Vector2i(Vector2(-heading.y, heading.x).round())
	var there := Vector2i(_free_stands(other).round())
	if side == there or not World.is_walkable(side) or World.get_entity_at(side) != null 			or not World._line_clear(from, side, side, player):
		return false  # The right is shut: wait; the other's is open.
	_free["sidestepped"] = true
	var goal: Vector2i = path[-1]
	var route: Array = [side]
	# Round the other as a wall, unless it stands on the route's end (it
	# will go; walled, there would be no way at all).
	for cell: Vector2i in World.find_path(side, goal, true, player, 0, false, {} if there == goal else {there: true}):
		route.append(cell)
	if route.back() != goal:
		route.append(goal)  # No way round now: on for the end, blocked again or not.
	print("[free] %s steps right from %s to %s round %s at %s (tick %d)" % [player.name, from, side, other.name, there, now])
	_free["path"] = route
	_free["blocked_route"] = route  # The same block: its clock and its one step aside go on.
	return true


## The route's string pulled (689 amended (5); Jeff: "mouse move directions is
## very unreponsive"): from where the body stands, straight at the farthest
## of its next FREE_PULL_CELLS cells in clear line (World._line_clear, as a
## held steer goes straight at the cursor), not cell centre to centre: a
## new click mid-walk heads its way at once instead of angling to the next
## centre first (765 ms to settle on the new way, the grid 150). Else a cell
## passed by on the way to the next is not gone back for.
func _free_pull(player: Player, path: Array, at: Vector2) -> void:
	var from := World.free_cell(player, at)
	for k in range(mini(path.size() - 1, FREE_PULL_CELLS), 0, -1):
		if World._line_clear(from, path[k], path[k], player):
			for i in k:
				path.pop_front()
			return
	while path.size() >= 2 and at.distance_to(Vector2(path[1])) <= Vector2(path[0]).distance_to(Vector2(path[1])):
		path.pop_front()


## Her route for his body while she leads him (695, ui's side; Guide under
## free walk, companions' side sends it each time her heel cell moves, from
## the cell after his): walked as a click route is. An empty path ends her
## lead (any stop but arriving: arriving sends none, the last route walked
## out). Another zone's, or a body on the grid, is not ours to steer.
func _guide_route(route: Dictionary) -> void:
	var player := _local_player()
	if player == null or String(route.get("zone", "")) != String(player.zone) or _free_own(player) == null:
		return
	var path: Array = []
	for at: Variant in route.get("path", []):
		if at is Vector2i:
			path.append(at)
		elif at is Array and (at as Array).size() == 2:
			path.append(Vector2i(int(at[0]), int(at[1])))
	if path.is_empty():
		if _free.get("guided", false):
			_free["path"] = []
		_free["guided"] = false
		return
	_free["path"] = path
	_free["guided"] = true


## A click on a creature to strike, or a shove let go, with a free body
## (697, ui's side; Jeff on v0.1.186: "left click on grave robber does move
## to them, but quite choppy"): the server's order holds and never steps a
## free body (combat's side), so the client walks it there, a route to the
## target's cell planned again as it moves (_free_chase), and stops in
## reach of it (699: centres within World.reach_limit), where the server
## strikes.
func _free_chase_start(player: Player, target: GridEntity, shove := false) -> void:
	if _free_own(player) == null:
		return
	_free_taken_over(player)
	_free["chase"] = target
	_free["chase_shove"] = shove
	_free["chase_tile"] = NONE
	_free["chase_sent"] = Time.get_ticks_msec()


## Each frame of a chase (697): in reach of the target (the centres within
## World.reach_limit, 699) or the target
## gone, done; its tile moved, the route planned again; the attack order
## sent again each FREE_CHASE_RESEND_MS while more than two cells off (the
## server drops one 4 s old: Player.FREE_CHASE_TICKS), never nearer, so a
## late one cannot land after the strike and swing again.
func _free_chase(player: Player, at: Vector2) -> void:
	var foe: Variant = _free.get("chase")
	if foe == null:
		return
	if not is_instance_valid(foe) or not (foe as GridEntity).spawned or (foe as GridEntity).zone != player.zone 			or not World.can_target(player, foe):
		_free["chase"] = null
		_free["path"] = []
		return
	var target := foe as GridEntity
	var cell := World.free_cell(player, at)
	var apart := World.distance(cell, target.tile)
	if at.distance_to(World.body_centre(target)) <= World.reach_limit(player) - 0.02:
		_free["chase"] = null
		_free["path"] = []
		return
	if target.tile != _free["chase_tile"]:
		_free["chase_tile"] = target.tile
		var route: Array = []
		for step: Vector2i in World.walk_path(cell, target.tile, player):
			route.append(step)
		_free["path"] = route
	var now := Time.get_ticks_msec()
	if not _free["chase_shove"] and apart > 2 and now - int(_free["chase_sent"]) >= FREE_CHASE_RESEND_MS:
		_free["chase_sent"] = now
		if Net.is_authority():
			World.order_attack(player, target)
		else:
			World._to_server(&"request_attack", [player.get_path(), target.get_path(), []])


## The player's own key, click or held steer (697): a chase given up, and
## a lead taken over.
func _free_taken_over(player: Player) -> void:
	_free["chase"] = null
	_guide_taken_over(player)


## The player's own key, click or held steer while she leads (695): her
## route dropped and the server told (the "guide" command's stop "moved":
## it cannot tell his input from her route's, both come as request_free).
func _guide_taken_over(player: Player) -> void:
	if not _free.get("guided", false):
		return
	_free["guided"] = false
	World.command(player, "guide", {"stop": "moved"})


## A click on [param tile]: its route (World.walk_path's cells), steered
## along; the button held from here steers to the cursor instead.
func _free_route(player: Player, tile: Vector2i) -> void:
	_free_taken_over(player)
	_held_target = NONE
	_free["held"] = true
	_free["at"] = Time.get_ticks_msec()
	var path: Array = []
	var own := _free_own(player)
	# From the cell the body is shown on (ahead of the server's claim), so
	# the route never starts behind it.
	var shown: Vector2 = own.shown(player) if own != null else Vector2(player.tile)
	var from := World.free_cell(player, shown) if own != null else player.tile
	# A click on the cell it is on, held or drawn in (rounded: past half way
	# into the next), stops it where it stands: a free body has no centre to
	# finish (the latency table's click stop went on 0.4 cells into it).
	if tile != NONE and tile != from and tile != Vector2i(shown.round()):
		for cell: Vector2i in World.walk_path(from, tile, player):
			path.append(cell)
	_free["path"] = path


## 678 amended: whether the straight way from the walk's end to [param tile]
## is open (World._line_clear: walls, corners, others, fire).
func _line_open(player: Player, tile: Vector2i) -> bool:
	return tile != NONE and World._line_clear(player.walk_end(), tile, tile, player)


## 678 amended: whether a held walk's new cell [param tile] lies more than
## MovePrediction.TURN_KEEP off the way to the last one, [param was], seen
## from the body at [param body] (grid units).
static func held_turns(body: Vector2, was: Vector2i, tile: Vector2i) -> bool:
	var before := Vector2(was) - body
	var after := Vector2(tile) - body
	if before.length() < 0.5 or after.length() < 0.5:
		return true
	return before.normalized().dot(after.normalized()) < cos(MovePrediction.TURN_KEEP)


## 678 amended: whether a held walk, not turned, is planned again for the
## new cell [param tile]: its way off the last plan's [param was] by more
## than HELD_DRIFT, or under HELD_PLAN_LEFT of [param left] planned steps.
static func held_replans(body: Vector2, was: Vector2i, tile: Vector2i, left: int) -> bool:
	if left < HELD_PLAN_LEFT:
		return true
	var before := Vector2(was) - body
	var after := Vector2(tile) - body
	return before.length() < 0.5 or after.length() < 0.5 or before.normalized().dot(after.normalized()) < cos(HELD_DRIFT)


## Building (the builder's mode on): the hover square shows the cell.
func _building() -> bool:
	return _builder_ui != null and _builder_ui.active


## Left button held after a move click: when the cursor reaches another
## cell, that is the new target, no ripple, a step's time apart at most. Brought onto a
## monster, the hold is an attack on it instead (and ends): walking for the
## ground under it would go round it.
func _retarget_held() -> void:
	if _free_own(_local_player()) != null:
		return  # A free body: the hold steers it (_free_intent).
	if _held_target == NONE or not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _test_holding):
		if _held_target != NONE and _held_steered:
			_let_go_held()
		_held_target = NONE
		return
	var player := _local_player()
	if player == null:
		_held_target = NONE
		return
	var foe := _entity_under_mouse()
	if foe is Monster and World.can_target(player, foe):
		_held_target = NONE
		World.command_attack(player, foe)
		return
	var cursor := _mouse_grid()
	var body := Iso.local_to_grid(player.position)
	if not is_nan(cursor.x) and player.raised != "draw" and not Net.test_hold_route 			and (cursor.distance_to(body) <= STEER_CELLS or _line_open(player, _snap_to_floor(cursor))):
		# 678: aimed near the body, the held button steers along the line;
		# farther too while the straight way to the cursor is open (678
		# amended: a route planned again as it went took each line's first
		# step and weaved, its facing off the way it went), else a route.
		player.enable_prediction()
		var direction := _line_step(player, cursor - body) if cursor.distance_to(body) > 0.5 else Vector2i.ZERO
		player.hint_step(direction)
		if direction != Vector2i.ZERO:
			_held_steered = true
			_send_held_step(player, direction)
		return
	_walk_origin = Vector2.INF
	player.hint_line(Vector2.INF, Vector2.ZERO)
	var tile := _snap_to_floor(cursor)
	if tile == NONE or tile == _held_target:
		return
	# A new walk at most once a straight step's time, no ripple: each one
	# re-plans the route after the step under way (MovePrediction.order).
	# One that turns the walk goes at once (678 amended; Jeff: "i can move
	# cursor behind me and character keeps going").
	var every := World.step_ticks(player, Vector2i.RIGHT, player.tile) * 1000.0 / World.TICK_RATE
	if not held_turns(body, _held_target, tile) and (Time.get_ticks_msec() - _held_sent_at < every
			or not held_replans(body, _held_target, tile, player.steps_planned())):
		return
	_move_click(player, tile, false)
	_held_steered = true


## 683 (the coordinator's latency table: a held walk let go with Pip in the
## line went on 5.7 cells, on the route it had fallen to): a held walk let go
## stops at the step under way, as a key's does. Its hint and line go at
## once, so the step's tail is not bent toward a step never to come
## (MovePrediction._let_go_bend), and a route planned past that step is cut
## there. A click let go without steering walks on to its cell.
func _let_go_held() -> void:
	var player := _local_player()
	if player == null:
		return
	_walk_origin = Vector2.INF
	player.hint_step(Vector2i.ZERO)
	player.hint_line(Vector2.INF, Vector2.ZERO)
	# On a client the walk shown goes on past the step under way; on the
	# authority (no prediction) the step's tile is the body's own and the
	# route is its move order.
	var under := player.shown_step_tile()
	if player.walk_end() != under or player.has_move_order:
		World.command_move(player, under)


## The cursor's point on the ground plane, in this node's space (the
## space Iso projects into).
func _mouse_point() -> Vector2:
	return to_local(get_global_mouse_position())


## The cursor's point on the ground plane in continuous grid units, as
## picked this frame (see _update_pick). NaN when the cursor misses the
## ground (3D, looking past the plane).
func _mouse_grid() -> Vector2:
	return _pick_grid


## Picks the ground point under the cursor, once a frame, after the camera
## has moved: the 3D view's floor-plane ray, or the 2D projection inverted.
func _update_pick() -> void:
	if _client3d != null:
		_pick_grid = _client3d.mouse_grid()
	else:
		camera.force_update_scroll()
		_pick_grid = Iso.local_to_grid(_mouse_point())


## The walkable cell nearest [param grid] (a ground-plane point in grid
## units) within SNAP_RANGE tiles, or NONE. The cell under the point
## itself wins when it is floor.
func _snap_to_floor(grid: Vector2) -> Vector2i:
	if is_nan(grid.x) or is_nan(grid.y):
		return NONE
	var under := Vector2i(roundi(grid.x), roundi(grid.y))
	if World.is_walkable(under):
		return under
	var best := NONE
	var best_distance := SNAP_RANGE * SNAP_RANGE
	var reach := ceili(SNAP_RANGE)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := under + Vector2i(dx, dy)
			if not World.is_walkable(cell):
				continue
			var distance := grid.distance_squared_to(Vector2(cell))
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


func _release_toss(player: Player) -> void:
	var target := _toss_target
	var direction := _toss_direction()
	_toss_target = null
	if is_instance_valid(target) and target.spawned:
		World.command_shove(player, target, direction)
		_free_chase_start(player, target, true)


## Grid direction the current right-button drag points along, by screen angle,
## or ZERO if the cursor has barely moved (a plain shove).
func _toss_direction() -> Vector2i:
	var drag := get_global_mouse_position() - _toss_from
	if drag.length() < TOSS_DRAG_MIN:
		return Vector2i.ZERO
	var best := Vector2i.ZERO
	var best_dot := -INF
	for direction in World.DIRECTIONS:
		var dot := drag.normalized().dot(_screen_vector(direction).normalized())
		if dot > best_dot:
			best = direction
			best_dot = dot
	return best


## Where a grid direction points on screen.
func _screen_vector(direction: Vector2i) -> Vector2:
	if _client3d != null:
		return _client3d.screen_vector(direction)
	return Iso.project(Vector2(direction))


## An arrow from the held target showing which way it will be tossed.
func _update_toss_aim() -> void:
	var direction := Vector2i.ZERO
	if is_instance_valid(_toss_target) and _toss_target.spawned:
		direction = _toss_direction()
	else:
		_toss_target = null
	if _client3d != null:
		_client3d.toss_aim(_toss_target, direction)
		return
	toss_aim.visible = direction != Vector2i.ZERO
	if not toss_aim.visible:
		return
	var along := _screen_vector(direction).normalized()
	var tail := _toss_target.position + Vector2(0, -8)
	var tip := tail + along * TOSS_AIM_LENGTH
	toss_aim.points = PackedVector2Array([
		tail, tip, tip + along.rotated(2.6) * 7.0, tip, tip + along.rotated(-2.6) * 7.0])


## --test-click: a left click where the cursor is, as the mouse would send it.
func _test_click() -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		_unhandled_input(click)


## --test-hover: parks the cursor over a cell, for screenshots.
func _test_hover() -> void:
	if Net.test_hover_tile == Vector2i(-1, -1) or DisplayServer.get_name() == "headless":
		return
	# Cell -> viewport (camera) -> window (stretch).
	var in_viewport: Vector2 = _client3d.screen_of_tile(Net.test_hover_tile) if _client3d != null \
			else get_global_transform_with_canvas() * Iso.tile_to_local(Net.test_hover_tile)
	Input.warp_mouse(get_viewport().get_screen_transform() * in_viewport)


## The door whose face is under the cursor, or null.
func _door_under_mouse() -> Door:
	if DisplayServer.get_name() == "headless":
		return null
	if _client3d != null:
		return _client3d.door_under_mouse()
	var mouse := get_global_mouse_position()
	for door in World.get_doors():
		if Geometry2D.is_point_in_polygon(door.to_local(mouse), door.face_polygon()):
			return door
	return null


## The camera eases toward the local player, a little behind it; in the
## WASD scheme it also leans toward the cursor (camera_lean). With no
## player (dedicated server, dead) it stays put. The 3D view follows by the
## same rule itself.
func _follow_player(delta: float) -> void:
	var player := _local_player()
	if player == null or _client3d != null:
		return
	_lead = Main.camera_lean(_lead, get_viewport(), 0.0, delta)
	var player_grid := Iso.local_to_grid(player.position)
	var rate := 1.0 - exp(-CAMERA_FOLLOW_RATE * delta)
	camera.position = camera.position.lerp(Iso.grid_to_local(player_grid + _lead), rate)


## The cursor's place on the screen as a lean, each axis in -1..1 (x right,
## y down): its offset from the middle over half the screen, counted from
## the edge of the dead zone round the middle, and no longer than 1. Only
## the cursor's place on the screen goes in, so the camera moving cannot
## change it.
static func screen_lean(mouse: Vector2, size: Vector2) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	var offset := (mouse - size * 0.5) / (size * 0.5)
	var length := offset.length()
	if length <= CAMERA_LEAN_DEADZONE:
		return Vector2.ZERO
	var out := minf((length - CAMERA_LEAN_DEADZONE) / (1.0 - CAMERA_LEAN_DEADZONE), 1.0)
	return offset / length * out


## A screen lean (screen_lean) as a vector on the ground, in grid units, at
## a camera yaw: right on the screen is right, down is toward the camera.
static func lean_to_ground(lean: Vector2, yaw_degrees: float) -> Vector2:
	var yaw := deg_to_rad(yaw_degrees)
	var right := Vector3(1, 0, -1).rotated(Vector3.UP, yaw).normalized()
	var up := Vector3(-1, 0, -1).rotated(Vector3.UP, yaw).normalized()
	var along := right * lean.x - up * lean.y
	return Vector2(along.x, along.z)


## One frame of the camera's lean from [param lean] toward where the cursor
## is on [param viewport]'s screen: CAMERA_LEAN_CELLS at most, eased. Only
## in the WASD scheme; in click the camera follows the player alone.
static func camera_lean(lean: Vector2, viewport: Viewport, yaw_degrees: float, delta: float) -> Vector2:
	var wanted := Vector2.ZERO
	if Net.controls == "wasd" and DisplayServer.get_name() != "headless":
		var on_screen := screen_lean(viewport.get_mouse_position(), viewport.get_visible_rect().size)
		wanted = lean_to_ground(on_screen, yaw_degrees) * CAMERA_LEAN_CELLS
	return lean.lerp(wanted, 1.0 - exp(-delta / CAMERA_LEAN_EASE))


## The id of the zone this view is in: World's zone where World names it (a
## host, the server), else this peer's loaded map (a joined client's
## World.zone is a bare Zone with no name; its map is map_name, set as the
## zone's level loads in _client_zone). 538 amended: Jeff's screenshots from
## the laptop were named "_209-201_16h_...", the zone blank.
func zone_name_here() -> String:
	if World.zone != null and not World.zone.name.is_empty():
		return World.zone.name
	return map_name


## 660, ui's side: the zone's name as the map and compass show it (the
## level's display name), "" when it has none; never a level id.
func zone_display_name() -> String:
	return str(level.get("display_name", "")).strip_edges()


## The player this peer's input controls, or null (dedicated server, dead,
## or not spawned yet).
func _local_player() -> Player:
	# The roster (players and companions), not a copy of every entity: this
	# is asked several times a frame.
	for entity in World.sought():
		if entity is Player and entity.owner_peer == Net.local_id and entity.spawned:
			return entity
	return null


## The entity whose sprite is under the cursor, or null. Sprites stand taller
## than their tile, so pointing at a body would otherwise hit the tile behind
## it. Where sprites overlap, the one drawn in front (lower on screen) wins.
## The local player is skipped so clicks pass through to what is behind it.
func _entity_under_mouse() -> GridEntity:
	if DisplayServer.get_name() == "headless":
		return null
	if _client3d != null:
		return _client3d.entity_under_mouse()
	var mouse := get_global_mouse_position()
	var own := _local_player()
	var best: GridEntity = null
	for entity in World.get_entities():
		if entity == own or not entity.spawned:
			continue
		var sprite := entity.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			continue
		var point := sprite.to_local(mouse)
		if not sprite.get_rect().has_point(point) or not sprite.is_pixel_opaque(point):
			continue
		if best == null or entity.position.y > best.position.y:
			best = entity
	return best


## Screen -> grid: the cell under the cursor on the ground plane (NONE
## when the cursor misses the ground).
func _mouse_tile() -> Vector2i:
	var grid := _mouse_grid()
	if is_nan(grid.x) or is_nan(grid.y):
		return NONE
	return Vector2i(roundi(grid.x), roundi(grid.y))


## The map (see Terrain for the format). Floor and fire go on the Ground
## layer, one surface right up to the walls; wall edges are drawn as
## WallEdges, the far ones in the Y-sorted layer and the near ones (see
## WallEdge.is_near) in the translucent NearWalls group above it. Doors are
## spawned by the server with the level (see _spawn_doors): they have state.
##
## Only where the 2D view is the one seen: not under the 3D view, nor on a
## server, where nobody looks (a big map took seconds to draw).
func _paint_level() -> void:
	RenderingServer.set_default_clear_color(FOREST_VOID if _terrain.get("outdoor", false) else VOID)
	ground.clear()
	for wall in _walls:
		wall.queue_free()
	_walls.clear()
	if not _draws_2d():
		return
	var edges: Dictionary = _terrain["edges"]
	var kind_at := func(key: Vector3i) -> int: return edges.get(key, Terrain.Edge.OPEN)
	var fire := _cell_set(_terrain["fire"])
	var floor_at := _floor_test()
	var kinds: Dictionary = _terrain.get("kinds", {})
	var heights: Dictionary = _terrain.get("heights", {})
	var stairs: Dictionary = _terrain.get("stairs", {})
	for cell: Vector2i in _terrain["floor"]:
		if cell in fire:
			ground.set_cell(cell, FIRE_SOURCE, Vector2i.ZERO)
		else:
			var look := "stair" if stairs.has(cell) else str(kinds.get(cell, "stone"))
			ground.set_cell(cell, FLOOR_SOURCE, Vector2i.ZERO, _ground_tile(look, int(heights.get(cell, 0))))
	for cell: Vector2i in _terrain.get("water", []):
		ground.set_cell(cell, FLOOR_SOURCE, Vector2i.ZERO, _ground_tile("water", int(heights.get(cell, 0))))
	for key: Vector3i in edges:
		if edges[key] != Terrain.Edge.WALL:
			continue
		var wall := WallEdge.new()
		wall.name = "Wall_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
		if WallEdge.is_near(key, floor_at):
			near_walls.add_child(wall)
		else:
			$YSort.add_child(wall)
		wall.setup(key, kind_at, WALL_VALUE)
		_walls.append(wall)


## Whether this peer shows the 2D view: no 3D view, and not a server.
func _draws_2d() -> bool:
	return _client3d == null and Net.mode != Net.Mode.SERVER


## [param cells] as a set, for lookups that do not go through the list.
static func _cell_set(cells: Array) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		out[cell] = true
	return out


## Whether a cell is floor, by a set of the map's floor.
func _floor_test() -> Callable:
	var floor_set := _cell_set(_terrain["floor"])
	return func(cell: Vector2i) -> bool: return floor_set.has(cell)


## 2D: how each ground looks, as a tint of the floor tile, and lighter by
## height (alternative tiles of the floor source, made once).
const GROUND_TINTS := {
	"stone": Color(1, 1, 1), "grass": Color(0.62, 0.95, 0.55), "dirt": Color(0.95, 0.75, 0.55),
	"water": Color(0.45, 0.6, 1.0), "stair": Color(1.0, 0.95, 0.7),
}
var _ground_tiles: Dictionary[String, int] = {}


func _ground_tile(look: String, height: int) -> int:
	var key := "%s_%d" % [look, height]
	if look == "stone" and height == 0:
		return 0
	if _ground_tiles.has(key):
		return _ground_tiles[key]
	if _ground_tiles.is_empty():
		ground.tile_set = ground.tile_set.duplicate(true)  # This map's alternatives, not the shared resource's.
	var source := ground.tile_set.get_source(FLOOR_SOURCE) as TileSetAtlasSource
	var id := source.create_alternative_tile(Vector2i.ZERO)
	var tint: Color = GROUND_TINTS.get(look, Color.WHITE)
	source.get_tile_data(Vector2i.ZERO, id).modulate = tint.lightened(height * 0.06)
	_ground_tiles[key] = id
	return id


## Reads level [param level_name] and makes it this peer's terrain and spawn
## table; the default map if there is no such level. False if neither loads.
func _load_level(level_name: String) -> bool:
	var loaded := Level.load_level(level_name)
	if loaded.is_empty() and level_name != Level.DEFAULT_MAP:
		push_warning("[level] no map %s; loading %s" % [level_name, Level.DEFAULT_MAP])
		loaded = Level.load_level(Level.DEFAULT_MAP)
	if loaded.is_empty():
		return false
	level = loaded
	map_name = str(loaded["name"])
	_room_here = ""  # 665, ui's side: a new level, its rooms unvisited.
	_room_left_at.clear()
	Companion.know_level(map_name, loaded)
	_terrain = loaded["terrain"]
	# Its felled cells (591): the server's own, a client's as told.
	if Net.is_authority() and World.clearing != null:
		World.clearing.apply(map_name, _terrain)
	else:
		if _clearing_told.has(map_name):
			Clearing.apply_cells(_terrain, _clearing_cells(map_name))
		Clearing.lay_plots(_terrain, _plots_told.get(map_name, []))
	level_entities.assign(loaded["entities"])
	_index_keys()
	player_starts.assign(loaded["starts"])
	level_centre = loaded["centre"]
	_level_stamps[map_name] = _level_stamp(map_name)
	print("[level] %s: %d cells, %d entities, %d starts, %d links" % [map_name, _terrain["floor"].size(),
		level_entities.size(), player_starts.size(), loaded["links"].size()])
	return true


## A client's felled cells by zone (591): zone -> cell -> stage, as told
## ("trunk" kept: a regrown cell is void again on a reload, the level's
## floor too where a ruin's ground grew back, 649).
var _clearing_told: Dictionary = {}


## A client's plots by zone (591 step 2): zone -> [plots, each with the
## "size" its kind stood at when told].
var _plots_told: Dictionary = {}


## [param town]'s store cell (its stockpile place's), where its plots face.
func _store_cell(town: String) -> Vector2i:
	return World.holdings.place(town).get("cell", Vector2i.ZERO)


## The size [param town]'s [param kind] stands at on its plot: "large" from
## its record's level 2 (economy's), else "small".
func _plot_size(town: String, kind: String) -> String:
	var level := int(World.towns.building(town, kind).get("level", 1)) if World.towns != null else 1
	return "large" if level >= 2 else Level.KIND_SIZE


## Plot [param plot] as a "clearing" message carries it: plot_wire's with
## the size its kind stands at now.
func _plot_told(plot: Dictionary) -> Dictionary:
	var wire := Clearing.plot_wire(plot)
	wire["size"] = _plot_size(plot["town"], plot["kind"])
	return wire


## Server: a plot laid in [param zone] (Clearing.plotted): a loaded zone
## lays its kind's walls at once (open till they are up, 566), the terrain
## drawn takes it, and everyone in the zone is told.
func _on_plotted(zone: String, plot: Dictionary) -> void:
	if not Net.is_authority():
		return
	if World.zones.has(zone):
		var built: Array = []
		if zone == map_name:
			Clearing.lay_plots(_terrain, [plot], _plot_size)
			built = _terrain["plot_buildings"]
		else:
			var terrain: Dictionary = Level.load_level(zone)["terrain"].duplicate(true)
			World.clearing.apply(zone, terrain)
			built = terrain["plot_buildings"]
		if not built.is_empty() and (built.back() as Dictionary)["rect"].intersects(plot["rect"]):
			World.add_plot(zone, built.back(), Level.plot_edges(built.back()))
		if zone == map_name and _client3d != null:
			_redraw_clearing([])
	for peer in World.peers_in(zone):
		if peer != Net.local_id:
			Net.message_to(peer, "clearing", {"zone": zone, "cells": [], "plots": [_plot_told(plot)]})


## Server: a plot dropped in [param zone] (Clearing.unplotted, 649, maps'
## side): a loaded zone takes its building and the edges it laid off the
## walk and the terrain drawn, and everyone in the zone is told it is gone.
func _on_unplotted(zone: String, plot: Dictionary) -> void:
	if not Net.is_authority():
		return
	if World.zones.has(zone):
		if zone == map_name:
			Clearing.unlay_plot(_terrain, plot["rect"])
		World.unplot(zone, plot["rect"])
		if zone == map_name and _client3d != null:
			_redraw_clearing([])
	for peer in World.peers_in(zone):
		if peer != Net.local_id:
			Net.message_to(peer, "clearing", {"zone": zone, "cells": [], "gone": [Clearing.plot_wire(plot)]})


## A zone's told cells as a "clearing" list ([[x, y, stage]]).
func _clearing_cells(zone: String) -> Array:
	var out := []
	var cells: Dictionary = _clearing_told.get(zone, {})
	for cell: Vector2i in cells:
		out.append([cell.x, cell.y, cells[cell]])
	return out


## Server: zone [param zone]'s cells felled or grown on (Clearing.changed):
## a loaded zone's terrain and walk follow at once, the outline's walls round
## them with them (591 amended: a felled cell walked into, a regrown trunk
## walled), and everyone in it is told.
func _on_clearing_changed(zone: String, cells: Array) -> void:
	if not Net.is_authority():
		return
	if zone == map_name and _client3d != null and _client3d.fields_running():
		# The view's ground fields read this terrain on a worker (decision
		# 660): laid once they are in place, a moment on.
		_held_clearings.append(_on_clearing_changed.bind(zone, cells))
		return
	if World.zones.has(zone):
		var was := World.enter_named(zone)
		for each: Array in cells:
			World.set_floor(Vector2i(int(each[0]), int(each[1])), str(each[2]) != Clearing.TRUNK)
		# Main's _terrain is the zone's while World is in it.
		var changes := Clearing.apply_cells(_terrain, cells)
		World.set_edges(changes)
		World.enter(was)
		if zone == map_name and _client3d != null:
			_redraw_clearing(cells, changes)
	for peer in World.peers_in(zone):
		if peer != Net.local_id:
			Net.message_to(peer, "clearing", {"zone": zone, "cells": cells})


## Client: a "clearing" message (591): kept by zone ("whole" replaces the
## zone's), laid on the terrain drawn if it is that zone's, and drawn.
func _on_clearing(data: Dictionary) -> void:
	var zone := str(data.get("zone", ""))
	var cells: Variant = data.get("cells", [])
	if zone == map_name and _client3d != null and _client3d.fields_running():
		_held_clearings.append(_on_clearing.bind(data))  # As the server's (decision 660).
		return
	if zone.is_empty() or not cells is Array:
		return
	if data.get("whole", false) or not _clearing_told.has(zone):
		_clearing_told[zone] = {}
	for each: Variant in cells:
		if each is Array and (each as Array).size() == 3:
			# A trunk is kept too (649): over the level's own floor (a ruin's
			# ground grown back) it is what makes the cell void on a reload.
			_clearing_told[zone][Vector2i(int(each[0]), int(each[1]))] = str(each[2])
	# Its plots (591 step 2): the whole list, or one laid.
	var laid: Array = []
	for wire: Variant in data.get("plots", []) if data.get("plots") is Array else []:
		var plot := Clearing.plot_from(wire)
		if not plot.is_empty():
			plot["size"] = str(wire.get("size", Level.KIND_SIZE))
			laid.append(plot)
	if data.get("whole", false):
		_plots_told[zone] = laid
	else:
		_plots_told[zone] = (_plots_told.get(zone, []) as Array) + laid
	# Plots dropped (649, maps' side): by their rect.
	var gone: Array[Rect2i] = []
	for wire: Variant in data.get("gone", []) if data.get("gone") is Array else []:
		var plot := Clearing.plot_from(wire)
		if not plot.is_empty():
			gone.append(plot["rect"])
	if not gone.is_empty():
		var kept: Array = []
		for plot: Dictionary in _plots_told.get(zone, []):
			if not plot["rect"] in gone:
				kept.append(plot)
		_plots_told[zone] = kept
	if zone == map_name and not data.get("whole", false) and not Net.is_authority():
		var changes := Clearing.apply_cells(_terrain, cells)
		for each: Array in cells:
			World.set_floor(Vector2i(int(each[0]), int(each[1])), str(each[2]) != Clearing.TRUNK)
		World.set_edges(changes)
		for plot: Dictionary in laid:
			Clearing.lay_plots(_terrain, [plot])
			var built: Array = _terrain.get("plot_buildings", [])
			if not built.is_empty() and (built.back() as Dictionary)["rect"].intersects(plot["rect"]):
				World.add_plot(zone, built.back(), Level.plot_edges(built.back()))
		for rect in gone:
			Clearing.unlay_plot(_terrain, rect)
			World.unplot(zone, rect)
		if _client3d != null:
			_redraw_clearing(cells, changes)


## The view drawn again where [param cells] changed: terrain's own redraw of
## them if it has one (585's way: a few chunks), else the whole zone; the
## walls on [param edges] (591 amended: the outline's, opened or made, key ->
## kind, already in the terrain's "edges") by terrain's clearing_walls when
## the view has it, else the zone drawn again.
func _redraw_clearing(cells: Array, edges: Dictionary = {}) -> void:
	if _client3d.building_room or _client3d.ground_filling:
		# Drawn once the crossing's room is all built (decision 660).
		_held_redraws.append(_redraw_clearing.bind(cells, edges))
		return
	if not _client3d.has_method("clearing_changed") or not edges.is_empty() and not _client3d.has_method("clearing_walls"):
		_view_zone = ""
		return
	_client3d.call("clearing_changed", _terrain, cells)
	if not edges.is_empty():
		_client3d.call("clearing_walls", edges)


## Server: zone [param zone_name] read again from its level (edited in the
## game: Level reads the overlay first) and rebuilt as "zone reset" does,
## but not healed: the players stay where they are, everything else is
## spawned again. Everyone in it is sent the new terrain. Nothing if the
## zone is not open (it reads the edited level when it opens).
func reload_zone(zone_name: String) -> void:
	if not Net.is_authority() or not World.zones.has(zone_name):
		return
	var was := World.enter_named(zone_name)
	Regen.forget()  # An edited level.json may mark it, or no longer.
	_load_level(zone_name)
	_reloading = true
	_start_level(false, false)
	_reloading = false
	World.enter(was)
	var message := BuilderHost.terrain_message(zone_name)
	for peer in World.peers_in(zone_name):
		if peer != Net.local_id:
			Net.message_to(peer, "terrain", message)
	_view_zone = ""  # A host in that zone draws it again.


# --- Regenerating levels (decision 465) ------------------------------------------

## Server: the "map" message for zone [param zone_name]: its name, the
## server's build, and the generation of a regenerating level (0 for the rest).
func map_message(zone_name: String) -> Dictionary:
	return {"name": zone_name, "server": Net.version, "generation": generation_of(zone_name)}


## The generation level [param level_name] is at: 0 before its first, and
## for a level that does not regenerate.
func generation_of(level_name: String) -> int:
	return int(_regen.get(level_name, {}).get("generation", 0))


## Server, on the slow world tick: a regenerating level that is due, its
## zone not awake, is made on _maker while the game goes on, and applied
## on a later slow tick (decision 684): one level at a time, the next
## started once the last is applied. Made all on one tick, the barrow's
## layers and the castle's halls held every player 0.4 to 1.35 s.
func _regenerate_due() -> void:
	if not _making.is_empty():
		if _maker != null and _maker.is_alive():
			return
		if not _apply_made():
			return  # Its zone awake: it waits for the zone to sleep.
	for level_name in Regen.marked_levels():
		if _start_making_if_due(level_name):
			return


## The generation being made off the main thread (decision 684):
## {level, generation, config} while _maker makes it or its result waits
## to be applied; {} with none. Regen.generate_prepared touches no node,
## autoload or cache; what it returns is written and laid on the main thread.
var _making := {}
var _maker: Thread = null


## Level [param level_name]'s next generation started on _maker if it is
## due and nobody is in it (as _regenerate_if_due). True if one was started.
func _start_making_if_due(level_name: String) -> bool:
	if not _may_regenerate(level_name):
		return false
	var config := Regen.config_of(level_name)
	var generation := generation_of(level_name) + 1
	var prepared := Regen.prepare(level_name)
	if prepared.is_empty():
		_apply_generation(level_name, config, generation, {})  # Not made: it waits a period, as ever.
		return false
	_making = {"level": level_name, "generation": generation, "config": config}
	_maker = Thread.new()
	_maker.start(Regen.generate_prepared.bind(prepared, generation))
	return true


## The generation _maker made, laid now if its zone is not awake: true
## when it was laid (or dropped, no longer the next: "regenerate now" laid
## one meanwhile), false while it waits. Waits for _maker first.
func _apply_made() -> bool:
	if _making.is_empty():
		return true
	var level_name: String = _making["level"]
	var zone: Zone = World.zones.get(level_name)
	if zone != null and World.zone_awake(zone):
		return false
	var made := _join_maker()
	var making := _making
	_making = {}
	if int(making["generation"]) != generation_of(level_name) + 1 or not Regen.may_write():
		return true
	_apply_generation(level_name, making["config"], int(making["generation"]), made)
	return true


## What _maker returned, once it has finished ({} with none running).
func _join_maker() -> Dictionary:
	if _maker == null:
		return _making.get("made", {})
	var made: Dictionary = _maker.wait_to_finish()
	_maker = null
	_making["made"] = made
	return made


## The generation being made let go, written nowhere (quitting): _maker
## joined, its result dropped; the level is laid again when next due.
func _drop_making() -> void:
	if _maker != null:
		_maker.wait_to_finish()
		_maker = null
	_making = {}


## Server: level [param level_name] laid again now if it regenerates, its
## time has come (Regen.due) and nobody is in it (its zone not open, or
## asleep). True if it was.
func _regenerate_if_due(level_name: String) -> bool:
	if not _may_regenerate(level_name):
		return false
	if _making.get("level", "") == level_name:
		# Being made off the main thread (decision 684): that one, waited for.
		var was := generation_of(level_name)
		_apply_made()
		return generation_of(level_name) > was
	return _regenerate(level_name, Regen.config_of(level_name))


## Whether level [param level_name] may be laid again now: a server's
## regenerating level, its time come (Regen.due), nobody in it.
func _may_regenerate(level_name: String) -> bool:
	if not Net.is_authority() or not Regen.marked(level_name) or not Regen.may_write():
		return false
	var state: Dictionary = _regen.get(level_name, {"generation": 0, "at_step": 0})
	if not Regen.due(state, Regen.config_of(level_name), World.steps):
		return false
	var zone: Zone = World.zones.get(level_name)
	return zone == null or not World.zone_awake(zone)  # Never under anyone's feet: it waits for the zone to sleep.


## Server: level [param level_name]'s next generation made (Regen.generate),
## written (Regen.write) and, when its zone is open, the zone rebuilt on
## it: what sits in an anchor stays as it was, the rest is laid fresh from
## the new markers and what lay outside is lost (ItemBook); places gone
## with it leave the holdings and every player's map. When no map joins
## the anchors, or the overlay refuses it, the level stands as it is and
## waits a period again.
func _regenerate(level_name: String, config: Dictionary) -> bool:
	var generation := generation_of(level_name) + 1
	return _apply_generation(level_name, config, generation, Regen.generate(level_name, generation))


## Generation [param generation] of [param level_name], [param made]
## (Regen.generate's), written and laid: _regenerate's, or _maker's on the
## main thread (decision 684). {} or a refused write: it waits a period.
func _apply_generation(level_name: String, config: Dictionary, generation: int, made: Dictionary) -> bool:
	if made.is_empty() or not Regen.write(level_name, made):
		_regen[level_name] = {"generation": generation - 1, "at_step": World.steps}
		return false
	_regen[level_name] = {"generation": generation, "at_step": World.steps}
	print("[regen] %s: generation %d (seed %d, %d of %d tries, every %d days)" % [level_name, generation, made["seed"], made["tries"],
		Regen.TRIES, config["every_days"]])
	if World.zones.has(level_name):
		_rebuild_regenerated(level_name, made["anchors"])
	# Places outside the anchors are gone: from the holdings, and from the
	# maps of those who knew them, sent their world over again.
	_world_map = WorldMap.build()
	if World.holdings != null:
		var gone := World.holdings.rebind(_world_map)
		if not gone.is_empty():
			_forget_places(gone)
		_place_captives(_world_map, gone)  # A new generation's camps hold their captives; a gone camp's come home (decision 518).
	# The map's other holders (maps-2a's reading, 2026-10-18): the raid
	# groups route over the new floor (their routes and legs dropped, each
	# group going on from where it is); the game's richness is worked out
	# again on it (its steps from the mines are per cell and read once), the
	# herds pointed at it.
	if World.raid_groups != null:
		World.raid_groups.use_map(_world_map)
	if World.trade != null:
		World.trade.use_map(_world_map)
	if World.richness != null:
		_remake_richness()
	if World.forage != null:
		World.forage.world_map = _world_map
	return true


## The game's richness worked out again on the world map now (368
## amended): on a pool task, the old one answering Herds and Forage until
## it is in (_swap_richness). Waiting for the old one's steps here froze the
## box 17 s at a regeneration, its holdings having mines: their steps take
## tens of seconds. One asked while one is being made is made after it, on
## the newest map.
func _remake_richness() -> void:
	if _richness_next != null:
		_richness_stale = true
		return
	_richness_next = WorldRichness.new(_world_map, World.holdings)
	_richness_next.start()


## The richness _remake_richness made, put in once its steps are in, and
## Herds pointed at it; each tick, never waiting.
func _swap_richness() -> void:
	if _richness_next == null or not _richness_next.is_ready():
		return
	World.richness = _richness_next
	_richness_next = null
	if World.herds != null:
		World.herds.richness = World.richness.richness
	if _richness_stale:
		_richness_stale = false
		_remake_richness()


## A richness being worked out (368 amended), and whether another is wanted
## after it.
var _richness_next: WorldRichness = null
var _richness_stale := false


## Server: zone [param level_name], open and asleep, rebuilt on its new
## map: its live state goes through the snapshot's form and only what sits
## in [param anchors] comes back (Regen.keep_section); a companion waiting
## there is remembered, to come back beside her owner.
func _rebuild_regenerated(level_name: String, anchors: Array) -> void:
	var was := World.enter_named(level_name)
	for id: String in _companions.keys():
		var pet: Companion = _companions[id]
		if is_instance_valid(pet) and pet.spawned and pet.zone == level_name:
			_remember_companion(id)
			if _records.has(id):
				_records[id].companion["tile"] = null
	var respawns: Array[Dictionary] = []
	for slot: int in _dead_since:
		respawns.append({"spawn": slot, "spawn_key": _key_of(slot),
			"ticks_left": maxi(_respawn_delay(slot) - (World.tick - _dead_since[slot]), 0)})
	for entity in World.get_entities():
		World.slot_uids(entity)
	var ground := ground_entries(World.zone)
	var raw: Dictionary = Snapshot.data_of({level_name: {"tick": World.tick, "entities": World.get_entities(), "respawns": respawns,
		"ground": ground, "records": World.record_list()}})["zones"][level_name]
	var sifted := Regen.keep_section(Snapshot.parse_zone(raw), anchors)
	_lose_items(sifted["lost"], level_name)
	_load_level(level_name)
	_start_level(false, false, sifted["kept"])
	_level_stamps[level_name] = _level_stamp(level_name)
	World.enter(was)


## Server: things left outside the anchors of [param level_name] when it
## was laid again: gone from the world, their histories saying so.
func _lose_items(uids: Array, level_name: String) -> void:
	for uid: int in uids:
		if World.items.has(uid):
			World.items.end(uid, "lost", Regen.LOST, level_name)


## Server: places [param gone] are no more: every record's known places
## forget them, and the players on whose map they were are sent their
## world again (WorldNews.resend).
func _forget_places(gone: Array[String]) -> void:
	for id: String in _records:
		var record: PlayerRecord = _records[id]
		var before := record.known_places.size()
		record.known_places = record.known_places.filter(func(place_id: String) -> bool: return place_id not in gone)
		if record.known_places.size() == before or _world_news == null:
			continue
		for peer: int in _peer_ids:
			if _peer_ids[peer] == id:
				_world_news.resend(peer)
	if _world_news != null:
		_world_news.update()


## What level [param level_name]'s files on disk are: their folder and each
## one's md5, so the console's reload sees an edited level however soon.
func _level_stamp(level_name: String) -> String:
	if not Level.exists(level_name):
		return "gone"
	var folder := Level.folder_of(level_name)
	if not DirAccess.dir_exists_absolute(folder):
		return "in memory"  # Level.register's: nothing on disk to change.
	var parts: Array[String] = [folder]
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".import"):
			parts.append("%s=%s" % [file, FileAccess.get_md5(folder + file)])
	return "|".join(parts)


## Server: the console's reload (decision 242): zone [param words][1], or
## with "all" each open zone whose level changed on disk since it was read
## (an edited level put in the overlay by hand, say), read again and rebuilt
## as builder mode does (reload_zone): the players stay, everyone in it gets
## the new terrain, no restart.
func _reload_command(words: PackedStringArray) -> String:
	if words.size() < 2:
		return "usage: reload <zone> | reload all (zones: %s)" % ", ".join(World.zones.keys())
	var names: Array[String] = []
	var lines: Array[String] = []
	if words[1] == "all":
		for each: String in World.zones.keys():
			if not Level.exists(each):
				continue  # Its level was taken away (builder undo): left as it is.
			if _level_stamps.get(each, "") != _level_stamp(each):
				names.append(each)
		if names.is_empty():
			return "no open zone's level changed on disk (%d open)" % World.zones.size()
	elif not World.zones.has(words[1]):
		return "zone %s is not open (zones: %s); it reads its level when it opens" % [words[1], ", ".join(World.zones.keys())]
	elif not Level.exists(words[1]):
		return "zone %s has no level on disk any more; left as it is" % words[1]
	else:
		names.append(words[1])
	for each in names:
		reload_zone(each)
		lines.append("%s reloaded from %s, %d players there kept" % [each, Level.folder_of(each), World.peers_in(each).size()])
	return "
".join(lines)


## Server: the game's edits to level [param level_name] are gone (the
## console's "builder drop"): builder mode forgets its copy, the zone reads
## the repo's level again.
func forget_level_edits(level_name: String) -> void:
	if _builder != null:
		_builder.docs.erase(level_name)
		for peer: int in _builder.sessions.keys():
			if _builder._session_zone.get(peer, "") == level_name:
				_builder.sessions.erase(peer)
	reload_zone(level_name)


## A client: a "terrain" message, level [param data]'s files as the server
## has them (edited in the game). Read so from now on; drawn again now if
## this client is in it.
func _on_terrain(data: Dictionary) -> void:
	if Net.is_authority() or not BuilderHost.register_terrain(data):
		return
	var level_name := str(data.get("name", ""))
	if level_name == map_name:
		_load_level(level_name)
		World.mirror_terrain(_terrain)
		_repaint()
		print("[zone] %s changed" % level_name)


## This zone's folds as the view draws them (640): [{rect, facing, count}],
## each told count (fold_counts) whose place is on this map, at the fold
## nearest its cell (Level.fold_near); a count with no fold there is left out.
func fold_view() -> Array:
	var out := []
	for id: String in fold_counts:
		if id.get_slice("/", 0) != map_name:
			continue
		var place: Variant = level.get("places", {}).get(id.get_slice("/", 1))
		if not place is Dictionary:
			continue
		var fold := Level.fold_near(_terrain.get("buildings", []), place["cell"])
		if not fold.is_empty():
			out.append({"rect": fold["rect"], "facing": fold["facing"], "count": int(fold_counts[id])})
	return out


func _show_folds() -> void:
	if _client3d != null:
		_client3d.set_folds(fold_view())


## Draws the terrain afresh in both views (a map loaded live). A
## [param crossing] (the view into another zone) builds the 3D room over
## frames behind the arrival card (decision 660); the zone's own terrain
## again (a building raised, a ruin) builds it at once, as it always has.
func _repaint(crossing := false) -> void:
	_paint_level()
	if minimap != null:
		_door_marks_at = -1  # A new level: its doors.
		minimap.rebuild(level)
	if _client3d != null:
		# The towns and folds go on the room once it is whole (_on_room_built).
		if crossing and arrival_card != null:
			arrival_card.begin(zone_display_name())
		_client3d.rebuild(_terrain, level_centre, crossing)


## The 3D room is whole (decision 660): what is drawn over it, the card
## lifted, the player's hands given back.
func _on_room_built() -> void:
	_show_towns()
	_show_folds()
	if arrival_card != null:
		arrival_card.finish()
	# The server's arrival shelter ends (combat's 661): the zone by the level
	# shown, as the player's zone names it (a client's World.zone is a mirror
	# with no name).
	tell_view_ready(map_name)


## What waited on the view's build (decision 660), done now, in order.
func _replay(held: Array[Callable]) -> void:
	var calls := held.duplicate()
	held.clear()
	for each: Callable in calls:
		each.call()


## The 3D room is still being built (decision 660): the player's input waits.
func _arriving() -> bool:
	return _client3d != null and _client3d.building_room


# --- Zones (server) -------------------------------------------------------------

## Where a player with no record of their own starts: --map (tests, a
## host), else the world's start zone (levels/world_map.json, decision 300),
## else Level.DEFAULT_MAP.
func default_zone() -> String:
	if not Net.map_name.is_empty() and Level.exists(Net.map_name):
		return Net.map_name
	var start := WorldMap.start_zone()
	return start if Level.exists(start) else Level.DEFAULT_MAP


## Server start: every zone the snapshot holds, back as it was saved, and
## the default zone; the player records; and a host's own player.
func _boot() -> void:
	Net.interest.reset()
	var snapshot := Snapshot.load(Net.state_path) if Net.state_path != "" else {"ok": false, "zones": {}, "players": [], "steps": 0}
	# The world's clock goes on from where it stopped: the world waits while
	# the server is down.
	World.steps = snapshot.get("steps", 0)
	# Each regenerating level's generation (decision 465), before any zone opens.
	_regen = Regen.states_from(snapshot.get("regen", {}))
	# Free movement (decision 689): as the admin last left it, or --free-walk.
	# As given, else as the admin last left it, else on (decision 693).
	World.free_walk = Net.free_walk if Net.free_walk_given or not snapshot.get("free_walk") is bool else bool(snapshot["free_walk"])
	# The draugr's rest over the barrow's dead (decision 580): none after a restart (573 amended (4);
	# Jeff: "why does his health and status not reset on server restart"): he is back seated, whole,
	# his dead awake. A room reset keeps it (_start_level); it is not saved.
	World.dead_rest.clear()
	# The named enemies' records (decision 716), alive or dead, as saved.
	World.named.clear()
	var named: Variant = snapshot.get("named", {})
	if named is Dictionary:
		for id: Variant in named:
			if named[id] is Dictionary:
				World.named[str(id)] = (named[id] as Dictionary).duplicate(true)
	# A level-placed captive (decision 518): the camps whose holds are placed already, so each is placed once.
	_placed_captives = snapshot.get("placed_captives", {}).duplicate(true) if snapshot.get("placed_captives") is Dictionary else {}
	_sought_bands = snapshot.get("sought_bands", {}).duplicate(true) if snapshot.get("sought_bands") is Dictionary else {}
	_alms_runs = snapshot.get("alms_runs", {}).duplicate(true) if snapshot.get("alms_runs") is Dictionary else {}
	_crypt_told = snapshot.get("crypt_told", {}).duplicate(true) if snapshot.get("crypt_told") is Dictionary else {}
	_runner_out = snapshot.get("runner_out", {}).duplicate(true) if snapshot.get("runner_out") is Dictionary else {}
	# The hour and the day's length go on as saved (DayNight), unless
	# --hour or --day-minutes say otherwise.
	DayNight.reset()
	DayNight.from_dict(snapshot.get("sky", {}))
	Weather.reload()
	var saved_weather: Variant = snapshot.get("sky", {}).get("overrides", {})
	Weather.overrides = saved_weather if saved_weather is Dictionary else {}
	Weather.storms_checked = int(snapshot.get("sky", {}).get("storms_checked", -1))
	if Net.day_minutes > 0.0:
		DayNight.set_day_minutes(Net.day_minutes)
	if Net.start_hour >= 0.0:
		DayNight.set_hour(Net.start_hour)
	if Net.season_days > 0:
		Season.set_season_days(Net.season_days)
	if Net.start_season != "":
		Season.set_season(Net.start_season)
	if Net.start_weather != "":
		Weather.set_override("all", Net.start_weather, 600.0, true)
	elif not snapshot.get("ok", false):
		# A new world opens under a clear sky for its first spell (decision
		# 533), whatever its first spell's hash says.
		Weather.set_override("all", "clear", Weather.spell_steps(Level.DEFAULT_REGION) / float(World.TICK_RATE) / 60.0, true)
	# Who holds which place: as the levels start them, then as the snapshot
	# left them, on the world's clock.
	var world_map := WorldMap.build()
	World.holdings = Holdings.new(world_map, Factions.read(), snapshot.get("holdings", {}), func() -> int: return World.steps)
	_start_world_news()
	# Every thing in the world and its history, as the snapshot left them.
	World.items = ItemBook.from_dict(snapshot.get("items", {}), World.steps_now)
	# The town's stores, as the snapshot left them, their gear in the book.
	World.stockpile = Stockpile.new(snapshot.get("stockpile", {}), World.steps_now, World.items)
	# The town's workers, workshops and jobs, as the snapshot left them.
	# A resident's mind about their trade's role profile (decision 378).
	Production.profile_of = Lore.profile
	Production.type_of = Townsfolk.roll_type  # The hidden type, by id (decision 393).
	World.production = Production.new(snapshot.get("production", {}), World.stockpile, World.holdings, World.steps_now)
	# How each town grows: its experience, residents and buildings.
	World.towns = Towns.new(snapshot.get("towns", {}), World.production)
	World.towns.herders_from_dict(snapshot.get("herders", {}))  # The hill herders (640).
	# The forest felled and growing back, as the snapshot left it (591).
	World.clearing = Clearing.new(snapshot.get("clearing", {}), snapshot.get("plots", {}))
	World.clearing.changed.connect(_on_clearing_changed)
	# A town's plots (591 step 2): laid at its kind's size, told as laid.
	World.clearing.size_of = _plot_size
	World.clearing.plotted.connect(_on_plotted)
	World.clearing.unplotted.connect(_on_unplotted)  # A plot dropped (649, maps' side).
	World.towns.building_changed.connect(_on_town_building_changed)
	World.towns.stage_changed.connect(func(town: String) -> void: _on_town_building_changed(town, ""))  # Its stage told (591).
	# The roofs storms broke and nobody has mended yet (decision 383).
	World.roofs_damaged.clear()
	for key: Variant in snapshot.get("roofs", []):
		World.roofs_damaged[str(key)] = true
	if not World.roof_changed.is_connected(_on_roof_changed):
		World.roof_changed.connect(_on_roof_changed)
	# The tall grass trampled flat and not yet standing again (decision 508).
	World.trampled_from_dict(snapshot["trampled"] if snapshot.get("trampled") is Dictionary else {})
	if not World.grass_changed.is_connected(_on_grass_changed):
		World.grass_changed.connect(_on_grass_changed)
	# The buildings the maps already have, for towns with no record of them.
	World.towns.seed_from(world_map)
	_world_map = world_map
	_place_captives(world_map)  # The camps' level-placed captives (decision 518).
	# Raid groups (decision 328): off until switched on (--raids, the console).
	World.raid_groups = WorldRaids.new(world_map, World.holdings, World.towns, snapshot.get("raid_groups", {}))
	World.raid_groups.clock = func() -> int: return World.steps
	World.raid_groups.live = func(area: String) -> bool: return World.zones.has(area) and (World.zones[area] as Zone).awake
	# A hungry camp raids sooner, for food (decision 410): how well it ate,
	# from the herds (made below, so read when asked).
	World.raid_groups.fed = func(camp_id: String) -> float: return World.herds.camp_fed(camp_id) if World.herds != null else 1.0
	World.raid_groups.hook(World.raids)
	# Trade routes (decision 504): caravans economy sends, walking the raid
	# groups' routes (one set of distance fields), saved like them.
	World.trade = TradeRoutes.new(world_map, World.holdings, World.towns, snapshot.get("trade", {}))
	World.trade.clock = func() -> int: return World.steps
	World.trade.get_routes = func() -> WorldRoutes: return World.raid_groups.routes
	World.trade.is_food = func(kind: String) -> bool:
		return World.economy.is_food(kind) if World.economy != null and World.economy.has_method("is_food") else kind in ["food", "meat"]
	# The road's news (decision 504, npc's side): what the wagons bring home, as card facts and the town's memory.
	Townsfolk.watch_road(World.production, World.trade, World.economy)
	if Net.raids:
		World.raid_groups.set_on(true)
	# Game's richness (decision 368): the steps from the mines worked out on
	# a pool task now, for Herds (decision 367) to ask cell by cell.
	World.richness = WorldRichness.new(world_map, World.holdings)
	World.richness.start()
	# Companions taken and freed in raids (decision 314).
	# In play: its residents have bodies, which raiders take themselves; not
	# (its zone asleep, or nobody near it: _town_near, decision 355), Towns
	# takes them off the record.
	World.towns.in_play = func(town: String) -> bool:
		var zone: Zone = World.zones.get(str(World.holdings.place(town).get("area", "")))
		return zone != null and zone.awake and _towns_near.has(town)
	World.towns.companion_taken = companion_taken
	World.towns.companion_freed = companion_freed
	# The temple counter's town: the temple building whose rect holds it
	# (buildings' 424 amended), its "town" (decision 434).
	World.counter_town = func(counter: GridEntity) -> String:
		var area := counter.zone if not counter.zone.is_empty() else World.zone.name
		for house: Dictionary in _world_map.areas.get(area, {}).get("buildings", []):
			var rect: Variant = Level.building_rect(house)
			if str(house.get("use", "")) == "temple" and rect is Rect2i and (rect as Rect2i).has_point(counter.tile) \
					and not str(house.get("town", "")).is_empty():
				return "%s/%s" % [area, house["town"]]
		return Stockpile.place_at(World.holdings, area, counter.tile)
	# Rescues (decision 428): a camp's held come home when it falls.
	World.towns.camps = World.holdings.camps
	World.towns.home_of = func(camp: String) -> String:
		var place := World.holdings.place(camp)
		var routes: WorldRoutes = World.raid_groups.routes if World.raid_groups != null else null
		var kinds: Array[String] = ["stockpile"]
		var store := World.holdings.nearest(kinds, str(place.get("area", "")), place.get("cell", Vector2i.ZERO), routes)
		if store.is_empty() or World.holdings.holder(store) != Stockpile.TOWN:
			var names: Array = World.towns.to_dict().keys()
			names.sort()
			return str(names[0]) if not names.is_empty() else ""
		return store
	if not World.holdings.place_taken.is_connected(_on_place_taken):
		World.holdings.place_taken.connect(_on_place_taken)
	# A town's plots (591 step 2), once economy's Towns asks for them: where
	# its kind's class fits on cleared level ground nearest its store (empty:
	# not yet), and laid there facing the store.
	if "plot" in World.towns and "lay" in World.towns:
		World.towns.set("plot", func(town: String, kind: String) -> Rect2i:
			return World.clearing.plot_for(town.get_slice("/", 0), str(Level.kinds().get(kind, {}).get("plot", "")), _store_cell(town)))
		World.towns.set("lay", func(town: String, kind: String, rect: Rect2i) -> void:
			var plot_class := str(Level.kinds().get(kind, {}).get("plot", ""))
			World.clearing.lay_plot(town.get_slice("/", 0), town, kind, rect, Clearing.facing_for(rect, plot_class, _store_cell(town))))
	# The sought (613 amended): where a story's newcomer waits, once economy's
	# rules carry the stories (sought.trades; economy's to turn on).
	if World.towns.rules.get("sought", {}).has("trades"):
		World.towns.place_sought = _place_sought
	# Wells and roofs (decision 426): a town's are its level's.
	World.towns.wells = func(town: String) -> int:
		var area: Dictionary = _world_map.areas.get(town.get_slice("/", 0), {})
		return (area.get("buildings", []) as Array).filter(func(house: Dictionary) -> bool:
			return str(house.get("slot", "")) == "building.well").size()
	World.towns.storms = func(town: String, from: float, to: float) -> Array:
		var area: Dictionary = _world_map.areas.get(town.get_slice("/", 0), {})
		var region := str(area.get("region", Level.DEFAULT_REGION))
		var least := float(Weather.climate_of(region).get("storm_min", Weather.STORM_MIN))
		return Weather.storms_between(region, from, to).filter(func(storm: Dictionary) -> bool: return float(storm["strength"]) >= least)
	World.towns.rain = func(town: String, from: float, to: float) -> float:
		var area: Dictionary = _world_map.areas.get(town.get_slice("/", 0), {})
		return Weather.rain_between(str(area.get("region", Level.DEFAULT_REGION)), from, to)
	World.towns.roofs = func(town: String) -> Array:
		var level := town.get_slice("/", 0)
		var listed: Array = _world_map.areas.get(level, {}).get("roofs", [])
		var out := []
		for index in World.damaged_roofs(level):
			var rect: Rect2i = listed[index]["rect"] if index < listed.size() else Rect2i()
			out.append({"index": index, "cells": rect.get_area()})
		return out
	World.towns.mend_roof = func(town: String, index: int) -> bool:
		return World.repair_roof(town.get_slice("/", 0), index)
	World.towns.companion_of = func(player_id: String) -> Dictionary:
		var record: PlayerRecord = _records.get(player_id)
		if record == null or record.companion.is_empty():
			return {}
		return {"name": str(record.companion.get("name", "")), "trade": str(record.companion.get("traits", {}).get("trade", ""))}
	# Prices, and each player's own gold.
	World.economy = Economy.new(snapshot.get("economy", {}), World.stockpile, World.production, World.steps_now)
	# Residents' cards grow from the town's events (decision 398).
	Townsfolk.watch(World.production, World.towns)
	Offers.ctx = _offers_context()  # What the town's people can offer (decision 435).
	_seat_settled()  # Snagfin and his like (decision 471).
	Offers.watch(World.towns, World.holdings, World.stockpile)
	if not World.handed.is_connected(_on_handed):
		World.handed.connect(_on_handed)  # A gift to one of them (decision 443).
	if not World.named_event.is_connected(_on_named_event):
		World.named_event.connect(_on_named_event)  # A named enemy's memories (716, npc's side).
	if not World.towns.visitor_came.is_connected(_on_visitor_came):
		World.towns.visitor_came.connect(_on_visitor_came)  # Visitors' news and bodies (711, npc's side).
		World.towns.visitor_left.connect(_on_visitor_left)
	_make_lawspeaker()
	# Residents' trade (decision 353): the inn's bed while it stands, and
	# players in a town's zone told how many it feeds.
	World.economy.building_stands = func(town: String, kind: String) -> bool:
		return World.towns.building(town, kind).get("state") == Towns.STANDING
	World.economy.dole_changed.connect(_on_dole_changed)
	World.economy.owed_paid.connect(func(player_id: String, gold: int) -> void: World.gold_changed.emit(player_id, gold))
	# Players' contributions toward the next build (decision 499).
	World.economy.shortfall = World.towns.shortfall
	World.economy.before_harvest = World.towns.before_harvest
	# The hill herders' droves, bought by the town (640).
	World.towns.drove = World.economy.buy_drove
	World.towns.visitor_arrives = World.economy.visitor_arrives  # Visitors (711).
	World.towns.visitor_sale = World.economy.visitor_sale
	# Each healer's hut its own potions (641).
	World.production.workshop_makes = _workshop_makes
	# Where a town's building stands, for decline's edge and the ground a
	# ruin gives back to the forest (649).
	World.towns.placed = _town_placed
	if not World.towns.ruined.is_connected(_on_town_ruined):
		World.towns.ruined.connect(_on_town_ruined)
	if not World.towns.reclaimed.is_connected(_on_town_reclaimed):
		World.towns.reclaimed.connect(_on_town_reclaimed)
	World.towns.folds_changed.connect(_on_folds_changed)
	World.production.build_lacks = func(town: String) -> Dictionary: return World.towns.shortfall(town).get("needs", {})
	World.production.town_pays = World.economy.owe_or_pay
	# Caravans to market over maps' trade routes (decision 504, economy's side).
	if World.trade != null:
		World.economy.trade_routes = func(town: String) -> Array:
			var out: Array = []
			for way: Dictionary in World.trade.routes():
				var market := str(way["to"]) if str(way["from"]) == town else str(way["from"]) if str(way["to"]) == town else ""
				if market.begins_with(TradeRoutes.MARKET):
					out.append({"id": way["id"], "market": market, "eta": World.trade.eta(way["id"]), "risk": World.trade.risk(way["id"])})
			return out
		World.economy.send_caravan = World.trade.send
		# Visitors come from the far ends of the town's roads (711).
		World.towns.visitor_from = func(town: String) -> Array:
			var out: Array = []
			for way: Dictionary in World.trade.routes():
				var far := str(way["to"]) if str(way["from"]) == town else str(way["from"]) if str(way["to"]) == town else ""
				var name := str(World.trade.end_of(far).get("name", "")) if not far.is_empty() else ""
				if not name.is_empty() and not name in out:
					out.append(name)
			return out
		World.trade.caravan_arrived.connect(World.economy.caravan_arrived)
		World.trade.caravan_raided.connect(World.economy.caravan_raided)
		World.trade.caravan_lost.connect(World.economy.caravan_lost)
	World.production.settle_fund = World.economy.settle_fund
	World.economy.contributed.connect(func(town: String, player_id: String, kind: String, gold: int, xp: int) -> void:
		World.towns.add_xp(town, xp, "%s gave %d gold toward the %s" % [player_id, gold, kind]))
	# The fallen come back at a temple or a healer's hut (decision 396).
	World.production.returned = _on_returned
	if not World.production.work_done.is_connected(_on_counter_work_done):
		World.production.work_done.connect(_on_counter_work_done)
	_seat_healers()
	# Raiders come into a played zone as its level's monsters do.
	World.spawn_spec = _spawn
	World.bless = barrow_won  # The draugr laid to rest (decisions 548, 573).
	World.charges_in = charges_in_zone  # His level at a pact's start (573).
	World.paid_deal = paid_deal_of  # A payer's deal kept till won (548 amended).
	World.deal_paid = set_deal_paid
	# The wildlife's herds (decision 367): counts on the world tick, bodies
	# near someone through the far tier's keepers.
	World.herds = Herds.new(snapshot.get("herds", {}), Herds.areas_of(world_map), {}, World.steps_now, World.holdings)
	World.herds.richness = World.richness.richness  # Maps' (decision 368).
	World.herds.here = func() -> String: return World.zone.name
	World.herds.spawn = _spawn
	World.herds.free_near = func(cell: Vector2i, reach: int) -> Vector2i:
		# Out of every player's way where it can be (Animal.unseen_cell).
		var players: Array[Vector2i] = []
		for player: Player in _players.values():
			if is_instance_valid(player) and player.spawned:
				players.append(player.tile)
		var draw := RandomNumberGenerator.new()
		draw.seed = hash(cell)
		var unseen := Animal.unseen_cell(cell, reach, players, draw)
		if unseen != World.NO_CELL:
			return unseen
		if World.is_free(cell) and World.fields.under_sky(cell):
			return cell
		draw.seed = hash(cell)
		return _free_cell_near(cell, reach, draw)
	# Herbs and the like laid wild near the towns (decision 502).
	World.forage = Forage.new(world_map, World.holdings, {}, World.steps_now)
	World.keepers.erase(_herds_kept)
	_herds_kept = World.herds
	World.keepers.append(World.herds)
	# A town's hunter takes from its area's herds near its store (decision 407).
	# Gathered and made raws bought by the store, materials by the makers (decision 498).
	World.production.deliver = World.economy.deliver
	World.production.buy_materials = World.economy.buy_materials
	World.production.wage_from = World.economy.wage_from_alms
	World.production.hunt_at = func(_town: String, site: Dictionary) -> String:
		return World.herds.hunt_one(str(site["area"]), site["cell"]) if World.herds != null else ""
	World.production.hunt = func(town: String) -> String:
		var place := World.holdings.place(town)
		var cell: Vector2i = place.get("cell", Vector2i.ZERO)
		return World.herds.hunt_one(str(place.get("area", town.get_slice("/", 0))), cell) if World.herds != null else ""
	# A beaten raid's companion captives come back (decision 314).
	World.companion_freed = companion_freed
	_records.clear()
	for record: PlayerRecord in snapshot["players"]:
		_records[record.player_id] = record
	_move_off_retired(snapshot)
	var saved: Dictionary = snapshot["zones"]
	var restored := 0
	for zone_name: String in saved:
		if Level.RETIRED.has(zone_name):
			continue  # Dropped by _move_off_retired's count; never opened.
		if not Level.exists(zone_name):
			print("[state] the snapshot's zone %s is no map here; left out" % zone_name)
			continue
		# Opened as saved: a level due is laid on the slow ticks after, one
		# at a time off the main thread (decision 684), not all here at boot.
		_open_zone(zone_name, saved[zone_name], false)
		restored += saved[zone_name]["entities"].size()
	_open_zone(default_zone())
	if snapshot["ok"]:
		print("[state] loaded %d entities and %d player records from %s (zones: %s)" % [
			restored, snapshot["players"].size(), Net.state_path, ", ".join(saved.keys())])
	World.enter(World.zones[default_zone()])
	if Net.mode != Net.Mode.SERVER:
		_admit(Net.local_id, Net.player_id, Net.player_name)


## The players saved in a retired level (Level.RETIRED, 666) moved to its
## heir's cell, offline or not, and the snapshot's zone, generation and rest
## for it left out; one count-only line each, for release to grep.
func _move_off_retired(snapshot: Dictionary) -> void:
	for old: String in Level.RETIRED:
		var to: Array = Level.RETIRED[old]
		var moved := 0
		for record: PlayerRecord in _records.values():
			if record.zone == old:
				record.zone = str(to[0])
				record.tile = to[1]
				record.companion["tile"] = null
				moved += 1
		var dropped := 0
		if snapshot.get("zones") is Dictionary and snapshot["zones"].has(old):
			dropped += 1
		if _regen.has(old):
			_regen.erase(old)
			dropped += 1
		if World.dead_rest.has(old):
			World.dead_rest.erase(old)
			dropped += 1
		if moved > 0 or dropped > 0:
			print("[level] retired %s: %d moved to %s, %d saved states dropped" % [old, moved, to[0], dropped])


## Loads zone [param zone_name] if it is not loaded yet: its map, its doors,
## its level entities (as [param saved], a snapshot's section for it, has
## them, if it does). Zones stay loaded. Null for a map that is not there.
## [param regenerate] false: a level due is not laid again first (boot).
func _open_zone(zone_name: String, saved := {}, regenerate := true) -> Zone:
	if World.zones.has(zone_name):
		return World.zones[zone_name]
	if not Level.exists(zone_name):
		return null
	# A regenerating level due is laid again before it opens (decision
	# 465); the snapshot's section for it keeps only what sits in an anchor.
	if regenerate and _regenerate_if_due(zone_name) and not saved.is_empty():
		var sifted := Regen.keep_section(saved, Regen.config_of(zone_name)["anchors"])
		saved = sifted["kept"]
		_lose_items(sifted["lost"], zone_name)
	var opened := World.add_zone(zone_name)
	var was := World.enter(opened)
	_load_level(zone_name)
	_zone_nodes(zone_name)
	World.load_terrain(_terrain)
	_spawn_doors()
	if saved.is_empty() or not _spawn_saved(saved):
		for slot in level_entities.size():
			_spawn(_slot_spec(slot))
	_test_herds()
	if Net.practice and World.zone.name == Net.PRACTICE_MAP:
		place_dummies()  # 673: the practice hall's dummies, each time the room is laid.
	_restore_ground(saved.get("ground", []))
	# The fixed heat and light now, with the doors in, not in a tick with
	# a player waiting (perf: 1.5-3 s on a 256 dungeon's first tick).
	var started := Time.get_ticks_msec()
	if Net.is_authority():
		World.fields.warm(World)
	print("[zone] %s loaded%s (its heat and light in %d ms)" % [zone_name, " from the snapshot" if not saved.is_empty() else "",
			Time.get_ticks_msec() - started])
	World.enter(was)
	return opened


## The node zone [param zone_name]'s entities live under and its spawner,
## made the same on the server and on a client, which has the one.
func _zone_nodes(zone_name: String) -> void:
	var holder := Node2D.new()
	holder.name = zone_name
	holder.y_sort_enabled = true
	$YSort/Entities.add_child(holder)
	var made := MultiplayerSpawner.new()
	made.name = "Spawner_" + zone_name
	add_child(made)
	made.spawn_path = made.get_path_to(holder)
	# Every peer builds entities the same way; only the server decides when.
	made.spawn_function = _build_entity
	spawner = made
	entities = holder


## Main's own state for the zone World is in (its level, spawn table,
## respawn timers, entity node and spawner), swapped as World switches.
func _on_zone_switched(from: Zone, to: Zone) -> void:
	from.main = {"level": level, "level_entities": level_entities, "player_starts": player_starts,
		"level_centre": level_centre, "map_name": map_name, "terrain": _terrain, "alive_slots": _alive_slots,
		"dead_since": _dead_since, "spawner": spawner, "entities": entities, "party_log": party_log,
		"slot_keys": _slot_keys, "key_slots": _key_slots}
	if to.main.is_empty():
		# A zone being opened: fresh state, until its level loads.
		level = {}
		level_entities = []
		_slot_keys = PackedStringArray()
		_key_slots = {}
		player_starts = []
		_terrain = {}
		_alive_slots = {}
		_dead_since = {}
		party_log = PartyLog.new()
		return
	level = to.main["level"]
	level_entities = to.main["level_entities"]
	_slot_keys = to.main["slot_keys"]
	_key_slots = to.main["key_slots"]
	player_starts = to.main["player_starts"]
	level_centre = to.main["level_centre"]
	map_name = to.main["map_name"]
	_terrain = to.main["terrain"]
	_alive_slots = to.main["alive_slots"]
	_dead_since = to.main["dead_since"]
	spawner = to.main["spawner"]
	entities = to.main["entities"]
	party_log = to.main["party_log"]


## A host: World back in the zone of its own player, the views drawing that
## zone (the room redrawn when it changed) and only its entities shown.
func _show_home_zone() -> void:
	if not Net.is_authority() or World.zones.is_empty():
		return
	World.enter(World.home())
	if World.zone.name != _view_zone:
		_view_zone = World.zone.name
		_repaint(true)
		camera.position = Iso.tile_to_local(level_centre)
		if arrival_card != null:
			arrival_card.say(zone_display_name())  # 665, ui's side: every crossing says the zone.
	for each: Zone in World.zones.values():
		var holder: Node2D = entities if each == World.zone else each.main.get("entities")
		if holder != null:
			holder.visible = each == World.zone


## A client: its player is now in zone [param zone_name]. The last zone's
## node and spawner go (its entities with them), the new map loads, and the
## new zone's entities arrive under its own node.
func _client_zone(zone_name: String) -> void:
	if entities != null:
		entities.free()
	if spawner != null:
		spawner.free()
	World.mirror_reset()
	_load_level(zone_name)
	_zone_nodes(zone_name)
	World.mirror_terrain(_terrain)
	_repaint(true)
	if arrival_card != null:
		arrival_card.say(zone_display_name())  # 665, ui's side: every crossing says the zone (not again over the card's).
	print("[zone] now in %s" % zone_name)


## Server: [param peer]'s player joins the game in their own zone (the
## record's, else the default), opened if need be.
func _admit(peer: int, id: String, player_name: String) -> void:
	var record: PlayerRecord = _records.get(id)
	var wanted := record.zone if record != null and Level.exists(record.zone) else default_zone()
	var into := _open_zone(wanted)
	if into == null:
		into = _open_zone(default_zone())
	_show_zone_to(peer, into.name)
	var was := World.enter(into)
	_join_player(peer, id, player_name)
	World.enter(was)


## Server: [param peer]'s player is in zone [param zone_name] now. A client
## is sent the zone's name, between losing the old zone's entities and
## getting the new one's (the spawner does both, by visibility), so they land
## under the right node. A host's own view follows in _show_home_zone.
## [param leaving]: the player's own body and their companion's, despawned
## but freed only at the end of the frame: taken from that client now, or
## their despawn would reach it after it has left the zone.
func _show_zone_to(peer: int, zone_name: String, leaving: Array[GridEntity] = []) -> void:
	var old: String = World.peer_zone.get(peer, "")
	World.peer_zone[peer] = zone_name
	# It sees nothing of the new zone until its player is there (centre).
	Net.interest.forget(peer)
	if peer == Net.local_id:
		return
	if peer in multiplayer.get_peers():
		for entity in leaving:
			if is_instance_valid(entity) and entity.sync != null and entity.is_inside_tree():
				entity.sync.update_visibility(peer)
	if not old.is_empty() and old != zone_name:
		World.update_visibility(peer, old)
	if Level.overlaid(zone_name):
		# Edited in the game: the client's own copy (its pck's) is not it.
		Net.message_to(peer, "terrain", BuilderHost.terrain_message(zone_name))
	if World.clearing != null:
		# Before the map: the client lays its felled cells as it loads it (591).
		Net.message_to(peer, "clearing", {"zone": zone_name, "whole": true, "cells": World.clearing.cells_of(zone_name),
			"plots": World.clearing.plots_of(zone_name).map(_plot_told)})
	Net.message_to(peer, "map", map_message(zone_name))
	Net.message_to(peer, "notes", {"zone": zone_name, "notes": _sought_notes(zone_name)})  # The sought's door notes (decision 643).
	Net.message_to(peer, "sky", sky_message())
	_send_towns(peer, zone_name)
	Net.message_to(peer, "roofs", {"level": zone_name, "damaged": World.damaged_roofs(zone_name)})
	Net.message_to(peer, "grass", {"level": zone_name, "full": true, "flat": World.trampled_cells(zone_name)})
	World.update_visibility(peer, zone_name)


## The console's "move <player> <x> <y> [zone]" (decision 531; Jeff:
## "teleport me to the trader"): the connected player of that name (as
## "players" lists them: the game's Player3 or the name they joined with,
## exactly) put at the nearest walkable cell to (x, y) in that zone, else
## their own, as travel takes anyone (their companion at heel brought
## along; a returning player's free-cell and spawn-safety placement, 465;
## the client sent the zone afresh) and told where they are. Refused, with
## nothing moved, for no such player online, a name two players share (how
## many, not who), no such zone, a cell off the map, or none walkable within
## MOVE_REACH of it. No id is printed (the journal is grepped).
const MOVE_REACH := 8


## The cell just outside [param building]'s front (its facing side), in
## the middle: where a move to its code lands (decision 537).
static func front_of(building: Dictionary) -> Vector2i:
	var rect: Rect2i = building["rect"]
	var facing: Vector2i = building.get("facing", Vector2i(0, 1))
	var at := rect.position + (rect.size - Vector2i.ONE) / 2
	while rect.has_point(at):
		at += facing if facing != Vector2i.ZERO else Vector2i(0, 1)
	return at
func _move_command(words: PackedStringArray) -> String:
	# Or to a building by its code (decision 537): move <player> H3 [zone].
	var by_code := words.size() >= 3 and not words[2].is_valid_int() and words[2].substr(1).is_valid_int()
	if not by_code and (words.size() < 4 or not words[2].is_valid_int() or not words[3].is_valid_int()):
		return "move <player> <x> <y> [zone], or move <player> <building code> [zone]: the player by name as \"players\" lists them"
	var wanted := words[1]
	var peers: Array[int] = []
	for peer: int in _players:
		var player: Player = _players[peer]
		if not is_instance_valid(player) or not player.spawned:
			continue
		var record: PlayerRecord = _records.get(_peer_ids.get(peer, ""))
		if player.name == wanted or record != null and record.name == wanted:
			peers.append(peer)
	if peers.is_empty():
		return "move: no player %s online" % wanted
	if peers.size() > 1:
		return "move: %d players online are called %s; not moved" % [peers.size(), wanted]
	var peer := peers[0]
	var mover: Player = _players[peer]
	var zone_name := (words[3] if words.size() > 3 else mover.zone) if by_code else (words[4] if words.size() > 4 else mover.zone)
	if not Level.exists(zone_name):
		return "move: no zone %s" % zone_name
	var parsed := Level.load_level(zone_name)
	var target := Vector2i(int(words[2]), int(words[3])) if not by_code else World.NO_CELL
	if by_code:
		var code := words[2].to_upper()
		for building: Dictionary in parsed.get("buildings", []):
			if str(building.get("code", "")) == code:
				target = front_of(building)
		if target == World.NO_CELL:
			return "move: no building %s in %s" % [code, zone_name]
	var size: Vector2i = parsed.get("size", Vector2i.ZERO)
	if not Rect2i(Vector2i.ZERO, size).has_point(target):
		return "move: %s is off %s's map (%d x %d)" % [target, zone_name, size.x, size.y]
	var cell := _walkable_near(parsed, target)
	if cell == World.NO_CELL:
		return "move: nothing walkable within %d of %s in %s; not moved" % [MOVE_REACH, target, zone_name]
	var who := mover.name
	if not travel(peer, zone_name, "", {}, cell):
		return "move: %s could not go to %s" % [who, zone_name]
	var moved: Player = _players.get(peer)
	var landed: Vector2i = moved.tile if is_instance_valid(moved) else cell
	var place := str(Level.load_level(zone_name).get("display_name", zone_name))
	Net.broadcast_to([peer], "party", {"from": "Server", "text": "You find yourself in %s." % (place if not place.is_empty() else zone_name)})
	print("[admin] moved %s to %s in %s" % [who, landed, zone_name])
	return "moved %s to %s in %s%s" % [who, landed, zone_name, "" if landed == target else " (nearest walkable to %s)" % target]


## Whether [param link] (a level's, Level.parse) lets [param peer]'s player
## through (decision 540): a link not sealed does; a sealed one only when
## they or the companion with them hold its mark (party_has, decision 576). Their companion goes with them, as always.
func sealed_open(link: Dictionary, peer: int) -> bool:
	var mark := str(link.get("sealed", ""))
	if mark.is_empty():
		return true
	return party_has(peer, mark)


## Server: mark [param mark] put on player [param id]'s record (decision
## 540; enemy-ai's call when the draugr is beaten), or taken off with
## [param on] false. False for no such record or no change.
func mark_player(id: String, mark: String, on := true) -> bool:
	var record: PlayerRecord = _records.get(id)
	if record == null or mark.is_empty() or not mark.is_valid_identifier():
		return false
	if on == (mark in record.marks):
		return false
	if on:
		record.marks.append(mark)
		record.marks.sort()
	else:
		record.marks.erase(mark)
	for peer: int in _peer_ids:
		if _peer_ids[peer] == id:
			_told_closed.erase(peer)  # A sealed way they stand on is tried again.
	return true


## The console's "mark <player> <mark>" and "mark <player> -<mark>"
## (decision 540): the mark put on, or taken off, the record of the player
## of that exact name online, as "move" finds them (531).
func _mark_command(words: PackedStringArray) -> String:
	if words.size() != 3:
		return "mark <player> <mark> | mark <player> -<mark>: the player by name as \"players\" lists them; a mark is one word"
	var wanted := words[1]
	var ids: Array[String] = []
	for peer: int in _players:
		var player: Player = _players[peer]
		if not is_instance_valid(player) or not player.spawned:
			continue
		var id: String = _peer_ids.get(peer, "")
		var record: PlayerRecord = _records.get(id)
		if (player.name == wanted or record != null and record.name == wanted) and id not in ids:
			ids.append(id)
	if ids.is_empty():
		return "mark: no player %s online" % wanted
	if ids.size() > 1:
		return "mark: %d players online are called %s; not marked" % [ids.size(), wanted]
	var on := not words[2].begins_with("-")
	var mark := words[2].trim_prefix("-")
	if not mark.is_valid_identifier():
		return "mark: a mark is one word of letters, digits and underscores (%s)" % mark
	var record: PlayerRecord = _records[ids[0]]
	if not mark_player(ids[0], mark, on):
		return "%s %s %s already" % [wanted, "carries" if on else "lacks", mark]
	print("[admin] %s %s %s" % [wanted, "marked" if on else "unmarked", mark])
	return "%s %s %s; marks: %s" % [wanted, "marked" if on else "unmarked", mark, ", ".join(record.marks) if not record.marks.is_empty() else "none"]


## The floor cell of level [param parsed] nearest [param target] (itself if
## it is floor) within MOVE_REACH, ring by ring; World.NO_CELL if none.
static func _walkable_near(parsed: Dictionary, target: Vector2i) -> Vector2i:
	var floor_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in parsed.get("terrain", {}).get("floor", []):
		floor_cells[cell] = true
	var best := World.NO_CELL
	for reach in MOVE_REACH + 1:
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				var cell := target + Vector2i(x, y)
				if maxi(absi(x), absi(y)) == reach and floor_cells.has(cell) \
						and (best == World.NO_CELL or Vector2(cell - target).length() < Vector2(best - target).length()):
					best = cell
		if best != World.NO_CELL:
			return best
	return best


## Server: [param peer]'s player (and their companion) go to zone
## [param to_map], at its spawn point [param to_spawn] ("" for its first
## start), or, across an edge, at the cell matching [param edge] ({side,
## cell}: the edge crossed and the cell just beyond it; WorldMap.arrival);
## nobody else moves. The zone is opened if need be. False if there is no
## such map or no such player.
func travel(peer: int, to_map: String, to_spawn := "", edge := {}, at := World.NO_CELL) -> bool:
	var id: String = _peer_ids.get(peer, "")
	var record: PlayerRecord = _records.get(id)
	if record == null or not Level.exists(to_map):
		return false
	# A regenerating level due is laid again before anyone arrives
	# (decision 465); a zone already open does the same here.
	_regenerate_if_due(to_map)
	var target := _open_zone(to_map)
	var from_name: String = World.peer_zone.get(peer, record.zone)
	World.enter_named(from_name)
	var player: Player = _players.get(peer)
	var pet: Companion = _companions.get(id)
	var leaving: Array[GridEntity] = [player, pet]
	_travelling = true
	if is_instance_valid(player) and player.spawned:
		record.remember(player)
		World.despawn(player)
	if is_instance_valid(pet) and pet.spawned:
		_remember_companion(id)
		# Told to stay, on town ground: she stays and works (decision 284).
		if pet.stays_put() and _stay_in_town(record, pet):
			Net.broadcast_to([peer], "party", {"from": "Server", "text": "%s stays in %s, working as its %s. Come back and %s will travel with you again." % [
				record.companion.get("name", "Your companion"), _town_words(str(record.companion["resident"].get("place", ""))), record.companion["resident"].get("trade", ""),
				_companion_subject(record)]})
		World.despawn(pet)
	_travelling = false
	_players.erase(peer)
	_companions.erase(id)
	_respawn_at.erase(peer)
	World.enter(target)
	var spawns: Dictionary = level.get("spawn_points", {})
	record.tile = spawns.get(to_spawn, player_starts[0] if not player_starts.is_empty() else Vector2i.ZERO)
	if not edge.is_empty():
		record.tile = WorldMap.arrival(edge["side"], edge["cell"], level["size"])
	if at != World.NO_CELL:
		record.tile = at
	record.zone = to_map
	if not record.companion.is_empty() and not record.companion.has("resident"):
		record.companion["tile"] = null  # Beside their player.
	_show_zone_to(peer, to_map, leaving)
	_join_player(peer, id, record.name)
	_shelter_arrival(peer, id)
	if to_spawn == "from_below":
		_reveal_from_below(to_map)  # The hidden door pushed open from behind (608).
	print("[zone] %s went from %s to %s" % [record.name, from_name, to_map])
	party_log.add("%s went to %s." % [record.name, str(level.get("display_name", to_map))])
	World.enter(World.home())
	return true


## Server: [param peer]'s player just arrived by travel (World in their new
## zone): sheltered while their view builds (decision 661), their companion
## with them, unless sheltered on arriving within SHELTER_COOLDOWN_MSEC.
func _shelter_arrival(peer: int, id: String) -> void:
	var player: Player = _players.get(peer)
	if not is_instance_valid(player) or not player.spawned:
		return
	var now := Time.get_ticks_msec()
	if _sheltered_at.has(id) and now - _sheltered_at[id] < SHELTER_COOLDOWN_MSEC:
		return  # Spawn grace alone (_join_player's).
	_sheltered_at[id] = now
	World.shelter(player, ARRIVAL_SHELTER_TICKS)
	var pet: Companion = _companions.get(id)
	if is_instance_valid(pet) and pet.spawned and pet.zone == player.zone:
		World.shelter(pet, ARRIVAL_SHELTER_TICKS, player)


## Server: the "view_ready" command (decision 661): [param player]'s client
## has built the view of zone [param zone_name]; their shelter, and their
## companion's, gives way to plain spawn grace. One naming another zone (a
## stale one) does nothing.
func _view_ready(player: Player, zone_name: String) -> void:
	if zone_name != player.zone:
		return
	World.unshelter(player, SPAWN_GRACE_TICKS)
	# Where their companion is, said again once they can see (the first
	# went by under the loading), when the view took a while.
	if Time.get_ticks_msec() - int(_where_told.get(player.owner_peer, 0)) > WHERE_AGAIN_MS and _where_told.has(player.owner_peer):
		var record: PlayerRecord = _records.get(_peer_ids.get(player.owner_peer, ""))
		if record != null:
			var words := _companion_whereabouts(record, player.zone)
			if not words.is_empty():
				Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": words})
	_where_told.erase(player.owner_peer)
	var pet: Companion = _companions.get(_peer_ids.get(player.owner_peer, ""))
	if is_instance_valid(pet) and pet.shelter_lead == player:
		World.unshelter(pet, SPAWN_GRACE_TICKS)


## Client: this view of zone [param zone_name] is built (decision 661; perf's
## view build calls it): the server ends this player's arrival shelter.
func tell_view_ready(zone_name: String) -> void:
	var player := _local_player()
	if player != null:
		World.command(player, "view_ready", {"zone": zone_name})


## Tests and the eval: the host's player into zone [param level_name], the
## zone rebuilt fresh.
func load_map(level_name: String) -> bool:
	if not travel(Net.local_id, level_name):
		return false
	_start_level()
	return true


## Server: a player stepping onto a level link goes to the zone it leads
## to, with their companion; nobody else moves.
func _on_entity_moved(entity: GridEntity, _from: Vector2i, to: Vector2i) -> void:
	if not entity is Player:
		return
	_tell_draft(entity, to)
	_take_link(entity, to)


## Server: a player whose step onto a level link's cell was refused (a body
## stood on it) takes the link all the same (decision 571): a body there
## never shuts the way.
func _on_link_bumped(entity: GridEntity, at: Vector2i) -> void:
	if entity is Player:
		_take_link(entity, at)


## [param entity] (a player) at level link [param to] goes through it, or is
## told it is closed or sealed; off any link, told again next time.
func _take_link(entity: GridEntity, to: Vector2i) -> void:
	for link: Dictionary in level.get("links", []):
		if link["tile"] == to and link.get("closed", false):
			# Shown, not travelled yet (decision 463): said once a stand.
			if _told_closed.get(entity.owner_peer) != to:
				_told_closed[entity.owner_peer] = to
				party_log.add("The way on is closed.")
			return
		if link["tile"] == to and not sealed_open(link, entity.owner_peer):
			# Sealed (decision 540): open to the marked alone, said once a stand.
			if _told_closed.get(entity.owner_peer) != to:
				_told_closed[entity.owner_peer] = to
				party_log.add("The way is sealed.")
			return
		if link["tile"] == to:
			_told_closed.erase(entity.owner_peer)
			print("[level] %s took the link at %s to %s (%s)" % [_display_name(entity), to, link["to_map"], link["to_spawn"]])
			# After the tick: not mid-step.
			travel.call_deferred(entity.owner_peer, str(link["to_map"]), str(link["to_spawn"]))
			return
	_told_closed.erase(entity.owner_peer)  # Off it: told again next time.


## Server: a player walking into the map's edge where the level has a
## neighbour goes there, arriving at the matching cell of its opposite edge
## (level.json "neighbours"), with their companion, as a link takes them.
func _on_walked_off(entity: GridEntity, direction: Vector2i) -> void:
	if entity is Animal:
		var cross := Animal.crossing_off(entity as Animal, direction, _world_map, World.zone.name)
		if not cross.is_empty():
			_animal_crossed.call_deferred(entity, cross)  # After the tick: not mid-step.
		return
	if not entity is Player:
		return
	var beyond := entity.tile + direction
	var side := WorldMap.side_off(level.get("size", Vector2i.ZERO), beyond)
	var neighbours: Dictionary = level.get("neighbours", {})
	if side.is_empty() or not neighbours.has(side) or not Level.exists(neighbours[side]):
		return
	print("[level] %s walked off the %s edge at %s to %s" % [_display_name(entity), side, entity.tile, neighbours[side]])
	# After the tick: not mid-step.
	travel.call_deferred(entity.owner_peer, str(neighbours[side]), "", {"side": side, "cell": beyond})


## Server: a herd's animal fled off the map's edge into the next area
## ([param cross]: Animal.crossing_off): gone from here, its unit moved to
## its species' group there (Herds.moved, decision 367); kept, not dead.
func _animal_crossed(animal: Animal, cross: Dictionary) -> void:
	if not is_instance_valid(animal) or not animal.spawned or World.herds == null:
		return
	var group := World.herds.moved(str(animal.spawn_spec.get("group", "")), str(cross["to"]), cross["at"])
	print("[herds] %s fled off the %s edge at %s into %s (group %s)" % [animal.name, cross["side"], animal.tile, cross["to"], group])
	_despawn_kept(animal)


## Server: one Door node per door edge, through the spawner so every client
## gets it. Wood, 20 hp.
## The level's doors spawned, wood; the hidden niche's (608: the door on
## the "hidden" niche's edge, terrain "niches") stone and locked with
## HIDDEN_LOCK, a key nobody holds, so only a press on it (_on_niche_pressed)
## or a climb from below (_reveal_from_below) opens it.
func _spawn_doors() -> void:
	var edges: Dictionary = _terrain["edges"]
	var hidden: Dictionary[Vector3i, bool] = {}
	for niche: Dictionary in _terrain.get("niches", []):
		if str(niche["kind"]) == "hidden":
			hidden[niche["edge"]] = true
	for key: Vector3i in edges:
		if edges[key] == Terrain.Edge.DOOR:
			var props := {"max_hp": 20, "body_material": GridEntity.BodyMaterial.WOOD}
			if hidden.has(key):
				props = {"max_hp": 20, "body_material": GridEntity.BodyMaterial.STONE, "lock": HIDDEN_LOCK}
			Net.interest.add(spawner.spawn({"script": DOOR, "name": "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"],
				"edge": [key.x, key.y, key.z], "zone": World.zone.name, "props": props}))


# --- Server: level and players ------------------------------------------------

## (Re)builds the zone World is in, from its level: the R restart, and
## the console's reset and zone reset. Removing the old entities and spawning
## new ones replicates to its clients through its spawner. With
## [param from_snapshot], entities (and every player record) come from the
## --state file when it has this zone; otherwise the room starts whole
## ([param whole]): its players healed and dead companions back. Everyone in
## the zone keeps their place; nobody in another zone is touched.
func _start_level(from_snapshot := false, whole := true, with_saved := {}) -> void:
	if not Net.is_authority():
		return
	var here := World.zone.name
	var peers := World.peers_in(here)
	if Net.mode != Net.Mode.SERVER and not World.peer_zone.has(Net.local_id) and Net.local_id not in peers:
		peers.append(Net.local_id)  # A host with no player yet comes in here.
	var ids: Dictionary[int, String] = {}
	for peer in peers:
		var id: String = _peer_ids.get(peer, Net.player_id if peer == Net.local_id else Net.player_of(peer))
		ids[peer] = id
		var player: Player = _players.get(peer)
		if is_instance_valid(player) and player.spawned and _records.has(id):
			_records[id].remember(player)
	for id: String in _companions.keys():
		var pet: Companion = _companions[id]
		if not is_instance_valid(pet) or pet.zone == here:
			_companions.erase(id)
	var rests := World.dead_rest.duplicate(true)  # The draugr's rests (580; 573 amended (3)): every zone's, not this room's to lose.
	var named := World.named.duplicate(true)  # Decision 716: every named one's, alive or dead.
	World.reset()
	World.dead_rest = rests
	World.named = named
	for child in entities.get_children():
		entities.remove_child(child)
		child.queue_free()
	Net.interest.clear_zone(here)
	World.load_terrain(_terrain)
	_spawn_doors()
	for peer in peers:
		_players.erase(peer)
		_peer_ids.erase(peer)
		_respawn_at.erase(peer)
	_alive_slots.clear()
	_dead_since.clear()
	var saved := with_saved
	if from_snapshot and Net.state_path != "":
		var snapshot := Snapshot.load(Net.state_path)
		if snapshot["ok"]:
			_records.clear()
			for record: PlayerRecord in snapshot["players"]:
				_records[record.player_id] = record
			saved = snapshot["zones"].get(here, {})
	elif whole:
		_revived = _revive_companions(here)
		# A rebuilt room starts whole: the living come back healed too.
		for record: PlayerRecord in _records.values():
			if not record.companion.is_empty() and record.zone in [here, ""]:
				record.companion["hp"] = 0  # 0: spawn at full stats.
	if saved.is_empty() or not _spawn_saved(saved):
		for slot in level_entities.size():
			_spawn(_slot_spec(slot))
	_test_herds()
	if Net.practice and World.zone.name == Net.PRACTICE_MAP:
		place_dummies()  # 673: the practice hall's dummies, each time the room is laid.
	_restore_ground(saved.get("ground", []))
	for peer in peers:
		var id: String = ids[peer]
		if id != "":
			_join_player(peer, id, _records[id].name if _records.has(id) else (Net.player_name if peer == Net.local_id
				else Net.DEFAULT_NAME))
	World.end_unclaimed_items()
	if not from_snapshot and whole:
		# A rebuilt room starts whole: every player at full hp and stamina.
		for player: Player in _players.values():
			if is_instance_valid(player) and player.spawned and player.zone == here:
				World.restore(player, player.max_hp, player.max_stamina, player.facing)
				var record: PlayerRecord = _records.get(_peer_ids.get(player.owner_peer, ""))
				if record != null:
					record.remember(player)


## --test-herds=<n> (perf's benches, before economy's herds place any):
## n sets of TEST_HERDS (13 animals a set) in the zone World is in when
## it is outdoors, each herd on free cells under the sky a few apart about a cell drawn
## at random, the draw seeded by the zone's name so every run puts them in
## the same places. Not saved: a restart or a rebuild puts them in again.
func _test_herds() -> void:
	if Net.test_herds <= 0 or not Net.is_authority() or not World.fields.outdoor:
		return
	var open: Array[Vector2i] = []
	for cell in World.floor_cells():
		if World.is_free(cell) and World.fields.under_sky(cell):
			open.append(cell)
	if open.is_empty():
		return
	open.sort()  # floor_cells is in no set order: the draw must be.
	var draw := RandomNumberGenerator.new()
	draw.seed = hash(World.zone.name + "/test_herds")
	var made := 0
	for set in Net.test_herds:
		for group in TEST_HERDS.size():
			var kinds: Array = TEST_HERDS[group]
			var near := open[draw.randi_range(0, open.size() - 1)]
			for i in kinds.size():
				var at := _free_cell_near(near, 4, draw)
				if at == World.NO_CELL:
					break
				var spec := Level._spec_for("monster_" + str(kinds[i]), Level.MONSTER_TYPES)
				spec["name"] = "Herd%d_%d_%s_%d" % [set + 1, group + 1, kinds[i], i + 1]
				spec["tile"] = at
				if _spawn(spec) != null:
					made += 1
	print("[main] --test-herds: %d animals in %d sets of herds in %s" % [made, Net.test_herds, World.zone.name])


## A free cell under the sky within [param reach] of [param near], drawn by
## [param draw]; NO_CELL if a few tries find none.
func _free_cell_near(near: Vector2i, reach: int, draw: RandomNumberGenerator) -> Vector2i:
	for attempt in 12:
		var at := near + Vector2i(draw.randi_range(-reach, reach), draw.randi_range(-reach, reach))
		if World.is_free(at) and World.fields.under_sky(at):
			return at
	return World.NO_CELL


## A snapshot's section for the zone World is in ({entities, respawns}): its
## entities in the room again. False if it has none to restore.
func _spawn_saved(section: Dictionary) -> bool:
	var saved: Array = section.get("entities", [])
	var records: Array = section.get("records", [])
	if saved.is_empty() and section.get("respawns", []).is_empty() and records.is_empty():
		return false
	# Level entities that became something else (decision 471): handed over
	# once, neither spawned nor kept. A dead one's timer, its key gone from
	# the level, is dropped below as any lost marker's is.
	var became: Dictionary = level.get("became", {})
	if not became.is_empty():
		saved = saved.filter(func(entry: Dictionary) -> bool: return not _hand_over(became, entry["spec"], entry))
		records = records.filter(func(record: Dictionary) -> bool: return not _hand_over(became, record["entry"], record["entry"]))
	# Monsters kept as records stay records, holding their slots (and their
	# things) till someone comes near (decision 352); none before them.
	if World.herds != null:
		# A herd's bodies of a species the level no longer keeps (397 amended:
		# the wilds' wolves): not spawned again; its records fold to nothing.
		var was := saved.size()
		saved = saved.filter(func(entry: Dictionary) -> bool: return not World.herds.culls(World.zone.name, entry["spec"]))
		if saved.size() < was:
			print("[herds] culled %d bodies in %s: the level keeps none of their kind" % [was - saved.size(), World.zone.name])
		records = World.herds.fold_records(World.zone.name, records)  # Animals of before the herds (decision 367).
	World.set_records(records)
	# A record from before keys (decision 433) gets its slot's key now, while
	# its index still means what it did, so the next save keeps it by key.
	for record in World.record_list():
		var spawn: Variant = record["entry"].get("spawn", -1)
		var slot := _slot_for(int(spawn) if spawn is int or spawn is float else -1, str(record["entry"].get("spawn_key", "")))
		if slot >= 0 and str(record["entry"].get("spawn_key", "")).is_empty():
			record["entry"]["spawn_key"] = _key_of(slot)
	var recorded := _recorded_slots()
	# Every key the snapshot names (decision 610): a marker one of them names
	# is no moved marker for another.
	_saved_keys = {}
	for entry: Dictionary in saved:
		_saved_keys[str(entry["spec"].get("spawn_key", ""))] = true
	for record in World.record_list():
		_saved_keys[str(record["entry"].get("spawn_key", ""))] = true
	for respawn: Dictionary in section.get("respawns", []):
		_saved_keys[str(respawn.get("spawn_key", ""))] = true
	_saved_keys.erase("")
	_adopted = 0
	for entry: Dictionary in saved:
		var spec := _level_spec_for(entry["spec"])
		var entity := _spawn(spec)
		if entity == null:
			continue
		# The draugr whole again from a saved zone (573 amended (4), Jeff: a restart resets him).
		World.restore(entity, entity.max_hp if entity is Draugr else entry["hp"], entry["stamina"], entry["facing"])
		if entry.get("slots") != null:
			World.set_slots(entity, entry["slots"], entry.get("items", []))
		_top_up(entity, entry["spec"])
	if _adopted > 0:
		# For release, counts only (decision 610): moved markers found.
		print("[state] %s: %d saved level entities found their moved markers" % [World.zone.name, _adopted])
	# Slots with no entity and a saved timer are dead: pick their timers up.
	for respawn: Dictionary in section.get("respawns", []):
		var dead := _slot_for(int(respawn["spawn"]), str(respawn.get("spawn_key", "")))
		if dead >= 0 and not _alive_slots.has(dead) and not recorded.has(dead):
			_dead_since[dead] = World.tick - (_respawn_delay(dead) - respawn["ticks_left"])
	# Slots with neither are new in the level since the save (every dead
	# slot's timer is saved): there now, or dead from now if their tile is taken.
	for slot in level_entities.size():
		if not _alive_slots.has(slot) and not _dead_since.has(slot) and not recorded.has(slot):
			print("[state] %s is new in the level since the save" % level_entities[slot]["name"])
			if _spawn(_slot_spec(slot)) == null:
				_dead_since[slot] = World.tick
	return true


## Whether the saved level entity [param spec] (a saved entry's spec, or a
## record's entry; [param saved], where its hp and things are) is one the
## level says became something else ([param became], level.json "became",
## decision 471): by its spawn key, or from before keys by its name. If so,
## it goes to on_became, its id and {name, hp, slots, items, tile}.
func _hand_over(became: Dictionary, spec: Dictionary, saved: Dictionary) -> bool:
	var key := str(spec.get("spawn_key", ""))
	var id := str(became.get(key, ""))
	if key.is_empty():
		for each: String in became.values():
			if str(spec.get("name", "")).to_lower() == each:
				id = each
	if id.is_empty():
		return false
	var tile: Variant = spec.get("tile")
	var entry := {"name": str(spec.get("name", "")), "hp": int(saved.get("hp", 0)), "slots": saved.get("slots"),
		"items": saved.get("items", []), "tile": tile if tile is Vector2i else Snapshot.vector(tile)}
	print("[state] %s became %s (decision 471): handed over, not spawned" % [entry["name"], id])
	on_became(id, entry)
	return true


## A saved level entity became [param id] (decision 471, _hand_over); npc's
## side seats it as that resident. Each one handed over is kept here too.
var became_handed: Array[Dictionary] = []
## Server: a saved monster whose spawn key the level says "became" a
## resident (enemy-ai's hook in _spawn_saved, decision 471): the one-time
## conversion. [param id] is the resident's (residents.json "settled"),
## [param entry] the saved monster ({name, hp, slots, items, tile}). He is
## seated as at boot, and what he carried goes to the town's store in his
## name; logged once, and never again (he is a worker from then on, and
## nothing saved carries his key). spawn_key_test reads became_handed.
func on_became(id: String, entry: Dictionary) -> void:
	became_handed.append({"id": id, "entry": entry})
	var table := Townsfolk.settled()
	if not table.has(id) or World.production == null:
		return
	var was_worker := not World.production.worker(id).is_empty()
	_seat_settled()
	var settled: Dictionary = table[id]
	var town := str(settled.get("town", ""))
	if World.stockpile != null and not town.is_empty():
		for uid: Variant in entry.get("items", []) if entry.get("items") is Array else []:
			if int(uid) != 0:
				World.stockpile.bank(town, int(uid), str(settled.get("name", id)), "his own", World.zone.name if World.zone != null else "", Vector2i(-1, -1), "banked", "")
	if not was_worker:
		print("[state] %s became a resident (was monster at %s)" % [settled.get("name", id), entry.get("tile", "?")])


# --- Far monsters kept as records (decision 352) -------------------------------

## Monsters near someone come back from their records; then those far from
## everyone long enough, and calm, become records (see retire_tiles).
func _retire_and_recall() -> void:
	var near := World._tier_origins()
	if near.is_empty():
		return  # Nobody has ever been here (a test room): nothing is far.
	var started := Time.get_ticks_usec()
	if not World.zone.records.is_empty():
		for at in near:
			_recall_near(at, RECALL_NOW_TILES)
		# Further out, nearest first, as long as the budget lasts.
		var waiting: Array[Dictionary] = []
		for at in near:
			waiting.append_array(World.take_records_near(at, recall_tiles))
		waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _nearest_of(World.record_tile(a), near) < _nearest_of(World.record_tile(b), near))
		for record in waiting:
			if Time.get_ticks_usec() - started > RECALL_BUDGET_USEC or _recall(record) == null:
				World.add_record(record)  # Its turn on the next pass.
	for keeper: Object in World.keepers:
		for at in near:
			keeper.recall_near(at, recall_tiles)
	started = Time.get_ticks_usec()
	var due := World.tick - RETIRE_AFTER_TICKS
	for entity: GridEntity in World.monsters().duplicate():
		var monster := entity as Monster
		# Most are not far, or not for long yet: passed over with a look.
		if monster == null or monster.far_since < 0 or monster.far_since > due:
			continue
		if Time.get_ticks_usec() - started > RETIRE_BUDGET_USEC:
			break
		if _retirable(monster, near):
			_retire(monster)


## How far [param at] is from the nearest of [param near].
static func _nearest_of(at: Vector2i, near: Array[Vector2i]) -> int:
	var nearest := 1 << 30
	for each in near:
		nearest = mini(nearest, World.distance(at, each))
	return nearest


## The records waiting round a player who joined (Zone.recalls_due), made
## again in turn for RECALL_BUDGET_USEC.
func _recall_due() -> void:
	var due := World.zone.recalls_due
	if due.is_empty():
		return
	var started := Time.get_ticks_usec()
	while not due.is_empty() and Time.get_ticks_usec() - started < RECALL_BUDGET_USEC:
		var record: Dictionary = due.pop_front()
		if _recall(record) == null:
			World.add_record(record)  # No room for it now: kept, tried again later.


## Whether [param monster] can be kept as a record: far from everyone in
## [param near] for long enough, past retire_tiles, calm, nobody's, not a
## raider (Raids holds those as nodes), and with nothing for the world tick
## to walk it to (going back after a fight, or still on a march), so as a
## record it stays exactly where the world tick would have left it.
func _retirable(monster: Monster, near: Array[Vector2i]) -> bool:
	if not monster.spawned or monster.raid != "" or monster.owner_peer != 0 or monster.keeper_peer != 0:
		return false
	if monster.far_since < 0 or World.tick - monster.far_since < RETIRE_AFTER_TICKS:
		return false
	if monster.target != null or monster.alert != Monster.Alert.IDLE or monster._returning or World.is_stunned(monster):
		return false
	if monster.idle == Monster.Idle.MARCH and not monster.route.is_empty() and monster.tile != monster.route.back():
		return false
	for at in near:
		if World.distance(monster.tile, at) <= retire_tiles:
			return false
	return true


## [param monster] kept as a record on its zone instead of a node: what a
## snapshot keeps of it (its slot, hp, stamina, facing, things) and where
## it is on its route. Not a death: its slot is neither alive nor dead
## meanwhile (_recorded_slots), and its things stay where they are held.
func _retire(monster: Monster) -> void:
	# A kind with a world-tick store of its own (wildlife's herds) takes it
	# there instead: its keeper's record, not one of ours.
	for keeper: Object in World.keepers:
		if keeper.takes(monster):
			keeper.retire(monster)
			_despawn_kept(monster)
			return
	var entry := Snapshot.entry(monster)
	if entry.is_empty():
		return
	var route: Array = []
	for point in monster.route:
		route.append([point.x, point.y])
	var record := {"entry": entry, "route": route, "route_index": monster._route_index, "route_step": monster._route_step}
	_despawn_kept(monster)
	World.add_record(record)


## Zone [param each] fallen asleep, nobody in it (397 amended (3)): every
## body a keeper takes (the herds') goes back into its count at once, so a
## sleeping zone holds counts only and its herds' spare is not shut by
## bodies nobody sees; the next visit makes them again (recall_near). One
## wounded or fleeing goes back whole. Nobody's own, none in a raid.
func _retire_sleeping(each: Zone) -> void:
	if not Net.is_authority() or World.keepers.is_empty():
		return
	var was := World.enter(each)
	var back := 0
	for entity: GridEntity in World.monsters().duplicate():
		var monster := entity as Monster
		if monster == null or not monster.spawned or monster.raid != "" or monster.owner_peer != 0 or monster.keeper_peer != 0:
			continue
		for keeper: Object in World.keepers:
			if keeper.takes(monster):
				keeper.retire(monster)
				_despawn_kept(monster)
				back += 1
				break
	World.enter(was)
	if back > 0:
		print("[herds] %s asleep: %d bodies back into their counts" % [each.name, back])


## [param monster] gone from the room but kept (a record, a keeper's): not
## a death, its slot neither alive nor dead.
func _despawn_kept(monster: Monster) -> void:
	var slot := int(monster.spawn_spec.get("spawn", -1))
	if slot >= 0 and _alive_slots.get(slot) == monster:
		_alive_slots.erase(slot)
	_travelling = true  # Kept, not dead.
	World.despawn(monster)
	_travelling = false
	# Freed at the end of the frame (despawn); its name let go now, so one
	# made again under it this frame keeps it. (Taken out of the tree instead,
	# a node queued to be freed is not.)
	monster.name = "%s_kept_%d" % [monster.name, monster.get_instance_id()]


## The records within [param reach] (recall_tiles if -1) of [param at]
## made again, and what keepers keep there.
func _recall_near(at: Vector2i, reach := -1) -> void:
	reach = recall_tiles if reach < 0 else reach
	for record in World.take_records_near(at, reach):
		if _recall(record) == null:
			World.add_record(record)  # No room for it now: kept, tried again later.
	for keeper: Object in World.keepers:
		keeper.recall_near(at, reach)


## [param record] made again as it was kept (_retire): as the snapshot
## path makes a saved entity, on its tile or the nearest free one, then its
## place on its route, so a patrol goes on from there. Null if it cannot be.
func _recall(record: Dictionary) -> GridEntity:
	var parsed := Snapshot.parse_entry(record["entry"])
	if parsed.is_empty():
		return null
	var spec := _level_spec_for(parsed["spec"])
	spec["tile"] = _nearest_free(spec["tile"])
	var entity := _spawn(spec)
	if entity == null:
		return null
	World.restore(entity, parsed["hp"], parsed["stamina"], parsed["facing"])
	if parsed.get("slots") != null:
		World.set_slots(entity, parsed["slots"], parsed.get("items", []))
	var monster := entity as Monster
	if monster != null:
		var route: Array[Vector2i] = []
		for point: Variant in record.get("route", []):
			var tile: Variant = Snapshot.vector(point)
			if tile is Vector2i:
				route.append(tile)
		if not route.is_empty():
			monster.route = route
		monster._route_index = clampi(int(record.get("route_index", 0)), 0, maxi(monster.route.size() - 1, 0))
		monster._route_step = int(record.get("route_step", 1))
	return entity


## A level chest's starting kit brought to a saved world (decision 468;
## Jeff: "make sure that there is a bow and arrow bundle in the town chest
## for practice"): each id of its level props' "stock" that the saved chest
## was never given (not in its saved props' "stocked") is minted into a free
## slot, once; one already in it counts as given. "stocked" stays in the
## chest's props, so the save keeps it and a thing taken never comes back.
## With no free slot it waits for the next load. Logged for release.
func _top_up(entity: GridEntity, saved_spec: Dictionary) -> void:
	var props: Dictionary = entity.spawn_spec.get("props", {})
	var stock: Variant = props.get("stock", [])
	if not entity is Chest or not stock is Array or stock.is_empty():
		return
	var saved_props: Variant = saved_spec.get("props", {})
	var had: Variant = saved_props.get("stocked", []) if saved_props is Dictionary else []
	var stocked: Array = had.duplicate() if had is Array else []
	var slots := entity.slots.duplicate()
	var uids := World.slot_uids(entity)
	var given: Array[String] = []
	for each: Variant in stock:
		var id := str(each)
		if id in stocked or not Items.exists(id):
			continue
		if id in slots:
			stocked.append(id)
			continue
		var free := slots.find("")
		if free < 0:
			print("[state] %s has no room for its stock: %s" % [entity.name, id])
			continue
		slots[free] = id
		uids[free] = World.items.mint(id, "stocked", World._label_of(entity), entity.zone, entity.tile, World.style_from(entity))
		World.items.mark_grave(uids[free], World.grave_from(entity), entity.zone, entity.tile)  # Decision 555.
		stocked.append(id)
		given.append(id)
	props["stocked"] = stocked
	entity.spawn_spec["props"] = props
	if not given.is_empty():
		World.set_slots(entity, slots, uids)
		print("[state] %s topped up: %s" % [entity.name, ", ".join(given)])


## The keys the snapshot being loaded names (_spawn_saved; decision 610),
## and how many of its level entities found their moved markers.
var _saved_keys := {}
var _adopted := 0


## The slot of the marker [param saved] (a saved level entity whose key
## [param key] the level no longer has) was moved to (decision 610,
## extending 433's keys): the nearest marker within MOVED_MARKER_REACH cells
## of its old cell with the same script and the same slots, held by no
## living entity and named by nothing the snapshot saved; -1 if none. A
## moved chest comes back as itself, its things and all, not as a stray
## beside a new one.
func _moved_marker(saved: Dictionary, key: String) -> int:
	var was := Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
	var props: Dictionary = saved.get("props", {}) if saved.get("props") is Dictionary else {}
	var best := -1
	for slot in level_entities.size():
		var marker: Dictionary = level_entities[slot]
		var at: Vector2i = marker["tile"]
		var off := at - was
		if maxi(absi(off.x), absi(off.y)) > MOVED_MARKER_REACH or _alive_slots.has(slot) or _saved_keys.has(_key_of(slot)):
			continue
		var marker_props: Dictionary = marker.get("props", {}) if marker.get("props") is Dictionary else {}
		if str(marker.get("script", "")) != str(saved.get("script", "")) or str(marker_props.get("slots", [])) != str(props.get("slots", [])):
			continue
		if best < 0 or Vector2(off).length() < Vector2(Vector2i(level_entities[best]["tile"]) - was).length():
			best = slot
	return best


## The spawn slots the zone's records hold.
func _recorded_slots() -> Dictionary:
	var slots := {}
	for record in World.record_list():
		var spawn: Variant = record["entry"].get("spawn", -1)
		var slot := _slot_for(int(spawn) if spawn is int or spawn is float else -1, str(record["entry"].get("spawn_key", "")))
		if slot >= 0:
			slots[slot] = true
	return slots


## What a level entity is — script, shape, tint, scale, props — always comes
## from the spawn table as it is now; a snapshot only says where it stands
## (and, separately, its hp, stamina and facing). Otherwise an entity saved by
## an older build would keep that build's looks for ever. The slot is the
## saved one, or for a snapshot from before slots, the table entry of the
## same name. Anything that is not a level entity is returned as saved.
func _level_spec_for(saved: Dictionary) -> Dictionary:
	var key := str(saved.get("spawn_key", ""))
	var slot := _slot_for(int(saved.get("spawn", -1)), key)
	if slot == -1 and key.is_empty():
		for i in level_entities.size():
			if level_entities[i]["name"] == saved.get("name") and not _alive_slots.has(i):
				slot = i
				break
	if slot == -1 and not key.is_empty():
		# Its marker moved (decision 610): the marker it was, within reach.
		slot = _moved_marker(saved, key)
		if slot >= 0:
			_saved_keys[_key_of(slot)] = true
			_adopted += 1
			var moved := _slot_spec(slot)
			moved["tile"] = level_entities[slot]["tile"]
			return moved
	if slot == -1 or _alive_slots.has(slot):
		# No level entity now (its marker gone), or its slot taken: as saved,
		# holding no slot.
		saved.erase("spawn")
		saved.erase("spawn_key")
		return saved
	var spec := _slot_spec(slot)
	spec["tile"] = saved["tile"]
	return spec


## The spawn table entry for [param slot], tagged with its index so the
## entity can be tracked through death and respawn, and its key, which a
## snapshot keeps (decision 433).
## A dead slot's wait (ticks): its level's "respawn_s" for its kind
## (decision 561: the barrow's dead 10 minutes, its robbers 5), else
## RESPAWN_DELAY_TICKS.
func _respawn_delay(slot: int) -> int:
	return Monster.respawn_ticks(str(level_entities[slot].get("kind", "")), RESPAWN_DELAY_TICKS)


func _slot_spec(slot: int) -> Dictionary:
	var spec: Dictionary = level_entities[slot].duplicate(true)
	spec["spawn"] = slot
	spec["spawn_key"] = _key_of(slot)
	return spec


## Each level entity's key by slot, and each key's slot (decision 433),
## made once as the level is read (_index_keys) and swapped with the zone.
var _slot_keys := PackedStringArray()
var _key_slots: Dictionary[String, int] = {}
## How far (cells, either way) a level entity's marker may move and its saved
## entity still find it (decision 610).
const MOVED_MARKER_REACH := 2


func _index_keys() -> void:
	_slot_keys = PackedStringArray()
	_key_slots = {}
	for slot in level_entities.size():
		var at: Vector2i = level_entities[slot]["tile"]
		var key := "%d,%d" % [at.x, at.y]
		_slot_keys.append(key)
		_key_slots[key] = slot


## Level entity [param slot]'s key (decision 433): its marker cell, "x,y".
## A level that gains an entity moves the slots after it; their keys stay.
func _key_of(slot: int) -> String:
	return _slot_keys[slot]


## The slot a snapshot names: by [param key] if it has one (-1 if the level
## no longer has that marker), else, from before keys, by its index
## [param spawn] (right while the level is as it was then).
func _slot_for(spawn: int, key: String) -> int:
	if not key.is_empty():
		return _key_slots.get(key, -1)
	return spawn if spawn >= 0 and spawn < level_entities.size() else -1


## Brings dead level entities back: after their wait (_respawn_delay), with no player
## within RESPAWN_MIN_DISTANCE of the spawn tile (RESPAWN_JOIN_DISTANCE of
## one just put down), onto a free tile; one a zone every
## RESPAWN_STAGGER_TICKS, the farthest from every player first (decision
## 382). A record (decision 352) is no dead slot, so never one of them. With
## [param force], all at once regardless of time and distance. Returns how
## many.
func _check_respawns(tick: int, force := false) -> int:
	var zone_name: String = World.zone.name if World.zone != null else ""
	if _woken.has(zone_name):
		_woken.erase(zone_name)
		_space_after_wake(tick)
	if not force and _respawned_at.has(zone_name) and tick - _respawned_at[zone_name] < RESPAWN_STAGGER_TICKS:
		return 0
	var due: Array[Array] = []  # [steps from the nearest player, slot, spec]
	for slot: int in _dead_since.keys():
		if not force and tick - _dead_since[slot] < _respawn_delay(slot):
			continue
		var spec := _slot_spec(slot)
		var tile: Vector2i = spec["tile"]
		if not World.is_free(tile) or not _camp_lets_back(spec) or not World.named_may_rise(spec):
			continue
		var away := _nearest_player(tile, tick)
		if not force and away < 0:
			continue
		due.append([away, slot, spec])
	if not force:
		due.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var count := 0
	for each: Array in due:
		if _spawn(each[2]) == null:
			continue
		count += 1
		print("[world] respawned %s at %s" % [EntityFactory.type_name(each[2]), each[2]["tile"]])
		if not force:
			_respawned_at[zone_name] = tick
			break
	return count


## How far [param tile] is from the nearest player in this zone (a big
## number with none); -1 if one is too near for a respawn there:
## within RESPAWN_MIN_DISTANCE, or RESPAWN_JOIN_DISTANCE of one put down
## less than RESPAWN_ARRIVAL_TICKS ago.
func _nearest_player(tile: Vector2i, tick: int) -> int:
	var nearest := 1 << 30
	for peer: int in _players:
		var player: Player = _players[peer]
		if not is_instance_valid(player) or not player.spawned or player.zone != World.zone.name:
			continue
		var away := World.distance(player.tile, tile)
		var arrived := tick - int(_arrived_at.get(peer, -RESPAWN_ARRIVAL_TICKS)) < RESPAWN_ARRIVAL_TICKS
		if away <= RESPAWN_MIN_DISTANCE or arrived and (away <= RESPAWN_JOIN_DISTANCE or World.has_line_of_sight(player.tile, tile)):
			return -1
		nearest = mini(nearest, away)
	return nearest


## The zone World is in has just woken (decision 382 amended (2); Jeff died
## in the castle to 10 back in two minutes after 19 hours away): of its dead
## at most one is due now, each of the rest its own full wait after the one
## before (soonest due first), or later if its own timer says so.
func _space_after_wake(tick: int) -> void:
	var slots: Array = _dead_since.keys()
	if slots.is_empty():
		return
	var due_at := func(slot: int) -> int: return _dead_since[slot] + _respawn_delay(slot)
	slots.sort_custom(func(a: int, b: int) -> bool: return due_at.call(a) < due_at.call(b))
	var at := tick
	for i in slots.size():
		var slot: int = slots[i]
		var delay := _respawn_delay(slot)
		at = maxi(due_at.call(slot), tick if i == 0 else at + delay)
		_dead_since[slot] = at - delay
	print("[world] %s woke: %d dead come back one at a time, the last in %d s" % [World.zone.name, slots.size(),
		roundi(float(at - tick) / World.TICK_RATE)])


## The snapshot's writer (decision 360): the world is gathered here, on the
## main thread (it reads the nodes), copied whole, and the JSON made and
## written (a temp file, renamed over the snapshot) on this thread. One at a
## time, in order: a periodic save while one is still being written is
## skipped (the next comes in SNAPSHOT_EVERY_TICKS), and any other waits
## for that one first, then for its own; quitting waits for the last.
var _saver: Thread = null
## Whether this run has said how many level entities a save holds by key.
var _keys_said := false


## The snapshot, written before this returns; with [param wait] false (the
## periodic one), written on _saver while the game goes on.
func _save_state(wait := true) -> void:
	if not Net.is_authority() or Net.state_path == "":
		return
	if not wait and _saver != null and _saver.is_alive():
		return  # The last is still being written: this one is skipped.
	for peer: int in _players.keys():
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.spawned and _records.has(_peer_ids.get(peer, "")):
			_records[_peer_ids[peer]].remember(player)
	for id: String in _companions.keys():
		_remember_companion(id)
	var records: Array[PlayerRecord] = []
	records.assign(_records.values())
	var zones := {}
	var level_held := 0
	var keyed := 0
	var was := World.zone
	for each: Zone in World.zones.values():
		World.enter(each)
		var respawns: Array[Dictionary] = []
		for slot: int in _dead_since:
			respawns.append({"spawn": slot, "spawn_key": _key_of(slot),
				"ticks_left": maxi(_respawn_delay(slot) - (World.tick - _dead_since[slot]), 0)})
		for entity in World.get_entities():
			World.slot_uids(entity)  # A chest's things get their instances before the book is saved.
			if int(entity.spawn_spec.get("spawn", -1)) >= 0:
				level_held += 1
				keyed += 1 if str(entity.spawn_spec.get("spawn_key", "")) != "" else 0
		var ground := ground_entries(each)
		zones[each.name] = {"tick": World.tick, "entities": World.get_entities(), "respawns": respawns, "ground": ground,
			"records": World.record_list()}
	World.enter(was)
	if not _keys_said:
		# Once a run, for release (decision 433): whether the save has its
		# level entities by their keys, told without reading it.
		_keys_said = true
		print("[state] saved %d level entities, %d keyed" % [level_held, keyed])
	var data := Snapshot.data_of(zones, records, {"steps": World.steps,
		"holdings": World.holdings.to_dict() if World.holdings != null else {},
		"stockpile": World.stockpile.to_dict() if World.stockpile != null else {},
		"production": World.production.to_dict() if World.production != null else {},
		"towns": World.towns.to_dict() if World.towns != null else {},
		"herders": World.towns.herders_to_dict() if World.towns != null else {},
		"clearing": World.clearing.to_dict() if World.clearing != null else {},
		"plots": World.clearing.plots_to_dict() if World.clearing != null else {},
		"roofs": World.roofs_damaged.keys(),
		"trampled": World.trampled_to_dict(),
		"raid_groups": World.raid_groups.to_dict() if World.raid_groups != null else {},
		"trade": World.trade.to_dict() if World.trade != null else {},
		"placed_captives": _placed_captives.duplicate(true),
		"sought_bands": _sought_bands.duplicate(true),
		"alms_runs": _alms_runs.duplicate(true),
		"crypt_told": _crypt_told.duplicate(true),
		"runner_out": _runner_out.duplicate(true),
		"economy": World.economy.to_dict() if World.economy != null else {},
		"herds": World.herds.to_dict() if World.herds != null else {},
		"items": World.items.to_dict(),
		"regen": _regen,
		"free_walk": World.free_walk,  # Decision 689: the admin's switch outlives a restart.
		"named": World.named,  # Decision 716: the named enemies' records.
		"sky": _sky_saved()}).duplicate(true)  # Its own: the sim goes on meanwhile.
	_finish_saving()
	_saver = Thread.new()
	_saver.start(Snapshot.write.bind(Net.state_path, data))
	if wait:
		_finish_saving()


## Waits for the snapshot being written, if one is.
func _finish_saving() -> void:
	if _saver != null:
		_saver.wait_to_finish()
		_saver = null


## Once every awake zone has stepped: the snapshot, every SNAPSHOT_EVERY_TICKS,
## written on a thread (decision 360).
func _on_world_stepped() -> void:
	if Net.is_authority():
		_swap_richness()
	if Net.is_authority() and World.steps % SNAPSHOT_EVERY_TICKS == 0:
		_save_state(false)
	if Net.is_authority() and World.steps % World.WORLD_TICK_STEPS == 0:
		# The clients' clocks, kept from drifting off the world's.
		Net.broadcast("sky", sky_message())
		_regenerate_due()
	if Net.is_authority() and World.steps % HALL_SEAL_EVERY == 0:
		for zone_name: String in _hall_seals:
			if _hall_seals[zone_name]:
				_apply_hall_seal(zone_name)  # A seal that waited for the hall to empty (666).


## The "sky" message: the world clock (DayNight.to_dict) and the server's
## World.steps now, which a client counts on from (decision 290).
func sky_message() -> Dictionary:
	var data := _sky_saved()
	data.erase("storms_checked")  # The server's own: not sent.
	data["steps"] = World.steps
	# The server's climates: a client works the weather out from them.
	data["climates"] = Weather.climates()
	return data


## The clock and the weather's overrides, as the snapshot keeps them.
func _sky_saved() -> Dictionary:
	var data := DayNight.to_dict()
	data["overrides"] = Weather.live_overrides(World.steps)
	data["storms_checked"] = Weather.storms_checked
	return data


## The console's weather: [param words] after it. With none, each open
## zone's weather now.
func _weather_command(words: PackedStringArray) -> String:
	if words.size() >= 2:
		var kind := words[1].to_lower()
		if kind == "reload":
			Weather.reload()
		elif kind != "auto" and not Weather.KINDS.has(kind):
			return "usage: weather [%s|auto|reload] [<minutes>] [<region>|all]" % "|".join(Weather.KINDS.keys())
		else:
			var minutes := words[2].to_float() if words.size() >= 3 and words[2].is_valid_float() else 30.0
			var region := words[3] if words.size() >= 4 else "all"
			if region != "all" and not Weather.climates().has(region):
				return "no climate for region %s (regions: %s)" % [region, ", ".join(Weather.climates().keys())]
			Weather.set_override(region, kind, minutes)
		if Net.state_path != "":
			_save_state()
		Net.broadcast("sky", sky_message())
	var lines: Array[String] = []
	var was := World.zone
	for each: Zone in World.zones.values():
		World.enter(each)
		var here: Dictionary = Weather.at(World.fields.region, World.steps) if World.outdoor else {}
		lines.append("%s (%s): %s" % [each.name, World.fields.region, "indoors" if here.is_empty() else
			"%s, cloud %.2f rain %.2f fog %.2f wind %.2f" % [here["kind"], here["cloud"], here["rain"], here["fog"], here["wind"]]])
	World.enter(was)
	return "
".join(lines) if not lines.is_empty() else "no open zones"


## The console's hour and day_minutes: [param words] after the command.
func _sky_command(words: PackedStringArray) -> String:
	if words.size() >= 2:
		if not words[1].is_valid_float() or (words[0].to_lower() == "day_minutes" and words[1].to_float() <= 0.0):
			return "usage: hour <0..24> | day_minutes <minutes>"
		if words[0].to_lower() == "hour":
			DayNight.set_hour(fposmod(words[1].to_float(), 24.0))
		else:
			DayNight.set_day_minutes(words[1].to_float())
		if Net.state_path != "":
			_save_state()
		Net.broadcast("sky", sky_message())
	var now := DayNight.now()
	return "hour %.2f, a day takes %.1f minutes, daylight %.2f" % [DayNight.hour(now),
		DayNight.day_steps / float(World.TICK_RATE) / 60.0, DayNight.daylight(now)]


## The console's season and season_days: [param words] after the command.
func _season_command(words: PackedStringArray) -> String:
	if words.size() >= 2:
		var word := words[1].to_lower()
		if words[0].to_lower() == "season":
			if not word in Season.NAMES:
				return "usage: season <%s> | season_days <n>" % "|".join(Season.NAMES)
			Season.set_season(word)
		else:
			if not word.is_valid_int() or word.to_int() < 1:
				return "usage: season <%s> | season_days <n>" % "|".join(Season.NAMES)
			Season.set_season_days(word.to_int())
		DayNight.update()
		if Net.state_path != "":
			_save_state()
		Net.broadcast("sky", sky_message())
	var now := DayNight.now()
	var here := Season.at(World.fields.region, now)
	return "%s (year %.3f), a season takes %d days, cold %.2f, snow cover %.2f" % [here["name"],
		Season.year_fraction(now), Season.season_days, here["cold"], here["snow"]]


func _exit_tree() -> void:
	# Clean shutdown (quit, window closed): keep the last state, unless it was
	# kept before the zones were let go (_release_zones), which an empty world
	# saved now would overwrite.
	if not _released:
		_save_state()
	# A periodic snapshot still being written finishes first (decision 360).
	_finish_saving()
	# A generation being made is let go, written nowhere (decision 684).
	_drop_making()
	# Routes still being made on pool tasks would crash a server on its way out.
	if World.raid_groups != null:
		World.raid_groups.finish()
	if World.trade != null:
		World.trade.finish()
	if World.richness != null:
		World.richness.finish()
	if _richness_next != null:
		_richness_next.finish()
	# The stdin thread runs this node's method: it must have stopped before
	# the node goes, or the server crashes on its way out (one stopped within
	# 2 s of starting found it still waiting out stdin's end; decision 299).
	# It sees _stdin_stop within 100 ms unless a live terminal holds it in a
	# read, when it cannot be joined and is left to die.
	_stdin_stop = true
	var deadline := Time.get_ticks_msec() + 500
	while _stdin_thread != null and _stdin_thread.is_alive() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	if _stdin_thread != null and _stdin_thread.is_started() and not _stdin_thread.is_alive():
		_stdin_thread.wait_to_finish()


func _spawn(spec: Dictionary) -> GridEntity:
	spec["zone"] = World.zone.name
	var entity := spawner.spawn(spec) as GridEntity
	if not World.spawn(entity, spec["tile"]):
		entities.remove_child(entity)
		entity.queue_free()
		return null
	Net.interest.add(entity)
	if entity is Monster and entity.has_method("offers_for"):
		_hook_talker(entity)  # One that talks (the draugr, 548): its first words and its withdrawals (decision 546, npc's side).
	if spec.has("spawn"):
		_alive_slots[spec["spawn"]] = entity
		_dead_since.erase(spec["spawn"])
	return entity


## Gives [param peer] the player its [param id] stands for: back where that
## player left off if the server has seen the id before (nearest free tile
## if its own is taken), fresh at a start tile if not. [param respawn] is a
## death: known player, but a start tile and full stats.
func _join_player(peer: int, id: String, player_name: String, respawn := false, at := World.NO_CELL) -> void:
	var record: PlayerRecord = _records.get(id)
	var known := record != null
	if not known:
		record = PlayerRecord.new()
		record.player_id = id
		record.index = _records.size() + 1
		record.color = PLAYER_TINTS[(record.index - 1) % PLAYER_TINTS.size()]
		_records[id] = record
	record.name = player_name
	var asked := Net.asked_body(id)
	if asked != &"":
		record.body = asked
	if Net.asked_body(id) != &"" or Net.asked_look(id) != "":
		record.look = Net.asked_look(id)  # Their choice this join (none: seeded by name).
	var back := known and not respawn
	# The zone laid again since they were last in it (decision 465): their
	# saved cell may be rock now, so the nearest anchor's spawn point, or
	# the nearest floor, and their companion beside them.
	var generation := generation_of(World.zone.name)
	var shifted := generation > 0 and not respawn and int(record.seen_generation.get(World.zone.name, 0)) != generation
	if shifted and back:
		var spawn: Variant = Regen.anchor_spawn_near(level, record.tile)
		if spawn != null:
			record.tile = spawn
		record.companion["tile"] = null
	var tile := _nearest_free(record.tile) if back else _free_start_tile()
	if respawn and at != World.NO_CELL:
		tile = _nearest_free(at)  # Brought back at a temple or a hut (decision 396).
	if not World.is_free(tile):
		print("[net] no free tile for %s (%s)" % [player_name, id.left(8)])
		return
	# Monsters kept as records near where they come in are back first
	# (decision 352): those near enough to count for spawn safety now, the
	# rest over the next ticks, before the player's view arrives.
	_recall_near(tile, RECALL_JOIN_NOW_TILES)
	var due := World.take_records_near(tile, recall_tiles)
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return World.distance(World.record_tile(a), tile) < World.distance(World.record_tile(b), tile))
	World.zone.recalls_due.append_array(due)
	# Spawn safety: not next to a hostile. Applies to coming back and to
	# respawning; a first join is at a start tile anyway and gets the same check.
	var intended := tile
	var threat := _nearest_hostile_distance(intended)
	if threat <= SPAWN_SAFE_DISTANCE and not (back and _reloading):
		tile = _safest_start_tile(intended)
		print("[spawn] %s: hostile %d tiles from the %s tile %s; using start tile %s, %d from the nearest hostile" % [
			player_name, threat, "saved" if back else "start", intended, tile, _nearest_hostile_distance(tile)])
		back = false
	else:
		print("[spawn] %s: %s tile %s, no hostile within %d" % [
			player_name, "saved" if back else "start", tile, SPAWN_SAFE_DISTANCE])
	var player := _spawn({
		"script": PLAYER, "shape": "capsule", "name": "Player%d" % record.index, "tile": tile,
		"peer": peer, "tint": record.color, "label": player_name, "look": record.look,
	}) as Player
	if player == null:
		return
	if known and not respawn:
		World.restore(player, record.hp if record.hp > 0 else player.max_hp, record.stamina, record.facing)
	World.protect(player, SPAWN_GRACE_TICKS)
	_arrived_at[peer] = World.tick
	player.player_id = id
	player.body = record.body
	World.set_slots(player, record.slots, record.slot_items)
	record.remember(player)
	record.zone = World.zone.name
	if not World.peer_zone.has(peer):
		World.peer_zone[peer] = World.zone.name
	# What this peer is sent is what is round its player now.
	Net.interest.centre(peer, World.zone.name, player.tile)
	_players[peer] = player
	_peer_ids[peer] = id
	migrate_totem(record)  # A count from before 573 amended onto the totem (items').
	_sync_charges(record)
	_living_came(player)
	_fell_at.erase(peer)
	print("[net] %s (%s) joined as %s at %s%s" % [
		player_name, id.left(8), player.name, tile, " (back)" if back else ""])
	party_log.add("%s joined." % player_name)
	if shifted:
		# Back at a newer generation: told; a first visit is not.
		if int(record.seen_generation.get(World.zone.name, 0)) > 0:
			Net.broadcast_to([peer], "party", {"from": "Server", "text": "The ways have shifted since you were last here."})
		record.seen_generation[World.zone.name] = generation
	_join_companion(record, player)
	_on_gold_changed(id, World.gold_of(id))
	_test_foe(player)
	if admin_peer_allowed(peer, id) and peer != Net.local_id:
		Net.message_to(peer, "admin", {"admin": true})  # 672: their F10 opens the panel.


# --- Towns -----------------------------------------------------------------------

## Server: a town's building was unlocked, built, raised, damaged or
## repaired (Towns.building_changed): every peer, and this one, is told the
## town's buildings ("town" {town, buildings}).
func _on_town_building_changed(town: String, _kind: String) -> void:
	Net.broadcast("town", {"town": town, "buildings": World.towns.buildings_of(town), "awake": World.towns.awake_of(town),
		"stage": World.towns.stage(town)})
	World.open_roofs(town.get_slice("/", 0))


## Server: a roof of [param level] was damaged or mended (World.damage_roof,
## repair_roof, decision 383): every peer, and this one, is told the level's
## damaged roofs ("roofs" {level, damaged: their indices}).
func _on_roof_changed(level: String) -> void:
	Net.broadcast("roofs", {"level": level, "damaged": World.damaged_roofs(level)})
	_show_towns()


## Server: a telegraph shown (decision 602): the players in its zone are told
## ("telegraph", its data).
func _tell_telegraph(_id: int, data: Dictionary) -> void:
	var peers := World.peers_in(str(data["zone"]))
	if not peers.is_empty():
		Net.broadcast_to(peers, "telegraph", data)


## Server: a telegraph over: its zone's players are told ("telegraph" {id,
## landed}).
func _tell_telegraph_ended(zone_name: String, id: int, landed: bool) -> void:
	var peers := World.peers_in(zone_name)
	if not peers.is_empty():
		Net.broadcast_to(peers, "telegraph", {"id": id, "landed": landed})


## A "telegraph" message (decision 602): one shown (it has "cells"), kept in
## telegraphs and telegraph_started; else one over, telegraph_ended.
func _on_telegraph(data: Dictionary) -> void:
	var id := int(data.get("id", 0))
	if data.has("cells"):
		telegraphs[id] = data
		telegraph_started.emit(id, data)
	elif telegraphs.has(id):
		telegraphs.erase(id)
		telegraph_ended.emit(id, bool(data.get("landed", false)))


## Server: tall grass of [param level] was trampled or stood again
## (World.grass_changed, decision 508): the players in its zone are told
## ("grass" {level, flat, stood}: flat [x, y, ...]).
func _on_grass_changed(level: String, flat: PackedInt32Array, stood: PackedInt32Array) -> void:
	var peers := World.peers_in(level)
	if not peers.is_empty():
		Net.broadcast_to(peers, "grass", {"level": level, "flat": flat, "stood": stood})


## Server: how many residents [param town] feeds (or who go hungry)
## changed (Economy.dole_changed, decision 353): the players in its zone
## are told, in the party log.
func _on_dole_changed(town: String, count: int) -> void:
	var peers := World.peers_in(town.get_slice("/", 0))
	if peers.is_empty():
		return
	var text := "Nobody in town is on the dole now." if count == 0 \
			else "%d in town %s on the dole (fed by the town, or hungry): its kitchen works for food first." % [count, "is" if count == 1 else "are"]
	Net.broadcast_to(peers, "party", {"from": "Town", "text": text})


## Server: a herder's fold changed (Towns.folds_changed, 640): every peer
## is told the folds of its area ("folds" {counts: {place id: sheep}}).
func _on_folds_changed(place_id: String) -> void:
	var area := str(World.holdings.place(place_id).get("area", "")) if World.holdings != null else ""
	Net.broadcast("folds", {"counts": World.towns.folds(area)})


## Server: [param peer], come to [param zone_name], is told the buildings of
## each town there, and the herders' folds (640).
func _send_towns(peer: int, zone_name: String) -> void:
	if World.towns == null:
		return
	var folds := World.towns.folds(zone_name)
	if not folds.is_empty():
		Net.message_to(peer, "folds", {"counts": folds})
	for town: String in World.towns.to_dict():
		if town.begins_with(zone_name + "/"):
			Net.message_to(peer, "town", {"town": town, "buildings": World.towns.buildings_of(town), "awake": World.towns.awake_of(town),
				"stage": World.towns.stage(town)})


## The view's buildings drawn as their towns have them: the server's own
## records on the server (its player never gets a zone's greeting), else
## what it was told.
func _show_towns() -> void:
	if _client3d == null:
		return
	if Net.is_authority() and World.towns != null:
		for town: String in World.towns.to_dict():
			town_states[town] = World.towns.buildings_of(town)
	for town: String in town_states:
		_client3d.set_town(town, town_states[town])
	var level := str(_terrain.get("level", ""))
	if Net.is_authority() and not level.is_empty():
		_client3d.set_roofs(level, World.damaged_roofs(level))
	for told: String in roof_states:
		_client3d.set_roofs(told, roof_states[told])


# --- Trade -----------------------------------------------------------------------

## Server: a player's gold changed; their client is told ("shop" {gold}).
func _on_gold_changed(id: String, gold: int) -> void:
	if id.begins_with("companion:"):
		tell_companion_gold(id.trim_prefix("companion:"))  # Her purse (decision 614): to her card.
		return
	for peer: int in _peer_ids:
		if _peer_ids[peer] == id:
			Net.message_to(peer, "shop", {"gold": gold})


## A player's bandaging of [param patient] could not begin (decision 625):
## why, to that player alone as a Server line (BANDAGE_REFUSED).
func _tell_bandage_refused(player: GridEntity, patient: GridEntity) -> void:
	var why := World.bandage_refusal(player, patient)
	var line := str(BANDAGE_REFUSED.get(why, ""))
	if line.is_empty() or (player as Player).owner_peer == 0:
		return
	var whom := "yourself" if patient == player else _display_name(patient)
	Net.broadcast_to([(player as Player).owner_peer], "party", {"from": "Server", "text": line % whom})


## A player's bandaging broken off (decision 625): why, to them alone.
func _tell_bandage_broke(by: GridEntity, patient: GridEntity, state: StringName) -> void:
	if state != &"interrupted" or not by is Player or (by as Player).owner_peer == 0:
		return
	var why: String = {"patient_moved": "%s moved" % _display_name(patient), "moved": "you moved", "hurt": "someone was hurt",
		"not_safe": "a monster came near"}.get(World.bandage_broke_why, "")
	if not why.is_empty():
		Net.broadcast_to([(by as Player).owner_peer], "party", {"from": "Server", "text": "Your bandaging broke off: %s." % why})


## Why a player's own bandage could not begin (decision 625), %s whom.
const BANDAGE_REFUSED := {"not_beside": "You can't bandage %s: come within two steps of them, nothing between.", "no_wound": "You can't bandage %s: there's no wound to bind.",
	"mending": "You can't bandage %s: the wound is bound already.", "busy": "You can't bandage %s: your hands are busy.",
	"no_kit": "You can't bandage %s: you have no bandaging kit.", "hurt_now": "You can't bandage %s: give it a breath after that blow.",
	"not_safe": "You can't bandage %s: a monster is too near."}


## Server: [param by] traded at [param shop], or was refused ([param why]):
## they are sent the shop again, and the refusal.
## Server: a move refused for the armour slot's rule (decision 622): its
## why to the player who moved it (a companion's, to her keeper).
func _on_slot_refused(by: GridEntity, why: String) -> void:
	var peer := by.owner_peer if by is Player else by.keeper_peer
	if peer != 0:
		Net.broadcast_to([peer], "party", {"from": "Server", "text": why[0].to_upper() + why.substr(1) + "."})


func _on_traded(by: GridEntity, shop: GridEntity, why: String) -> void:
	if by is Player and by.owner_peer != 0 and is_instance_valid(shop):
		_send_shop(by as Player, shop, why)


## Server: sends [param player]'s client what [param shop]'s town sells and
## what it would pay for the things they carry ("shop" {shop, town, gold,
## goods [{uid, id, price}], offers {id: gold}, why}); a shop the town
## doesn't hold is sent with none.
func _send_shop(player: Player, shop: GridEntity, why := "") -> void:
	var place := World.shop_place(shop)
	var data := {"shop": str(shop.get_path()), "town": place, "gold": World.gold_of(player.player_id),
		"goods": [], "offers": {}, "why": why}
	if not place.is_empty() and World.economy != null:
		data["goods"] = World.economy.goods(place, World.fence_state(shop))
		data["offers"] = World.economy.offers(place, Array(player.slots))
	Net.message_to(player.owner_peer, "shop", data)


## Server: sends [param player]'s client the barter at [param shop]
## (decision 560): "barter" {shop, town, gold, goods [{uid, id, price}],
## buys {id: {gold, up_to}}, fenced {uid: gold} (their grave goods, at
## the fenced price), pack [{slot, uid, id}] (their own things), resident,
## why}; a shop the town doesn't hold is sent with none. With [param maker]
## (decision 562: a maker's barter, [param shop] their body) "shop" is ""
## and "resident" their path: their own make, and what they buy from their
## purse ("" otherwise).
func _send_barter(player: Player, shop: GridEntity, why := "", maker := "") -> void:
	var place := World.shop_place(shop) if maker.is_empty() else str(World.production.worker(maker).get("town", ""))
	var data := {"shop": str(shop.get_path()) if maker.is_empty() else "", "resident": str(shop.get_path()) if not maker.is_empty() else "",
		"town": place, "gold": World.gold_of(player.player_id), "goods": [], "buys": {}, "fenced": {}, "pack": [], "why": why,
		"fence": World.fence_state(shop) if maker.is_empty() else ""}
	var uids := World.slot_uids(player)
	for slot in player.slots.size():
		if not player.slots[slot].is_empty():
			# A stack's every unit (decision 619): the barter gives that many of its uids.
			data["pack"].append({"slot": slot, "uid": uids[slot], "id": player.slots[slot], "uids": World.slot_units(player, slot),
				"count": World.slot_count(player, slot)})
	if not maker.is_empty() and World.economy != null:
		data["goods"] = World.economy.maker_goods(maker)
		data["buys"] = World.economy.maker_buys(maker, Array(player.slots))
		var hut := _care_hut_of(maker)
		if not hut.is_empty():
			# The healer's care (584 amended): what his hut takes, and whether and how you are in it.
			var rule := care_rule(hut)
			var given := care_given(player.player_id, hut)
			data["care"] = {"gold": rule["retainer"], "herbs": rule["herbs"], "antlers": rule["antlers"],
				"in_care": in_care(player.player_id, hut), "by": care_via(player.player_id, hut),
				"given": {"herbs": int(given.get("herbs", 0)), "antlers": int(given.get("antlers", 0))}}  # 584 amended (2).
	elif not place.is_empty() and World.economy != null:
		data["goods"] = World.economy.goods(place, data["fence"])
		data["buys"] = World.economy.buys(place, Array(player.slots))
		for each: Dictionary in data["pack"]:
			if data["fence"] == Economy.FENCE_NIGHT and data["buys"].has(each["id"]) and World.items.is_grave(int(each["uid"])):
				data["fenced"][each["uid"]] = World.economy.fence_price(int(data["buys"][each["id"]]["gold"]))
	Net.message_to(player.owner_peer, "barter", data)


# --- The healer's care (decision 584 amended) ------------------------------------------

## The healer's hut whose care medicine man [param worker_id] gives (his
## town's zone's, maps' 372), "" if he is none or has no hut.
func _care_hut_of(worker_id: String) -> String:
	if World.production == null or not "medicine_man" in World.production.worker(worker_id).get("trades", []):
		return ""
	return _healers_hut_of(str(World.production.worker(worker_id).get("town", "")))


## What the healer's hut [param place_id] takes for his care
## (Economy.care_rule): its kin errand only at a hut a town has built.
func care_rule(place_id: String) -> Dictionary:
	if World.economy == null:
		return {}
	var shop := _return_workshop(place_id)
	var town := shop.get_slice(":", 0) if not shop.is_empty() else ""
	var built: bool = World.towns != null and not town.is_empty() and World.towns.building(town, "healers_hut").get("state") == Towns.STANDING
	return World.economy.care_rule(built)


## Whether player [param player_id] is in the care of the healer's hut
## [param place_id] (584 amended): only then does it bring them back.
func in_care(player_id: String, place_id: String) -> bool:
	var record: PlayerRecord = _records.get(player_id)
	return record != null and record.care.has(place_id)


## How player [param player_id] came into the care of [param place_id]
## ("gold", "herbs", "antlers", "quest"; any hut's for ""), "" if not.
## npc reads "herbs" or "quest" as his first errand done
## (Economy.CARE_QUEST_WAYS).
func care_via(player_id: String, place_id := "") -> String:
	var record: PlayerRecord = _records.get(player_id)
	if record == null:
		return ""
	if not place_id.is_empty():
		return str(record.care.get(place_id, ""))
	for place: String in record.care:
		return str(record.care[place])
	return ""


## Player [param player_id] comes into the care of the healer's hut
## [param place_id] by [param way] (Economy.CARE_WAYS): the retain command's
## bypass, or npc's call when his first errand is done ("quest", which also
## upgrades a paid way). False if nothing changed.
func grant_care(player_id: String, place_id: String, way: String) -> bool:
	var record: PlayerRecord = _records.get(player_id)
	if record == null or place_id.is_empty():
		return false
	var kept := Economy.care_after(str(record.care.get(place_id, "")), way)
	if kept.is_empty():
		return false
	record.care[place_id] = kept
	print("[economy] %s is in the care of %s (%s)" % [record.name, place_id, kept])
	# The way in met: its tally goes (584 amended (2)); the herbs' only once his first errand counts as done.
	care_clear(player_id, place_id, ["antlers", "herbs"] if kept in Economy.CARE_QUEST_WAYS else ["antlers"])
	return true


## The tally toward the care of the hut [param place_id] (584 amended (2)):
## what [param player_id] has handed so far, {herbs, antlers, brew_herbs,
## brew_antlers} as present; {} for none.
func care_given(player_id: String, place_id: String) -> Dictionary:
	var record: PlayerRecord = _records.get(player_id)
	if record == null:
		return {}
	return (record.care_given.get(place_id, {}) as Dictionary).duplicate()


## [param count] more of [param key] handed toward the care of
## [param place_id]: the new total (0 with no record).
func care_give(player_id: String, place_id: String, key: String, count: int) -> int:
	var record: PlayerRecord = _records.get(player_id)
	if record == null or place_id.is_empty() or count <= 0:
		return 0
	var mine: Dictionary = record.care_given.get(place_id, {})
	mine[key] = int(mine.get(key, 0)) + count
	record.care_given[place_id] = mine
	return int(mine[key])


## The tally's [param keys] toward [param place_id] cleared, a count met.
func care_clear(player_id: String, place_id: String, keys: Array) -> void:
	var record: PlayerRecord = _records.get(player_id)
	if record == null or not record.care_given.has(place_id):
		return
	var mine: Dictionary = record.care_given[place_id]
	for key: Variant in keys:
		mine.erase(str(key))
	if mine.is_empty():
		record.care_given.erase(place_id)


## Server: the "retain" command (584 amended) {resident: the medicine
## man's path, pay: "gold" | "herbs" | "antlers", gold if left out}: the
## player hands him care_rule's retainer gold (into his purse), or the herbs
## or antlers they hold (into his hut's store: herbs as the resource,
## antlers as themselves; no sale), counted toward care_rule's number on
## their record's tally (584 amended (2): the pack holds four): short of it
## he says how many more; at it they are in his hut's care. The barter is
## sent again, its why on a refusal: too far away, already in his care,
## not enough gold (10), no herbs in your pack. The way in once met, ""
## before that or refused.
func retain(player: Player, args: Dictionary) -> String:
	var body := get_node_or_null(NodePath(str(args.get("resident", "")))) as Resident
	if body == null or World.production == null or World.economy == null:
		return ""
	var hut := _care_hut_of(body.worker_id)
	var pay := str(args.get("pay", "gold"))
	var me := player.player_id
	var why := ""
	var rule := care_rule(hut) if not hut.is_empty() else {}
	if hut.is_empty():
		why = "he keeps no hut"
	elif body.zone != player.zone or World.distance(player.tile, body.tile) > World.COMPANION_REACH:
		why = "too far away"
	elif in_care(me, hut):
		why = "already in his care"
	elif pay not in ["gold", "herbs", "antlers"]:
		why = "he takes gold, herbs or antlers"
	elif pay == "gold" and World.gold_of(me) < int(rule["retainer"]):
		why = "not enough gold (%d)" % int(rule["retainer"])
	var paid: Array[int] = []
	if why.is_empty() and pay != "gold":
		var left := int(rule[pay]) - int(care_given(me, hut).get(pay, 0))
		paid = World.units(player, pay).slice(0, maxi(left, 0))  # Unit by unit, stacks too (decision 619).
		if paid.is_empty():
			why = "no %s in your pack" % pay
	var met := false
	if why.is_empty():
		var name := str(World.production.worker(body.worker_id).get("name", "The healer"))
		if pay == "gold":
			World.add_gold(me, -int(rule["retainer"]), "the healer's retainer")
			World.production.pay(body.worker_id, int(rule["retainer"]), "a retainer")
			met = true
		else:
			var store := str(World.production.worker(body.worker_id).get("town", ""))
			var taken := World.take_units(player, paid)
			for uid: int in taken:
				if not store.is_empty():
					World._bank_thing(store, uid, _display_name(player), _display_name(player), player.zone, player.tile)
			var total := care_give(me, hut, pay, taken.size())
			met = total >= int(rule[pay])
			if not met:
				Net.broadcast_to([player.owner_peer], "party", {"from": name,
					"text": str(Offers.settings().get("care", {}).get("counted", "That's %d. %d more and you're in my care.")) % [total, int(rule[pay]) - total]})
		if met:
			grant_care(me, hut, pay)
			Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": "%s takes you into his care." % name})
	_send_barter(player, body, why, body.worker_id)
	return pay if why.is_empty() and met else ""


## Server: whether [param player] can barter at [param shop] (decision
## 560): within reach of the counter, or of a merchant of its town (a
## resident of the merchant trade or type) who fronts it.
func _barter_reach(player: GridEntity, shop: GridEntity) -> bool:
	if World.reaches(player, shop):
		return true
	var place := World.shop_place(shop)
	if place.is_empty() or World.production == null:
		return false
	for entity: GridEntity in World.townsfolk():
		if not entity is Resident or (entity as Resident).town != place or not World.reaches(player, entity):
			continue
		var who := World.production.worker((entity as Resident).worker_id)
		if "merchant" in who.get("trades", []) or str(who.get("type", "")) == "merchant":
			return true
	return false


## Server: [param player]'s client is sent counter [param counter]'s work
## for them (World.counter_view: "counter" message, decision 438).
func _send_counter(player: Player, counter: GridEntity, why := "") -> void:
	Net.message_to(player.owner_peer, "counter", World.counter_view(player, counter, why))


## Server: a job on a thing for someone is done (Production.work_done): a
## reforge that could not be done gives the fee back from the treasury;
## its owner, at a counter of that town, is sent it again.
func _on_counter_work_done(job: Dictionary) -> void:
	var town := str(job.get("town", ""))
	if bool(job.get("failed", false)) and int(job.get("fee", 0)) > 0 and World.stockpile.take(town, "gold", int(job["fee"]), "refund:%s" % job.get("payer", "")):
		World.add_gold(str(job.get("payer", "")), int(job["fee"]), "a reforge that could not be done")
	var owner := str(job.get("for", ""))
	for peer: int in _players:
		var player: Player = _players[peer]
		if not is_instance_valid(player) or World.owner_of(player) != owner:
			continue
		for entity: GridEntity in World.get_entities():
			if not World.counter_kind(entity).is_empty() and World.reaches(player, entity) and World.counter_place(entity) == town:
				_send_counter(player, entity)


## The counter screen fed (economy's "counter" message for the open counter).
func _on_counter_told(data: Dictionary) -> void:
	if counter_panel == null or pack_panel == null or not is_instance_valid(pack_panel.other):
		return
	if str(data.get("counter", "")) != str(pack_panel.other.get_path()):
		return
	counter_panel.show_counter(data, slot_title)


## What the pack calls the thing in the player's slot [param slot]: the
## note's head (a named thing's title) or the catalog name.
func slot_title(slot: int) -> String:
	var player := _local_player()
	if player == null or slot < 0 or slot >= player.slots.size():
		return ""
	if slot < player.slot_notes.size() and not player.slot_notes[slot].is_empty():
		var head := player.slot_notes[slot].split("\n", false)[0]
		return head.substr(0, head.find(",")) if head.contains(",") else head
	return Items.name_of(player.slots[slot])


func _order_at_counter(slot: int, effect: String, to_id: String) -> void:
	var player := _local_player()
	if player == null or pack_panel == null or not is_instance_valid(pack_panel.other):
		return
	var args := {"counter": str(pack_panel.other.get_path()), "do": "order", "slot": slot, "effect": effect}
	if not to_id.is_empty():
		args["to_id"] = to_id
	World.command(player, "counter", args)


func _collect_at_counter(uid: int) -> void:
	var player := _local_player()
	if player == null or pack_panel == null or not is_instance_valid(pack_panel.other):
		return
	World.command(player, "counter", {"counter": str(pack_panel.other.get_path()), "do": "collect", "uid": uid})


## The client's counter screen's data.
func _on_counter_message(data: Dictionary) -> void:
	counter_data = data
	if data.has("gold"):
		gold = int(data["gold"])
	counter_told.emit(data)


## The client's shop panel and the gold beside the pack.
func _on_shop_message(data: Dictionary) -> void:
	if data.has("gold"):
		gold = int(data["gold"])
	if shop_panel != null:
		shop_panel.gold = gold
		if data.has("shop"):
			shop_panel.show_shop(data)


# --- Companions ----------------------------------------------------------------

## Where [param record]'s companion is when she is not with them in
## [param zone] (Jeff's barrow: Pip worked in town and he thought she had
## failed to follow), as one line for her player: held by raiders, gone
## home as a friend, left them, or resting, working or sick in a town, each
## with what brings her back. "" when she is with them, or there is none.
func _companion_whereabouts(record: PlayerRecord, zone: String) -> String:
	var hers := record.companion
	if hers.is_empty() or bool(hers.get("solo", false)) or not hers.get("alive", true):
		return ""
	var her_name := str(hers.get("name", "Your companion"))
	if hers.has("taken"):
		return "%s was carried off by raiders and is held by them still." % her_name
	if hers.get("parted") is Dictionary:
		return "%s went home to %s. Ask %s there to travel with you again." % [her_name, _town_words(str(hers["parted"].get("place", ""))), _companion_object(record)]
	if hers.has("left"):
		return "%s left you and lives in %s now." % [her_name, _town_words(str(hers["left"].get("place", "")))]
	var resident: Dictionary = hers.get("resident", {})
	var town := str(resident.get("zone", ""))
	if resident.is_empty() or town == zone:
		return ""
	var town_name := str(Level.load_level(town).get("display_name", town)) if Level.exists(town) else town
	var doing := "working" if not str(resident.get("trade", "")).is_empty() else "resting"
	if hers.get("sick") is Dictionary and not hers["sick"].is_empty():
		doing = "sick in %s bed" % {"her": "her", "him": "his", "them": "their"}.get(_companion_object(record), "her")  # Decision 501.
	return "%s is %s in %s, not with you. Go to %s and %s will travel with you again." % [her_name, doing, town_name, town_name, _companion_subject(record)]


## Tells [param player] where their companion is, if not with them
## (_companion_whereabouts), and keeps the time, so the line is said again
## once their view of the zone is built (_view_ready) if it took a while.
func _tell_whereabouts(record: PlayerRecord, player: Player) -> void:
	var words := _companion_whereabouts(record, player.zone if not player.zone.is_empty() else World.zone.name)
	if words.is_empty():
		return
	Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": words})
	_where_told[player.owner_peer] = Time.get_ticks_msec()


## Gives [param player] its record's companion: a new one on first join,
## spawned adjacent; the remembered one, where it was, if it is alive; none
## if it died. A companion that is already in the world (its owner was away)
## just gets its owner back.
func _join_companion(record: PlayerRecord, player: Player) -> void:
	if not Net.companions:
		return
	if bool(record.companion.get("solo", false)):
		return  # Nobody with them since theirs went home to her town (686): none given.
	# Carried off by raiders (decision 314): held till she is freed.
	if record.companion.has("taken"):
		print("[net] %s's companion %s is held by raiders (%s); none spawned" % [record.name, record.companion.get("name", "?"),
			record.companion["taken"].get("by", "?")])
		_tell_whereabouts(record, player)
		return
	# Parted as friends (581 amended (3)): she rests in her town till asked there.
	if record.companion.get("parted") is Dictionary:
		_tell_whereabouts(record, player)
		return
	# Gone home, having left them (decision 581): she does not come.
	if record.companion.has("left"):
		var town := _town_words(str(record.companion["left"].get("place", "")))
		print("[net] %s's companion %s left them and lives in %s" % [record.name, record.companion.get("name", "?"), town])
		_tell_whereabouts(record, player)
		return
	# Working in a town (decision 284): elsewhere, she stays at it; here,
	# she leaves it and goes with them, her job waiting.
	var resident: Dictionary = record.companion.get("resident", {})
	if not resident.is_empty() and not record.companion.has("home"):
		record.companion["home"] = resident.duplicate()  # A record from before decision 381.
	if not record.companion.has("home"):
		_fill_home(record)
	if not resident.is_empty():
		if str(resident.get("zone", "")) != World.zone.name:
			print("[net] %s's companion %s works in %s; not here" % [record.name, record.companion.get("name", "?"), resident.get("zone", "?")])
			_tell_whereabouts(record, player)  # Told where she is, so she does not read as lost.
			return
		_heard_from_worker(record)
		if World.towns != null:
			World.towns.note_companion_out(str(resident.get("place", "")), String(record.companion["name"]))
		record.companion.erase("resident")
		party_log.add("%s leaves her work in the town and goes with %s." % [record.companion["name"], record.name])
		if record.companion.get("sick") is Dictionary and not record.companion["sick"].is_empty():
			# Sick in her bed (decision 501): she goes all the same.
			party_log.add("%s is sick with %s, and goes with %s all the same." % [record.companion["name"],
				record.companion["sick"].get("kind", "a fever"), record.name])
		# Her body in town goes; she comes as herself (decision 333 amended).
		for body: GridEntity in World.townsfolk().duplicate():
			if (body as Resident).player_id == record.player_id:
				_travelling = true
				World.despawn(body)
				_travelling = false
	var existing: Companion = _companions.get(record.player_id)
	if is_instance_valid(existing) and existing.spawned and existing.zone != player.zone:
		# Waiting in a zone they are not in (a rejoin somewhere else: a start
		# tile, a town after death): she comes to them, never left alone.
		_remember_companion(record.player_id)
		record.companion["tile"] = null
		_travelling = true
		World.despawn(existing)
		_travelling = false
		_companions.erase(record.player_id)
		existing = null
	if is_instance_valid(existing) and existing.spawned:
		if World.distance(existing.tile, player.tile) > REJOIN_NEAR:
			# He was put somewhere else (a start tile away from a hostile, a
			# town): she comes with him, beside him (decision 705; Jeff came
			# back 130 cells from Pip, and she walked it alone).
			var was := existing.tile
			World._relocate(existing, _nearest_free(player.tile))
			print("[spawn] %s's companion %s waited at %s, %d from where %s came back; beside them" % [
				record.name, existing.name, was, World.distance(was, player.tile), record.name])
		existing.works_as = ""
		existing.home = record.companion.get("home", {})
		existing.keeper = player
		# A rejoin is a new peer: she is theirs again (replicated, so their
		# client knows her for their own: a right click opens her pack).
		existing.keeper_peer = player.owner_peer
		existing.current_intent = Companion.Intent.FOLLOW
		if existing.mind != null:
			existing.mind.warm()
		print("[net] %s's companion %s was waiting at %s and follows again" % [
			record.name, existing.name, existing.tile])
		_tell_sickness(existing, record, true)
		return
	# A record from before companions existed, or one that never got one,
	# has none: give it one now.
	var is_new := record.companion.is_empty() or not record.companion.get("name") is String
	if is_new:
		record.companion = {"hp": 0, "stamina": 0, "tile": [player.tile.x, player.tile.y], "alive": true}
	_give_traits(record)
	if not record.companion.get("alive", true):
		print("[net] %s's companion %s died earlier; none spawned" % [record.name, record.companion["name"]])
		return
	# Where it was, unless that is no place to appear alone: it has no saved
	# tile, or a hostile is close to it. Then beside its owner, who was put
	# somewhere safe.
	var saved: Variant = Snapshot.vector(record.companion.get("tile"))
	var wanted: Vector2i = player.tile
	if saved != null and str(record.companion.get("tile_zone", player.zone)) != player.zone:
		saved = null  # Her tile is another zone's (she waited there; they are back somewhere else).
	if saved != null and World.distance(saved, player.tile) > REJOIN_NEAR:
		saved = null  # He came back somewhere else in it (705): beside him.
	if saved != null and not is_new:
		if _nearest_hostile_distance(saved) > SPAWN_SAFE_DISTANCE:
			wanted = saved
		else:
			print("[spawn] %s's companion %s: hostile within %d of its saved tile %s; beside its owner instead" % [
				record.name, record.companion["name"], SPAWN_SAFE_DISTANCE, saved])
	var tile := _nearest_free(wanted)
	if not World.is_free(tile):
		print("[net] no free tile for %s's companion %s near %s" % [record.name, record.companion["name"], wanted])
		return
	var pet := _spawn({
		"script": COMPANION, "shape": "capsule", "name": String(record.companion["name"]), "tile": tile,
		"tint": COMPANION_TINT, "label": String(record.companion["name"]),
		"look": CompanionCard.look_of(record.companion.get("traits", {}), record.player_id),
		"props": {"keeper_peer": player.owner_peer},
	}) as Companion
	if pet == null:
		return
	pet.keeper_id = record.player_id
	pet.keeper = player
	pet.traits = record.companion["traits"]
	# Her body by her card's pronoun (Pip "he"); CompanionCard.body_of to come.
	pet.body = CompanionCard.body_of(pet.traits, pet.keeper_id)
	pet.card = str(record.companion["card"])
	pet.how_we_met = str(record.companion.get("how_we_met", ""))
	pet.card_by = str(record.companion.get("card_by", "plain"))
	pet.card_written.connect(_on_card_written.bind(pet, record))
	pet.grown = CompanionFacts.from_record(record.companion.get("facts", []), record.companion.get("beliefs", []))
	pet.heard = record.companion.get("heard", [])
	# Her bond with her player (decision 444): first met now if never, and
	# her voice told it from her record as it stands.
	if Standing.entry(record.companion, record.player_id).is_empty():
		Standing.met(record.companion, record.player_id, World.steps)
	pet.bond_words = func() -> String:
		# And what her bond's step does to her (decision 555).
		var step: String = (Companion.loyalty().get("words", {}) as Dictionary).get(pet.bond_step, "")
		var fact := Standing.fact(record.companion, record.player_id, record.name, Standing.COMPANION)
		return fact if step.is_empty() else (fact + " " + step % record.name).strip_edges()
	pet.superstition = CompanionCard.leaning(record.companion.get("traits", {}), record.player_id, "superstition")
	# Her focus (decision 577): an old card's rolled from her traits now.
	if not record.companion.get("focus") is Dictionary or (record.companion["focus"] as Dictionary).is_empty():
		record.companion["focus"] = CompanionCard.roll_focus(record.companion.get("traits", {}))
	pet.focus = record.companion["focus"]
	pet.talk.assign(record.companion.get("talk", []))
	pet.facts_changed.connect(_on_facts_changed.bind(pet, record))
	pet.restore_said(record.companion.get("said", []))
	World.set_slots(pet, record.companion.get("slots", []), record.companion.get("items", []))
	pet.party_log = party_log
	pet.home = record.companion.get("home", {})
	# The draugr's blessing (decision 544): she brings her downed player back.
	pet.can_revive = func() -> bool: return _can_revive(pet, record)
	pet.revive = func(by: GridEntity, body: GridEntity) -> bool: return _start_channel(by, body)
	_wire_guide(pet, record, player)  # Her guiding (decision 551).
	_bond_warned(pet)  # Taken where she said it wasn't safe (555 amended).
	pet.mind = _make_mind()
	if _claude_voices.has(record.player_id):
		pet.mind = ClaudeMind.new(pet.mind, _claude_voices[record.player_id], self)
	pet.mind.warm()  # The model loads now, not on her first ask.
	pet.write_card()  # Once: a plain card stands until it is written.
	pet.said.connect(_on_companion_said.bind(pet))
	# The deeds she sees and her voice feels (decision 621).
	pet.deed.connect(func(event: String, why: String) -> void: _bond(_record_of(pet), event, why))
	pet.felt.connect(_bond_felt.bind(pet))
	pet.played.connect(_bond_played.bind(pet))
	pet.on_road = _on_road
	pet.in_town = func(cell: Vector2i) -> bool: return not _town_ground(World.zone.name, cell).is_empty()
	if int(record.companion.get("hp", 0)) > 0:
		World.restore(pet, int(record.companion["hp"]), int(record.companion.get("stamina", pet.max_stamina)), pet.facing)
	_companions[record.player_id] = pet
	_set_mood(record)  # Once she is hers: before it, her step never reached her (fond after every join).
	print("[net] %s's companion %s is at %s%s" % [
		record.name, pet.name, tile, " (new)" if is_new else ""])
	_tell_sickness(pet, record, true)


# --- Her guiding (decision 551) ---------------------------------------------------

## Server: [param pet]'s guiding wired as she joins (decision 551): the
## world's routes, her walk's stops and ways out, what she knows for her
## voice, and a walk her player's id still has (they crossed into this zone
## with her, or a stopped one to take up again) bound to the new bodies.
func _wire_guide(pet: Companion, record: PlayerRecord, player: Player) -> void:
	pet.guide_routes = func() -> WorldRoutes: return World.raid_groups.routes if World.raid_groups != null else null
	pet.guide_done = _guide_done
	pet.guide_words = func() -> String: return _roads_words(record, pet)
	var walk: Guide = _guides.get(record.player_id)
	if walk != null:
		walk.bind(pet, player)
		pet.guide = walk
		player.led_by = String(pet.name) if walk.going() else ""
		player.led_to = str(walk.goal.get("key", "")) if walk.going() else ""
		if walk.going():
			_guide_check.call_deferred(pet)  # The road on from here, once her voice is in.
	_tell_roads(record, pet)
	_tell_capabilities(record, pet)  # And what she has learned (decision 576).
	_tell_focus(record, pet)  # And her focus (decision 577).
	tell_companion_gold(record.player_id)  # And her gold (decision 614).


## What she knows of the roads, for her voice: the places nearest first
## (places_told of them) she knows the way to; none for none.
func _roads_words(record: PlayerRecord, pet: Companion) -> String:
	var known := Guide.destinations(record.companion, World.holdings, _world_map)
	if known.is_empty():
		return ""
	var here := func(each: Dictionary) -> int:
		return World.distance(each["cell"], pet.tile) if each["area"] == pet.zone else 100000
	known.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return here.call(a) < here.call(b))
	var names: Array[String] = []
	for each: Dictionary in known.slice(0, int(Guide.setting("places_told", 5.0))):
		names.append(str(each["name"]))
	# Devoted, she offers; below it she follows; sullen, she leads nowhere
	# (decisions 555, 621).
	var offer: String = (Companion.loyalty().get("guide_words", {}) as Dictionary).get(pet.bond_step, "")
	var can := ", and can lead them there" if pet.bond_at_least("devoted") else ""
	return ("You know the way to %s, having been there with %s%s. %s" % [", ".join(names), record.name, can, offer]).strip_edges()


## Her player's map told what she knows the way to (decision 551): the
## "world" message's "guide" {companion, places (Holdings ids), areas}.
func _tell_roads(record: PlayerRecord, pet: Companion) -> void:
	var peer := _peer_of(record.player_id)
	if peer == 0 or _world_news == null or not _world_news.send.is_valid():
		return
	var roads := Guide.roads_of(record.companion)
	_world_news.send.call(peer, {"full": false, "guide": {"companion": String(pet.name),
		"places": (roads["places"] as Array).duplicate(), "areas": (roads["areas"] as Array).duplicate()}})


## Each companion out with her player comes to know where she stands (her
## roads, decision 551), on the same beat as her player's own fog.
func _observe_roads() -> void:
	if World.holdings == null:
		return
	for id: String in _companions:
		var pet: Companion = _companions[id]
		var record: PlayerRecord = _records.get(id)
		if record == null or not is_instance_valid(pet) or not pet.spawned or record.companion.has("resident") \
				or not is_instance_valid(pet.keeper) or not pet.keeper.spawned:
			continue
		var places: Array = []
		for place_id: String in World.holdings.places_in(pet.zone):
			places.append({"id": place_id, "cell": World.holdings.place(place_id)["cell"]})
		if Guide.observe(record.companion, pet.zone, pet.tile, places):
			_tell_roads(record, pet)


## Her player's words to her (decision 551): an ask to lead the way to a
## place she knows sets her off, and her voice, about to answer, is told
## she agreed; one she does not know, that she does not know the way;
## "lead on" takes a stopped walk up again. True if it was such an ask.
func _guide_said(player: Player, pet: Companion, line: String) -> bool:
	var record := _record_of(pet)
	if record == null:
		return false
	var walk: Guide = _guides.get(record.player_id)
	if Guide.asks_resume(line):
		# As far as she offered (551 phase 2), else the stopped walk.
		var offer: Dictionary = _guide_offers.get(record.player_id, {})
		if int(offer.get("day", -1)) == Townsfolk.day_of(World.steps):
			_start_guide(pet, player, offer["to"])
			return true
		if walk != null and not walk.going() and walk.keeps():
			_start_guide(pet, player, walk.goal)
			return true
	if not Guide.asks(line):
		return false
	var known := Guide.destinations(record.companion, World.holdings, _world_map)
	var to := Guide.named_in(line, known)
	if to.is_empty() and RegEx.create_from_string("(?i)\\b(to|towards?)\\b").search(line) == null:
		to = _nearest_known(pet, known)  # Not said where (decision 616): the nearest place she knows.
	if to.is_empty():
		pet.guide_note = "%s asks you to lead them somewhere you have not been with them: you do not know the way there." % record.name
		return true
	if pet.zone == to["area"] and World.distance(pet.tile, to["cell"]) <= int(Guide.setting("arrive", 3.0)):
		pet.guide_note = "%s asks you to lead them to %s, and you are there already." % [record.name, to["name"]]
		return true
	_start_guide(pet, player, to)
	return true


## Of [param known] (Guide.destinations), the place nearest [param pet] in
## her own area, else the first she knows; {} if none.
func _nearest_known(pet: Companion, known: Array[Dictionary]) -> Dictionary:
	var best := {}
	for each: Dictionary in known:
		if each["kind"] == "place" and each["area"] == pet.zone and (best.is_empty()
				or World.distance(pet.tile, each["cell"]) < World.distance(pet.tile, best["cell"])):
			best = each
	return best if not best.is_empty() else (known[0] if not known.is_empty() else {})


## [param pet] sets off leading [param player] to [param to] (Guide's
## destination), her voice told so once; unless the road there is not safe
## (551 phase 2), or she refused it earlier today: her voice told why.
func _start_guide(pet: Companion, player: Player, to: Dictionary) -> void:
	if not pet.bond_at_least("devoted"):
		# Only devoted, she takes the lead (decision 621, Jeff's); sullen
		# or colder, she is unhappy with them (555).
		var why := "you will not lead them anywhere now: you are unhappy with them" if not pet.bond_at_least("wary") \
			else "you follow them, and do not trust yourself to take the lead yet"
		pet.guide_note = "%s asked you to lead them to %s, but %s." % [_display_name(player), to["name"], why]
		party_log.add("%s won't lead the way." % pet.name)
		return
	var day := Townsfolk.day_of(World.steps)
	var before: Dictionary = (_guide_refused.get(pet.keeper_id, {}) as Dictionary).get(str(to.get("key", "")), {})
	if int(before.get("day", -1)) == day:
		pet.guide_note = "%s asks you again to lead them to %s; you refused earlier today and still will not: it isn't safe: %s." % [
			_display_name(player), to["name"], before["reason"]]
		return
	var no := _guide_refusal(pet, player, to)
	if not no.is_empty():
		_guide_refuse(pet, player, to, no)
		pet.guide_note = "%s asked you to lead them to %s, but you will not go: it isn't safe: %s.%s Tell them so." % [
			_display_name(player), to["name"], no["reason"], _as_far_words(no)]
		party_log.add("%s won't lead the way to %s: it isn't safe." % [pet.name, to["name"]])
		return
	_guide_offers.erase(pet.keeper_id)
	var walk: Guide = _guides.get(pet.keeper_id)
	if walk != null and walk.goal.get("key") == to.get("key"):
		walk.resume()
	else:
		walk = Guide.new(to)
	walk.bind(pet, player)
	walk.send_route = _send_guide_route  # (Unbound: a walk holding itself would never be freed.)
	_guides[pet.keeper_id] = walk
	pet.guide = walk
	player.led_by = String(pet.name)
	player.led_to = str(to.get("key", ""))
	pet.guide_note = "%s asked you to lead them to %s, and you know the way: you are leading them there now, walking ahead; you told them to follow as you set off, so don't say it again." % [_display_name(player), to["name"]]
	party_log.add("%s leads the way to %s." % [pet.name, to["name"]])
	print("[guide] %s leads %s to %s (%s)" % [pet.name, _display_name(player), to["name"], to["key"]])


## [param walk]'s route for its leader's free body to her heel (695): the
## owner's "world" message's "guide_route" {companion, zone, path: [[x, y],
## ...]}, empty when the walk ends; their client steers it as a click's
## route, and their own key or click stops it ("guide" {"stop": "moved"}).
func _send_guide_route(path: Array, walk: Guide) -> void:
	if not is_instance_valid(walk.leader) or not is_instance_valid(walk.pet) or _world_news == null or not _world_news.send.is_valid():
		return
	_world_news.send.call(walk.leader.owner_peer, {"full": false, "guide_route": {"companion": String(walk.pet.name),
		"zone": walk.leader.zone, "path": path}})


## The "guide" command's "stop" (695): [param player]'s own key or click
## took over the route their client was steering; her walk stops as
## "moved", as a grid body's own step stops it.
func _guide_stop_asked(player: Player, why: String) -> void:
	var pet: Companion = _companions.get(_peer_ids.get(player.owner_peer, ""))
	if why != "moved" or not is_instance_valid(pet) or pet.guide == null or not pet.guide.going() or pet.guide.leader != player:
		return
	_guide_done(pet, "moved")


## The "guide" command (decision 551, the map's "ask her to lead you
## there"): its "to", a place's Holdings id or an area's name she knows.
func _guide_asked(player: Player, to_key: String) -> void:
	var pet: Companion = _companions.get(_peer_ids.get(player.owner_peer, ""))
	var record := _record_of(pet) if is_instance_valid(pet) and pet.spawned else null
	if record == null or pet.zone != player.zone:
		return
	for each: Dictionary in Guide.destinations(record.companion, World.holdings, _world_map):
		if each["key"] == to_key:
			_start_guide(pet, player, each)
			return


## Her walk stopped, or at a way out (Companion.guide_done, Guide.step's
## [param why]): through the way with her player; else stopped, control
## theirs, the party log and her voice told why.
func _guide_done(pet: Companion, why: String) -> void:
	var walk := pet.guide
	if walk == null:
		return
	if why == "cross" and _guide_cross(pet, walk):
		return
	if why == "cross":
		why = "no_way"
	walk.stop(why)
	var record := _record_of(pet)
	var who := _display_name(walk.leader) if is_instance_valid(walk.leader) else (record.name if record != null else "")
	if is_instance_valid(walk.leader):
		walk.leader.led_by = ""
		walk.leader.led_to = ""
	var words := Guide.stop_words(why, who)
	print("[guide] %s stops: %s" % [pet.name, why])
	if why == "arrived":
		party_log.add("%s has brought %s to %s." % [pet.name, who, walk.goal["name"]])
		pet.guide = null
		_guides.erase(pet.keeper_id)
		pet._ask_voice("You have led %s to %s, as they asked." % [who, walk.goal["name"]])
	elif why != "moved" and why != "lost":
		party_log.add("%s stops leading the way: %s." % [pet.name, words])
		pet._ask_voice("You stopped leading %s to %s: %s." % [who, walk.goal["name"], words])


## Through the way out her walk is at (Guide.crossing, at
## Guide.crossing_at): a link (closed, or sealed to her player, stops it)
## or an edge, her player and she together, after the tick (Main.travel).
## False if it cannot be taken.
func _guide_cross(pet: Companion, walk: Guide) -> bool:
	var way := walk.crossing
	var peer := walk.leader.owner_peer
	if way.is_empty() or not Level.exists(str(way.get("to", ""))):
		return false
	if way["kind"] == "link":
		for link: Dictionary in level.get("links", []):
			if link["tile"] == way["at"] and (link.get("closed", false) or not sealed_open(link, peer)):
				return false
		travel.call_deferred(peer, str(way["to"]), str(way.get("to_spawn", "")))
	else:
		var out: Vector2i = Guide.SIDES.get(str(way["side"]), Vector2i.ZERO)
		travel.call_deferred(peer, str(way["to"]), "", {"side": way["side"], "cell": walk.crossing_at + out})
	walk.crossing_now = true
	print("[guide] %s takes %s through to %s" % [pet.name, _display_name(walk.leader), way["to"]])
	# Through this area from a way in to a way out with no stop: a safe
	# passage halves its dangers (551 phase 2, RoadKnowledge's).
	var record := _record_of(pet)
	if walk.clean and record != null and RoadKnowledge.passed(record.companion, pet.zone, Townsfolk.day_of(World.steps)):
		print("[guide] %s came through %s safely" % [pet.name, pet.zone])
	return true


## The refusal of the road from where [param pet] stands to [param to],
## leading [param player] (Guide.refusal): {} if she will go. Her offer is
## dropped when it is where she stands or the goal itself.
func _guide_refusal(pet: Companion, player: Player, to: Dictionary) -> Dictionary:
	var record := _record_of(pet)
	if record == null:
		return {}
	var routes: WorldRoutes = pet.guide_routes.call() if pet.guide_routes.is_valid() else null
	var company := 0
	for peer: int in _players:
		var other: Player = _players[peer]
		if other != player and is_instance_valid(other) and other.spawned and other.zone == player.zone \
				and World.distance(other.tile, player.tile) <= HEARING_RANGE:
			company += 1
	var no := Guide.refusal(record.companion, record.player_id, Guide.road_of(routes, pet.zone, pet.tile, to), company,
		Townsfolk.day_of(World.steps), World.holdings, Guide.destinations(record.companion, World.holdings, _world_map), _world_map)
	var as_far: Dictionary = no.get("as_far", {})
	if not as_far.is_empty() and (as_far["key"] == to["key"]
			or as_far["area"] == pet.zone and World.distance(as_far["cell"], pet.tile) <= int(Guide.setting("arrive", 3.0))):
		no["as_far"] = {}
	return no


## She refused to lead [param player] to [param to] for [param no]
## (_guide_refusal's): kept for the day, her offer standing.
func _guide_refuse(pet: Companion, player: Player, to: Dictionary, no: Dictionary) -> void:
	var day := Townsfolk.day_of(World.steps)
	var refused: Dictionary = _guide_refused.get(pet.keeper_id, {})
	for key: String in refused.keys():
		if int(refused[key].get("day", -1)) != day:
			refused.erase(key)
	refused[str(to["key"])] = {"day": day, "reason": no["reason"], "as_far": no["as_far"],
		"area": str((no.get("worst", {}) as Dictionary).get("area", ""))}
	_guide_refused[pet.keeper_id] = refused
	if (no["as_far"] as Dictionary).is_empty():
		_guide_offers.erase(pet.keeper_id)
	else:
		_guide_offers[pet.keeper_id] = {"day": day, "to": no["as_far"]}
	print("[guide] %s refuses to lead %s to %s: %s" % [pet.name, _display_name(player), to["key"], no["reason"]])


## Her offer in [param no], for her voice: " You would lead them as far as
## the mill." or "".
func _as_far_words(no: Dictionary) -> String:
	var as_far: Dictionary = no.get("as_far", {})
	return "" if as_far.is_empty() else " You would lead them as far as %s, and no further." % as_far["name"]


## [param pet]'s walk weighed again from where she stands (551 phase 2:
## come into a new area, or news heard): stopped if the road on is not
## safe, her voice told why. True if it stopped.
func _guide_check(pet: Companion) -> bool:
	if not is_instance_valid(pet) or pet.guide == null or not pet.guide.going() or not is_instance_valid(pet.guide.leader):
		return false
	var walk := pet.guide
	var no := _guide_refusal(pet, walk.leader, walk.goal)
	if no.is_empty():
		return false
	var who := _display_name(walk.leader)
	_guide_refuse(pet, walk.leader, walk.goal, no)
	walk.stop("unsafe")
	walk.leader.led_by = ""
	walk.leader.led_to = ""
	party_log.add("%s stops leading the way to %s: it isn't safe." % [pet.name, walk.goal["name"]])
	pet._ask_voice("You stopped leading %s to %s: it isn't safe: %s.%s" % [who, walk.goal["name"], no["reason"], _as_far_words(no)])
	return true


## The road's news (551 phase 2, npc's road_news through road_heard): heard
## by each companion out with a player in [param town]'s zone (news told)
## or resting in that town, kept as a heard danger (RoadKnowledge.heard); a
## walk going on is weighed again.
func _road_heard(town: String, news: Dictionary) -> void:
	var told: Array = news.get("told", [])
	for id: String in _records:
		var record: PlayerRecord = _records[id]
		if record.companion.is_empty():
			continue
		var pet: Companion = _companions.get(id)
		var resident: Variant = record.companion.get("resident")
		var hears := str(resident.get("place", "")) == town if resident is Dictionary \
			else id in told and is_instance_valid(pet) and pet.spawned
		if not hears or RoadKnowledge.heard(record.companion, news, World.holdings, Guide.rules()).is_empty():
			continue
		print("[guide] %s hears of the raid by %s" % [record.companion.get("name", ""), news.get("camp", "")])
		if is_instance_valid(pet) and pet.guide != null:
			_guide_check(pet)


## What she lives through, kept as a danger of the area (decision 551):
## downed, carried off, her player falling beside her, a blow leaving her or
## them under hurt_mark of their hp.
func _roads_downed(entity: GridEntity, _source: GridEntity, _ticks: int) -> void:
	_roads_lived(entity, "downed")


func _roads_taken(entity: GridEntity, _by: String) -> void:
	if entity is Companion:
		_roads_lived(entity, "taken")


func _roads_fell(entity: GridEntity, _cause: StringName) -> void:
	if entity is Player:
		_roads_lived(entity, "fell")


func _roads_struck(entity: GridEntity, amount: int, _source: GridEntity, _cause: StringName) -> void:
	if amount > 0 and entity.hp > 0 and entity.max_hp > 0 and float(entity.hp) / entity.max_hp < Guide.setting("hurt_mark", 0.25):
		_roads_lived(entity, "hurt")


## [param entity] (her, or her player with her near) lived [param why]
## where they stand: the danger noted on her roads.
func _roads_lived(entity: GridEntity, why: String) -> void:
	var pet := entity as Companion
	if pet == null and entity is Player:
		var near: Companion = _companions.get(_peer_ids.get(entity.owner_peer, ""))
		if is_instance_valid(near) and near.spawned and near.zone == entity.zone and World.distance(near.tile, entity.tile) <= HEARING_RANGE:
			pet = near
	var record := _record_of(pet) if pet != null else null
	if record == null or record.companion.has("resident"):
		return
	if not Guide.note_danger(record.companion, entity.zone, why, Townsfolk.day_of(World.steps)).is_empty():
		print("[guide] %s will remember %s: %s" % [pet.name, entity.zone, why])


# --- The draugr's blessing (decision 544) -------------------------------------

## The mark the draugr's blessed carry (540's, on a player's record; on a
## companion's, record.companion["marks"]).
const BLESSED := "draugr"
## The lock on the draugr's hall door while it is held shut (573 amended):
## a key nobody holds.
const HALL_LOCK := "draugr_hall"
## The hidden door's lock (608): the first hall's hidden niche, a key nobody
## holds; lifted by a press on it or a climb from below.
const HIDDEN_LOCK := "hidden_niche"
## How long the one who finds it stands while the slab gives way (608
## amended (2)): Client3D's shudder, grind back and slide, 1.1 s, so the
## press's carry does not take them down the stair before it is seen.
const NICHE_FOUND_HOLD := 11
## How often a waiting seal on the hall is asked again (666): 1 s.
const HALL_SEAL_EVERY := 10
## The hall's door while the Ossuary's dead stand (666): a key nobody holds.
const DEAD_LOCK := "ossuary_dead"
## Said to one who tries the sealed hall door (666; a draft for lore).
const DEAD_LINE := "The dead bar the way."
## The device's two halves (items' kinds, 544's items' side): minted no more
## since 573 (the charges are a count on the record); those held are keepsakes.


# --- Leaving (decision 581) -------------------------------------------------------

## The leaving rules: companion_traits.json "leaving".
static func leaving_rules() -> Dictionary:
	var rules: Variant = CompanionCard.tables().get("leaving", {})
	return rules if rules is Dictionary else {}


## After her bond moved by [param event] ([param why]): at the bottom step,
## or on the last straw at or below its step, she will leave (her record's
## "leaving" {deed, why, day}); she goes at the next calm moment
## (_leaving_tick), or, dead now (bled out), when she is next back.
func _check_leaving(record: PlayerRecord, event: String, why: String) -> void:
	if record.companion.has("left") or record.companion.has("leaving") or record.companion.has("resident"):
		return
	var step := bond_step_of(record.companion, record.player_id)
	var straw: Dictionary = leaving_rules().get("last_straw", {})
	var straw_at := Companion.STEPS.find(str(straw.get("at", "sullen")))
	if step == Companion.STEPS[0] or event == str(straw.get("deed", "")) and Companion.STEPS.find(step) <= straw_at:
		record.companion["leaving"] = {"deed": event, "why": why, "day": Townsfolk.day_of(World.steps)}
		print("[bond] %s's companion %s will leave them (%s: %s)" % [record.name, record.companion.get("name", "?"), event, why])


## Each tick, this zone's companions who will leave: at a calm moment
## (nothing hostile near her, neither she nor her player down) she says so
## and sets off for the nearest way out; there, or past walk_s and out of
## her player's sight (at most twice walk_s), she is gone home.
func _leaving_tick() -> void:
	for id: String in _companions.keys():
		var pet: Companion = _companions[id]
		var record: PlayerRecord = _records.get(id)
		if record == null or not record.companion.has("leaving") or not is_instance_valid(pet) or not pet.spawned or pet.zone != World.zone.name:
			continue
		var going: Dictionary = record.companion["leaving"]
		var player: Player = _players.get(_peer_of(id))
		if not pet.leaving:
			if not World.calm(pet) or World.is_downed(pet) or is_instance_valid(player) and World.is_downed(player):
				continue
			_begin_leaving(record, pet, going, player)
			continue
		var seen := is_instance_valid(player) and player.spawned and player.zone == pet.zone \
				and World.distance(player.tile, pet.tile) <= Companion.SIGHT_RANGE and World.has_line_of_sight(player.tile, pet.tile)
		var from := int(going.get("from", World.tick))
		var until := int(going.get("until", 0))
		if pet.tile == pet.leaving_to or World.tick >= until and not seen or World.tick >= until + (until - from):
			_gone_home(record, pet, id)


## She says she is leaving and sets off (decision 581): her voice asked past
## the rate limit, the party told where she goes, her player's things put
## down for them, a walk she was leading ended.
func _begin_leaving(record: PlayerRecord, pet: Companion, going: Dictionary, player: Player) -> void:
	pet.leaving = true
	pet.leaving_to = _nearest_way_out(pet.tile)
	going["from"] = World.tick
	going["until"] = World.tick + roundi(float(leaving_rules().get("walk_s", 30)) * World.TICK_RATE)
	going["place"] = _home_place(record)
	going["grave"] = _grave_carried(pet)
	var town := _town_words(str(going["place"]))
	if _guides.has(record.player_id):
		_guide_done(pet, "moved")
	if str(going.get("deed", "")) == PARTED:
		pet._ask_voice("%s asked you to go home for a while, and you part as friends: you go home to %s, and will travel with them again when they ask." % [record.name, town], "", true)
		party_log.add("%s goes home to %s; you part as friends." % [pet.name, town])
	else:
		pet._ask_voice("You are leaving %s for good, and going home to %s: they %s." % [record.name, town, str(going.get("why", "wronged you"))], "", true)
		party_log.add("%s leaves you, and goes home to %s." % [pet.name, town])
	_return_gear(record, pet, player)


## What of her player's she carries goes back (decision 581): a thing her
## player once carried and did not name for her (a named gift is hers),
## put down at their feet (at hers, with no player here); her own things
## and named gifts go with her.
func _return_gear(record: PlayerRecord, pet: Companion, player: Player) -> void:
	var theirs := "player:" + record.player_id
	var returned: Array[String] = []
	for slot in pet.slots.size():
		var uid := World.slot_uid(pet, slot)
		if uid == 0:
			continue
		var history := World.items.history(uid)
		var carried: bool = (history.get("carriers", []) as Array).any(func(row: Dictionary) -> bool: return str(row["who"]) == theirs)
		var named: bool = (history.get("events", []) as Array).any(func(event: Dictionary) -> bool: return str(event.get("kind", "")) == "named")
		if not carried or named:
			continue
		var what := World.item_title(uid).get_slice(" (", 0)
		if what.is_empty():
			what = "the " + str(Items.def(World.items.id_of(uid)).get("name", World.items.id_of(uid)))
		var taken := World.take_item(pet, pet, slot)
		if taken == 0:
			continue
		World.put_on_ground(taken, player.tile if is_instance_valid(player) and player.zone == pet.zone else pet.tile)
		returned.append(what)
	if not returned.is_empty():
		party_log.add("%s leaves you %s." % [pet.name, Companion._listed(returned)])


## Gone home (decision 581): a resident of her home town (her record's
## "leaving" place), working her trade; her record "left" {day, deed, why,
## place}, and she no longer joins her player.
func _gone_home(record: PlayerRecord, pet: Companion, id: String) -> void:
	var going: Dictionary = record.companion.get("leaving", {})
	var place := str(going.get("place", ""))
	pet.leaving = false
	if not str(record.companion.get("from_worker", "")).is_empty():
		_recruit_home(record, pet, id, str(going.get("deed", "")), str(going.get("why", "")))
		return
	if not _rest_in_town(record, pet, id, place, false):
		_travelling = true
		World.despawn(pet)
		_travelling = false
		_companions.erase(id)
	if str(going.get("deed", "")) == PARTED:
		# Parted as friends (581 amended (3)): no wrong to put right; asked, she comes.
		record.companion["parted"] = {"day": Townsfolk.day_of(World.steps), "place": str(record.companion.get("resident", {}).get("place", place))}
		record.companion.erase("leaving")
		print("[bond] %s's companion %s parted with them and rests in %s" % [record.name, record.companion.get("name", "?"), record.companion["parted"]["place"]])
		return
	record.companion["left"] = {"day": Townsfolk.day_of(World.steps), "deed": str(going.get("deed", "")), "why": str(going.get("why", "")),
		"place": str(record.companion.get("resident", {}).get("place", place)), "repaired": false,
		"area": str(record.companion.get("warned_area", "")), "grave": going.get("grave", [])}
	record.companion.erase("leaving")
	_favour_words(record)
	print("[bond] %s's companion %s left them and lives in %s" % [record.name, record.companion.get("name", "?"), record.companion["left"]["place"]])


## The grave goods [param pet] carries (555 amended), their uids: given back
## to the dead, they repair the deed she left over (581 amended).
func _grave_carried(pet: Companion) -> Array:
	var out := []
	for slot in pet.slots.size():
		var uid := World.slot_uid(pet, slot)
		if uid != 0 and _grave_goods(uid):
			out.append(uid)
	return out


# --- Winning her back (581 amended) -------------------------------------------

## Whether [param record]'s companion left them and lives in a town.
static func has_left(record: PlayerRecord) -> bool:
	return record != null and record.companion.get("left") is Dictionary


## Her worker id in town ("companion:<her name>", as _rest_in_town keys it).
static func _left_worker(record: PlayerRecord) -> String:
	return "companion:%s" % record.companion.get("name", "")


## The deed a parting leaves over (581 amended (3)): no wrong, so no gate.
const PARTED := "parted"


## Whether [param line] asks her to go home for a while (581 amended (3)):
## one of the rules' part_words, as words of the line.
static func asks_to_part(line: String) -> bool:
	var said := " %s " % line.to_lower().replace("'", "").replace(",", " ").replace(".", " ").replace("?", " ").replace("!", " ")
	for words: String in leaving_rules().get("part_words", []):
		if (" %s " % words.to_lower().replace("'", "")) in said:
			return true
	return false


## [param player] asks [param pet], their companion with them, to go home
## for a while (581 amended (3)): at the next calm moment she sets off as
## one who leaves does (_leaving_tick), and rests in her home town marked
## "parted": no bond lost, and asked there, she comes. Whether it was such
## a word (one who is leaving, held or resting already, it is not).
func _part_said(player: Player, pet: Companion, line: String) -> bool:
	var record := _record_of(pet)
	if record == null or not asks_to_part(line) or pet.keeper != player:
		return false
	for state: String in ["leaving", "left", "parted", "taken", "resident"]:
		if record.companion.has(state):
			return false
	record.companion["leaving"] = {"deed": PARTED, "why": "", "day": Townsfolk.day_of(World.steps)}
	print("[bond] %s asked their companion %s to go home for a while" % [record.name, pet.name])
	return true


## Whether [param line] asks one to come along (581 amended (2)): one of
## the rules' recruit_words, as words of the line.
static func asks_to_come(line: String) -> bool:
	var said := " %s " % line.to_lower().replace(",", " ").replace(".", " ").replace("?", " ").replace("!", " ")
	for words: String in leaving_rules().get("recruit_words", []):
		if (" %s " % words.to_lower()) in said:
			return true
	return false


## [param player] asked [param body], their own companion's body in her
## town, who left them, to come with them (581 amended (2)): willing
## (favour_gate ""), she leaves her work and goes with them, her bond
## started again at the rules' rejoin_at; not, her voice answers as ever,
## told why she left and what would bring her back. Whether she came.
func _recruit_said(body: Resident, player: Player, line: String) -> bool:
	var record: PlayerRecord = _records.get(player.player_id)
	if record != null and body.player_id == player.player_id and record.companion.get("parted") is Dictionary and asks_to_come(line):
		# Parted as friends (581 amended (3)): no gate, her bond as it was.
		record.companion.erase("parted")
		party_log.add("%s is glad to travel with %s again." % [body.person, _display_name(player)])
		_join_companion(record, player)
		var friend: Companion = _companions.get(record.player_id)
		if is_instance_valid(friend) and friend.spawned:
			friend._ask_voice("%s came to your town and asked you to travel with them again, and you were glad to." % record.name, "", true)
		return true
	if body.player_id != player.player_id or not has_left(record) or not asks_to_come(line):
		return false
	var gate := favour_gate(record)
	if not gate.is_empty():
		print("[bond] %s asked %s to come again: not yet (%s)" % [record.name, record.companion.get("name", "?"), gate])
		return false
	var left: Dictionary = record.companion["left"]
	record.companion.erase("left")
	record.companion.erase("warned_area")
	var rejoin := int(leaving_rules().get("rejoin_at", -1))
	Standing.bump(record.companion, record.player_id, rejoin - Standing.score(record.companion, record.player_id), "asked you back", World.steps)
	record.companion["bond_best"] = mini(int(record.companion.get("bond_best", 0)), rejoin)
	if World.production != null and World.production.has_method("set_left"):
		World.production.call("set_left", _left_worker(record), "", "")
	_set_mood(record)
	print("[bond] %s's companion %s goes with them again (left over %s on day %s)" % [record.name, record.companion.get("name", "?"),
		left.get("deed", "?"), left.get("day", "?")])
	party_log.add("%s agrees to travel with %s again." % [body.person, _display_name(player)])
	_join_companion(record, player)
	var pet: Companion = _companions.get(record.player_id)
	if is_instance_valid(pet) and pet.spawned:
		pet._ask_voice("%s asked you to travel with them again, and you agreed. You left them once because they %s; you have not forgotten it." % [
			record.name, str(left.get("why", "wronged you")).trim_suffix(".")], "", true)
	return true


# --- Recruiting a resident (686) ----------------------------------------------

## A recruit rule (companion_traits.json "leaving"): trusted_at, the score
## a resident's card must hold toward one who asks; bond_most, the bond one
## comes with at most; former_most, how many former companions a record
## keeps; unforgiven_at, the score one who left over a wrong not put right
## asks; recruit_roles, the trades a town will not let go; recruit_asked,
## the sentence their resident voice is given for each refusal.
static func recruit_rule(key: String, fallback: Variant) -> Variant:
	return leaving_rules().get(key, fallback)


## Why [param worker_id] ([param body]) would not go with [param record]'s
## player now (686): "with" (one is with them already), "elsewhere" (out
## with another player), "away" (sick, away, lost, sought, on another's
## errand), "role" (the town's lawspeaker, priest or medicine man, or one
## the town only tolerates), "needed" (its only one of a trade it needs:
## economy's Towns.sole_needed), "name" (another's companion has the name),
## "trust" (their card under trusted_at, or unforgiven_at for a former one
## who left over a wrong not put right; a former one who parted as a friend
## needs none); "" for willing.
func recruit_refusal(record: PlayerRecord, worker_id: String, body: Resident = null) -> String:
	var production := World.production
	var worker := production.worker(worker_id) if production != null else {}
	if worker.is_empty() or worker_id.begins_with(Townsfolk.COMPANION):
		return "away"
	var c := record.companion
	if c.has("name") and not (c.get("left") is Dictionary or c.get("parted") is Dictionary) or c.has("leaving") or c.has("taken"):
		return "with"
	for other: PlayerRecord in _records.values():
		if other != record and str(other.companion.get("from_worker", "")) == worker_id:
			return "elsewhere"
	if bool(worker.get("away", false)) or bool(worker.get("sick", false)) \
			or body != null and (body.strayed or not body.sought.is_empty() or not body.escort_of.is_empty()):
		return "away"
	var trades: Array = worker.get("trades", [])
	var card := Townsfolk.card_of(production, worker_id)
	for trade: Variant in trades:
		if str(trade) in recruit_rule("recruit_roles", ["lawspeaker", "priest", "medicine_man"]):
			return "role"
	if bool(card.get("outcast", false)):
		return "role"
	if World.towns != null and World.towns.has_method("sole_needed") and not World.towns.sole_needed(str(worker.get("town", "")), worker_id).is_empty():
		return "needed"
	var name := str(card.get("traits", {}).get("name", worker.get("name", "")))
	for other: PlayerRecord in _records.values():
		if other != record and str(other.companion.get("name", "")) == name:
			return "name"
	var hers: Dictionary = _former_of(record, worker_id).get("companion", {})
	if hers.get("parted") is Dictionary:
		return ""
	var needs := int(recruit_rule("trusted_at", Standing.setting("trusted")))
	var left: Variant = hers.get("left")
	if left is Dictionary and not bool(left.get("repaired", false)) \
			and CompanionCard.justice(hers.get("traits", {}), record.player_id) >= int(leaving_rules().get("justice_at", 7)):
		needs = int(recruit_rule("unforgiven_at", 6))
	return "" if Standing.score(card, record.player_id) >= needs else "trust"


## [param record]'s former companion who is the town's [param worker_id]
## now (686), {} for none.
static func _former_of(record: PlayerRecord, worker_id: String) -> Dictionary:
	for each: Dictionary in record.former:
		if str(each.get("worker", "")) == worker_id:
			return each
	return {}


## [param player] asked [param body], a town's own resident, to come with
## them (686): willing (recruit_refusal ""), any companion of theirs away in
## her town is handed to it (_hand_companion_over), and the resident leaves their
## work (Production.set_away) and comes as their companion: a former one
## as she was (one who left starts again at rejoin_at), else a new card
## (CompanionCard.from_resident), the bond their card's score at most
## bond_most. Not willing, their voice is told why (npc's set_asked) and
## answers as ever. Whether they came.
func _resident_recruit_said(body: Resident, player: Player, line: String) -> bool:
	if not body.player_id.is_empty() or body.worker_id.is_empty() or World.production == null or not asks_to_come(line):
		return false
	var record: PlayerRecord = _records.get(player.player_id)
	if record == null:
		return false
	var production := World.production
	var worker_id := body.worker_id
	var why := recruit_refusal(record, worker_id, body)
	if not why.is_empty():
		var asked: Dictionary = recruit_rule("recruit_asked", {})
		var their_trades: Array = production.worker(worker_id).get("trades", [])
		var said := str(asked.get(why, asked.get("trust", "{player} asked you to travel with them, and you would rather not."))) \
				.replace("{player}", record.name).replace("{companion}", str(record.companion.get("name", "another"))) \
				.replace("{trade}", str(their_trades[0]).replace("_", " ") if not their_trades.is_empty() else "worker")
		production.set_asked(worker_id, record.player_id, said)
		print("[bond] %s asked %s along: not now (%s)" % [record.name, body.person, why])
		return false
	var former := _former_of(record, worker_id)
	if record.companion.has("name") and not _hand_companion_over(record):
		print("[bond] %s asked %s along: %s could not be settled in her town" % [record.name, body.person, record.companion.get("name", "?")])
		return false
	var worker := production.worker(worker_id)
	var card := Townsfolk.card_of(production, worker_id)
	var town := str(worker.get("town", ""))
	var trades: Array = worker.get("trades", [])
	var trade := str(trades[0]) if not trades.is_empty() else ""
	var hers: Dictionary
	var bond := mini(Standing.score(card, record.player_id), int(recruit_rule("bond_most", 2)))
	if not former.is_empty():
		hers = (former["companion"] as Dictionary).duplicate(true)
		record.former.erase(former)
		if hers.get("left") is Dictionary:
			bond = int(leaving_rules().get("rejoin_at", -1))
		elif hers.get("parted") is Dictionary:
			bond = Standing.score(hers, record.player_id)
		for key: String in ["left", "parted", "leaving", "resident", "warned_area", "taken"]:
			hers.erase(key)
	else:
		var traits := CompanionCard.from_resident(record.player_id, worker_id, card, worker, _trade_words(trade), _town_words(town))
		hers = {"name": traits["name"], "traits": traits, "card": CompanionCard.plain_card(traits), "card_by": "plain",
			"hp": 0, "stamina": 0, "tile": null, "alive": true}
		var met := CompanionCard.met(traits, record.name)
		hers["how_we_met"] = met.left(1).to_upper() + met.substr(1) + "."
	Standing.set_score(hers, record.player_id, bond, "asked you to travel with them", World.steps)
	hers["bond_best"] = maxi(int(hers.get("bond_best", bond)), bond)
	hers["heard"] = worker.get("heard", []).duplicate(true)
	hers["from_worker"] = worker_id
	hers["tile"] = null
	var zone := str(World.holdings.place(town).get("area", "")) if World.holdings != null and not town.is_empty() else ""
	if not zone.is_empty():
		hers["home"] = {"place": town, "zone": zone, "trade": trade}
	record.companion = hers
	production.set_away(worker_id, true)
	production.set_asked(worker_id, record.player_id, "")
	_travelling = true
	World.despawn(body)
	_travelling = false
	_set_mood(record)
	print("[bond] %s's new companion: %s, the %s of %s (%s)" % [record.name, hers["name"], trade, town, "again" if not former.is_empty() else "first time"])
	party_log.add("%s leaves %s work in the town and goes with %s." % [body.person,
		{"she": "her", "he": "his", "they": "their"}.get(str(hers.get("traits", {}).get("pronoun", "she")), "her"), _display_name(player)])
	_join_companion(record, player)
	var pet: Companion = _companions.get(record.player_id)
	if is_instance_valid(pet) and pet.spawned:
		pet._ask_voice("%s asked you to travel with them, and you agreed: you left your work in the town to go with them." % record.name, "", true)
	return true


## A trade's words for a card ("a smith"): the companions' profession
## table's first for it, else the trade's own word.
static func _trade_words(trade: String) -> String:
	for each: Variant in CompanionCard.tables().get("profession", []):
		if each is Dictionary and str(each.get("trade", "")) == trade:
			return str(each.get("words", ""))
	return "a %s" % trade.replace("_", " ") if not trade.is_empty() else "one of its people"


## [param record]'s companion, away from them (resting, left or parted; or
## a recruited one come home), handed to her town for good (686): one who
## was a town's resident goes back to their own worker (away no longer);
## any other is settled as one of its residents (npc's Townsfolk.settle:
## "settled:<name>"). Their card's standing toward the player is her bond
## (Standing.set_score), what she heard is theirs, her record goes to
## record.former (newest first, former_most kept) and the record has
## nobody ({"solo": true}). She settles in her town unless one of her
## name lives there, else the next town with none (_settle_place), seated
## there first if she has no worker in it (she never rested, or another of
## her name was settled from the one they shared); with one of her name in
## every town she settles as someone else (_fresh_name), no former entry.
## False, and nothing changed, if there is still no worker for her.
func _hand_companion_over(record: PlayerRecord) -> bool:
	var production := World.production
	if production == null or not record.companion.has("name"):
		return false
	var hers := record.companion
	var fresh := ""
	var worker_id := str(hers.get("from_worker", ""))
	if not worker_id.is_empty():
		if production.worker(worker_id).is_empty():
			return false
		production.set_away(worker_id, false)
	else:
		if World.towns == null:
			return false
		# Her town, unless one of her name lives there (the coordinator: no
		# two Wrens side by side): the next town with none, else her town as
		# someone else, a fresh name and a card of her own.
		var who := _left_worker(record)
		var name := str(hers["name"])
		var town := str(production.worker(who).get("town", ""))
		if town.is_empty():
			town = str(hers.get("resident", hers.get("home", {})).get("place", ""))
		if town.is_empty():
			town = _first_town()
		var place := _settle_place(name, town, who)
		if place.is_empty():
			place = town
			fresh = _fresh_name(place)
		var seat := fresh if not fresh.is_empty() else name
		var purse := 0
		var loan := 0.0
		var working_off := false
		if not production.worker(who).is_empty() and (str(production.worker(who).get("town", "")) != place or not fresh.is_empty()):
			loan = float(production.worker(who).get("loan", 0.0))  # A debt is never written off (economy): it follows her.
			working_off = bool(production.worker(who).get("working_off", false))
			purse = World.towns.drop_companion(who)
		var trade := str(hers.get("traits", {}).get("trade", ""))
		if production.worker("companion:%s" % seat).is_empty() and not place.is_empty() and not trade.is_empty():
			World.towns.note_companion_in(place, seat, trade, record.player_id)
		worker_id = Townsfolk.settle(production, World.towns, "companion:%s" % seat)
		if worker_id.is_empty():
			return false
		production.pay(worker_id, purse, "what the town owed: her own purse, carried from where she rested")  # (Not earnings.)
		if loan > 0.0:
			production.set_loan(worker_id, loan, working_off)
	var card := Townsfolk.card_of(production, worker_id)
	Standing.set_score(card, record.player_id, Standing.score(hers, record.player_id), "travelled with you", World.steps)
	production.set_card(worker_id, card)
	if hers.get("heard") is Array:
		production.set_heard(worker_id, hers["heard"])
	# Her resting body, if it stands: the town's body for the worker comes in its place.
	for each: GridEntity in World.townsfolk().duplicate():
		if (each as Resident).player_id == record.player_id:
			_travelling = true
			World.despawn(each)
			_travelling = false
	var kept := hers.duplicate(true)
	kept.erase("resident")
	kept.erase("from_worker")
	if fresh.is_empty():
		record.former.push_front({"companion": kept, "worker": worker_id})
		record.former.resize(mini(record.former.size(), int(recruit_rule("former_most", 3))))
	record.companion = {"solo": true}
	print("[bond] %s's companion %s is the town's %s now%s" % [record.name, hers.get("name", "?"), worker_id,
		" (another of her name lives in every town: someone else now, not to be asked back)" if not fresh.is_empty() else ""])
	return true


## The town (a store place id) [param name] may settle in (686): [param
## first] unless a resident there other than [param besides] bears the
## name, else the first of the towns in order (_first_town's) with none;
## "" when every town has one.
func _settle_place(name: String, first: String, besides: String) -> String:
	var towns: Array[String] = []
	if not first.is_empty():
		towns.append(first)
	if World.holdings != null:
		var places := World.holdings.places_of(Stockpile.TOWN)
		places.sort()
		for each in places:
			if each != first and World.holdings.place(each).get("kind") == Stockpile.KIND:
				towns.append(each)
	for town in towns:
		var named := World.towns.residents(town).any(func(id: String) -> bool:
			return id != besides and str(World.production.worker(id).get("name", "")) == name)
		if not named:
			return town
	return ""


## A name no resident of [param place] and no player's companion has, from
## the companions' name table (686: one settled as someone else).
func _fresh_name(place: String) -> String:
	var used := {}
	for id: String in World.towns.residents(place):
		used[str(World.production.worker(id).get("name", ""))] = true
	for other: PlayerRecord in _records.values():
		used[str(other.companion.get("name", ""))] = true
	for name: Variant in CompanionCard.tables().get("name", []):
		if not used.has(str(name)) and World.production.worker("companion:%s" % name).is_empty():
			return str(name)
	return "Newcomer"


## A recruited resident (686) home from [param record]'s player, parted as
## a friend or having left over [param deed] ([param why]): out of the
## world ([param pet], [param id]), back to their own worker (_hand_companion_over),
## her leaving kept on her former entry for asking her back.
func _recruit_home(record: PlayerRecord, pet: Companion, id: String, deed: String, why: String) -> void:
	_travelling = true
	World.despawn(pet)
	_travelling = false
	_companions.erase(id)
	record.companion.erase("leaving")
	var day := Townsfolk.day_of(World.steps)
	var place := str(record.companion.get("home", {}).get("place", ""))
	if deed == PARTED:
		record.companion["parted"] = {"day": day, "place": place}
	else:
		record.companion["left"] = {"day": day, "deed": deed, "why": why, "place": place, "repaired": false}
	var name := str(record.companion.get("name", "?"))
	if not _hand_companion_over(record):
		print("[bond] %s's companion %s went home, but has no worker there" % [record.name, name])


## Her town (a store place id) since she left [param record]'s player: her
## worker's, else her record's "left" place.
func _left_town(record: PlayerRecord) -> String:
	var worker := World.production.worker(_left_worker(record)) if World.production != null else {}
	var town := str(worker.get("town", ""))
	return town if not town.is_empty() else str(record.companion.get("left", {}).get("place", ""))


## Whether she wants the wrong put right, not just time (581 amended):
## her card's justice (CompanionCard.justice) at the rules' justice_at.
func _justice_driven(record: PlayerRecord) -> bool:
	return CompanionCard.justice(record.companion.get("traits", {}), record.player_id) >= int(leaving_rules().get("justice_at", 7))


## How [param deed] (the one she left over) is put right: the rules'
## repairs, else the town's word of them ("reputation").
static func repair_of(deed: String) -> String:
	return str((leaving_rules().get("repairs", {}) as Dictionary).get(deed, "reputation"))


## What still keeps her from going with [param record]'s player again
## (581 amended): "time" (her bond under the rules' return_at), "repair"
## (justice-driven, the wrong not put right), "" for nothing: asked, she
## comes (581 amended (2)).
func favour_gate(record: PlayerRecord) -> String:
	if not has_left(record):
		return ""
	if _justice_driven(record) and not bool(record.companion["left"].get("repaired", false)):
		return "repair"
	if Standing.score(record.companion, record.player_id) < int(leaving_rules().get("return_at", -3)):
		return "time"
	return ""


## Her favour moved by [param kind] (the rules' "favour": gift, errand,
## reputation) for [param why] (a clause, "they"), once a game day each.
## Whether it moved.
func _favour(record: PlayerRecord, kind: String, why: String) -> bool:
	if not has_left(record):
		return false
	var left: Dictionary = record.companion["left"]
	var day := Townsfolk.day_of(World.steps)
	var today: Dictionary = left.get("favour_today", {})
	if int(today.get("day", -1)) != day:
		today = {"day": day, "kinds": []}
	if kind in today["kinds"]:
		return false
	var delta := int((leaving_rules().get("favour", {}) as Dictionary).get(kind, 0))
	if kind == "reputation" and _justice_driven(record):
		delta *= int(leaving_rules().get("justice_reputation", 2))
	if delta == 0:
		return false
	today["kinds"].append(kind)
	left["favour_today"] = today
	Standing.bump(record.companion, record.player_id, delta, why, World.steps)
	print("[bond] %s's companion %s, away: %s (%+d, %d)" % [record.name, record.companion.get("name", "?"), why, delta,
		Standing.score(record.companion, record.player_id)])
	_favour_words(record)
	return true


## The wrong she left over put right (581 amended): [param how] the
## deed's repair kind; nothing for another kind, or put right already.
func _favour_repaired(record: PlayerRecord, how: String) -> void:
	if not has_left(record):
		return
	var left: Dictionary = record.companion["left"]
	if bool(left.get("repaired", false)) or repair_of(str(left.get("deed", ""))) != how:
		return
	left["repaired"] = true
	print("[bond] %s's companion %s, away: the wrong put right (%s)" % [record.name, record.companion.get("name", "?"), how])
	_favour_words(record)


## Her two sentences for her resident voice while she is away (581
## amended, npc's Production.set_left): why she left, and what would bring
## her back, in her terms; facts, never lines, told only to her player.
func _favour_words(record: PlayerRecord) -> void:
	if World.production == null or not has_left(record):
		return
	var left: Dictionary = record.companion["left"]
	var words: Dictionary = leaving_rules().get("words", {})
	var why := str(words.get("why", "You left %s because they %s.")) % [record.name, str(left.get("why", "wronged you")).trim_suffix(".")]
	var back := ""
	match favour_gate(record):
		"repair":
			var kind := repair_of(str(left.get("deed", "")))
			back = str((words.get("repair", {}) as Dictionary).get(kind, words.get("time", ""))) % record.name
		"time":
			back = str(words.get("time", "")) % record.name
		_:
			back = str(words.get("ready", "")) % record.name
	left["words"] = [why, back]
	var who := _left_worker(record)
	if World.production.has_method("set_left"):
		World.production.call("set_left", who, why, back)


## On the world tick (581 amended): each companion away from her player
## once a game day: her bond fades toward nothing (Standing.decay, owner
## only), her town's word of them moves her, and puts right a wrong the
## town can vouch for; a visit with food that lasted the rules' hour; her
## grave goods given back to the dead.
func _favour_tick() -> void:
	var day := Townsfolk.day_of(World.steps)
	for id: String in _records:
		var record: PlayerRecord = _records[id]
		if not has_left(record):
			continue
		var left: Dictionary = record.companion["left"]
		_favour_visit(record, left)
		if not (left.get("grave", []) as Array).is_empty() and _grave_given_back(left["grave"]):
			_favour_repaired(record, "grave")
		if int(left.get("checked", -1)) == day:
			continue
		left["checked"] = day
		if not Standing.decay(record.companion, World.steps).is_empty():
			_favour_words(record)
		var town := _left_town(record)
		if World.production != null and not town.is_empty() \
				and Townsfolk.reputation(World.production, town, id) >= float(leaving_rules().get("reputation_at", 3)):
			_favour(record, "reputation", "are spoken well of in your town")
			_favour_repaired(record, "reputation")


## A visit (581 amended): her player brought her food (_on_handed) and
## stays near her body, in her zone, the rules' visit_hours: the
## "visit" repair. Gone from beside her, the visit ends.
func _favour_visit(record: PlayerRecord, left: Dictionary) -> void:
	var visit: Variant = left.get("visit")
	if not visit is Dictionary:
		return
	var player: Player = _players.get(_peer_of(record.player_id))
	var body: Resident = null
	for each: GridEntity in World.entities():
		if each is Resident and (each as Resident).player_id == record.player_id:
			body = each
	if body == null or not is_instance_valid(player) or not player.spawned or player.zone != body.zone \
			or World.distance(player.tile, body.tile) > int(leaving_rules().get("visit_cells", 6)):
		left.erase("visit")
		return
	var hour := maxi(DayNight.day_steps, 1) / 24.0
	if World.steps - int(visit.get("from", World.steps)) >= roundi(hour * float(leaving_rules().get("visit_hours", 1))):
		left.erase("visit")
		_favour_repaired(record, "visit")


## Whether every one of [param uids] (grave goods) is back with the dead
## (581 amended): carried by nobody, on the ground where it was taken, or
## laid in a temple's store.
func _grave_given_back(uids: Array) -> bool:
	for uid: int in uids:
		var history := World.items.history(uid)
		if history.is_empty():
			continue  # Gone from the book: nothing to give back.
		if not str(history.get("holder", "")).is_empty():
			return false
		var at := World.items.at_of(uid)
		var taken := ""
		for event: Dictionary in history.get("events", []):
			if str(event.get("kind", "")) == "grave goods":
				taken = str(event.get("zone", ""))
		var temple: bool = at.begins_with("stockpile:") and World.holdings != null \
				and World.holdings.place(at.trim_prefix("stockpile:")).get("kind") == "temple"
		if not temple and (taken.is_empty() or not at.begins_with(taken + "@")):
			return false
	return true


## Her home town's store place: her record's "home" if it is still a town's
## store, else the first town with one.
func _home_place(record: PlayerRecord) -> String:
	var home := str(record.companion.get("home", {}).get("place", ""))
	if not home.is_empty() and World.holdings != null and World.holdings.place(home).get("kind") == Stockpile.KIND:
		return home
	return _first_town()


## The first town's store place, "" for none.
func _first_town() -> String:
	if World.holdings == null:
		return ""
	var places := World.holdings.places_of(Stockpile.TOWN)
	places.sort()
	for each in places:
		if World.holdings.place(each).get("kind") == Stockpile.KIND:
			return each
	return ""


## A town's store place [param place] in words: its area's shown name.
func _town_words(place: String) -> String:
	var area := str(World.holdings.place(place).get("area", "")) if World.holdings != null and not place.is_empty() else ""
	return Companion.place_name(area) if not area.is_empty() else "her town"


## The nearest level link's cell to [param from] in this zone; NONE for none.
func _nearest_way_out(from: Vector2i) -> Vector2i:
	var best := Companion.NONE
	var links: Array = Level.load_level(World.zone.name).get("links", []) if Level.exists(World.zone.name) else []
	for link: Dictionary in links:
		var at: Vector2i = link["tile"]
		if best == Companion.NONE or World.distance(from, at) < World.distance(from, best):
			best = at
	return best


## The rules of the field return: economy.json "return" "field".
func _field_rules() -> Dictionary:
	var rules: Variant = Production.read_rules().get("return", {}).get("field", {})
	return rules if rules is Dictionary else {}


## Server: the draugr laid to rest (enemy-ai's call through World.bless,
## decisions 544 and 573): each player of [param player_ids] standing alive
## is blessed if not yet (marked BLESSED, for good) and takes the charges of
## [param deal] (easy, normal or hard: economy's return.field deals) up to
## their capacity onto their Draugr's Totem (573 amended: World.mint_totem
## at the first win, World.totem_add; over it, lost and said; the record
## keeps best and containers, Economy.barrow_won raising best); their
## companion, standing alive in the same zone and not downed, is blessed
## too, with the fact and the bond. Nothing is minted (573: the charges are
## a count on the record, no item). How many players were blessed.
func barrow_won(player_ids: Array, deal: String) -> int:
	var field := _field_rules()
	var blessed := 0
	for each: Variant in player_ids:
		var id := str(each)
		var record: PlayerRecord = _records.get(id)
		var player: Player = _players.get(_peer_of(id))
		if record == null or not is_instance_valid(player) or not player.spawned:
			continue
		var first := not BLESSED in record.marks
		var won: Dictionary = Economy.barrow_won(record.barrow, deal, field)
		record.barrow = won["barrow"]
		# The Draugr's Totem holds the charges (573 amended, items' side): the
		# record keeps best and containers alone.
		record.barrow.erase("tokens")
		var uid := World.mint_totem(player)
		var given := Economy.field_tokens(deal, field)
		var took := World.totem_add(uid, given, Economy.barrow_capacity(record.barrow, field))
		_sync_charges(record)
		blessed += 1
		var line := "The draugr yields. %s %stakes %d charges (%d of %d)." % [record.name, "is blessed and " if first else "",
			took, World.totem_charges(uid), Economy.barrow_capacity(record.barrow, field)]
		if given - took > 0:
			line += " The dead's gift spills: %d more than they can hold." % (given - took)
		party_log.add(line)
		grant_capability(BLESSED, [id])  # The mark, hers too (decision 576's catalog).
	return blessed


## The level the holy knights lie in (714): its generation names the one.
const KNIGHTS_LEVEL := "barrow_deep"


## The holy knight of barrow_deep's generation now (714, dungeon's side
## (1); Jeff: "the knights name could be different each time you go"): one
## of its regenerate block's "knights" (lore's fourteen), drawn by
## Regen.seed_for from the level and its generation, the same on every
## machine; "" before its first generation or with no list.
func barrow_knight() -> String:
	var knights: Array = Regen.config_of(KNIGHTS_LEVEL).get("knights", [])
	var generation := generation_of(KNIGHTS_LEVEL)
	if knights.is_empty() or generation <= 0:
		return ""
	return str(knights[posmod(Regen.seed_for(KNIGHTS_LEVEL + "#knight", generation), knights.size())])


## Server: a relic of tier [param tier] (the deal it was won at, its place
## among the deals: 0 the least) laid on the altar for [param player] (714,
## dungeon's side (1); npc's Aldous calls it): their amulet charged with
## that deal's charges (573's field_tokens), up to its capacity
## (barrow_capacity), the spill lost and said; an amulet minted, uncharged,
## if they have none (reset, or lost). The charges taken, 0 for none (no
## room left, no such tier, no record or not in the game); the player told
## (_sync_charges). The line is the caller's.
func charge_from_relic(player: Player, tier: int) -> int:
	if not Net.is_authority() or not is_instance_valid(player):
		return 0
	var id := player.player_id
	var record: PlayerRecord = _records.get(id)
	if record == null:
		return 0
	var field := _field_rules()
	var deals := Economy.deals(field)
	if tier < 0 or tier >= deals.size():
		return 0
	var uid := World.totem_of(id)
	if uid == 0:
		uid = World.mint_totem(player)
	var given := Economy.field_tokens(str(deals[tier].get("name", "")), field)
	var took := World.totem_add(uid, given, Economy.barrow_capacity(record.barrow, field))
	_sync_charges(record)
	if given - took > 0:
		party_log.add("The relic's gift spills: %d more than %s can hold." % [given - took, record.name])
	return took


## Server: capability [param id] (levels/capabilities.json, decision 576)
## given to each player of [param player_ids] in the game, and to the
## companion with them, alive and up, in their zone: her mark, the
## catalog's party line, fact on her card and bond event, and her player's
## map told what she now holds. The players' own lines are the caller's
## (barrow_won's charges). How many players it reached.
func grant_capability(id: String, player_ids: Array) -> int:
	if not Capabilities.live(id):
		return 0  # Unknown, or a draft with no area yet.
	var holders := str(Capabilities.entry(id).get("holders", "both"))
	var reached := 0
	for each: Variant in player_ids:
		var player_id := str(each)
		var record: PlayerRecord = _records.get(player_id)
		var player: Player = _players.get(_peer_of(player_id))
		if record == null or not is_instance_valid(player) or not player.spawned:
			continue
		reached += 1
		if holders != "companion":
			mark_player(player_id, id)
		var pet: Companion = _companions.get(player_id)
		if holders == "player" or not is_instance_valid(pet) or not pet.spawned or pet.zone != player.zone or World.is_downed(pet):
			continue
		var marks: Array = record.companion.get("marks", [])
		if not id in marks:
			marks.append(id)
			marks.sort()
			record.companion["marks"] = marks
			party_log.add(Capabilities.said(id, "companion_line", String(pet.name), record.name))
			_tell_capabilities(record, pet)
		pet.note_fact(Capabilities.said(id, "fact", String(pet.name), record.name))
		_bond(record, str(Capabilities.entry(id).get("bond", "earned")), str(Capabilities.entry(id).get("bond_why", "")))
	return reached


# --- Her focus (decision 577) ---------------------------------------------------

## Her blows that land, and a kill: fighting.
func _focus_struck(entity: GridEntity, amount: int, source: GridEntity, cause: StringName) -> void:
	if amount <= 0 or not source is Companion or cause not in [&"attack", &"shot"] or not entity.is_creature():
		return
	if cause == &"attack":
		_grow_focus(source as Companion, "struck")
	if entity.hp <= 0:
		_grow_focus(source as Companion, "killed")


## Her bow loosed: stealth.
func _focus_shot(by: GridEntity, _angle: float, _step: int) -> void:  # World.loosed (583: the angle and the draw's step).
	if by is Companion:
		_grow_focus(by as Companion, "shot")


## Food she ate (a meal's "mass" buff on her): fighting.
func _focus_ate(entity: GridEntity, kind: String, state: StringName) -> void:
	if entity is Companion and kind == "mass" and state != &"faded":
		_grow_focus(entity as Companion, "ate")


## [param pet]'s focus grown by [param event] (the rules' "grow"), within the
## day's cap: her record's and her body's; a new lean is a fact on her card,
## and her player's map told when a whole number moves.
func _grow_focus(pet: Companion, event: String) -> void:
	var record := _record_of(pet)
	var rules := CompanionCard.focus_rules()
	var grow: Variant = rules.get("grow", {}).get(event)
	if record == null or pet.focus.is_empty() or not grow is Array or (grow as Array).size() < 2:
		return
	var day := Townsfolk.day_of(World.steps)
	var today: Dictionary = record.companion.get("focus_day", {})
	var grown := float(today.get("grown", 0.0)) if int(today.get("day", -1)) == day else 0.0
	var points := minf(float(grow[1]), float(rules.get("daily_cap", 3)) - grown)
	if points <= 0.0:
		return
	var was := pet.focus
	var now := CompanionCard.grow_focus(was, str(grow[0]), points)
	record.companion["focus_day"] = {"day": day, "grown": snappedf(grown + points, 0.01)}
	record.companion["focus"] = now
	pet.focus = now
	var lean := CompanionCard.lean_of(now)
	if not lean.is_empty() and lean != CompanionCard.lean_of(was):
		pet.note_fact(str(rules.get("taken_to", {}).get(lean, "")).replace("{her}", String(pet.name)))
	for kind in CompanionCard.FOCUS:
		if roundi(float(now[kind])) != roundi(float(was.get(kind, 0))):
			_tell_focus(record, pet)
			break


## Her player's map told her focus (decision 577): the "world" message's
## "focus" {companion, fight, magic, stealth}, whole numbers, for ui's chart.
func _tell_focus(record: PlayerRecord, pet: Companion) -> void:
	var peer := _peer_of(record.player_id)
	if peer == 0 or _world_news == null or not _world_news.send.is_valid() or pet.focus.is_empty():
		return
	var told := {"companion": String(pet.name)}
	for kind in CompanionCard.FOCUS:
		told[kind] = roundi(float(pet.focus.get(kind, 0)))
	_world_news.send.call(peer, {"full": false, "focus": told})


## Her keeper's client told her gold (decision 614, the card's side): the
## "world" message's "companion_gold" {companion, gold}, from her purse
## (Economy.companion_purse), on join and whenever it changes.
func tell_companion_gold(keeper_id: String) -> void:
	var peer := _peer_of(keeper_id)
	var pet: Variant = _companions.get(keeper_id)  # Untyped: a freed one is never read typed (572).
	if peer == 0 or not is_instance_valid(pet) or _world_news == null or not _world_news.send.is_valid():
		return
	_world_news.send.call(peer, {"full": false, "companion_gold": {"companion": String((pet as Companion).name),
		"gold": World.gold_of(Economy.companion_purse(keeper_id))}})


## Whether the player on [param peer], or the companion with them (out with
## them, alive, in their zone), holds capability or mark [param id]
## (decision 576: bringing her opens the way).
func party_has(peer: int, id: String) -> bool:
	var player_id: String = _peer_ids.get(peer, "")
	var record: PlayerRecord = _records.get(player_id)
	if record == null or id.is_empty():
		return false
	if id in record.marks:
		return true
	var pet: Companion = _companions.get(player_id)
	var player: Player = _players.get(peer)
	return is_instance_valid(pet) and pet.spawned and not record.companion.has("resident") and is_instance_valid(player) \
		and pet.zone == player.zone and id in (record.companion.get("marks", []) as Array)


## Her player's map told what she has learned (decision 576): the "world"
## message's "capabilities" {companion, held: [{id, words, teacher}]}, the
## live ones of her marks.
func _tell_capabilities(record: PlayerRecord, pet: Companion) -> void:
	var peer := _peer_of(record.player_id)
	if peer == 0 or _world_news == null or not _world_news.send.is_valid():
		return
	_world_news.send.call(peer, {"full": false, "capabilities": {"companion": String(pet.name),
		"held": Capabilities.held(record.companion.get("marks", []))}})


## The charges held by the players in zone [param zone_name], summed: what
## the draugr's level rises by at the start of a pact (573, enemy-ai's side).
func charges_in_zone(zone_name: String) -> int:
	var total := 0
	for peer: int in _peer_ids:
		if World.peer_zone.get(peer, "") == zone_name:
			total += World.totem_charges(World.totem_of(_peer_ids[peer]))
	return total


## The draugr's deal [param player_id] paid for in [param zone_name] and has
## not won (548 amended; Jeff: "as long as you paid once you get unlimited
## attempts"): their record's paid_deals entry, {} for none or no record.
## The zone through PAID_ZONE_MOVED, so a deal bought before the barrow's
## redesign is the same deal after it.
func paid_deal_of(player_id: String, zone_name: String) -> Dictionary:
	var record: PlayerRecord = _records.get(player_id)
	if record == null:
		return {}
	return (record.paid_deals.get(str(PAID_ZONE_MOVED.get(zone_name, zone_name)), {}) as Dictionary).duplicate()


## [param player_id]'s deal with the draugr in [param zone_name] paid for at
## [param level] (kept on their record, so it outlives a death, a restart
## and a rejoin), or won ([param level] "": erased). Nothing for a player
## with no record or a level that is not a deal's.
func set_deal_paid(player_id: String, zone_name: String, level: String) -> void:
	var record: PlayerRecord = _records.get(player_id)
	if record == null:
		return
	var key := str(PAID_ZONE_MOVED.get(zone_name, zone_name))
	if level.is_empty():
		record.paid_deals.erase(key)
	elif level in PlayerRecord.PAID_LEVELS:
		record.paid_deals[key] = {"level": level, "paid_step": World.steps}


## [param record]'s charges moved off the record onto a Draugr's Totem
## (decision 573 amended): a record with barrow "tokens" left, its player
## in the game, gets its totem (World.mint_totem) holding them, and the
## record's tokens go. For the switch-over's join (dungeon's and
## companions' sides, which read the totem); nothing calls it before they
## land. The totem's uid, 0 if nothing moved.
func migrate_totem(record: PlayerRecord) -> int:
	var player: Player = _players.get(_peer_of(record.player_id)) if record != null else null
	var tokens := int(record.barrow.get("tokens", 0)) if record != null else 0
	if tokens <= 0 or not is_instance_valid(player) or not player.spawned:
		return 0
	var uid := World.mint_totem(player)
	if uid == 0:
		return 0
	World.items.set_charges(uid, World.items.charges_of(uid) + tokens)
	record.barrow.erase("tokens")
	print("[state] %s's %d charges moved onto their Draugr's Totem" % [record.name, tokens])
	return uid


## The barrow as player [param id] had never been there (672 amended,
## dungeon's side: the admin's "quests reset all", ui's _quests_reset_all;
## Jeff: reset everything quest-shaped, so things can be tested): the
## draugr's blessing off (BLESSED, the sealed temple way), the deal won and
## its room (record.barrow), the Draugr's Totem's charges emptied (the totem
## itself is items'), and the draft line said again. What it cleared, in
## words; [] for no record. The world's barrow (the hidden niche found) is
## every player's: "zone reset <name>" lays that again.
func reset_barrow(id: String) -> Array[String]:
	var cleared: Array[String] = []
	var record: PlayerRecord = _records.get(id)
	if record == null:
		return cleared
	if BLESSED in record.marks:
		mark_player(id, BLESSED, false)
		cleared.append("the draugr's blessing")
	if not record.barrow.is_empty():
		record.barrow = {}
		cleared.append("the deal won")
	var totem := World.totem_of(id)
	if totem != 0 and World.totem_charges(totem) > 0:
		World.items.set_charges(totem, 0)
		cleared.append("the totem's charges")
	var told := _draft_told.keys().filter(func(key: String) -> bool: return key.begins_with(id + "@"))
	for key: String in told:
		_draft_told.erase(key)
	if not told.is_empty():
		cleared.append("the draft felt")
	_sync_charges(record)
	return cleared


## [param record]'s player, if in the game, told its charges and the most it
## may hold (Player.charges and charge_room, replicated; decision 573).
func _sync_charges(record: PlayerRecord) -> void:
	var player: Player = _players.get(_peer_of(record.player_id))
	if is_instance_valid(player):
		player.charges = World.totem_charges(World.totem_of(record.player_id))
		player.charge_room = Economy.barrow_capacity(record.barrow, _field_rules())


## The doors of the draugr's hall in zone [param zone_name] (573 amended):
## the door edges on the rim of its "lair" anchor (580's Hall of Fallen
## Souls, one in its north wall).
func _hall_doors(zone_name: String) -> Array[Door]:
	var out: Array[Door] = []
	var rect := hall_lair_rect(zone_name)
	if not rect.has_area():
		return out
	for door: Door in World.get_doors():
		if door.zone != zone_name:
			continue
		var cells := Terrain.edge_cells(door.key)
		if rect.has_point(cells[0]) != rect.has_point(cells[1]):
			out.append(door)
	return out


## The draugr's hall_door (573 amended, Jeff: "the door closes when you
## enter"): [param held], his hall's doors shut and locked behind the first
## player in (HALL_LOCK, a key nobody holds; stone, no blow breaks them), so
## the ways out are his gold, his death or one's own; let go (a pact won,
## an unpaid fall, a fight lost), the lock lifted. Said to the party.
func _hold_hall_door(zone_name: String, held: bool) -> void:
	var zone: Zone = World.zones.get(zone_name)
	if zone == null:
		return
	var was := World.enter(zone)
	var doors := _hall_doors(zone_name)
	for door in doors:
		World.hold_door(door, held, HALL_LOCK)
	World.enter(was)
	if not doors.is_empty():
		party_log.add("The hall's door shuts behind you." if held else "The hall's door opens.")
	if not held:
		_apply_hall_seal(zone_name)  # The challenge over, the dead's seal holds again by its own rule (666).


## The zones whose hall the standing dead seal (666, dungeon's side; Jeff:
## "they must be cleared to enter the hall"): zone name -> whether the
## draugr's ossuary_sealed last said any of its dead stands.
var _hall_seals: Dictionary[String, bool] = {}


## The draugr's ossuary_sealed (666, enemy-ai's side: true while any
## skeleton or grave guard spawned in his zone stands, false when every one
## is dead or laid at rest): [param sealed] kept for [param zone_name] and
## the hall's door held or let go by it (_apply_hall_seal).
func _seal_hall(zone_name: String, sealed: bool) -> void:
	_hall_seals[zone_name] = sealed
	_apply_hall_seal(zone_name)


## The dead's seal on zone [param zone_name]'s hall door (666): held shut
## with DEAD_LOCK, a key nobody holds, while its dead stand, but entry only:
## never while a living player stands inside the hall (nobody is shut in by
## the dead rising behind them; the challenge's HALL_LOCK alone keeps anyone
## in), and never over a challenge's lock. Let go when every one is down.
## Asked again every few steps (_on_world_stepped) so a seal that waited
## for the hall to empty takes hold once it has.
func _apply_hall_seal(zone_name: String) -> void:
	var zone: Zone = World.zones.get(zone_name)
	if zone == null or not _hall_seals.has(zone_name):
		return
	var was := World.enter(zone)
	var doors := _hall_doors(zone_name)
	var rect := hall_lair_rect(zone_name)
	var inside := false
	for entity in World.entities():
		if entity is Player and entity.spawned and entity.hp > 0 and rect.has_point(entity.tile):
			inside = true
	for door in doors:
		if door.lock == HALL_LOCK:
			continue
		if _hall_seals[zone_name] and not inside:
			if door.lock != DEAD_LOCK:
				World.hold_door(door, true, DEAD_LOCK)
		else:
			World.hold_door(door, false, DEAD_LOCK)
	World.enter(was)


## The rect of zone [param zone_name]'s "lair" anchor (580's Hall of Fallen
## Souls, an anchor of the Ossuary since 666); an empty rect for none.
func hall_lair_rect(zone_name: String) -> Rect2i:
	for anchor: Dictionary in Regen.config_of(zone_name).get("anchors", []):
		if str(anchor.get("name", "")) == "lair":
			return anchor["rect"]
	return Rect2i()


## Server: [param entity] pressed on a burial niche's edge (World.niche_pressed,
## 608: a step into it that the wall or the shut door refused). A player
## on the hidden niche with its door still locked finds it: the lock
## lifted, the door opened and said; any other niche, or the found door
## shut again, "Only the dead lie here." once a stand (_told_niche).
func _on_niche_pressed(entity: GridEntity, key: Vector3i) -> void:
	if not entity is Player:
		return
	var peer: int = entity.owner_peer
	var door := World.door_on(key)
	if World.niche_edges.get(key, "") == "hidden" and door != null and door.lock == HIDDEN_LOCK:
		_told_niche.erase(peer)
		World.hold_door(door, false, HIDDEN_LOCK)
		door.open = true
		World.halt(entity, World.tick + NICHE_FOUND_HOLD)
		party_log.add("The slab swings aside: a stair goes down into the dark.")
		print("[level] %s found the hidden door at %s in %s" % [_display_name(entity), Terrain.edge_cells(key)[0], World.zone.name])
		return
	if _told_niche.get(peer) != key:
		_told_niche[peer] = key
		party_log.add("Only the dead lie here.")


## The first hall of regenerating level [param zone_name] (608 amended: where
## the draft is felt, where she searches): the "entrance" anchor's rect from
## its template (the first anchor unless one is named); Rect2i() for a level
## that does not regenerate.
func hall_rect(zone_name: String) -> Rect2i:
	var config := Regen.config_of(zone_name)
	var anchors: Array = config.get("anchors", [])
	if anchors.is_empty():
		return Rect2i()
	var entrance: Dictionary = anchors[0]
	for anchor: Dictionary in anchors:
		if str(anchor.get("name", "")) == str(config.get("entrance", "")):
			entrance = anchor
	return entrance["rect"]


## Server: [param player] stepped to [param to]. In the first hall with the
## hidden door still shut (608 amended; Jeff: "a text saying 'you feel a cool
## draft coming from one of the niches'"), the line to them alone, once a
## generation (_draft_told); found, or a generation later, nothing or again.
func _tell_draft(player: Player, to: Vector2i) -> void:
	var id: String = _peer_ids.get(player.owner_peer, "")
	if id.is_empty():
		return
	var rect := hall_rect(World.zone.name)
	if rect == Rect2i() or not rect.has_point(to):
		return
	var niche := World.hidden_niche()
	if niche.is_empty() or niche["open"]:
		return
	var key := "%s@%s" % [id, World.zone.name]
	var generation := generation_of(World.zone.name)
	if _draft_told.get(key, -1) == generation:
		return
	_draft_told[key] = generation
	Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": "You feel a cool draft coming from one of the niches."})


## A player come up into [param zone_name] by its "from_below" spawn point
## (608): the hidden door there, if still locked, is pushed open from
## behind, and said.
func _reveal_from_below(zone_name: String) -> void:
	for door: Door in World.get_doors():
		if door.zone == zone_name and door.lock == HIDDEN_LOCK and not door.open:
			World.hold_door(door, false, HIDDEN_LOCK)
			door.open = true
			party_log.add("The slab swings aside from behind.")


## [param player] come into the zone (joined, or travelled in): a draugr
## fighting a pact there draws breath from it, half his most at once (573;
## Draugr.living_came, enemy-ai's side, called when he has it).
func _living_came(player: Player) -> void:
	for monster in World.monsters():
		if is_instance_valid(monster) and monster.has_method("living_came"):
			monster.call("living_came", player)


## The record whose count [param entity]'s return spends: a player's own, a
## companion's her player's; null for others.
func _blessing_record(entity: GridEntity) -> PlayerRecord:
	if entity is Player:
		return _records.get(_peer_ids.get(entity.owner_peer, ""))
	if entity is Companion:
		return _records.get((entity as Companion).keeper_id)
	return null


## Whether [param entity] carries the draugr's blessing (decision 544): a
## player marked BLESSED, a companion with BLESSED in her marks.
func _blessed(entity: GridEntity) -> bool:
	var record := _blessing_record(entity)
	if record == null:
		return false
	if entity is Player:
		return BLESSED in record.marks
	return BLESSED in record.companion.get("marks", [])


## Her can_revive: blessed, a charge left on her player's count (573: no
## token to carry).
func _can_revive(pet: Companion, record: PlayerRecord) -> bool:
	return _blessed(pet) and _uses_left(record) > 0 and (not is_instance_valid(pet.keeper) or _blessed(pet.keeper))


## Charges left on [param record]'s Draugr's Totem (573 amended; the
## record's count before, "uses" before that).
static func _uses_left(record: PlayerRecord) -> int:
	return World.totem_charges(World.totem_of(record.player_id)) if record != null else 0


## World.downed (decision 544; Mortally Wounded): a blessed body lies downed
## for the field rules' window_s, whatever its own player's charges (573:
## anyone blessed with a charge may bring it back); an unblessed player lies
## unblessed_s, their last moments, for Bleed Out (nobody brings them back);
## an unblessed companion dies as ever.
func _downed(target: GridEntity, _source: GridEntity, _cause: StringName) -> int:
	if target is Resident and not (target as Resident).sought.is_empty() and not (target as Resident).escort_of.is_empty():
		# A sought one led home (613, enemy-ai's side): beaten down, not killed; a word gets them up (_sought_spoken).
		return roundi(float(_field_rules().get("window_s", 30)) * World.TICK_RATE)
	if not (target is Player or target is Companion):
		return 0
	if target is Player and not _players.has(target.owner_peer):
		return 0
	var blessed := _blessed(target)
	if not blessed and target is Companion:
		return 0
	return roundi(float(_field_rules().get("window_s" if blessed else "unblessed_s", 30 if blessed else 10)) * World.TICK_RATE)


## World.entity_downed: said to the party, and to the fallen.
func _on_downed(entity: GridEntity, _source: GridEntity, ticks: int) -> void:
	var seconds := ceili(float(ticks) / World.TICK_RATE)
	if not _blessed(entity):
		party_log.add("%s is mortally wounded." % _display_name(entity))
	else:
		party_log.add("%s is down. A blessed hand beside them can bring them back within %d seconds." % [_display_name(entity), seconds])
	if entity is Player:
		var player := entity as Player
		# Mortally Wounded: the heart beats at the first of the field rules' beats.
		player.heart = int((_field_rules().get("heart", {}).get("beats", [120]) as Array)[0])
		player.heart_held = false
		player.heart_at = World.tick
		player.heart_debt = 0.0
		Net.broadcast_to([entity.owner_peer], "party", {"from": "Server", "text": ("You are mortally wounded. Hold Slow Heart to wait for a blessed hand, or bleed out to be brought back." if _blessed(entity)
			else "You are mortally wounded, and nobody can bring you back here. Bleed out to be brought back.")})
	for pet: Companion in _companions.values():
		if is_instance_valid(pet) and pet.spawned and (pet.keeper == entity or pet == entity):
			pet.note_downed(entity == pet.keeper)


# --- Mortally Wounded (Jeff's down screen) ---------------------------------------

## Zone -> the tick its everyone-down wait ends (_all_fallen_tick).
var _all_fallen_at: Dictionary[String, int] = {}


## The "slow_heart" command: Slow Heart held or let go by the downed
## [param player]; only the blessed may (the unblessed's button is greyed).
## Pressed, the heart steps down on the next tick; let go, it climbs back a
## beat each step_s from then.
func _slow_heart(player: Player, held: bool) -> void:
	if not World.is_downed(player) or player.heart <= 0 or not _blessed(player):
		return
	if held and not player.heart_held:
		player.heart_at = World.tick - _heart_step_ticks()
	elif not held and player.heart_held:
		player.heart_at = World.tick  # Let go: it climbs a step_s later.
	player.heart_held = held


func _heart_step_ticks() -> int:
	return maxi(roundi(float(_field_rules().get("heart", {}).get("step_s", 2)) * World.TICK_RATE), 1)


## Each tick, this zone's downed players: the heart a beat down each step_s
## while Slow Heart is held, a beat up while it is not; the blood runs at the
## beat's drain, the window (World.extend_downed) longer by what a slower
## heart saves. Up again or gone, the heart is 0.
func _tend_hearts() -> void:
	var rules: Dictionary = _field_rules().get("heart", {})
	var beats: Array = (rules.get("beats", [120, 80, 40]) as Array).map(func(beat: Variant) -> int: return int(beat))  # JSON reads floats.
	var drain: Array = rules.get("drain", [1.0, 0.5, 0.2])
	for peer: int in _players:
		var player: Player = _players[peer]
		if not is_instance_valid(player) or not player.spawned or player.zone != World.zone.name:
			continue
		if not World.is_downed(player):
			if player.heart != 0:
				player.heart = 0
			continue
		var stage := maxi(beats.find(player.heart), 0)
		if World.tick - player.heart_at >= _heart_step_ticks():
			var to := clampi(stage + (1 if player.heart_held else -1), 0, beats.size() - 1)
			if to != stage:
				stage = to
				player.heart = int(beats[stage])
				player.heart_at = World.tick
		player.heart_debt += 1.0 - float(drain[mini(stage, drain.size() - 1)])
		if player.heart_debt >= 1.0:
			var owed := floori(player.heart_debt)
			player.heart_debt -= owed
			World.extend_downed(player, owed)


## Each tick, this zone: every player in it downed, and each one's companion
## there downed or gone, so nobody is left to help: "All have fallen",
## economy's tell_all_fallen (the "return" message's all_fallen, everyone_s),
## and when it runs out each bleeds out (the return at once). One up again
## ends the wait, and they are told ({all_fallen: 0}).
func _all_fallen_tick() -> void:
	var here := World.zone.name
	var peers: Array = []
	var fallen := true
	for peer: int in _players:
		var player: Player = _players[peer]
		if not is_instance_valid(player) or not player.spawned or player.zone != here:
			continue
		peers.append(peer)
		var pet: Companion = _companions.get(_peer_ids.get(peer, ""))
		if not World.is_downed(player) or is_instance_valid(pet) and pet.spawned and pet.zone == here and not World.is_downed(pet):
			fallen = false
	if peers.is_empty() or not fallen:
		if _all_fallen_at.has(here):
			_all_fallen_at.erase(here)
			for peer: Variant in peers:
				Net.message_to(int(peer), "return", {"all_fallen": 0})
		return
	if not _all_fallen_at.has(here):
		party_log.add("All have fallen.")
		_all_fallen_at[here] = World.tick + tell_all_fallen(peers) * World.TICK_RATE
	elif World.tick >= _all_fallen_at[here]:
		_all_fallen_at.erase(here)
		for peer: Variant in peers:
			var player: Player = _players.get(int(peer))
			if is_instance_valid(player) and World.is_downed(player):
				World.damage(player, player.hp, null, &"bled")


## Server: [param by] begins to bring back the downed [param body] (held E
## on it, or her REVIVE): [param by] blessed, with a charge left on its
## player's count (573: no half to carry). False if it cannot.
func _start_channel(by: GridEntity, body: GridEntity) -> bool:
	if not World.is_downed(body) or not _blessed(by) or not _blessed(body):
		return false  # The unblessed lie their last moments; nobody brings them back (573).
	var record := _blessing_record(by)
	if _uses_left(record) <= 0:
		if by is Player:
			Net.broadcast_to([by.owner_peer], "party", {"from": "Server", "text": "You hold no charge. The draugr gives more."})
		return false
	if not World.calm(by) or not World.calm(body):
		# When it is safe (Mortally Wounded): nothing hostile near either, no blow just now.
		if by is Player:
			Net.broadcast_to([by.owner_peer], "party", {"from": "Server", "text": "Not while they're fighting near."})
		return false
	return World.try_channel(by, body, roundi(float(_field_rules().get("channel_s", 4)) * World.TICK_RATE))


## World.channel_changed (decision 544): a return done spends one charge of
## the channeler's player's count (573) and stands the body up; one broken is said.
func _on_channel(by: GridEntity, body: GridEntity, state: StringName) -> void:
	if not is_instance_valid(body):
		return
	if state == &"started":
		party_log.add("%s kneels beside %s." % [_display_name(by), _display_name(body)])
	elif state == &"broken":
		party_log.add("%s's return of %s is broken." % [_display_name(by) if is_instance_valid(by) else "Someone", _display_name(body)])
	elif state == &"done":
		var record := _blessing_record(by)
		if record == null or not World.totem_spend(World.totem_of(record.player_id)):
			return
		_sync_charges(record)
		World.raise_downed(body, roundi(body.max_hp * float(_field_rules().get("hp", 0.5))))
		if by is Player and has_left(record) and body.zone == str(World.holdings.place(_left_town(record)).get("area", "")):
			_favour_repaired(record, "temple")  # Their blessing spent on another in her town (581 amended).
		party_log.add("%s brought %s back (%d charges left)." % [_display_name(by), _display_name(body), _uses_left(record)])
		for pet: Companion in _companions.values():
			if is_instance_valid(pet) and pet.spawned and (pet == by or pet == body or pet.keeper == body):
				pet.note_brought_back(_display_name(by), _display_name(body))


## Server: the companion called [param wanted] (a name is never rolled
## twice: _give_traits), if a player's record has her alive: {player_id,
## where: "party" (with her player or waiting in the world), "resting" (in
## a town, "companion:<player_id>" there), "taken" (held by raiders)}; {}
## if none. npc's resident of the same name (Pip) stands down while she is
## (no body, no alms run), so there is one of him.
func companion_named(wanted: String) -> Dictionary:
	for id: String in _records:
		var pet: Dictionary = _records[id].companion
		if str(pet.get("name", "")) != wanted or not bool(pet.get("alive", true)):
			continue
		var where := "taken" if pet.has("taken") else "resting" if pet.has("resident") else "party"
		return {"player_id": id, "where": where}
	return {}


## Her subject pronoun by her card ("she", "he", "they").
func _companion_subject(record: PlayerRecord) -> String:
	var traits: Dictionary = record.companion.get("traits", {})
	var pronoun := str(traits.get("pronoun", "she"))
	return pronoun if pronoun in ["she", "he", "they"] else "she"


## Her object pronoun by her card ("her", "him", "them").
func _companion_object(record: PlayerRecord) -> String:
	var traits: Dictionary = record.companion.get("traits", {})
	return {"she": "her", "he": "him", "they": "them"}.get(str(traits.get("pronoun", "she")), "her")


## Server (decision 501, companions' side): [param pet]'s voice reads her
## record's sickness while she has one; one that ended (her record's
## "was_sick", left by npc's Townsfolk in town or _sickness_in_party) is told
## once, to the party log, as a fact on her and to her exchange, then erased.
## [param away]: it ran while her player was away from her.
func _tell_sickness(pet: Companion, record: PlayerRecord, away: bool) -> void:
	pet.sick_words = func() -> String:
		var sick: Variant = record.companion.get("sick", {})
		return Companion.sick_sentence(sick, Townsfolk.day_of(World.steps)) if sick is Dictionary else ""
	var was: Variant = record.companion.get("was_sick")
	if not was is Dictionary or was.is_empty():
		return
	var told := Companion.sickness_told(String(record.companion.get("name", pet.name)), record.name, _companion_object(record), was, away)
	party_log.add(told["log"])
	pet.note_fact(told["fact"])
	pet._narrate(told["narrate"])
	record.companion.erase("was_sick")


## Her record's sickness ends (decision 501): "sick" goes, and "was_sick"
## ({since, ended, cured_by, kind}) stays to be told once.
func _end_companion_sickness(record: PlayerRecord) -> void:
	var was: Dictionary = record.companion.get("sick", {})
	record.companion["was_sick"] = {"since": was.get("since", 0), "ended": Townsfolk.day_of(World.steps),
		"cured_by": was.get("cured_by", ""), "kind": was.get("kind", "a fever")}
	record.companion.erase("sick")


## Server, on the world tick (decision 501): a companion with her player
## (not resting in town, where npc's Townsfolk keeps it) is well again once
## her sickness is over (Companion.sickness_over, Townsfolk.sick_days); told
## at once when she stands, else when she next joins.
func _sickness_in_party() -> void:
	var today := Townsfolk.day_of(World.steps)
	for id: String in _records:
		var record: PlayerRecord = _records[id]
		var sick: Variant = record.companion.get("sick")
		if not sick is Dictionary or sick.is_empty() or record.companion.has("resident"):
			continue
		if not Companion.sickness_over(sick, today, Townsfolk.sick_days()):
			continue
		_end_companion_sickness(record)
		var pet: Companion = _companions.get(id)
		if is_instance_valid(pet) and pet.spawned:
			_tell_sickness(pet, record, false)


## Server: a raid group ([param by]) beat [param entity] down and took it
## (World.entity_taken, decision 314). A companion: the companions who saw
## it and she herself are told it as facts, her record says who holds her
## (companion_taken), her player is told, and she leaves the map as one who
## travels, not one who dies (her pack and facts kept with her record).
func _on_entity_taken(entity: GridEntity, by: String) -> void:
	if entity is Resident:
		_resident_taken(entity as Resident, by)
		return
	var pet := entity as Companion
	if pet == null:
		return
	var id := pet.keeper_id
	for other: Companion in _companions.values():
		if is_instance_valid(other) and other.spawned and other != pet and other.witnessed(pet):
			other.note_taken(_display_name(pet))
	pet.note_carried_off()
	_remember_companion(id)
	companion_taken(id, by)
	party_log.add("%s was carried off by raiders." % _display_name(pet))
	var player: Player = _players.get(pet.keeper_peer)
	if pet.keeper_peer != 0 and is_instance_valid(player):
		Net.broadcast_to([pet.keeper_peer], "party", {"from": "Server", "text": "Raiders beat %s down and carried them off." % _display_name(pet)})
	_travelling = true  # Taken, not dead.
	World.despawn(pet)
	_travelling = false
	_companions.erase(id)


## A resident beaten down by raid group [param by] (decision 333): its
## town's records hold it captive (Towns.resident_taken, economy's) and its
## body goes, as one carried off, not one who died.
func _resident_taken(body: Resident, by: String) -> void:
	if not body.player_id.is_empty():
		_companion_taken_in_town(body, by)
	elif not body.sought.is_empty() and World.towns != null:
		World.towns.sought_lost(body.sought)  # Lost on the way (613): sought again, somewhere else, after economy's days.
	elif World.towns != null:
		World.towns.resident_taken(body.town, body.worker_id, by)
	party_log.add("Raiders beat %s down and carried them off." % _display_name(body))
	_travelling = true  # Taken, not dead.
	World.despawn(body)
	_travelling = false


## A companion resting in town, her body (a Resident) beaten down by raid
## group [param by] (decision 333 amended): held as one taken beside her
## player (companion_taken), a fact about her in her record, her player told.
func _companion_taken_in_town(body: Resident, by: String) -> void:
	var record: PlayerRecord = _records.get(body.player_id)
	if record == null or not companion_taken(body.player_id, by):
		return
	var pet_name := str(record.companion.get("name", body.name))
	var town := str(Level.load_level(World.zone.name).get("display_name", World.zone.name)) if Level.exists(World.zone.name) else World.zone.name
	var grown := CompanionFacts.from_record(record.companion.get("facts", []), record.companion.get("beliefs", []))
	grown.add_fact("%s was beaten down and carried off by raiders in %s." % [pet_name, town], "event", body.player_id)
	record.companion["facts"] = grown.facts
	record.companion["beliefs"] = grown.beliefs
	for peer: int in _players:
		if _peer_ids.get(peer, "") == body.player_id:
			Net.broadcast_to([peer], "party", {"from": "Server", "text": "Raiders carried %s off from %s." % [pet_name, town]})


## Server: the zone World is in has a body for each resident of its towns
## (Towns.residents, not away), then for each companion resting or working
## in one away from her player (her record's "resident", not held, her
## player's Companion not out: decision 333 amended), at most RESIDENTS_MAX,
## and none for anyone else (decision 333). A body comes where its day puts
## it now, and goes when the record says it is gone (taken, away, moved, her
## player come for her); bodies are never saved. A body's key is its worker
## id, or "companion:<player id>" for a companion.
func _sync_residents() -> void:
	if World.towns == null or World.production == null or World.holdings == null or _world_map == null:
		return
	var area: Dictionary = _world_map.areas.get(World.zone.name, {})
	var wanted := {}
	if not area.is_empty():
		for place_id: String in World.holdings.places_in(World.zone.name):
			var place := World.holdings.place(place_id)
			if place.get("kind") != "stockpile":
				continue
			# Bodies only while someone is near (decision 355); a far town
			# takes none of the RESIDENTS_MAX either.
			if not _town_near(place_id, place):
				continue
			var ids: Array[String] = World.towns.residents(place_id).filter(func(who: String) -> bool:
				return not who.begins_with("companion:") and not World.production.worker(who).is_empty() \
					and not bool(World.production.worker(who).get("away", false)))
			ids.sort()
			var folk: Array[Dictionary] = []
			for who in ids:
				var trades: Array = World.production.worker(who).get("trades", [])
				folk.append({"key": who, "name": str(World.production.worker(who).get("name", who)),
					"trade": str(trades[0]) if not trades.is_empty() else "", "player": "",
					"type": str(World.production.worker(who).get("type", ""))})
			folk.append_array(_companions_resting(place_id))
			var homes := _homes(area, place)
			for i in folk.size():
				if wanted.size() < RESIDENTS_MAX:
					var each: Dictionary = folk[i]
					each["town"] = place_id
					each["places"] = _resident_places(area, place, each["trade"], homes, i)
					var settled := Townsfolk.settled()
					if settled.has(each["key"]):
						# A stall, not a house (decision 471): the 3x3 about the marked cell;
						# his work the store's counter; his body's kind the table's.
						var home_at: Variant = settled[each["key"]].get("home")
						if home_at is Array and home_at.size() == 2:
							each["places"]["home"] = Rect2i(Vector2i(int(home_at[0]) - 1, int(home_at[1]) - 1), Vector2i(3, 3))
						var store: Vector2i = place.get("cell", Vector2i.ZERO)
						each["places"]["work"] = Rect2i(store - Vector2i(1, 1), Vector2i(3, 3))
						each["kind"] = str(settled[each["key"]].get("kind", ""))
					if each["trade"] == "lawspeaker":
						# His rounds (decision 459): the town's homes in the order
						# they are given, with who lives there; his own left out.
						var stops: Array = []
						for k in mini(folk.size(), homes.size()):
							if k != i and str(folk[k].get("player", "")).is_empty():
								stops.append({"rect": homes[k], "who": str(folk[k]["name"]), "id": str(folk[k]["key"])})
						each["places"]["rounds"] = stops
					wanted[each["key"]] = each
			# Strangers passing through (711, npc's side): at the inn, the store or the temple by kind.
			for each: Dictionary in _visitors_wanted(area, place_id, place):
				if wanted.size() < RESIDENTS_MAX:
					wanted[each["key"]] = each
		# The healer's hut (decision 404): whoever economy seats there (the
		# medicine man, a worker whose town is the hut's place id) has a body
		# at the hut as a town's folk have theirs, only while someone is near.
		# And the hill herder's (640, npc's side; Jeff: "herders exist as people"): a place keyed one of
		# economy.json herder.places (herders_hut, hill_shieling) the same way, his fold (the place's ground) his
		# work by day and his hut his home by night; on his drove, the loop after this one.
		var herder_rule: Dictionary = World.production.rules.get("herder", {})
		var herder_keys: Array = herder_rule.get("places", [])
		for place_id: String in World.holdings.places_in(World.zone.name):
			var place := World.holdings.place(place_id)
			var fold_place: bool = str(place.get("key", "")) in herder_keys
			if (place.get("kind") != "healers_hut" and not fold_place) or not _town_near(place_id, place):
				continue
			var cell: Vector2i = place.get("cell", Vector2i.ZERO)
			var hut := Rect2i(cell - Vector2i.ONE, Vector2i(3, 3))
			# His hut: the building.hut beside the place (maps' 640: hills/herders_hut, hill_shieling), or one named
			# after the key; the healer's, its own slot.
			var slots: Array[String] = ["building.healers_hut"]
			if fold_place:
				slots = ["building.hut", "building." + str(place.get("key", ""))]
			for building: Dictionary in area.get("buildings", []):
				var rect: Rect2i = building.get("rect", Rect2i())
				if str(building.get("slot", "")) in slots and rect.grow(1).has_point(cell):
					hut = rect
			var radius := int(place.get("radius", 2)) if fold_place else 2
			var ground := Rect2i(cell - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))
			if fold_place:
				var fold: Dictionary = Level.fold_near(area.get("buildings", []), cell)  # The fold within FOLD_REACH (maps' 640).
				if not fold.is_empty():
					ground = fold["rect"]
			var ids := World.production.worker_ids(place_id).filter(func(who: String) -> bool:
				return not who.begins_with("companion:") and not bool(World.production.worker(who).get("away", false)))
			for who: String in ids:
				if wanted.size() >= RESIDENTS_MAX:
					break
				var trades: Array = World.production.worker(who).get("trades", [])
				wanted[who] = {"key": who, "name": str(World.production.worker(who).get("name", who)),
					"trade": str(trades[0]) if not trades.is_empty() else "", "player": "", "town": place_id,
					"type": str(World.production.worker(who).get("type", "")),
					"places": {"work": ground if fold_place else hut, "home": hut, "square": ground}}
		# The herder on his drove (640, npc's side): away from his fold with his sheep until the record's "back",
		# he stands at the buyer's store square (the record's "buyer" when economy keeps it, else Towns.drove_town
		# now) while a player is near that town, as its folk do; home again, the fold's body as above.
		var herder_trade := str(herder_rule.get("trade", "herder"))
		var herders: Dictionary = World.towns.herders_to_dict()
		for id: String in herders:
			var who := "%s:%s" % [herder_trade, id]
			var worker := World.production.worker(who)
			if worker.is_empty() or not bool(worker.get("away", false)) or int(herders[id].get("back", 0)) <= World.production.now():
				continue
			var buyer := str(herders[id].get("buyer", ""))
			if buyer.is_empty():
				buyer = World.towns.drove_town(id)
			var market := World.holdings.place(buyer)
			if market.is_empty() or str(market.get("area", "")) != World.zone.name or not _town_near(buyer, market):
				continue
			if wanted.size() >= RESIDENTS_MAX or wanted.has(who):
				continue
			var store: Vector2i = market.get("cell", Vector2i.ZERO)
			var square := Rect2i(store - Vector2i(2, 2), Vector2i(5, 5))
			var trades: Array = worker.get("trades", [])
			wanted[who] = {"key": who, "name": str(worker.get("name", who)), "trade": str(trades[0]) if not trades.is_empty() else "",
				"player": "", "town": buyer, "type": str(worker.get("type", "")),
				"places": {"work": square, "home": square, "square": square}}
	# The lost (decision 487): a town's people beyond the walls stand at their
	# cell of this zone, chosen once here (far from the store, off held
	# ground, reachable), while a player is near that cell; a walked one home
	# at the town's ground is home.
	for place_id: String in World.holdings.places_in(World.zone.name):
		var place := World.holdings.place(place_id)
		if place.get("kind") != "stockpile":
			continue
		for who: String in Townsfolk.strayed_of(World.production, place_id):
			if wanted.size() >= RESIDENTS_MAX:
				break
			var cell: Variant = Townsfolk.stray_cell(World.production, who)
			if cell == null:
				cell = _stray_cell(place)
				if cell == null:
					continue
				Townsfolk.set_stray_cell(World.production, who, cell)
			var origins := World._tier_origins()
			if not origins.is_empty() and _nearest_of(cell, origins) > recall_tiles:
				continue
			var trades: Array = World.production.worker(who).get("trades", [])
			var store: Vector2i = place.get("cell", Vector2i.ZERO)
			wanted[who] = {"key": who, "name": str(World.production.worker(who).get("name", who)), "trade": str(trades[0]) if not trades.is_empty() else "",
				"player": "", "town": place_id, "type": str(World.production.worker(who).get("type", "")), "strayed": true,
				"places": {"strayed": Rect2i(cell, Vector2i.ONE), "square": Rect2i(store - Vector2i(2, 2), Vector2i(5, 5))}}
	# The sought (decision 613, npc's side; economy's entry, maps' refuge): a town's wanted newcomer stands at the
	# refuge they were placed at, lost or held, while a player is near it (as a stray); freed, they stand beside the
	# player leading them, in whatever zone that player is (the entry's freed_by is the state, no record of its own:
	# a body not wanted is despawned as any other); at their town's ground they are home (_sought_home).
	for each: Dictionary in _sought_here():
		if wanted.size() >= RESIDENTS_MAX:
			break
		wanted[str(each["key"])] = each
	var have := {}
	for entity: GridEntity in World.townsfolk().duplicate():
		var body := entity as Resident
		if not body.sought.is_empty() and not body.escort_of.is_empty() and _at_towns_ground(body):
			_sought_home(body)
		elif body.strayed and not body.escort_of.is_empty() and _at_towns_ground(body):
			_came_home(body)
		elif not body.escort_of.is_empty() and Townsfolk.is_sick(World.production, body.worker_id) and _at_healers_hut(body):
			# Walked to the healer (decision 501): the healer sees to them.
			var by := Offers.name_of(Offers.ctx, body.escort_of)
			if by.is_empty() or by == "<null>":
				by = body.escort_name
			Townsfolk.treat(World.production, body.worker_id, by, "the healer", body.escort_of)
			body.escort_of = ""
			body.escort_name = ""
		if wanted.has(body.worker_id):
			have[body.worker_id] = true
			body.places = wanted[body.worker_id]["places"]
			# A retrained worker's body follows its trade (Pip to acolyte, a soak's retrain; 566 amended: the
			# work tick reads it), its label the spawn's until it stands again.
			var trade := str(wanted[body.worker_id].get("trade", ""))
			if not trade.is_empty() and body.trade != trade:
				body.trade = trade
			# The herder's body follows him to market and home (640, npc's side): its town the entry's.
			var town := str(wanted[body.worker_id].get("town", ""))
			if not town.is_empty() and body.town != town:
				body.town = town
		else:
			_travelling = true
			World.despawn(body)
			_travelling = false
	for who: String in wanted:
		if not have.has(who):
			_spawn_resident(wanted[who])
	_notes_tick()


## The sought wanted in this zone (decision 613, npc's side): _sync_residents'
## entries for every town's placed sought whose refuge is here (economy's
## entry, its place a holdings place with a cell), and for every freed one
## whose leader stands here, beside them.
func _sought_here() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if World.towns == null or World.production == null or World.holdings == null:
		return out
	var origins := World._tier_origins()
	for town_id: String in World.holdings.all_places():
		var town_place := World.holdings.place(town_id)
		if town_place.get("kind") != "stockpile":
			continue
		for entry: Dictionary in World.towns.sought(town_id):
			var id := str(entry.get("id", ""))
			var place_id := str(entry.get("place", ""))
			if id.is_empty() or place_id.is_empty() or World.production.worker(id).is_empty():
				continue
			var store: Vector2i = town_place.get("cell", Vector2i.ZERO)
			var freed_by := str(entry.get("freed_by", ""))
			var spec := {"key": id, "name": str(entry.get("name", id)), "trade": str(entry.get("trade", "")), "player": "", "town": town_id,
				"type": str(World.production.worker(id).get("type", "")), "strayed": true, "sought": id,
				"holder": str(entry.get("holder", "")), "where": str(entry.get("where", ""))}
			var cell: Vector2i
			if freed_by.is_empty():
				var refuge := World.holdings.place(place_id)
				if refuge.is_empty() or str(refuge.get("area", "")) != World.zone.name:
					continue
				cell = _nearest_free(refuge.get("cell", Vector2i.ZERO))
				if not origins.is_empty() and _nearest_of(cell, origins) > recall_tiles:
					continue
			else:
				var leader := _player_body(freed_by)
				if leader == null:
					continue
				cell = _nearest_free(leader.tile)
				spec["escort"] = freed_by
				spec["escort_name"] = _display_name(leader)
			spec["places"] = {"strayed": Rect2i(cell, Vector2i.ONE), "square": Rect2i(store - Vector2i(2, 2), Vector2i(5, 5))}
			out.append(spec)
	return out


## The sought's bands (613, enemy-ai's side): each town's sought placed
## with a holder at a place in this zone has its band (band_of) stood about
## the place once for that placing (_stand_band); the zone's living guards
## tagged with the entry are counted first, so a band is topped up, never
## doubled. A band killed stays dead until the sought is placed again (lost
## on the way, or wandered back from town); freed, home or called off, the
## entry is forgotten and its living guards stay as they are.
func _sync_bands() -> void:
	if World.towns == null or World.holdings == null or World.zone == null:
		return
	var rule: Dictionary = World.towns.rules.get("sought", {})
	var seen := {}
	for town_id: String in World.holdings.all_places():
		if World.holdings.place(town_id).get("kind") != "stockpile":
			continue
		for entry: Dictionary in World.towns.sought(town_id):
			var id := str(entry.get("id", ""))
			var place_id := str(entry.get("place", ""))
			if id.is_empty() or place_id.is_empty() or not str(entry.get("freed_by", "")).is_empty() 					or str(entry.get("holder", "")).is_empty():
				continue  # Not placed, led home, or lost (no holder): no band.
			seen[id] = true
			var band: Dictionary = _sought_bands.get(id, {})
			if str(band.get("place", "")) != place_id:
				band = {"place": place_id, "stood": false}
				_sought_bands[id] = band
			var refuge := World.holdings.place(place_id)
			if bool(band["stood"]) or refuge.is_empty() or str(refuge.get("area", "")) != World.zone.name:
				continue
			var made := _stand_band(id, band_of(rule, entry), refuge)
			band["stood"] = true
			print("[sought] %s's band at %s: %d stood for the %s" % [id, place_id, made, str(entry.get("holder", "")).replace("_", " ")])
	for id: String in _sought_bands.keys():
		if not seen.has(id):
			_sought_bands.erase(id)


## The band holding sought [param entry] (613; economy's rules' sought as
## [param rule]): its trade's row's band where the entry was placed at that
## row's where (613 amended: sought.trades[trade]; its alt, a camp, has
## none), else sought.guards[where].band (613 as first landed); [{kind,
## count}], [] for none.
static func band_of(rule: Dictionary, entry: Dictionary) -> Array:
	var where := str(entry.get("where", ""))
	var trades: Variant = rule.get("trades")
	if trades is Dictionary and trades.get(str(entry.get("trade", ""))) is Dictionary:
		var row: Dictionary = trades[str(entry.get("trade", ""))]
		return (row["band"] as Array).duplicate(true) if row.get("band") is Array and str(row.get("where", "")) == where else []
	var guards: Variant = rule.get("guards", {})
	var guard: Variant = guards.get(where) if guards is Dictionary else null
	return (guard["band"] as Array).duplicate(true) if guard is Dictionary and guard.get("band") is Array else []


## Stands sought [param id]'s [param band] about [param refuge] (a
## holdings place in this zone): each kind's count less its living guards
## tagged with [param id], on the free cells nearest the place's cell
## within its radius and BAND_REACH, inside its room when it has one
## (Monster.room_of), never on the cell or beside it, where the sought
## stands. Each guards that cell facing the place and keeps the room
## (props keeps_room; its props' "sought" the tag, both saved). How many.
func _stand_band(id: String, band: Array, refuge: Dictionary) -> int:
	if band.is_empty():
		return 0
	var at: Vector2i = refuge.get("cell", Vector2i.ZERO)
	var room := Monster.room_of(at)
	var reach := maxi(int(refuge.get("radius", 0)), 1) + BAND_REACH
	var standing := {}
	for entity in World.monsters():
		var props: Variant = entity.spawn_spec.get("props", {})
		if entity.spawned and entity.hp > 0 and props is Dictionary and str(props.get("sought", "")) == id:
			var kind := World.kind_of(entity)
			standing[kind] = int(standing.get(kind, 0)) + 1
	var spots: Array[Vector2i] = []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := at + Vector2i(dx, dy)
			if World.distance(cell, at) > 1 and (not room.has_area() or room.has_point(cell)) and World.is_free(cell):
				spots.append(cell)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := World.distance(a, at)
		var db := World.distance(b, at)
		return da < db if da != db else (a.y < b.y if a.y != b.y else a.x < b.x))
	var made := 0
	for row: Variant in band:
		if not row is Dictionary:
			continue
		var kind := str(row.get("kind", ""))
		for i in int(row.get("count", 0)) - int(standing.get(kind, 0)):
			if spots.is_empty():
				push_warning("[sought] no room for %s's band at %s" % [id, refuge.get("id", "")])
				return made
			var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
			if spec.is_empty():
				push_warning("[sought] %s's band names no monster kind %s" % [id, kind])
				break
			var cell: Vector2i = spots.pop_front()
			spec["name"] = ("Band_%s_%s_%d_%d" % [id, kind, World.tick, i + 1]).validate_node_name()
			spec["tile"] = cell
			spec["home"] = cell
			var toward := Senses.way_toward(cell, at)
			if toward != Vector2i.ZERO:
				spec["facing"] = toward
			spec["idle"] = {"mode": "guard"}
			var props: Dictionary = (spec["props"] as Dictionary).duplicate(true) if spec.get("props") is Dictionary else {}
			props["sought"] = id
			props["keeps_room"] = true
			spec["props"] = props
			if _spawn(spec) != null:
				made += 1
	return made


## The spawned player [param player_id] in this zone, null for none.
func _player_body(player_id: String) -> Player:
	if player_id.is_empty():
		return null
	for entity in World.get_entities():
		if entity is Player and entity.spawned and (entity as Player).player_id == player_id:
			return entity as Player
	return null


## Server: [param player] ([param player_id], [param speaker]) spoke to the
## sought [param body] (decision 613, npc's side): held and watched, it
## stays (its thought says why); else economy frees it (Towns.free_sought)
## and it follows them home, its set line said.
func _sought_spoken(body: Resident, player_id: String, speaker: String, player: Player) -> void:
	if World.is_downed(body):
		World.raise_downed(body, 1)  # Beaten down on the way home (613, enemy-ai's side): a word, and they get up.
		print("[sought] %s the %s gets up at %s's word" % [body.person, body.trade.replace("_", " "), speaker])
		return
	if not body.escort_of.is_empty() or World.towns == null:
		return
	if not body.holder.is_empty() and body.watched():
		print("[sought] %s will not follow %s: the %s watch" % [body.person, speaker, body.holder.replace("_", " ")])
		return
	if not World.towns.free_sought(body.sought, player_id):
		return
	body.start_escort(player_id, speaker)
	body.holder = ""
	if body.has_meta("sought_waiting"):
		body.remove_meta("sought_waiting")
	var town_word := str(World.holdings.place(body.town).get("name", body.town))
	Townsfolk.learn(World.production, body.sought, "%s found you %s and is leading you to %s." % [speaker, Towns.where_words(body.where), town_word])
	print("[sought] %s the %s is freed by %s %s, led to %s" % [body.person, body.trade.replace("_", " "), speaker, Towns.where_words(body.where), body.town])
	if player != null:
		_resident_says(body, str(Offers.sought_words(body.trade).get("freed", "Lead on.")), "", player)


## The sought [param body] at its town's ground, led there (decision 613,
## npc's side): economy's sought_home (a resident, the xp, the rescued
## signal), the card's fact, its arrival said to the one who led it; the
## body is one of the town's from the next sync.
func _sought_home(body: Resident) -> void:
	var by := Offers.name_of(Offers.ctx, body.escort_of)
	if by.is_empty() or by == "<null>":
		by = body.escort_name
	var id := body.sought
	var trade := body.trade
	var town_word := str(World.holdings.place(body.town).get("name", body.town))
	if World.towns.sought_home(id):
		Townsfolk.learn(World.production, id, "%s brought you to %s, where you live and work now." % [by, town_word])
		print("[sought] %s the %s is home in %s, brought by %s" % [body.person, trade.replace("_", " "), body.town, by])
		var leader := _player_body(body.escort_of)
		if leader != null:
			var line := str(Offers.sought_words(trade).get("arrival", "I am the %s you sent for."))
			_resident_says(body, line % trade.replace("_", " ") if line.contains("%s") else line, "", leader)
	body.strayed = false
	body.sought = ""
	body.holder = ""
	body.escort_of = ""
	body.escort_name = ""


## The hill herder's word of a sought one at his fold (640, npc's side):
## the first sought entry of any town placed at [param place_id] (his
## holding, the hills' refuge) with nobody leading them home, in
## residents.json sought's "shelter" (by story, else trade, else default;
## the name and the trade); "" for none. Lore's wording by story comes
## after Jeff's check; the default carries it till then.
func _shelter_words(place_id: String) -> String:
	if World.towns == null or place_id.is_empty():
		return ""
	var table: Dictionary = Townsfolk.days().get("sought", {})
	var fallback: Dictionary = table.get("default", {})
	for town: String in World.towns.to_dict():
		for entry: Dictionary in World.towns.sought(town):
			if str(entry.get("place", "")) != place_id or not str(entry.get("freed_by", "")).is_empty():
				continue
			var trade := str(entry.get("trade", ""))
			var by: Dictionary = table.get(str(entry.get("story", "")), table.get(trade, fallback))
			var line := str(by.get("shelter", fallback.get("shelter", "")))
			return line % [str(entry.get("name", "someone")), trade.replace("_", " ")] if not line.is_empty() else ""
	return ""


## The word [param town] sent out (decision 613, npc's side): one line per
## sought with a place, for the officials and the rumour.
func _sought_words(town: String) -> Array[String]:
	var out: Array[String] = []
	if World.towns == null:
		return out
	for entry: Dictionary in World.towns.sought(town):
		if str(entry.get("place", "")).is_empty():
			continue
		var trade := str(entry.get("trade", "")).replace("_", " ")
		if str(entry.get("freed_by", "")).is_empty():
			out.append("We have no %s. Word is %s the %s was seen %s." % [trade, entry.get("name", "someone"), trade, Towns.where_words(str(entry.get("where", "")))])
		else:
			out.append("%s the %s is found %s and is being led here." % [entry.get("name", "Someone"), trade, Towns.where_words(str(entry.get("where", "")))])
	return out


## The notes on doors in zone [param zone_name] (decision 643; Jeff: "a
## small note saying where they went"): for each sought entry of a town
## here with a "door" (economy's 613 amended: the workshop they kept,
## "<town>:<kind>", or "inn"; a Holdings place id, no colon, posts none:
## no sought trade works at one), the cell just outside that building's door
## while it stands, and the story's note with the where (Offers.note_words):
## [{tile: [x, y], text}], one a cell, rebuilt from Towns.sought each turn,
## so an ended entry (home, answered, dropped) takes its note down with it.
func _sought_notes(zone_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if World.towns == null or World.holdings == null or _world_map == null:
		return out
	var taken := {}
	for town_id: String in World.holdings.all_places():
		var town_place := World.holdings.place(town_id)
		if town_place.get("kind") != "stockpile" or str(town_place.get("area", "")) != zone_name:
			continue
		for entry: Dictionary in World.towns.sought(town_id):
			var door := str(entry.get("door", ""))
			if door.is_empty() or (door != "inn" and not door.begins_with(town_id + ":")):
				continue  # Never came, or a workshop that is a Holdings place (economy: a healer's hut's id has no colon).
			var use := "inn" if door == "inn" else door.trim_prefix(town_id + ":")
			var cell: Variant = _note_cell(zone_name, town_id, str(town_place.get("key", "")), use)
			if cell == null or taken.has(cell):
				continue
			taken[cell] = true
			var text := str(Offers.note_words(str(entry.get("story", ""))).get("note", "Away %s. Back when I can."))
			if text.contains("%s"):
				text = text % Towns.where_words(str(entry.get("where", "")))
			out.append({"tile": [cell.x, cell.y], "text": text})
	return out


## The cell just outside the door of [param town_id]'s standing (or damaged)
## building of [param use] in [param zone_name], its world-map record by
## the town's [param key]: across the first door edge of a kind with doors,
## else the front cell (a solid building's door is terrain); null for none
## (decision 643).
func _note_cell(zone_name: String, town_id: String, key: String, use: String) -> Variant:
	if str(World.towns.building(town_id, use).get("state", "")) not in [Towns.STANDING, Towns.DAMAGED]:
		return null
	for building: Dictionary in _world_map.areas.get(zone_name, {}).get("buildings", []):
		if str(building.get("town", "")) != key or str(building.get("use", "")) != use:
			continue
		var rect: Rect2i = building.get("rect", Rect2i())
		if not (building.get("doors", []) as Array).is_empty():
			var doors := Level.kind_doors(building)
			if not doors.is_empty():
				for cell: Vector2i in Terrain.edge_cells(doors[0]):
					if not rect.has_point(cell):
						return cell
		return Level.front_cell(rect, building.get("facing", Vector2i(0, 1)))
	return null


## Each turn (decision 643): this zone's door notes to its peers when they
## change (the "notes" message, whole; a joining peer gets them with the map).
func _notes_tick() -> void:
	var zone_name := World.zone.name
	var notes := _sought_notes(zone_name)
	var packed := var_to_str(notes)
	if str(_notes.get(zone_name, "")) == packed:
		return
	_notes[zone_name] = packed
	Net.broadcast_to(World.peers_in(zone_name), "notes", {"zone": zone_name, "notes": notes})


## The rumour a townsperson of [param town] tells [param player_id] on a
## greeting on [param day] (decision 643): the first sought entry with a
## where and nobody leading them home, its story's rumour line
## (Offers.note_words) with the name, the trade and the where only, never
## the mishap (lore's rule); once a day per player and town, "" after.
func _rumour_for(town: String, player_id: String, day: int) -> String:
	if World.towns == null:
		return ""
	if int(_rumour_said.get("_day", -1)) != day:
		_rumour_said = {"_day": day}
	for entry: Dictionary in World.towns.sought(town):
		if str(entry.get("where", "")).is_empty() or not str(entry.get("freed_by", "")).is_empty():
			continue
		var key := "%s|%s" % [town, player_id]
		if _rumour_said.has(key):
			return ""
		_rumour_said[key] = true
		var line := str(Offers.note_words(str(entry.get("story", ""))).get("rumour", "%s the %s has gone off, %s they say."))
		if line.count("%s") == 3:
			line = line % [entry.get("name", "Someone"), str(entry.get("trade", "")).replace("_", " "), Towns.where_words(str(entry.get("where", "")))]
		return line
	return ""


## Where the lost of the town at [param place] stand (decision 487): a
## walkable free cell of this zone at least "strays.far" from the store,
## not inside a building, off held ground (covered by no place whose holder
## is not the town's), among the farthest dozen one a path over the zone's
## grid reaches from the store (the coordinator's condition: walkable from
## the town); null when the zone has none. One in three cells is looked
## at, which is enough to find the far edge.
func _stray_cell(place: Dictionary) -> Variant:
	var store: Vector2i = place.get("cell", Vector2i.ZERO)
	var far := int(Townsfolk.rules().get("strays", {}).get("far", 24))
	var mine := World.holdings.holder(str(place.get("id", "")))
	var buildings: Array = _world_map.areas.get(World.zone.name, {}).get("buildings", []) if _world_map != null else []
	var could: Array[Vector2i] = []
	for cell: Vector2i in World.floor_cells():
		if (cell.x + cell.y) % 3 != 0 or World.distance(cell, store) < far or not World.is_walkable(cell) or not World.is_free(cell):
			continue
		if _on_held_ground(cell, mine) or buildings.any(func(b: Dictionary) -> bool: return (b.get("rect", Rect2i()) as Rect2i).has_point(cell)):
			continue
		could.append(cell)
	if could.is_empty():
		return null
	could.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return World.distance(a, store) > World.distance(b, store))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("stray:%s:%d" % [place.get("id", ""), Townsfolk.day_of(World.steps)])
	var top := could.slice(0, mini(could.size(), 12))
	while not top.is_empty():
		var cell: Vector2i = top.pop_at(rng.randi() % top.size())
		# Walkable from the town: a path over this zone's own grid (206's routes
		# join areas; within one zone the grid is the finer truth), doors opened.
		if not World.find_path(cell, store, true).is_empty():
			return cell
	return null


## Whether [param cell] lies within the radius of a place of this zone held
## by anyone but [param mine] (a raiders' camp, another's keep).
func _on_held_ground(cell: Vector2i, mine: String) -> bool:
	for id: String in World.holdings.places_in(World.zone.name):
		var place := World.holdings.place(id)
		if World.holdings.holder(id) != mine and World.holdings.covers(id, cell):
			return true
	return false


## Whether the lost [param body], walked home, stands on its town's ground
## (within the store's radius and a step).
func _at_towns_ground(body: Resident) -> bool:
	var place := World.holdings.place(body.town)
	return not place.is_empty() and World.distance(body.tile, place.get("cell", Vector2i.ZERO)) <= int(place.get("radius", 2)) + 1


## The lost [param body] is home (decision 487): the card and economy's
## record say so, the pleas to walk them home are met (Offers.walked_home:
## the notice, the pay, the standing), and the body is one of the town's
## again from the next sync.
func _came_home(body: Resident) -> void:
	var by := Offers.name_of(Offers.ctx, body.escort_of)
	if by.is_empty() or by == "<null>":
		by = body.escort_name
	Townsfolk.came_home(World.production, body.worker_id, by)
	Offers.walked_home(body.town, body.worker_id, body.escort_of, by)
	print("[state] %s was walked home to %s by %s" % [body.person, body.town, by])
	body.strayed = false
	body.escort_of = ""
	body.escort_name = ""


## Whether the town at [param place_id] has its residents' bodies: once a
## player or companion of the zone is within recall_tiles of its stockpile,
## till all are beyond retire_tiles (as far monsters are kept as records,
## decision 352; the residents are Towns' and Production's already, a body
## is only where it is now), and while raiders are in the zone or one of
## its folk hides from them, so a raid under way meets the bodies it came
## for. A zone nobody has been in (a test room) keeps them. Kept in
## _towns_near, which Towns.in_play reads.
func _town_near(place_id: String, place: Dictionary) -> bool:
	var near := World._tier_origins()
	var cell: Variant = place.get("cell")
	var now := near.is_empty() or not cell is Vector2i
	if not now:
		now = _nearest_of(cell, near) <= (retire_tiles if _towns_near.has(place_id) else recall_tiles)
	if not now and _towns_near.has(place_id) and (World.raids.any_in(World.zone.name) or _hiding_in(place_id)):
		now = true
	if now:
		_towns_near[place_id] = true
	else:
		_towns_near.erase(place_id)
	return now


## Whether one of the bodies of the town at [param place_id] is hiding (from
## raiders).
func _hiding_in(place_id: String) -> bool:
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		if body != null and body.town == place_id and body.doing == Resident.Doing.HIDE:
			return true
	return false


## The companions resting or working in the town at [param place_id], away
## from their players, by player id: [{key ("companion:<player id>"),
## name, trade, player}].
func _companions_resting(place_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = _records.keys()
	ids.sort()
	for player_id: String in ids:
		var record: PlayerRecord = _records[player_id]
		var resident: Dictionary = record.companion.get("resident", {})
		var out_with: Companion = _companions.get(player_id)
		if resident.get("place", "") != place_id or record.companion.has("taken") or not record.companion.get("alive", true) \
				or is_instance_valid(out_with) and out_with.spawned:
			continue
		out.append({"key": "companion:" + player_id, "name": str(record.companion.get("name", "")),
			"trade": str(resident.get("trade", "")), "player": player_id})
	return out


## Server: the resident [param player] speaks to with [param line], or
## null (decision 336): one it names within earshot, else the nearest within
## RESIDENT_EARSHOT; none when the line names [param pet] (their own
## companion, if she hears) or the resident is hiding.
func _resident_addressed(player: Player, line: String, pet: Companion) -> Resident:
	if pet != null and Companion._named(line, String(pet.name)):
		return null
	var nearest: Resident = null
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		var d := World.distance(body.tile, player.tile)
		if body.doing == Resident.Doing.HIDE or d > HEARING_RANGE or body.worker_id.begins_with(Offers.VISITOR):
			continue  # A visitor answers a click, not the mind (711, npc's side).
		if not body.person.is_empty() and Companion._named(line, body.person):
			return body
		if d <= RESIDENT_EARSHOT and (nearest == null or d < World.distance(nearest.tile, player.tile)):
			nearest = body
	return nearest


## Server: [param body] is asked [param line] by [param speaker]: an ask
## waits for the resident mind, replacing one of theirs still waiting.
func _ask_resident(body: Resident, speaker: String, line: String, player: Player = null) -> void:
	_write_resident_card(body)
	_resident_serial += 1
	var id := body.get_instance_id()
	var player_id := player.player_id if player != null else ""
	if not player_id.is_empty():
		Offers.spoke_to(player_id, body.worker_id)  # An errand to them is done by speaking (decision 435).
		if not body.sought.is_empty():
			_sought_spoken(body, player_id, speaker, player)  # The sought: freed by a word when no holder sees them (decision 613).
		elif body.strayed:
			body.start_escort(player_id, speaker)  # Lost beyond the walls: a word, and they follow you home (decision 487).
		elif Townsfolk.is_sick(World.production, body.worker_id) and int(Townsfolk.sickness_of(World.production, body.worker_id).get("treated", -1)) < 0 \
				and not _healers_hut_of(body.town).is_empty():
			body.start_escort(player_id, speaker)  # Sick: a word, and they let you walk them to the healer (decision 501).
	body.asked_by = player_id
	body.asked_by_name = speaker
	if not player_id.is_empty() and World.production != null:
		# Their first words make the standing entry (decision 443).
		var card := Townsfolk.card_of(World.production, body.worker_id)
		if not card.is_empty() and Standing.met(card, player_id, World.production.now()):
			World.production.set_card(body.worker_id, card)
			body.first_words = true
	if _resident_quiet(body, player):
		_held_tongue("heard")  # Words to them mid-fight get no answer (675, npc's side).
	else:
		_resident_asks = _resident_asks.filter(func(each: Dictionary) -> bool: return each["body"] != id)
		_resident_asks.append({"body": id, "ask": body.voice_ask(speaker, line, _resident_serial), "at": World.tick,
			"player": player_id, "peer": player.owner_peer if player != null else -1})
	body.asked_by = ""
	body.asked_by_name = ""
	body.first_words = false
	Transcript.record(body.person, speaker, line)


## Server: [param player_id]'s client (peer [param peer]) is sent what
## [param body] offers them now ("offers" {entity, speaker, offers}; decision
## 435): with each answer, when the panel opens, after an accept.
func _send_offers(body: Resident, player_id: String, peer: int) -> void:
	if body == null or not is_instance_valid(body) or player_id.is_empty() or peer < 0 or not body.player_id.is_empty():
		return
	var data := {"entity": String(body.get_path()), "speaker": body.person, "offers": Offers.of(body.worker_id, player_id)}
	var standing := _standing_for(player_id, body.worker_id)
	if not standing.is_empty():
		data["standing"] = {"id": standing["id"], "title": standing["title"]}  # PROTOCOL_REVISION 23 (decision 536).
	Net.message_to(peer, "offers", data)


## Server: [param player] accepts offer [param offer_id] (of the resident
## whose id it opens with), with [param gold] for a loan: a shop line is
## sold at the town's counter when they stand at one, a commission or an
## errand goes on the resident's card and their record, a loan is paid
## down (economy); the party log says, and their offers are sent again.
func _accept_offer(player: Player, offer_id: String, gold: int) -> void:
	var worker_id := offer_id.get_slice(Offers.SEP, 0)
	var body: Resident = null
	for entity: GridEntity in World.townsfolk():
		if entity is Resident and (entity as Resident).worker_id == worker_id:
			body = entity
	if body == null:
		# A talking monster's deal (decision 629): ui's button, the typed path's amount.
		for monster: GridEntity in World.monsters():
			if monster.has_method("offers_for") and monster.spawned and monster.zone == player.zone and World.distance(monster.tile, player.tile) <= HEARING_RANGE:
				for offer: Dictionary in monster.offers_for(player.player_id):
					if str(offer.get("id", "")) == offer_id:
						_monster_accepts(monster, player, offer, gold)
						return
		return
	if World.distance(body.tile, player.tile) > HEARING_RANGE:
		return
	var result := Offers.accept(worker_id, player.player_id, _display_name(player), offer_id, gold)
	_standing.erase(player.player_id)  # Taken, or tried: nothing stands (decision 536).
	if result.get("read") is Array and not result["read"].is_empty():
		_read_page(player, body, result["read"])  # The scholar's chronicle (decision 491).
	elif not str(result.get("ware", "")).is_empty():
		_visitor_sells(player, body, str(result["ware"]))
	elif int(result.get("relic", 0)) > 0:
		_relic_returned(player, body, int(result["relic"]))
	elif int(result.get("buy", 0)) > 0:
		var counter := _counter_near(player, str(World.production.worker(worker_id).get("town", "")))
		if counter == null:
			party_log.add("%s must stand at the town's counter to buy." % _display_name(player))
		else:
			World.try_buy(player, counter, int(result["buy"]))  # Answered by traded.
	elif not str(result.get("line", "")).is_empty():
		party_log.add(str(result["line"]))
	_send_offers(body, player.player_id, player.owner_peer)


## Server: [param body] reads [param lines] (a page: the scholar's
## chronicle, decision 491) to [param player]: one "party" message from the
## reader with the lines joined by newlines (ui's shape: one entry in the
## talk log that wraps and scrolls, one prefix, one timestamp; never
## "speech", which would pop the whole page as a bubble). Nobody else gets
## it.
func _read_page(player: Player, body: Resident, lines: Array) -> void:
	if player == null or lines.is_empty():
		return
	var reader := body.person if body != null else "The scholar"
	Net.broadcast_to([player.owner_peer], "party", {"from": reader, "text": "
".join(lines.map(func(line: Variant) -> String: return str(line)))})
	if body != null:
		Transcript.record(body.person, _display_name(player), "[reads the chronicle: %d lines]" % lines.size())


## The shop counter of [param town] that [param player] reaches, if any.
func _counter_near(player: Player, town: String) -> GridEntity:
	for entity: GridEntity in World._entities:
		if entity is Chest and (entity as Chest).shop and entity.spawned and World.shop_place(entity) == town and World.reaches(player, entity):
			return entity
	return null


## The zone [param player_id] is in: their body's (in this zone), else their
## record's last.
func _zone_of_player(player_id: String) -> String:
	for entity: GridEntity in World.sought():
		if entity is Player and (entity as Player).player_id == player_id and entity.spawned:
			return entity.zone
	var record: PlayerRecord = _records.get(player_id)
	return record.zone if record != null else ""


## What Offers reads of the world (decision 435): World's records and the
## callables it needs, economy's where economy has them (pay_loan,
## pay_commission), so a server without them offers no loan help and pays
## no commission yet.
func _offers_context() -> Dictionary:
	var pay: Dictionary = Production.read_rules().get("commissions", {})
	return {
		"production": World.production,
		"goods": Callable(World.economy, "goods") if World.economy != null else Callable(),
		"catalog": Callable(Production, "items_catalog"),
		"captives": Callable(World.towns, "captives") if World.towns != null else Callable(),
		"camps": (func() -> Array: return World.holdings.camps()) if World.holdings != null else Callable(),
		"hostile": func(faction: String, town: String) -> bool:
			return World.holdings != null and World.holdings.factions.hostile(faction, World.holdings.holder(town)),
		"short": func(town: String) -> Array:
			var short: Array = World.production.signals_of(town, Production.items_catalog()).get("short", {}).keys() if World.production != null else []
			short.sort()
			return short,
		"area_name": func(area: String) -> String: return str(_world_map.areas.get(area, {}).get("display_name", area)) if _world_map != null else area,
		"pay_loan": Callable(World.economy, "pay_loan") if World.economy != null and World.economy.has_method("pay_loan") else Callable(),
		"pay_commission": Callable(World.economy, "pay_commission") if World.economy != null and World.economy.has_method("pay_commission") else Callable(),
		"pay": func() -> Dictionary: return pay,
		"zone_of": _zone_of_player,
		"name_of": func(player_id: String) -> String:
			var record: PlayerRecord = _records.get(player_id)
			return record.name if record != null and not record.name.is_empty() else Offers.TRAVELLER,  # Never the id: it is the key to their record.
		"players_in": _players_in,
		"memory": _town_memory,
		"set_memory": _set_town_memory,
		"visitor": _visitor_of,
		"visitor_price": _visitor_price,
		"relics": _relics_held,
		"barrow_knight": barrow_knight,
		"lawspeaker": func(town: String) -> Dictionary: return World.towns.lawspeaker(town) if World.towns != null and World.towns.has_method("lawspeaker") else _lawspeaker_records.get(town, {}).duplicate(true),
		"set_lawspeaker": func(town: String, record: Dictionary) -> void:
			if World.towns != null and World.towns.has_method("set_lawspeaker"):
				World.towns.set_lawspeaker(town, record)
			else:
				_lawspeaker_records[town] = record.duplicate(true),
		"note": func(town: String, line: String) -> void:
			print("[lawspeaker] %s: %s" % [town, line])
			party_log.add("In %s, %s." % [str(_world_map.areas.get(town.get_slice("/", 0), {}).get("display_name", town.get_slice("/", 0))) if _world_map != null else town, line]),
		# The bard's night (decision 490): who stands in the town's inn, whether it stands, and the song to them.
		"has_inn": func(town: String) -> bool:
			return World.towns != null and str(World.towns.building(town, "inn").get("state", "")) == Towns.STANDING,
		"listeners": func(town: String) -> Array:
			var inn := _inn_rect(town)
			var out: Array = []
			if inn.size == Vector2i.ZERO:
				return out
			for peer: int in _players:
				var player: Player = _players[peer]
				if player != null and player.spawned and inn.has_point(player.tile):
					out.append(player.player_id)
			return out,
		"say": func(town: String, song: Dictionary) -> void: _sung(town, song),
		# Sickness (decision 501): the healer's hut of a town's zone and its medicine man, his visit, a companion's card, a death.
		# The building fund (decision 499, npc's side): economy's next build, what it lacks, a gift, a purse.
		"contribution_wanted": func(town: String) -> Dictionary: return World.economy.contribution_wanted(town) if World.economy != null and World.economy.has_method("contribution_wanted") else {},
		"shortfall": func(town: String) -> Dictionary: return World.towns.shortfall(town) if World.towns != null and World.towns.has_method("shortfall") else {},
		"contribute": func(town: String, player_id: String, amount: int) -> int: return int(World.economy.contribute(town, player_id, amount)) if World.economy != null and World.economy.has_method("contribute") else 0,
		"gold_of": func(player_id: String) -> int: return int(World.gold_of(player_id)),
		# The road's news (decision 504, npc's side): a camp's holder, for the raiders' name; a good's value, for how the wagon sold.
		"holder_of": func(place: String) -> String: return World.holdings.holder(place) if World.holdings != null else "",
		"value_of": func(kind: String) -> int: return int(World.economy.rules.get("value", {}).get(kind, 0)) if World.economy != null else 0,
		"healers_hut": func(town: String) -> String: return _healers_hut_of(town),
		# The medicine man's care (584 amended): economy's rule, retainer and record; the town his hut serves; his brew handed over.
		"care_hut": func(worker_id: String) -> String: return _care_hut_of(worker_id),
		"care_rule": func(place_id: String) -> Dictionary: return care_rule(place_id),
		"retain": func(player_id: String, healer_id: String, pay: String) -> Dictionary: return _retain_care(player_id, healer_id, pay),
		"grant_care": func(player_id: String, place_id: String, how: String) -> void: grant_care(player_id, place_id, how),
		"in_care": func(player_id: String, place_id: String) -> bool: return in_care(player_id, place_id),
		"care_via": func(player_id: String, place_id: String) -> String: return care_via(player_id, place_id),
		"care_given": func(player_id: String, place_id: String) -> Dictionary: return care_given(player_id, place_id),
		"care_give": func(player_id: String, place_id: String, key: String, count: int) -> int: return care_give(player_id, place_id, key, count),
		"care_clear": func(player_id: String, place_id: String, keys: Array) -> void: care_clear(player_id, place_id, keys),
		"hand_item": func(player_id: String, item_id: String, from_name: String) -> bool: return _hand_item(player_id, item_id, from_name),
		# The word the town sent out (decision 613, npc's side): who is sought and where they were seen, for the officials.
		"sought_words": func(town: String) -> Array[String]: return _sought_words(town),
		"healer_of": func(town: String) -> String:
			var hut := _healers_hut_of(town)
			if hut.is_empty() or World.production == null:
				return ""
			var ids := World.production.worker_ids(hut).filter(func(id: String) -> bool: return not bool(World.production.worker(id).get("away", false)))
			return str(ids[0]) if not ids.is_empty() else "",
		"send_healer": func(healer_id: String, sick_id: String, player_id: String) -> bool: return _send_healer(healer_id, sick_id, player_id),
		# One Pip (the coordinator's ruling with npc): the companion of that name, if a player has her.
		"companion_named": func(wanted: String) -> Dictionary: return companion_named(wanted),
		"road_news": func(town: String, news: Dictionary) -> void: _road_news(town, news),
		# The crypt's people (decision 546, npc's side, part 3): Aldous's secret told, and his two commissions.
		"secret_told": func(player_id: String, fact_id: String) -> void: _secret_told(player_id, fact_id),
		"crypt_asks": func(town: String, player_id: String) -> Dictionary: return _crypt_asks(town, player_id),
		"take_altar": func(town: String) -> int: return World.economy.take_altar(town) if World.economy != null and World.economy.has_method("take_altar") else 0,
		"altar_down": func(town: String, gold: int) -> void: _altar_down(town, gold),
		"give_gold": func(player_id: String, gold: int, why: String) -> void: _give_gold(player_id, gold, why),
		"companion_sick": func(id: String) -> Dictionary:
			var record: PlayerRecord = _records.get(id.trim_prefix("companion:"))
			return record.companion.get("sick", {}).duplicate(true) if record != null and record.companion.get("sick") is Dictionary else {},
		"set_companion_sick": func(id: String, sick: Dictionary) -> void:
			var record: PlayerRecord = _records.get(id.trim_prefix("companion:"))
			if record == null:
				return
			if sick.is_empty():
				var was: Dictionary = record.companion.get("sick", {})
				if was is Dictionary and not was.is_empty():
					_end_companion_sickness(record)
				else:
					record.companion.erase("sick")
			else:
				record.companion["sick"] = sick.duplicate(true),
		"died": func(town: String, id: String, why: String) -> bool:
			return bool(World.towns.died(town, id, why)) if World.towns != null and World.towns.has_method("died") else false,
		"lore": func(_town: String) -> Array:
			var facts := Lore.known_by(Lore.knower_for("townsfolk"), PackedStringArray(), "agreed")
			facts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("weight", 0)) > float(b.get("weight", 0)))
			return facts.map(func(fact: Dictionary) -> String: return str(fact.get("text", ""))),
		# The proposals' statuses from Jeff's page (458), for the scholar's chronicle (491).
		"statuses": func() -> Dictionary:
			return TownMemory.proposed_statuses(FileAccess.get_file_as_string(Net.proposed_path)) if not Net.proposed_path.is_empty() and FileAccess.file_exists(Net.proposed_path) else {},
		"town_name": func(town: String) -> String:
			return str(_world_map.areas.get(town.get_slice("/", 0), {}).get("display_name", town.get_slice("/", 0))) if _world_map != null else town,
		"players_words": func() -> bool: return Net.lawspeaker_players,
		"lawspeaker_of": _lawspeaker_of,
		"move_in": func(town: String, who: String, name: String, trade: String) -> bool:
			return World.towns != null and World.towns.has_method("move_in") and bool(World.towns.call("move_in", town, who, name, trade)),
		"visits": func(town: String) -> Array:
			var law := _lawspeaker_of(town)
			if law.is_empty() or World.production == null:
				return []
			return Townsfolk.visits(_town_folk(town), law, World.production.now()),
		"proposed": _write_proposed,
		"model": func() -> String: return str(Lawspeaker.MODELS.get(Net.lawspeaker, Net.lawspeaker)),
		"area_of": func(town: String) -> String: return str(World.holdings.place(town).get("area", "")) if World.holdings != null else "",
		"asked": _on_commission_asked,
		"done": _on_commission_done,
	}


## The ids of the players in play whose body or record is in [param area].
## Companions' hook for the road's news (decision 551, npc's side): their
## side sets it to a Callable taking (town: String, news: Dictionary); until
## then the news is logged and goes nowhere. The news dictionary's keys:
## Townsfolk._road_news.
var road_heard := Callable()


## Townsfolk's road_news (ctx): logged, and handed to road_heard when set.
func _road_news(town: String, news: Dictionary) -> void:
	print("[road] %s: the wagon %s on %s%s" % [town, news.get("kind", ""), news.get("route", ""), (" at " + str(news["camp"])) if not str(news.get("camp", "")).is_empty() else ""])
	if road_heard.is_valid():
		road_heard.call(town, news)


func _players_in(area: String) -> Array:

	var out := []
	for peer: int in _peer_ids:
		var player_id := str(_peer_ids[peer])
		if not player_id.is_empty() and _zone_of_player(player_id) == area and player_id not in out:
			out.append(player_id)
	if Net.is_authority() and not Net.player_id.is_empty() and _zone_of_player(Net.player_id) == area and Net.player_id not in out:
		out.append(Net.player_id)
	return out


## Server: [param by] put [param item] ([param uid]) into resident [param to]'s
## hands (World.handed): a gift (decision 443). The thing goes to the town's
## store in their name, so nothing is lost; the card remembers.
func _on_handed(by: GridEntity, to: GridEntity, item: String, uid: int) -> void:
	var player := by as Player
	var body := to as Resident
	if player != null and body != null and body.player_id == player.player_id and not player.player_id.is_empty():
		_favour_given(player, body, item)
		return
	if player == null or body == null or player.player_id.is_empty() or not body.player_id.is_empty() or World.production == null:
		return
	var slot := body.slots.find(item)
	if item == "remedy" and slot >= 0 and Townsfolk.is_sick(World.production, body.worker_id) and int(Townsfolk.sickness_of(World.production, body.worker_id).get("treated", -1)) < 0:
		# A remedy to the sick (decision 501): taken at once, used up, and the sickness breaks that night.
		var dose := _out_of_hands(body, slot)
		if dose != 0:
			World.items.place(dose, "used")
		Townsfolk.treat(World.production, body.worker_id, _display_name(player), "a remedy", player.player_id)
		return
	if slot >= 0 and World.stockpile != null and not body.town.is_empty():
		var taken := _out_of_hands(body, slot)
		if taken != 0:
			World.stockpile.bank(body.town, taken, body.person, "a gift from %s" % _display_name(player), body.zone, body.tile, "banked", "player:" + player.player_id)
	var line := Offers.gift(player.player_id, _display_name(player), body.worker_id, item)
	if not line.is_empty():
		party_log.add(line)


## Server: [param player] put [param item] into the hands of their own
## companion's body in town, who left them (581 amended): a gift moves her
## (once a day), food starts a visit (_favour_visit); the thing goes to her
## town's store, as a resident's gift does. Nothing for one who did not leave.
func _favour_given(player: Player, body: Resident, item: String) -> void:
	var record: PlayerRecord = _records.get(player.player_id)
	if not has_left(record):
		return
	var slot := body.slots.find(item)
	if slot >= 0 and World.stockpile != null and not body.town.is_empty():
		var taken := _out_of_hands(body, slot)
		if taken != 0:
			World.stockpile.bank(body.town, taken, body.person, "a gift from %s" % _display_name(player), body.zone, body.tile, "banked", "player:" + player.player_id)
	var thing := Companion._a(Items.name_of(item).to_lower())
	if str(Items.def(item).get("use", "")) == "eat":
		record.companion["left"]["visit"] = {"from": World.steps}
	_favour(record, "gift", "brought you %s" % thing)
	party_log.add("%s gives %s %s." % [_display_name(player), body.person, thing])


## Server: what a resident holds in [param slot] leaves its hands (banked, or a
## remedy used up: decisions 443 and 501); the instance uid, 0 for an empty
## slot. Nobody reaches a resident's slots by World.reaches, so this clears
## the slot outright, as the server's own act.
func _out_of_hands(body: Resident, slot: int) -> int:
	if slot < 0 or slot >= body.slots.size() or body.slots[slot].is_empty():
		return 0
	return World._take_out(body, slot)  # One unit of a stack handed him (decision 619).


## The lawspeaker's client (decision 448): the builder's ClaudeClient when
## Net.lawspeaker names a model (off by default; the key is the
## environment's, read by the client, never logged); null otherwise, and
## no round is ever made.
var _lawspeaker_client: Node = null
## His records until economy's Towns.lawspeaker holds them: town -> record.
var _lawspeaker_records: Dictionary = {}


func _make_lawspeaker() -> void:
	if _lawspeaker_client != null or not Net.is_authority() or Net.lawspeaker in ["", "off", "no", "false", "0"]:
		return
	var client := ClaudeClient.new()
	client.log_tag = "lawspeaker"
	add_child(client)
	_lawspeaker_client = client
	print("[lawspeaker] on: %s, one round a town a day; players' words %s" % [str(Lawspeaker.MODELS.get(Net.lawspeaker, Net.lawspeaker)),
		"in" if Net.lawspeaker_players else "out"])


## [param town]'s lawspeaker's worker id (trade "lawspeaker", decision 459), "" for none.
func _lawspeaker_of(town: String) -> String:
	if World.production == null:
		return ""
	for id: String in _town_folk(town):
		if "lawspeaker" in World.production.worker(id).get("trades", []):
			return id
	return ""


## [param town]'s people in the order _sync_residents gives homes by: the
## town's residents, no companions, none away, sorted.
func _town_folk(town: String) -> Array:
	if World.towns == null or World.production == null:
		return []
	var ids: Array = World.towns.residents(town).filter(func(who: String) -> bool:
		return not who.begins_with("companion:") and not World.production.worker(who).is_empty() and not bool(World.production.worker(who).get("away", false)))
	ids.sort()
	return ids


## Server: the people settled in a town by name (residents.json "settled",
## decision 471: Snagfin, the goblin merchant), seated through economy's
## door once their town has people of its own (so a town founded later
## does not spread its founding gold over him alone) and they are no
## worker yet: trade, type and origin "settled" to the record, a card in
## Jeff's words. At boot and on the world tick; nothing once he is there.
func _seat_settled() -> void:
	if World.production == null or World.towns == null or not World.towns.has_method("move_in"):
		return
	var table := Townsfolk.settled()
	for id: String in table:
		var entry: Dictionary = table[id]
		var town := str(entry.get("town", ""))
		if town.is_empty() or not World.production.worker(id).is_empty():
			continue
		if World.towns.residents(town).filter(func(who: String) -> bool: return who != id).is_empty():
			continue  # Not founded yet: he comes once there is a town to come to.
		# Economy's door; origin "settled" passes the town's room check (460 amended: he keeps his own stall).
		if not bool(World.towns.call("move_in", town, id, str(entry.get("name", id)), str(entry.get("trade", "")), "settled", str(entry.get("type", "")))):
			continue
		_write_settled_card(id, entry)
		print("[state] %s settled in %s as the town's %s" % [entry.get("name", id), town, str(entry.get("trade", "")).replace("_", " ")])


## [param id]'s card from its settled [param entry]: rolled as anyone's,
## then how they came and the standing fact in Jeff's words; outcast: no
## kin or grudge is ever rolled for them.
func _write_settled_card(id: String, entry: Dictionary) -> void:
	var card := ResidentCard.roll(id, str(entry.get("name", id)), str(entry.get("trade", "")), "settled")
	if not str(entry.get("came", "")).is_empty():
		card["came"] = str(entry["came"])
	card["outcast"] = bool(entry.get("outcast", false))
	if not str(entry.get("fact", "")).is_empty():
		ResidentCard.add_fact(card, World.production.now(), str(entry["fact"]))
	World.production.set_card(id, card)


## The healer's hut place of [param town]'s zone (maps' 372), "" for none.
func _healers_hut_of(town: String) -> String:
	if World.holdings == null:
		return ""
	var area := str(World.holdings.place(town).get("area", ""))
	for id: String in World.holdings.places_in(area):
		if World.holdings.place(id).get("kind") == "healers_hut":
			return id
	return ""


## Server: the medicine man [param healer_id] is asked, by [param player_id]'s
## word, to see to [param sick_id] (decision 501): a visit goes on his day
## (the sick one's home, "sick.visit_hours" from now; his body walks there
## when one stands, Resident.Doing.VISIT), and when it ends the sick one is
## treated by him whether or not anyone watched (_visits, on the world
## tick). False when he is already on a visit or the sick one is unknown.
var _visits: Dictionary = {}

func _send_healer(healer_id: String, sick_id: String, player_id: String) -> bool:
	if World.production == null or World.production.worker(healer_id).is_empty() or World.production.worker(sick_id).is_empty() or _visits.has(healer_id):
		return false
	var hours := int(Townsfolk.rules().get("sick", {}).get("visit_hours", 2))
	var until := World.steps + hours * int(DayNight.day_steps / 24)
	_visits[healer_id] = {"sick": sick_id, "until": until, "by": player_id}
	var home := Rect2i()
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		if body.worker_id == sick_id:
			home = body.places.get("home", Rect2i())
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		if body.worker_id == healer_id:
			body.visit = {"rect": home, "who": sick_id, "name": str(World.production.worker(sick_id).get("name", sick_id)), "until": until}
	print("[townsfolk] %s goes to see to %s" % [World.production.worker(healer_id).get("name", healer_id), World.production.worker(sick_id).get("name", sick_id)])
	return true


## Server, on the world tick: a medicine man's visit that has run its hours
## treats the sick one (decision 501), by his name, for the player whose
## word sent him.
func _visits_due() -> void:
	for healer_id: String in _visits.keys():
		var visit: Dictionary = _visits[healer_id]
		if World.steps < int(visit.get("until", 0)):
			continue
		_visits.erase(healer_id)
		if World.production == null:
			continue
		var name := str(World.production.worker(healer_id).get("name", healer_id))
		Townsfolk.treat(World.production, str(visit.get("sick", "")), name, "the medicine man", str(visit.get("by", "")))


## How far the medicine man reaches for herbs on his way (decision 502, npc's
## side): cells from where his body stands, each world tick.
const HERB_REACH := 6


## Server, on the world tick: a medicine man gathers herbs (decision 502,
## npc's side, amended): "herbs_a_day" (townsfolk.json "healer", 1) a day,
## by his body on its way while a player is near (not at home, in bed or
## hiding), else around his hut's cell once "gather_hour" has come; the
## world moves on whether or not anyone stands there. Nothing on a client
## (World.forage is null there).
## A medicine man's gathers today: {worker id: {day, count}} (the guard: a day's
## gather is never done twice, bodied or not).
var _herbs_gathered: Dictionary = {}


func _gather_herbs() -> void:
	if World.forage == null or World.production == null or World.holdings == null:
		return
	var today := Townsfolk.day_of(World.steps)
	var rule: Dictionary = Townsfolk.rules().get("healer", {})
	var a_day := int(rule.get("herbs_a_day", 1))
	# By his body, on his way, while a player is near: the visible gather.
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		if body == null or body.trade != "medicine_man" or body.town.is_empty() or body.doing in [Resident.Doing.HOME, Resident.Doing.BED, Resident.Doing.HIDE]:
			continue
		if _herbs_today(body.worker_id, today) >= a_day:
			continue
		if _take_herbs(body.worker_id, body.person, body.zone, body.tile, today):
			print("[townsfolk] %s gathered herbs on his way at %s" % [body.person, body.tile])
	# Without a body (nobody near his hut; the world moves on), at the hut once the hour has come.
	if DayNight.hour(World.steps) < float(rule.get("gather_hour", 14)):
		return
	for id: String in World.production.worker_ids():
		var who := World.production.worker(id)
		if not "medicine_man" in who.get("trades", []) or bool(who.get("away", false)) or Townsfolk.is_sick(World.production, id):
			continue
		if _herbs_today(id, today) >= a_day:
			continue
		var hut := World.holdings.place(str(who.get("town", "")))
		var area := str(hut.get("area", ""))
		if hut.is_empty() or not World.zones.has(area) or not hut.get("cell") is Vector2i:
			continue
		while _herbs_today(id, today) < a_day:
			if not _take_herbs(id, str(who.get("name", id)), area, hut["cell"], today):
				break
			print("[townsfolk] %s gathered herbs around the hut" % who.get("name", id))


## How many herbs [param id] has gathered on [param today].
func _herbs_today(id: String, today: int) -> int:
	var mark: Dictionary = _herbs_gathered.get(id, {})
	return int(mark.get("count", 0)) if int(mark.get("day", -1)) == today else 0


## The medicine man [param id] ([param name]) takes the nearest herbs within
## HERB_REACH of [param cell] in [param area] (terrain's Forage.take_near) and
## delivers them to the area's town store as a gatherer's raw (economy's
## Production.deliver_to, 498: bought at the delivery price), the pile's
## instance ended as a banked resource's is; a delivery refused puts them
## back where they were. True when herbs were taken and delivered.
func _take_herbs(id: String, name: String, area: String, cell: Vector2i, today: int) -> bool:
	# His own gathering goes into his own town's store, the hut's (502 amended, economy's soak: his workshop makes
	# from the hut's store, and nobody pays him for herbs the town has no use for); the area's town store only for
	# a medicine man with no town of his own.
	var store := str(World.production.worker(id).get("town", ""))
	if store.is_empty() or World.holdings.place(store).is_empty():
		store = _town_store_of(area)
	if store.is_empty():
		return false
	var uid: int = World.forage.take_near(area, cell, HERB_REACH)
	if uid == 0:
		return false
	var yields := World.items.yields_of(uid)
	if yields.is_empty():
		yields = {World.items.id_of(uid): 1}
	var delivered := false
	for what: String in yields:
		if World.stockpile.deposit(store, what, int(yields[what]), name, "gathered by the medicine man", id):
			delivered = true
	if not delivered:
		World.put_on_ground(uid, cell)
		return false
	World.items.end(uid, "banked", "%s by %s" % [store, name], area, cell)
	var mark: Dictionary = _herbs_gathered.get(id, {})
	_herbs_gathered[id] = {"day": today, "count": (int(mark.get("count", 0)) if int(mark.get("day", -1)) == today else 0) + 1}
	return true


## The town's store in [param area] (the stockpile place the town holds), ""
## for none.
func _town_store_of(area: String) -> String:
	for id: String in World.holdings.places_in(area):
		if World.holdings.place(id).get("kind") == Stockpile.KIND and World.holdings.holder(id) == Stockpile.TOWN:
			return id
	return ""


## Whether the sick [param body], walked to the healer, stands on the hut's
## ground (decision 501).
func _at_healers_hut(body: Resident) -> bool:
	var hut := _healers_hut_of(body.town)
	return not hut.is_empty() and World.holdings.covers(hut, body.tile)


## The standing inn of [param town] in this zone, as a rect; an empty one
## for none (decision 490).
func _inn_rect(town: String) -> Rect2i:
	if _world_map == null or World.holdings == null:
		return Rect2i()
	var key := str(World.holdings.place(town).get("key", ""))
	for building: Dictionary in _world_map.areas.get(World.zone.name, {}).get("buildings", []):
		if str(building.get("town", "")) == key and str(building.get("use", "")) == "inn":
			return building.get("rect", Rect2i())
	return Rect2i()


## Server: the bard sang in [param town] (decision 490, Townsfolk.perform's
## "say"): the lines to the players in the inn (their talk log), the
## named one told it is their own deed, and the bard's body, when one
## stands here, says it for the bubble.
func _sung(town: String, song: Dictionary) -> void:
	var listeners: Array = song.get("listeners", [])
	for peer: int in _players:
		var player: Player = _players[peer]
		if player == null or player.player_id not in listeners:
			continue
		Net.broadcast_to([peer], "party", {"from": str(song.get("name", "The bard")), "text": str(song.get("line", ""))})
		if not str(song.get("second", "")).is_empty():
			Net.broadcast_to([peer], "party", {"from": str(song.get("name", "The bard")), "text": str(song.get("second", ""))})
		if str(song.get("named", "")) == player.player_id:
			Net.broadcast_to([peer], "party", {"from": str(song.get("name", "The bard")), "text": "It is your own deed %s sings of." % song.get("name", "the bard")})
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		if body != null and body.worker_id == str(song.get("bard", "")) and body.town == town:
			if _resident_quiet(body):
				_held_tongue("song")  # The inn hears the song; no bubble near a fight (675, npc's side).
				continue
			Net.broadcast_to(hearers(body.tile), "speech", {"entity": String(body.get_path()), "speaker": body.person, "text": str(song.get("spoken", ""))})
			Transcript.record(body.person, body.person, "[sings] " + str(song.get("spoken", "")))


## Server: the proposals list for Jeff (decision 458), every town's
## "proposed" memories, written to Net.proposed_path (nothing when ""),
## keeping the status lines written into it by hand.
func _write_proposed() -> void:
	if Net.proposed_path.is_empty() or World.production == null:
		return
	var logs := {}
	var names := {}
	for id: String in World.production.worker_ids():
		var town := str(World.production.worker(id).get("town", ""))
		if not town.is_empty() and not logs.has(town):
			logs[town] = _town_memory(town)
			names[town] = str(_world_map.areas.get(town.get_slice("/", 0), {}).get("display_name", town.get_slice("/", 0))) if _world_map != null else town
	var who := func(worker_id: String) -> String:
		var worker := World.production.worker(worker_id)
		if worker.is_empty():
			return worker_id
		var trades: Array = worker.get("trades", [])
		return "%s the %s" % [worker.get("name", worker_id), str(trades[0]).replace("_", " ")] if not trades.is_empty() else str(worker.get("name", worker_id))
	var statuses := TownMemory.proposed_statuses(FileAccess.get_file_as_string(Net.proposed_path)) if FileAccess.file_exists(Net.proposed_path) else {}
	var file := FileAccess.open(Net.proposed_path, FileAccess.WRITE)
	if file == null:
		push_warning("[lawspeaker] cannot write the proposals list %s (%s)" % [Net.proposed_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(TownMemory.proposed_page(logs, names, who, statuses))
	file.close()


## Server: [param player_id] took on [param ask]: on their record too.
func _on_commission_asked(player_id: String, ask: Dictionary) -> void:
	var record: PlayerRecord = _records.get(player_id)
	if record != null:
		record.commissions.append(ask.duplicate(true))


## Server: [param ask] is met or lapsed: off their record, the party log
## told [param line]; economy paid them [param _paid] already.
func _on_commission_done(player_id: String, ask: Dictionary, line: String, _paid: int) -> void:
	var record: PlayerRecord = _records.get(player_id)
	if has_left(record) and str(ask.get("town", "")) == _left_town(record):
		_favour(record, "errand", "did a job for your town")  # 581 amended.
	if record != null:
		record.commissions = record.commissions.filter(func(each: Variant) -> bool:
			return not each is Dictionary or str(each.get("id", "")) != str(ask.get("id", "")))
	if not line.is_empty():
		party_log.add(line)


## A town's resident spoken to for the first time: its card's paragraph is
## asked of the resident mind once (decision 398, as a companion's is,
## 293: the "card" channel, off the tick), kept on the worker record when
## it comes; the plain card stands until then, or for good without a
## model. A companion resting in town has her own card.
func _write_resident_card(body: Resident) -> void:
	if not body.player_id.is_empty() or World.production == null:
		return
	var card := Townsfolk.card_of(World.production, body.worker_id)
	if card.is_empty() or str(card.get("card_by", "")) == "model" or body.worker_id in _resident_cards_out.values():
		return
	if _resident_mind == null:
		_resident_mind = _make_mind()
	if _resident_mind.busy("card"):
		return
	_resident_serial += 1
	_resident_cards_out[_resident_serial] = body.worker_id
	var ask := {"kind": "card", "serial": _resident_serial, "trigger": "%s's card, from the facts" % body.person,
		"system": ResidentCard.CARD_SYSTEM, "user": ResidentCard.facts(card)}
	var answer := _resident_mind.card(ask)
	if not answer.is_empty():
		_resident_card_written(_resident_serial, answer, "")


## The resident mind's answer to a card ask: taken if it is a paragraph
## with no speech in it (ResidentCard.take_written), else the plain card
## stands; logged either way.
func _resident_card_written(serial: int, answer: Dictionary, error: String) -> void:
	var worker_id := str(_resident_cards_out.get(serial, ""))
	_resident_cards_out.erase(serial)
	if worker_id.is_empty() or World.production == null:
		return
	var card := Townsfolk.card_of(World.production, worker_id)
	var taken := not card.is_empty() and ResidentCard.take_written(card, str(answer.get("card", "")))
	if taken:
		World.production.set_card(worker_id, card)
	MindLog.record({"kind": "card", "companion": str(card.get("traits", {}).get("name", worker_id)), "mind": "resident",
		"say": str(answer.get("card", "")), "error": error, "outcome": "applied" if taken else "rejected"})


## Server, every tick: the resident mind's answers taken; asks waited too
## long dropped; the next sent when the resident mind is free and no
## companion's voice is out (residents yield to companions).
func _resident_voices() -> void:
	if _resident_asks.is_empty() and _resident_out.is_empty() and _claims_asks.is_empty() and _claims_out.is_empty() and _resident_cards_out.is_empty():
		return
	if _resident_mind == null:
		_resident_mind = _make_mind()
	for result: Dictionary in _resident_mind.take_results():
		if str(result.get("kind", "")) == "facts":
			var asked: Dictionary = _claims_out.get(int(result.get("serial", 0)), {})
			_claims_out.erase(int(result.get("serial", 0)))
			if not asked.is_empty():
				_claims_answered(asked, result.get("answer", {}), str(result.get("error", "")))
			continue
		if str(result.get("kind", "")) == "card":
			_resident_card_written(int(result.get("serial", 0)), result.get("answer", {}), str(result.get("error", "")))
			continue
		var out: Dictionary = _resident_out.get(int(result.get("serial", 0)), {})
		_resident_out.erase(int(result.get("serial", 0)))
		if not out.is_empty():
			_mind_last_ticks = World.tick - int(out.get("at", World.tick))  # A slow mind hails nobody (decision 554).
			if not str(out.get("player", "")).is_empty():
				_hail_at[str(out["player"])] = Time.get_ticks_msec()  # An answer to them is a talk: no hail within the minute.
			_resident_answered(out, result.get("answer", {}), str(result.get("error", "")))
	for each: Dictionary in _resident_asks.duplicate():
		if World.tick - int(each["at"]) > RESIDENT_ASK_TICKS:
			_resident_asks.erase(each)
			MindLog.record({"kind": "voice", "companion": str(each["ask"].get("speaker", "")), "mind": "resident",
				"trigger": each["ask"].get("trigger", ""), "outcome": "dropped", "note": "waited too long for the mind"})
	_claims_asks = _claims_asks.filter(func(each: Dictionary) -> bool: return World.tick - int(each["at"]) <= RESIDENT_ASK_TICKS)
	if _resident_mind.busy("voice"):
		return
	for pet: Companion in _companions.values():
		if is_instance_valid(pet) and pet.mind != null and pet.mind.busy("voice"):
			return
	if _resident_asks.is_empty():
		# Nothing to answer: what was heard is weighed (decision 378).
		if not _claims_asks.is_empty() and not _resident_mind.busy("facts"):
			_send_claims(_claims_asks.pop_front())
		return
	var next: Dictionary = _resident_asks.pop_front()
	_resident_out[int(next["ask"]["serial"])] = next
	var answer := _resident_mind.voice(next["ask"])
	if not answer.is_empty():
		_resident_out.erase(int(next["ask"]["serial"]))
		_resident_answered(next, answer, "")


## Server: [param line], said by [param from] ([param speaker] its body),
## heard by each resident within RESIDENT_EARSHOT and by [param to] (the
## one it was said to): a claims ask waits for each (decision 378), at
## most one per resident per Hearsay "claims_ticks", a newer replacing one
## still waiting. A companion resting in town keeps hers in her card
## (later), and one hiding hears nothing.
func _heard_near(speaker: GridEntity, from: String, line: String, to: Resident = null) -> void:
	if World.production == null or not Hearsay.worth_asking(line):
		return
	for entity: GridEntity in World.townsfolk():
		var body := entity as Resident
		if body == null or body == speaker or not body.player_id.is_empty() or body.doing == Resident.Doing.HIDE:
			continue
		if body != to and (speaker == null or World.distance(body.tile, speaker.tile) > RESIDENT_EARSHOT):
			continue
		if World.tick - _claims_at.get(body.worker_id, -100000) < int(Hearsay.setting("claims_ticks")):
			continue
		_claims_asks = _claims_asks.filter(func(each: Dictionary) -> bool: return each["worker"] != body.worker_id)
		_claims_asks.append({"body": body.get_instance_id(), "worker": body.worker_id, "person": body.person,
			"from": from, "line": line, "at": World.tick,
			"from_id": ("player:" + (speaker as Player).player_id) if speaker is Player else ((speaker as Resident).worker_id if speaker is Resident else "")})
	# A companion out with her player hears it too, within her hearing
	# (decision 442): her own, kept in her player's record.
	for player_id: String in _companions:
		var pet: Companion = _companions[player_id]
		if not is_instance_valid(pet) or not pet.spawned or pet == speaker or not _records.has(player_id):
			continue
		if speaker == null or World.distance(pet.tile, speaker.tile) > HEARING_RANGE:
			continue
		var key := "pet:" + player_id
		if World.tick - _claims_at.get(key, -100000) < int(Hearsay.setting("claims_ticks")):
			continue
		_claims_asks = _claims_asks.filter(func(each: Dictionary) -> bool: return each["worker"] != key)
		_claims_asks.append({"pet": pet.get_instance_id(), "player": player_id, "worker": key, "person": String(pet.name),
			"from": from, "line": line, "at": World.tick})



## Server: [param body] said [param line] to [param to] (the lawspeaker,
## phase 1): one whose voice may embellish (378: a free type, or creativity
## high; never an official) gets the claims ask on their own line, and each
## claim beyond what they know becomes their tale in the town's memory log.
## The same queue as the hearers', the entry marked "own".
func _own_tale(body: Resident, line: String, to: String) -> void:
	if World.production == null or not body.player_id.is_empty() or not Hearsay.worth_asking(line):
		return
	if body.binding() == "official" or not (body.binding() == "free" or body.leaning("creativity") >= Resident.HIGH):
		return
	_claims_asks = _claims_asks.filter(func(each: Dictionary) -> bool: return each["worker"] != body.worker_id)
	_claims_asks.append({"body": body.get_instance_id(), "worker": body.worker_id, "person": body.person,
		"from": body.person, "line": line, "at": World.tick, "own": true, "to": to})


## The town memory logs (phase 1) until economy's Towns.memory holds them:
## town -> log. Not saved; a server with the hook saves them with the town.
var _memory_logs: Dictionary = {}


## [param town]'s memory log, a copy (economy's when Towns has it).
func _town_memory(town: String) -> Array:
	if World.towns != null and World.towns.has_method("memory"):
		return World.towns.call("memory", town)
	return _memory_logs.get(town, []).duplicate(true)


func _set_town_memory(town: String, log: Array) -> void:
	if World.towns != null and World.towns.has_method("set_memory"):
		World.towns.call("set_memory", town, log)
	else:
		_memory_logs[town] = log.duplicate(true)


## Server: [param each] (_claims_asks') sent to the resident mind, with
## what it knows and holds now.
func _send_claims(each: Dictionary) -> void:
	_resident_serial += 1
	if each.has("pet"):
		# A companion's (decision 442): shown what lore says she knows and
		# what is true of her, and what she holds.
		var pet := instance_from_id(int(each["pet"])) as Companion
		if pet == null or not is_instance_valid(pet):
			return
		var known: Array[String] = []
		var lore := Companion.lore_words(String(pet.name)).trim_prefix("What you know of the world: ")
		if not lore.is_empty():
			known.append(lore)
		for fact: Dictionary in pet.grown.facts:
			known.append(str(fact["text"]))
		each["ask"] = Hearsay.claims_ask(String(pet.name), known, pet.heard, str(each["from"]), str(each["line"]), _resident_serial,
			"who travels with %s" % pet.keeper_name())
	else:
		var body := instance_from_id(int(each["body"])) as Resident
		if body == null or not is_instance_valid(body):
			return
		each["ask"] = Hearsay.claims_ask(body.person, body.world_facts(), World.production.worker(body.worker_id).get("heard", []),
			str(each["from"]), str(each["line"]), _resident_serial)
	_claims_at[each["worker"]] = World.tick
	_claims_out[_resident_serial] = each
	var answer := _resident_mind.facts(each["ask"])
	if not answer.is_empty():
		_claims_out.erase(_resident_serial)
		_claims_answered(each, answer, "")


## Server: the claims [param answer] for [param each]: each claim weighed
## by the resident's intellect (Hearsay.hear), the held ones it shows false
## no longer believed; kept on its worker record; logged.
func _claims_answered(each: Dictionary, answer: Dictionary, error: String) -> void:
	if each.has("pet"):
		_pet_claims_answered(each, answer, error)
		return
	var worker := World.production.worker(str(each["worker"]))
	if worker.is_empty():
		return
	var heard: Array = worker.get("heard", []).duplicate(true)
	var body := instance_from_id(int(each["body"])) as Resident
	var trades: Array = worker.get("trades", [])
	var profile := Lore.profile(str(trades[0]) if not trades.is_empty() else "", str(worker.get("type", "")))
	var intellect := body.leaning("intellect") if is_instance_valid(body) else int(worker.get("intellect", profile.get("intellect", 5)))
	var superstition := body.leaning("superstition") if is_instance_valid(body) else int(worker.get("superstition", profile.get("superstition", 5)))
	var kept: Array[Dictionary] = []
	var claims: Variant = answer.get("facts", [])
	var town := str(worker.get("town", ""))
	var log := _town_memory(town) if not town.is_empty() else []
	var logged := false
	if bool(each.get("own", false)):
		# Their own tale (the lawspeaker, phase 1): believed, and the town's to remember.
		var noted := TownMemory.told(log, heard, str(each["worker"]), str(each.get("to", "")), claims if claims is Array else [], World.production.now())
		logged = not noted.is_empty()
		if logged:
			kept.append_array(noted)
	else:
		for claim: Variant in claims if claims is Array else []:
			if claim is Dictionary:
				var text := str(claim.get("text", ""))
				var entry := Hearsay.hear(heard, str(each["worker"]), intellect, text, str(claim.get("fits", "")),
					str(each["from"]), World.production.now(), Hearsay.is_omen(text, claim.get("omen")), superstition)
				if not entry.is_empty():
					kept.append(entry)
					if bool(entry.get("believed", false)) and str(entry.get("fits", "")) == "beyond" and str(each.get("from", "")).begins_with("player:") == false:
						# A player's (or anyone's) words believed are logged with their source.
						var said_by := str(each.get("from_id", "")) if each.has("from_id") else ""
						TownMemory.hold(log, text, str(each["worker"]), said_by, World.production.now())
						logged = true
	var gone: Variant = answer.get("overturns", [])
	var overturned := Hearsay.overturn(heard, gone if gone is Array else [])
	for turned: Dictionary in overturned:
		if not TownMemory.drop(log, str(turned.get("text", "")), str(each["worker"])).is_empty():
			logged = true
	if logged and not town.is_empty():
		_set_town_memory(town, log)
	if not kept.is_empty() or not overturned.is_empty():
		World.production.set_heard(str(each["worker"]), heard)
	MindLog.record({"kind": "claims", "companion": str(each["person"]), "mind": "resident", "trigger": each.get("ask", {}).get("trigger", ""),
		"heard": each["line"], "from": each["from"], "claims": claims, "kept": kept, "overturned": overturned, "intellect": intellect, "superstition": superstition,
		"error": error, "outcome": "weighed" if error.is_empty() else "not weighed"})


## Server: a companion's claims [param answer] ([param each]: her player's
## id, her body): each claim weighed by her intellect and superstition (her
## card's, CompanionCard.leaning), the held ones it shows false no longer
## believed; kept in her player's record ("heard") and on her (decision 442).
func _pet_claims_answered(each: Dictionary, answer: Dictionary, error: String) -> void:
	var record: PlayerRecord = _records.get(str(each["player"]))
	if record == null or record.companion.is_empty():
		return
	var traits: Dictionary = record.companion.get("traits", {})
	var intellect := CompanionCard.leaning(traits, record.player_id, "intellect")
	var superstition := CompanionCard.leaning(traits, record.player_id, "superstition")
	var heard: Array = record.companion.get("heard", []).duplicate(true)
	var kept: Array[Dictionary] = []
	var claims: Variant = answer.get("facts", [])
	for claim: Variant in claims if claims is Array else []:
		if claim is Dictionary:
			var text := str(claim.get("text", ""))
			var entry := Hearsay.hear(heard, "companion:" + record.player_id, intellect, text, str(claim.get("fits", "")),
				str(each["from"]), World.production.now() if World.production != null else World.tick,
				Hearsay.is_omen(text, claim.get("omen")), superstition)
			if not entry.is_empty():
				kept.append(entry)
	var gone: Variant = answer.get("overturns", [])
	var overturned := Hearsay.overturn(heard, gone if gone is Array else [])
	if not kept.is_empty() or not overturned.is_empty():
		record.companion["heard"] = heard
		var pet := instance_from_id(int(each["pet"])) as Companion
		if is_instance_valid(pet):
			pet.heard = heard
	MindLog.record({"kind": "claims", "companion": str(each["person"]), "mind": "facts", "trigger": each.get("ask", {}).get("trigger", ""),
		"heard": each["line"], "from": each["from"], "claims": claims, "kept": kept, "overturned": overturned, "intellect": intellect,
		"superstition": superstition, "error": error, "outcome": "weighed" if error.is_empty() else "not weighed"})


## A companion staying in town (as a resident, "companion:<name>"): what she
## has heard and her leanings go onto her worker record, so she gossips and
## is told things like anyone there (decision 442, npc's 422).
func _heard_to_worker(record: PlayerRecord) -> void:
	var who := "companion:%s" % record.companion.get("name", "")
	if World.production == null or World.production.worker(who).is_empty():
		return
	World.production.set_heard(who, record.companion.get("heard", []))
	var traits: Dictionary = record.companion.get("traits", {})
	for key in CompanionCard.LEANINGS:
		World.production.set_mind(who, key, CompanionCard.leaning(traits, record.player_id, key))
	_mood_to_worker(record)


## Her bond's step with her player (decision 555), by her Standing score:
## devoted and close at Standing's top and trusted, wary at its wronged,
## cooling, sullen and apart at companion_traits "loyalty" steps; else fond.
static func bond_step_of(card: Dictionary, player_id: String) -> String:
	var score := Standing.score(card, player_id)
	var steps: Dictionary = Companion.loyalty().get("steps", {})
	if score >= Standing.setting("top"):
		return "devoted"
	if score >= Standing.setting("trusted"):
		return "close"
	if score <= int(steps.get("apart", -7)):
		return "apart"
	if score <= int(steps.get("sullen", -5)):
		return "sullen"
	if score <= Standing.setting("wronged"):
		return "wary"
	if score <= int(steps.get("cooling", -1)):
		return "cooling"
	return "fond"


## Her bond's newest reason in the third person, for the town's talk
## (decision 555, npc's gossip): "they struck her"; "" for none.
static func mood_why_of(card: Dictionary, player_id: String, by := "they") -> String:
	var why: Array = Standing.entry(card, player_id).get("why", [])
	if why.is_empty():
		return ""
	var words := PackedStringArray()
	for word in str(why[-1]).split(" "):
		var said: String = {"you": "her", "your": "her", "yourself": "herself"}.get(word, word)
		words.append("your" if word == "their" and by == "you" else said)
	return by + " " + " ".join(words)


## Her bond moved, or she joined or rests (decision 555): her step on her
## record ("mood"), her body (bond_step), and while she rests the town's
## worker record.
func _set_mood(record: PlayerRecord) -> void:
	if record == null or record.companion.is_empty():
		return
	var step := bond_step_of(record.companion, record.player_id)
	record.companion["mood"] = step
	var pet: Companion = _companions.get(record.player_id)
	if is_instance_valid(pet):
		pet.bond_step = step
		pet.bond_why = mood_why_of(record.companion, record.player_id, "you")
	if record.companion.has("resident"):
		_mood_to_worker(record)


## Her mood and its newest reason onto her worker record while she rests
## (decision 555, for npc's resting body and the town's gossip).
func _mood_to_worker(record: PlayerRecord) -> void:
	var who := "companion:%s" % record.companion.get("name", "")
	if World.production == null or World.production.worker(who).is_empty():
		return
	World.production.set_mood(who, bond_step_of(record.companion, record.player_id), mood_why_of(record.companion, record.player_id))


## She leaves the town with her player again: what she heard there comes
## back with her (decision 442).
func _heard_from_worker(record: PlayerRecord) -> void:
	var who := "companion:%s" % record.companion.get("name", "")
	if World.production == null or World.production.worker(who).is_empty():
		return
	record.companion["heard"] = World.production.worker(who).get("heard", []).duplicate(true)
	World.production.set_mood(who, "", "")  # Out with her player again: no mood for the town (555).


## A resident's answer ([param out]: the ask waited for): said from its
## body, if it is still here and the answer is words; logged either way.
func _resident_answered(out: Dictionary, answer: Dictionary, error: String) -> void:
	var ask: Dictionary = out["ask"]
	var body := instance_from_id(int(out["body"])) as Resident
	# The voice rule, by code too (336 amended): the words said, and one clause of how, apart.
	var pronoun := str(Townsfolk.card_of(World.production, body.worker_id).get("traits", {}).get("pronoun", "")) if body != null else ""
	var spoken := Resident.spoken(Companion.trim_line(str(answer.get("say", "")).strip_edges()), body.person if body != null else "", {"she": "her", "he": "his"}.get(pronoun, "their"))
	var line := str(spoken["say"])
	var aside := str(spoken["aside"])
	var said := body != null and is_instance_valid(body) and body.spawned and not line.is_empty() and line != "..."
	var held := said and _resident_quiet(body, _player_of_id(str(out.get("player", ""))))  # An answer back mid-fight (675, npc's side).
	if held:
		said = false
		_held_tongue("voice")
	MindLog.record({"kind": "voice", "companion": str(ask.get("speaker", "")), "mind": "resident", "trigger": ask.get("trigger", ""),
		"prompt": "%s\n\n%s" % [ask.get("system", ""), ask.get("user", "")], "say": "" if held else line, "aside": "" if held else aside, "error": error,
		"outcome": "held tongue" if held else ("said" if said else "not said")})
	if not said:
		if not str(ask.get("hail", "")).is_empty() and body != null and is_instance_valid(body) and World.production != null:
			# A hail the mind did not answer (554 amended): its marks go back, so the thing can be said later today.
			var player_id := str(out.get("player", ""))
			var cue_text := str(ask.get("cue", ""))
			Resident.hail_undone(World.production, body.worker_id, player_id, cue_text)
			if _hail_heard.has(player_id):
				_hail_heard[player_id].erase(cue_text)
			if str(ask.get("hail", "")) == "greeting" and _hail_greetings.has(player_id):
				_hail_greetings[player_id]["n"] = maxi(int(_hail_greetings[player_id].get("n", 1)) - 1, 0)
		return
	Transcript.record(body.person, body.person, line)
	if not aside.is_empty():
		Transcript.record(body.person, body.person, "[aside] " + aside)
	party_log.add("%s said: \"%s\"%s" % [body.person, line, (" (%s)" % aside) if not aside.is_empty() else ""])
	_heard_near(body, body.person, line)
	_own_tale(body, line, str(ask.get("speaker", "")))
	Net.broadcast_to(hearers(body.tile), "speech", {"entity": String(body.get_path()), "speaker": body.person, "text": line, "aside": aside})
	_send_offers(body, str(out.get("player", "")), int(out.get("peer", -1)))


## A body for [param each] (_sync_residents' entry: key, name, trade,
## player, town, places), where its day puts it now.
func _spawn_resident(each: Dictionary) -> Resident:
	var who: String = each["key"]
	var town: String = each["town"]
	var places: Dictionary = each["places"]
	var trade: String = each["trade"]
	var doing := Resident.Doing.STRAYED if bool(each.get("strayed", false)) else (Resident.Doing.BED if Townsfolk.is_sick(World.production, who) else Resident.doing_now(trade, str(each.get("type", "")), who))
	# On his rounds (the lawspeaker, decision 459) "rounds" is a list of stops:
	# he starts at the hour's stop (as Resident._round_stop has it), or the
	# square with none.
	var spot: Variant = places.get(Resident.PLACE_OF[doing], places.get("square", Rect2i()))
	if spot is Array:
		var stops: Array = spot
		var now := DayNight.now()
		var index := Townsfolk.round_stop(stops.size(), Townsfolk.day_of(now), DayNight.hour(now)) if not stops.is_empty() else -1
		spot = (stops[index] as Dictionary).get("rect", Rect2i()) if index >= 0 and index < stops.size() and stops[index] is Dictionary 				else places.get("square", Rect2i())
	var area: Rect2i = spot if spot is Rect2i else Rect2i()
	var at := _nearest_free(area.get_center() if area.size != Vector2i.ZERO else World.holdings.place(town).get("cell", Vector2i.ZERO))
	if each.get("enter_at") is Vector2i:
		at = _nearest_free(each["enter_at"])  # A visitor just come walks in from the road (711, npc's side).
	var label := Resident.label_of(str(each["name"]), trade)
	# Their look for the character generator (decision 419): a companion
	# resting in town as she looks out with her player (293 amended), the
	# rest from their card (made now if need be, 398).
	var record: PlayerRecord = _records.get(str(each.get("player", "")))
	var look := CompanionCard.look_of(record.companion.get("traits", {}), record.player_id) \
			if record != null and not record.companion.is_empty() else ResidentCard.look_spec(Townsfolk.card_of(World.production, who), trade, str(each.get("type", "")))
	# A companion resting is named by her player's index, as their own body
	# is, never their id (691): the name and its path go to every client.
	var node_name := ("Resident_companion_%d" % record.index) if record != null and who.begins_with(Townsfolk.COMPANION) else ("Resident_" + who).validate_node_name()
	var spec := {"script": RESIDENT, "shape": "capsule", "name": node_name, "label": label, "tile": at, "look": look}
	if not str(each.get("kind", "")).is_empty():
		spec["kind"] = str(each["kind"])  # A goblin among them (decision 471): the client draws the kind's model.
	var body := _spawn(spec) as Resident
	if body == null:
		return null
	body.worker_id = who
	body.player_id = each["player"]
	body.person = str(each["name"])
	body.town_name = str(_world_map.areas.get(World.zone.name, {}).get("display_name", World.zone.name))
	body.card = str(record.companion.get("card", "")) if record != null else ""
	body.town = town
	body.trade = trade
	body.type = str(each.get("type", ""))
	body.places = places
	body.doing = doing
	body.strayed = bool(each.get("strayed", false))
	body.sought = str(each.get("sought", ""))
	body.holder = str(each.get("holder", ""))
	body.where = str(each.get("where", ""))
	if not body.sought.is_empty():
		if each.has("escort"):
			body.start_escort(str(each["escort"]), str(each.get("escort_name", "")))  # Led home: beside its leader, following (613).
		else:
			body.set_meta("sought_waiting", true)  # Waiting to be found: enemy-ai's monsters leave it alone (613).
	return body


## [param area]'s homes for the town at [param place]: its huts and houses
## linked to nothing within HOME_TILES of the store, nearest first, each
## as many times as it has room (HOME_ROOM): a list of insides (Rect2i).
func _homes(area: Dictionary, place: Dictionary) -> Array[Rect2i]:
	var store: Vector2i = place.get("cell", Vector2i.ZERO)
	var found: Array[Dictionary] = []
	for building: Dictionary in area.get("buildings", []):
		var rect: Rect2i = building["rect"]
		if str(building.get("use", "")).is_empty() and HOME_ROOM.has(building["slot"]) \
				and World.distance(rect.get_center(), store) <= HOME_TILES:
			found.append(building)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return World.distance((a["rect"] as Rect2i).get_center(), store) < World.distance((b["rect"] as Rect2i).get_center(), store))
	var out: Array[Rect2i] = []
	for building in found:
		for i in int(HOME_ROOM[building["slot"]]):
			out.append(building["rect"])
	return out


## Where a resident of [param trade] (the [param index]th of its town:
## residents in id order, then companions) goes, in [param area] for the town at [param place]: "work", the
## inside of the standing building its trade works in (none: the square);
## "home", its share of [param homes], else the inn if it stands, else its
## work; "square", the store's ground.
func _resident_places(area: Dictionary, place: Dictionary, trade: String, homes: Array[Rect2i], index: int) -> Dictionary:
	var key := str(place.get("key", ""))
	var radius := int(place.get("radius", 4))
	var store: Vector2i = place.get("cell", Vector2i.ZERO)
	var square := Rect2i(store - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))
	var kind := World.towns.kind_for(trade) if not trade.is_empty() else ""
	var work := Rect2i()
	var inn := Rect2i()
	for building: Dictionary in area.get("buildings", []):
		if str(building.get("town", "")) != key:
			continue
		var standing := str(World.towns.building(str(place.get("id", "")), str(building["use"])).get("state", "")) == Towns.STANDING
		if standing and building["use"] == kind:
			work = building["rect"]
		elif standing and building["use"] == "inn":
			inn = building["rect"]
	var home := homes[index] if index < homes.size() else (inn if inn.size != Vector2i.ZERO else work)
	var out := {"work": work if work.size != Vector2i.ZERO else square, "home": home if home.size != Vector2i.ZERO else square,
		"square": square}
	# The routine's other places (decision 404): the inn when linked and
	# standing, the temple and the well by their slots (no "use" or town of
	# their own yet, buildings' word), the nearest within HOME_TILES of the
	# store; a place the town lacks stays out, and the body keeps to the square.
	if inn.size != Vector2i.ZERO:
		out["inn"] = inn
	for want: Array in [["temple", "building.temple"], ["well", "building.well"]]:
		var best := Rect2i()
		for building: Dictionary in area.get("buildings", []):
			var rect: Rect2i = building.get("rect", Rect2i())
			if str(building.get("slot", "")) == want[1] and World.distance(rect.get_center(), store) <= HOME_TILES \
					and (best.size == Vector2i.ZERO or World.distance(rect.get_center(), store) < World.distance(best.get_center(), store)):
				best = rect
		if best.size != Vector2i.ZERO:
			# A 1x1 on water (the well) is stood beside, not in.
			out[want[0]] = best if want[0] != "well" else best.grow(1)
	if trade == "priest" and out.has("temple"):
		out["work"] = out["temple"]
	return out


## The companion of player [param player_id] is held by raid group
## [param by] (decision 314): her record says so ("taken": {by, zone, at}),
## so she is not spawned (_join_companion); a resident leaves her town's
## work. Called on World.entity_taken, and by Towns for a resident taken in
## a raid on a town nobody is in. False if that player has no companion.
func companion_taken(player_id: String, by: String) -> bool:
	var record: PlayerRecord = _records.get(player_id)
	if record == null or record.companion.is_empty():
		return false
	var resident: Dictionary = record.companion.get("resident", {})
	if not resident.is_empty() and World.towns != null:
		_heard_from_worker(record)
		World.towns.note_companion_out(str(resident.get("place", "")), String(record.companion.get("name", "")))
	record.companion.erase("resident")
	record.companion["taken"] = {"by": by, "zone": World.zone.name if World.zone != null else "", "at": World.steps}
	record.companion["tile"] = null
	print("[raids] %s's companion %s is held by %s" % [record.name, record.companion.get("name", "?"), by])
	return true


## The companion of player [param player_id] let go by whoever holds her
## (672 amended, the admin's quest reset): her record's "taken" cleared (she
## comes at the next join), and no raid group (Raids) or town (Towns) holds
## her as a captive any more, so no later rescue or beaten group frees her
## twice. No bond, fact or rescue. What was cleared, for the reset's line.
func companion_let_go(player_id: String) -> Array[String]:
	var out: Array[String] = []
	var record: PlayerRecord = _records.get(player_id)
	if record != null and record.companion.has("taken"):
		record.companion.erase("taken")
		record.companion["tile"] = null
		out.append("companion let go by the raiders")
	var who := "companion:%s" % player_id
	if World.raids != null and World.raids.drop_captive(who):
		out.append("a raid group's captive")
	if World.towns != null and World.towns.drop_captive(who):
		out.append("a camp's captive")
	return out


## The companion of player [param player_id] is freed from the raiders who
## held her (decision 314): with [param place] (a stockpile place, the
## town that freed her) she rests there, a resident working her trade, till
## her player comes (as _rest_in_town); without (her captors beaten), she
## comes back beside her player, at once if they are in this zone, else the
## next time they are put down. A fact about her either way.
## False if she was not held.
func companion_freed(player_id: String, place := "") -> bool:
	var record: PlayerRecord = _records.get(player_id)
	if record == null or not record.companion.has("taken"):
		return false
	record.companion.erase("taken")
	record.companion["tile"] = null
	_bond(record, "rescued", "carried you out of the raiders' camp")
	var pet_name := str(record.companion.get("name", "?"))
	var town := ""
	if not place.is_empty() and World.holdings != null and not World.holdings.place(place).is_empty():
		var trade := str(record.companion.get("traits", {}).get("trade", ""))
		var zone := str(World.holdings.place(place).get("area", ""))
		record.companion["resident"] = {"place": place, "zone": zone, "trade": trade}
		record.companion["home"] = record.companion["resident"].duplicate()
		if not trade.is_empty() and World.towns != null:
			World.towns.note_companion_in(place, pet_name, trade, player_id)
			_heard_to_worker(record)
		town = str(Level.load_level(zone).get("display_name", zone)) if Level.exists(zone) else zone
	var grown := CompanionFacts.from_record(record.companion.get("facts", []), record.companion.get("beliefs", []))
	grown.add_fact("%s was freed from the raiders%s." % [pet_name, " and brought to " + town if not town.is_empty() else ""],
		"event", player_id)
	record.companion["facts"] = grown.facts
	record.companion["beliefs"] = grown.beliefs
	print("[raids] %s's companion %s is free%s" % [record.name, pet_name, " in " + town if not town.is_empty() else ""])
	party_log.add("%s is free%s." % [pet_name, " and waits in " + town if not town.is_empty() else ""])
	if town.is_empty():
		# Freed in the field (her captors beaten): back beside her player at
		# once, if they are here.
		for peer: int in _players:
			var player: Player = _players[peer]
			var id: String = _peer_ids.get(peer, Net.player_id if peer == Net.local_id else Net.player_of(peer))
			if id == player_id and is_instance_valid(player) and player.spawned and player.zone == World.zone.name:
				_join_companion(record, player)
	return true


## A rebuilt room starts whole: companions that died come back with it, at
## full stats, beside their owner the next time that player is put down.
## Nothing else brings a dead companion back. Returns who came back.
func _revive_companions(zone_name := "") -> Array[String]:
	var revived: Array[String] = []
	for record: PlayerRecord in _records.values():
		if record.companion.is_empty() or record.companion.get("alive", true):
			continue
		if not zone_name.is_empty() and record.zone not in [zone_name, ""]:
			continue  # Another zone's rebuild brings them back.
		record.companion["alive"] = true
		record.companion["hp"] = 0  # Not a saved value: spawn at full stats.
		record.companion["tile"] = null  # No place of its own: beside its owner.
		revived.append("%s (%s's)" % [record.companion.get("name", "?"), record.name])
		print("[world] %s's companion %s is back" % [record.name, record.companion.get("name", "")])
	return revived


## Gives the companion in [param record] her traits (CompanionCard.roll,
## decision 293) if she has none: a new one's name rolled too, not one
## another record's companion has; one from before keeps hers. Her card is
## then her traits as plain facts until the written one comes (card_by
## "plain"; "model" once written).
func _give_traits(record: PlayerRecord) -> void:
	if record.companion.get("traits") is Dictionary and not record.companion["traits"].is_empty():
		return
	var taken: Array[String] = []
	for other: PlayerRecord in _records.values():
		if other != record and other.companion.get("name") is String:
			taken.append(str(other.companion["name"]))
	var kept := str(record.companion.get("name", "")) if record.companion.get("name") is String else ""
	var traits := CompanionCard.roll(record.player_id, kept, taken)
	record.companion["name"] = traits["name"]
	record.companion["traits"] = traits
	record.companion["card"] = CompanionCard.plain_card(traits)
	record.companion["card_by"] = "plain"
	var met := CompanionCard.met(traits, record.name)
	record.companion["how_we_met"] = met.left(1).to_upper() + met.substr(1) + "."
	print("[net] %s's companion %s: traits rolled (%s, %s)" % [record.name, traits["name"], traits["profession"], traits["temperament"]])


## What has become true of her changed (decision 294): kept in her record
## at once, with the talk not yet read for it.
func _on_facts_changed(pet: Companion, record: PlayerRecord) -> void:
	record.companion["facts"] = pet.grown.facts.duplicate(true)
	record.companion["beliefs"] = pet.grown.beliefs.duplicate(true)
	record.companion["talk"] = Array(pet.talk)


## Her card came back from the voice model: kept in her record.
func _on_card_written(pet: Companion, record: PlayerRecord) -> void:
	record.companion["card"] = pet.card
	record.companion["how_we_met"] = pet.how_we_met
	record.companion["card_by"] = pet.card_by


## Her player gone from her without her (left the game, or travelled on
## while she was told to stay): on ground of a stockpile the town holds,
## with a trade, she stays as one of its residents and works
## (Towns.note_companion_in), until her player comes back to her zone
## (_join_companion). The place and zone are kept in her record. False if
## she does not.
## A home for a record without one (decision 400: Wren worked in the
## castle's town, but her record was saved without "home" and she could not
## say so): the town her worker record ("companion:<her name>", Towns')
## names, as {place, zone, trade}. Nothing when it names none.
func _fill_home(record: PlayerRecord) -> void:
	if World.production == null or World.holdings == null:
		return
	var worker := World.production.worker("companion:%s" % record.companion.get("name", ""))
	var place := str(worker.get("town", ""))
	var zone := str(World.holdings.place(place).get("area", "")) if not place.is_empty() else ""
	if zone.is_empty():
		return
	var trades: Array = worker.get("trades", [])
	var trade := str(trades[0]) if not trades.is_empty() else str(record.companion.get("traits", {}).get("trade", ""))
	record.companion["home"] = {"place": place, "zone": zone, "trade": trade}


## The town store place whose town takes in [param cell] of zone
## [param zone_name], or "" (694 amended: Jeff logged out in the wilds'
## town square, nine cells from the store, and Pip did not rest): the
## store's own ground (Stockpile.place_at), or a named room of the level
## (its "rooms", as the town's name and music have it: Umbrage, the wilds'
## town) that takes in both the cell and a store the town holds.
func _town_ground(zone_name: String, cell: Vector2i) -> String:
	if World.holdings == null:
		return ""
	var place := Stockpile.place_at(World.holdings, zone_name, cell)
	if not place.is_empty():
		return place
	var rooms := _rooms_of(zone_name)
	for key: String in rooms:
		var rects: Array = rooms[key].get("rects", [])
		if not rects.any(func(rect: Rect2i) -> bool: return rect.has_point(cell)):
			continue
		for id in World.holdings.places_in(zone_name):
			var each := World.holdings.place(id)
			if each["kind"] == Stockpile.KIND and World.holdings.holder(id) == Stockpile.TOWN \
					and rects.any(func(rect: Rect2i) -> bool: return rect.has_point(each["cell"])):
				return id
	return ""


## Zone [param zone_name]'s level's named rooms (Level.room_at's): the
## level open now, an open zone's, else read once and kept.
func _rooms_of(zone_name: String) -> Dictionary:
	if World.zone != null and World.zone.name == zone_name and level.get("rooms") is Dictionary:
		return level["rooms"]
	var zone: Zone = World.zones.get(zone_name)
	if zone != null and zone.main.get("level", {}).get("rooms") is Dictionary:
		return zone.main["level"]["rooms"]
	if not _rooms_read.has(zone_name):
		var read := Level.load_level(zone_name) if Level.exists(zone_name) else {}
		_rooms_read[zone_name] = read.get("rooms", {}) if read.get("rooms") is Dictionary else {}
	return _rooms_read[zone_name]


func _stay_in_town(record: PlayerRecord, pet: Companion) -> bool:
	if World.towns == null or World.holdings == null or record.companion.is_empty():
		return false
	var pet_name := String(record.companion.get("name", pet.name))
	var place := _town_ground(pet.zone, pet.tile)
	var trade := str(record.companion.get("traits", {}).get("trade", ""))
	if place.is_empty() or trade.is_empty():
		return false
	World.towns.note_companion_in(place, pet_name, trade, record.player_id)
	_heard_to_worker(record)
	record.companion["resident"] = {"place": place, "zone": World.zone.name, "trade": trade}
	record.companion["home"] = record.companion["resident"].duplicate()
	pet.works_as = trade
	pet.home = record.companion["home"]
	print("[town] %s's companion %s stays in %s and works as its %s" % [record.name, pet_name, place, trade])
	party_log.add("%s stays in the town and works as its %s." % [pet_name, trade])
	return true


## A companion from before the roll (Wren, Nix: CompanionCard.is_legacy)
## rests in town between trips: her player gone from the game, she goes
## to the first stockpile the town holds, a resident there, working her
## trade if she has one, until her player comes to that zone
## (_join_companion). Nowhere for her (no town holds a stockpile yet), she
## waits where she is, as any companion.
func _rest_in_town(record: PlayerRecord, pet: Companion, id: String, at := "", told := true) -> bool:
	if World.towns == null or World.holdings == null:
		return false
	var place := at if not at.is_empty() else _first_town()
	if place.is_empty():
		return false
	var pet_name := String(record.companion.get("name", pet.name))
	var trade := str(record.companion.get("traits", {}).get("trade", ""))
	if not trade.is_empty():
		World.towns.note_companion_in(place, pet_name, trade, record.player_id)
		_heard_to_worker(record)
	record.companion["resident"] = {"place": place, "zone": str(World.holdings.place(place).get("area", "")), "trade": trade}
	record.companion["home"] = record.companion["resident"].duplicate()
	record.companion["tile"] = null  # Wherever she rests: beside her player when they come.
	_travelling = true  # She leaves; she does not die.
	World.despawn(pet)
	_travelling = false
	_companions.erase(id)
	print("[town] %s's companion %s rests in %s between trips" % [record.name, pet_name, place])
	if told:
		party_log.add("%s goes back to the town to rest." % pet_name)
	return true


## The console's `mind claude` ([param args] after it, decision 363): with
## none, who is on Claude and the session's spend; with a companion's name
## (or "all") and haiku, sonnet or off, her voice wrapped in a ClaudeMind or
## unwrapped. Never without ANTHROPIC_API_KEY set.
func _mind_claude(args: Array) -> String:
	if args.is_empty():
		var lines: Array[String] = []
		for id: String in _companions:
			var pet: Companion = _companions[id]
			if is_instance_valid(pet):
				var claude := pet.mind as ClaudeMind
				lines.append("%s: %s" % [pet.name, ("%s%s" % [claude.model, " (off: the key was refused)" if claude.off else ""]) if claude != null else "off"])
		lines.append("spent this session: " + ClaudeMind.spend_words())
		return "\n".join(lines)
	if args.size() < 2 or str(args.back()) not in ["haiku", "sonnet", "off"]:
		return "usage: mind claude [<name>|all haiku|sonnet|off]"
	var choice := str(args.back())
	if choice != "off" and not ClaudeMind.has_key():
		return "no ANTHROPIC_API_KEY in this process's environment: set it where the server runs, never in a file of the game's"
	var who := " ".join(args.slice(0, -1)).to_lower()
	var changed: Array[String] = []
	for id: String in _companions:
		var pet: Companion = _companions[id]
		if not is_instance_valid(pet) or who != "all" and String(pet.name).to_lower() != who:
			continue
		var own: CompanionMind = pet.mind
		if pet.mind is ClaudeMind:
			own = (pet.mind as ClaudeMind).inner
			(pet.mind as ClaudeMind).close()
		if choice == "off":
			_claude_voices.erase(id)
			pet.mind = own
		else:
			_claude_voices[id] = ClaudeMind.MODELS[choice]
			pet.mind = ClaudeMind.new(own, ClaudeMind.MODELS[choice], self)
		changed.append(String(pet.name))
	if changed.is_empty():
		return "no companion named %s" % who
	return "%s: voice %s" % [", ".join(changed), "on her own mind" if choice == "off" else "on " + ClaudeMind.MODELS[choice]]


func _make_mind() -> CompanionMind:
	if mind_kind == "ollama" and Net.llm_url != "" and Net.llm_model != "":
		return OllamaMind.new(Net.llm_url, Net.llm_model, self, Net.voice_url, Net.voice_model)
	return ScriptedMind.new()


func _remember_companion(id: String) -> void:
	var pet: Companion = _companions.get(id)
	var record: PlayerRecord = _records.get(id)
	if record == null or not is_instance_valid(pet) or not pet.spawned:
		return
	record.companion["hp"] = pet.hp
	record.companion["stamina"] = pet.stamina
	record.companion["tile"] = [pet.tile.x, pet.tile.y]
	record.companion["tile_zone"] = pet.zone  # (Her tile is in this zone; elsewhere she comes beside her player.)
	record.companion["alive"] = true
	record.companion["said"] = pet.said_lines()
	record.companion["slots"] = Array(pet.slots)
	record.companion["items"] = Array(World.slot_uids(pet))


## "say" {text}: chat, typed or a quick phrase (_player_said).
## "reset": rebuild the room, as the console's reset does. From the
## authority's own player always; from anyone else only while
## Net.player_reset is on.
func _on_command(entity: GridEntity, command_name: String, args: Dictionary) -> void:
	# Led by her (decision 551): doing anything but talk takes control back.
	if entity is Player and command_name not in ["say", "party", "guide", "face", "greet"]:
		var walk: Guide = _guides.get(_peer_ids.get(entity.owner_peer, ""))
		if walk != null and walk.going() and is_instance_valid(walk.pet):
			_guide_done(walk.pet, "moved")
	# Arriving (decision 661): anything but talk and looking ends the shelter.
	if entity is Player and command_name not in SHELTER_KEEPS and World.is_sheltered(entity):
		entity.protected = false
	if command_name == "view_ready" and entity is Player:
		_view_ready(entity as Player, str(args.get("zone", "")))
	elif command_name == "guide" and entity is Player:
		if args.has("stop"):
			_guide_stop_asked(entity, str(args["stop"]))  # Their own key or click took over her route (695).
		else:
			_guide_asked(entity, str(args.get("to", "")))
	elif command_name == "greet" and entity is Player:
		var hailed := get_node_or_null(NodePath(str(args.get("resident", ""))))
		if hailed is Resident:
			_greeted(entity, hailed as Resident)  # A click on a townsperson (decision 560, npc's side).
		elif hailed != null and hailed.has_method("offers_for"):
			_monster_greeted(entity, hailed as GridEntity)  # E on a talking monster (decision 629): his deal, spoken and sent.
	elif command_name == "make_way" and entity is Player:
		_make_way(entity, get_node_or_null(NodePath(str(args.get("target", "")))) as Companion)
	elif command_name == "say" and entity is Player:
		_player_said(entity, str(args.get("text", "")), int(args.get("phrase", 0)))
	elif command_name == "party" and entity is Player:
		_party_said(entity, str(args.get("text", "")))
	elif command_name == "bandage" and entity is Player:
		var patient := get_node_or_null(NodePath(str(args.get("target", "")))) as GridEntity
		if patient != null and World.is_downed(patient):
			_start_channel(entity, patient)  # Held E on the downed: the return (decision 544).
		elif patient != null and not World.try_bandage(entity, patient):
			_tell_bandage_refused(entity, patient)
	elif command_name == "slow_heart" and entity is Player:
		_slow_heart(entity as Player, bool(args.get("held", false)))
	elif command_name == "bleed_out" and entity is Player:
		if World.is_downed(entity):
			World.damage(entity, entity.hp, null, &"bled")  # Bleed Out (Mortally Wounded): the return follows at once.
	elif command_name == "search" and entity is Player:
		search(entity, get_node_or_null(NodePath(str(args.get("target", "")))) as Chest)
	elif command_name == "use" and entity is Player:
		World.try_use(entity, int(args.get("slot", -1)))
	elif command_name == "retain" and entity is Player:
		retain(entity as Player, args)
	elif command_name == "give_gold" and entity is Player:
		give_gold(entity as Player, args)
	elif command_name == "town_sheet" and entity is Player:
		ask_town_sheet(entity as Player, args)
	elif command_name == "stance" and entity is Player:
		var stance := str(args.get("kind", ""))
		var toward := _point_direction(entity, args)
		if World.try_stance(entity, stance, bool(args.get("lob", false))) and stance == "block" and toward != Vector2i.ZERO:
			World.face(entity, toward)  # The shield toward the cursor (decision 593).
	elif command_name == "signature" and entity is Player:
		# Ctrl and a click (decision 593): the body that way, beside it.
		var way := _point_direction(entity, args)
		var marked := World.get_entity_at(entity.tile + way) if way != Vector2i.ZERO else null
		if marked != null:
			World.order_signature(entity, marked)
	elif command_name == "apply_item" and entity is Player:
		# The thing on the cursor, applied by a click (decision 593): a bandage.
		var on := get_node_or_null(NodePath(str(args.get("target", "")))) as GridEntity
		var slot := int(args.get("slot", -1))
		if on != null and slot >= 0 and slot < entity.slots.size() and Items.def(entity.slots[slot]).get("use") == "bandage":
			if World.is_downed(on):
				_start_channel(entity, on)
			elif not World.try_bandage(entity, on):
				_tell_bandage_refused(entity, on)
	elif command_name == "lob" and entity is Player:
		# Its "at" cell (decision 677): where the lob is aimed.
		var at: Variant = args.get("at")
		if at is Array and (at as Array).size() == 2:
			World.try_lob(entity, Vector2i(int(at[0]), int(at[1])))
		else:
			World.try_stance(entity, "")
	elif command_name == "loose" and entity is Player:
		# Its "angle" (radians on the grid; decision 583), else the
		# angle to its "at" cell.
		var angle: Variant = args.get("angle")
		var at: Variant = args.get("at")
		if angle is float or angle is int:
			World.try_loose(entity, float(angle))
		elif at is Array and (at as Array).size() == 2:
			World.try_loose(entity, Vector2(Vector2i(int(at[0]), int(at[1])) - entity.tile).angle())
	elif command_name in ["pick_up", "drop", "throw"] and entity is Player:
		_item_command(entity, command_name, args)
	elif command_name == "lantern" and entity is Player:
		(entity as Player).toggle_lantern()
	elif command_name == "swing" and entity is Player:
		var swing := _point_direction(entity, args) if args.has("at") else _direction_arg(args)
		if swing != Vector2i.ZERO:
			World.order_swing(entity, swing)
	elif command_name == "face":
		var facing := _direction_arg(args)
		if facing != Vector2i.ZERO:
			World.face(entity, facing)
	elif command_name == "transfer":
		var from := get_node_or_null(NodePath(str(args.get("from", "")))) as GridEntity
		var to := get_node_or_null(NodePath(str(args.get("to", "")))) as GridEntity
		if from != null and to != null and not _relic_handed(entity, from, int(args.get("from_slot", -1)), to):
			World.try_transfer(entity, from, int(args.get("from_slot", -1)), to, int(args.get("to_slot", -1)), int(args.get("count", 0)))
	elif command_name == "door":
		var edge: Variant = args.get("edge")
		if edge is Array and edge.size() == 3:
			var key := Vector3i(int(edge[0]), int(edge[1]), int(edge[2]))
			var held := World.door_on(key)
			if held != null and not held.open and held.lock == HALL_LOCK and entity is Player:
				Net.broadcast_to([entity.owner_peer], "party", {"from": "Server", "text": "The door is shut."})
			elif held != null and not held.open and held.lock == DEAD_LOCK and entity is Player:
				Net.broadcast_to([entity.owner_peer], "party", {"from": "Server", "text": DEAD_LINE})
			if held != null and World.niche_edges.get(key, "") == "hidden" and not held.open:
				_on_niche_pressed(entity, key)  # E at the hidden niche presses on it (608).
				return
			World.try_toggle_door(entity, key)
	elif command_name == "shop" and entity is Player:
		var shop := get_node_or_null(NodePath(str(args.get("shop", "")))) as GridEntity
		if shop == null or not World.reaches(entity, shop):
			return
		if str(args.get("do", "")) == "buy":
			World.try_buy(entity, shop, int(args.get("uid", 0)))  # Answered by traded.
		else:
			_send_shop(entity as Player, shop)
	elif command_name in ["barter", "trade"] and entity is Player:
		# Barter at a shop's counter (decision 560), or with a maker (562: a
		# "resident" in place of "shop"): look, or trade all or nothing.
		var maker := ""
		var shop: GridEntity = null
		var why := ""
		if args.has("resident"):
			var body := get_node_or_null(NodePath(str(args.get("resident", "")))) as Resident
			if body == null or World.production == null or World.production.worker(body.worker_id).is_empty():
				return
			maker = body.worker_id
			shop = body
			why = "" if World.reaches(entity, body) else "too far away"
		else:
			shop = get_node_or_null(NodePath(str(args.get("shop", "")))) as GridEntity
			if shop == null:
				return
			why = "" if _barter_reach(entity, shop) else "too far from the counter"
		if command_name == "trade" and why.is_empty():
			var give: Variant = args.get("give", [])
			var take: Variant = args.get("take", [])
			why = World.try_barter(entity, shop, give if give is Array else [], take if take is Array else [], int(args.get("gold", 0)), maker)
		_send_barter(entity as Player, shop, why, maker)
	elif command_name == "counter" and entity is Player:
		# A temple's or a shop's counter's work (decision 438): look, order, collect.
		var counter := get_node_or_null(NodePath(str(args.get("counter", "")))) as GridEntity
		if counter == null or not World.reaches(entity, counter) or World.counter_kind(counter).is_empty():
			return
		var why := ""
		match str(args.get("do", "look")):
			"order":
				why = World.counter_order(entity, counter, int(args.get("slot", -1)), str(args.get("effect", "")), str(args.get("to_id", "")))
			"collect":
				why = World.counter_collect(entity, counter, int(args.get("uid", 0)))
		_send_counter(entity as Player, counter, why)
	elif command_name == "offers" and entity is Player:
		# The talk panel opens on a resident (decision 435): their offers.
		var asked := get_node_or_null(NodePath(str(args.get("entity", ""))))
		var body := asked as Resident
		if body != null and body.spawned and World.distance(body.tile, entity.tile) <= HEARING_RANGE:
			_send_offers(body, (entity as Player).player_id, entity.owner_peer)
		elif asked != null and asked.has_method("offers_for") and asked.spawned and World.distance(talk_cell(asked), entity.tile) <= HEARING_RANGE:
			_send_monster_offers(asked as GridEntity, (entity as Player).player_id, entity.owner_peer)  # A talking monster's deals asked again (decision 629).
	elif command_name == "offer" and entity is Player:
		_accept_offer(entity as Player, str(args.get("id", "")), int(args.get("gold", 0)))
	elif command_name == "reset" and entity is Player:
		var who := _display_name(entity)  # The rebuild frees the entity.
		if not Net.player_reset and entity.owner_peer != Net.local_id:
			print("[world] %s asked for a reset; players may not (--no-player-reset)" % who)
			return
		print("[world] %s reset the room" % who)
		_start_level()
		party_log.add("%s reset the room." % who)
	elif command_name == "admin" and entity is Player:
		_admin_from(entity as Player, str(args.get("line", "")))
	elif command_name == "builder" and entity is Player:
		var id: String = _peer_ids.get(entity.owner_peer, Net.player_id if entity.owner_peer == Net.local_id else "")
		if _builder == null:
			Net.broadcast_to([entity.owner_peer], "builder", {"state": "error", "error": "builder mode is off on this server"})
		else:
			_builder.command(entity.owner_peer, id, entity.zone, args)


## {"dir": [x, y]} as one of the eight directions, or ZERO.
static func _direction_arg(args: Dictionary) -> Vector2i:
	var raw: Variant = args.get("dir")
	if raw is not Array or raw.size() != 2:
		return Vector2i.ZERO
	var direction := Vector2i(int(raw[0]), int(raw[1]))
	return direction if direction in World.DIRECTIONS else Vector2i.ZERO


## The way from [param entity] to a command's "at" ([x, y], a ground point
## in grid units, decision 593), snapped to one of the eight; ZERO for none.
## The body a swing where [param player] stands, toward [param cursor] (a
## ground point), would strike: World.stand_target by name (it reads only
## what a client mirrors: the occupancy, the slots, the terrain, the
## peers), with the direction the Shift swing's command takes
## (_point_direction); null for none, or before it lands.
static func stand_target_now(player: GridEntity, cursor: Vector2) -> GridEntity:
	if player == null or not World.has_method("stand_target") or not cursor.is_finite():
		return null
	var direction := grid_direction(cursor - Vector2(player.tile))
	if direction == Vector2i.ZERO:
		return null
	return World.call("stand_target", player, direction) as GridEntity


## Combat's (c): while the stand key is held with a weapon to swing (a
## bow draws instead), the body the swing would strike is ringed at its
## feet (Client3D.stand_ring); none, no ring.
func _show_stand_ring(player: Player) -> void:
	var body: GridEntity = null
	if player != null and Keys.held("stand") and World.off_hand(player) != "draw":
		body = stand_target_now(player, _mouse_grid())
	if body != null:
		_client3d.stand_ring(body.tile, true)
	else:
		_client3d.stand_ring(Vector2i.ZERO, false)


static func _point_direction(entity: GridEntity, args: Dictionary) -> Vector2i:
	var raw: Variant = args.get("at")
	if raw is not Array or raw.size() != 2:
		return Vector2i.ZERO
	var point := Vector2(float(raw[0]), float(raw[1]))
	if not point.is_finite():
		return Vector2i.ZERO
	return grid_direction(point - World.shot_origin(entity))  # A free body's own centre (688).


## The talk panel (Tab) and the chat box (Enter), on the HUD.
func _build_talk() -> void:
	bubbles = SpeechBubbles.new()
	bubbles.name = "Bubbles"
	bubbles.anchor_of = _bubble_anchor
	bubbles.tile_px = _bubble_tile_px
	$HUD.add_child(bubbles)
	$HUD.move_child(bubbles, 0)
	compass = HudCompass.new()
	compass.name = "Compass"
	$HUD.add_child(compass)
	hint_panel = HintPanel.new()
	hint_panel.name = "Hints"
	hint_panel.visible = Net.hints
	$HUD.add_child(hint_panel)
	options_panel = OptionsPanel.new()
	options_panel.name = "Options"
	options_panel.visible = false
	options_panel.hints_changed.connect(func(shown: bool) -> void:
		if hint_panel != null:
			hint_panel.visible = shown)
	# Over the HUD and the main menu both (Jeff, 2026-10-22: the menu blocked the
	# options screen): on a canvas layer of its own above them (a Control under
	# Main alone would sit in the world's canvas, scaled by the camera).
	_options_layer = CanvasLayer.new()
	_options_layer.name = "OptionsLayer"
	_options_layer.layer = OPTIONS_LAYER
	add_child(_options_layer)
	_options_layer.add_child(options_panel)
	pack_panel = PackPanel.new()
	pack_panel.name = "Pack"
	pack_panel.transfer = _transfer
	pack_panel.sound = _sound
	pack_panel.use = use_slot
	item_icons = ItemIcons.new()
	item_icons.name = "ItemIcons"
	add_child(item_icons)
	pack_panel.icons = item_icons
	$HUD.add_child(pack_panel)
	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.marks = _minimap_marks
	$HUD.add_child(minimap)
	if not level.is_empty():
		_door_marks_at = -1  # A new level: its doors.
		minimap.rebuild(level)
	minimap.big = Net.test_minimap
	shop_panel = ShopPanel.new()
	shop_panel.name = "Shop"
	shop_panel.pack = pack_panel
	shop_panel.buy = _buy
	$HUD.add_child(shop_panel)
	ui_sounds = UiSounds.new()
	ui_sounds.name = "UiSounds"
	ui_sounds.sfx_of = func() -> Sfx: return _client3d.sfx if _client3d != null else null
	add_child(ui_sounds)
	ui_sounds.watch(options_panel)
	ui_sounds.watch(pack_panel)
	shop_panel.refused.connect(func(_why: String) -> void: ui_sounds.play("ui.error"))
	shop_panel.box_shown = false  # 560, ui's side: the barter window shows the goods.
	# 560, ui's side: the barter window beside the pack, fed by economy's
	# barter message (Main.barter_told, connected by name so either side
	# lands first), and the talk bar under a greeting resident's bubble.
	barter_panel = BarterPanel.new()
	barter_panel.name = "Barter"
	barter_panel.pack = pack_panel
	barter_panel.trade_asked.connect(_trade)
	barter_panel.care_asked.connect(_retain)
	barter_panel.refused.connect(func(_why: String) -> void: ui_sounds.play("ui.error"))
	$HUD.add_child(barter_panel)
	if has_signal("barter_told"):
		connect("barter_told", _on_barter_told)
	down_screen = DownScreen.new()
	down_screen.name = "DownScreen"
	down_screen.slow_heart.connect(_ask_slow_heart)
	down_screen.bleed_out.connect(_ask_bleed_out)
	$HUD.add_child(down_screen)
	arrival_card = ArrivalCard.new()  # 660, ui's side.
	$HUD.add_child(arrival_card)
	# Combat's ground telegraphs (602, ui's side), connected by name so either side lands first.
	if has_signal("telegraph_started"):
		connect("telegraph_started", _on_telegraph_started)
	if has_signal("telegraph_ended"):
		connect("telegraph_ended", _on_telegraph_ended)
	_bar = PanelContainer.new()
	_bar.name = "TalkBar"
	_bar.visible = false
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", UiTheme.constant("row"))
	_bar.add_child(bar_row)
	_bar_name = Label.new()
	_bar_name.theme_type_variation = &"Heading"
	_bar_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_bar_name)
	var bar_talk := Button.new()
	bar_talk.text = "Talk"
	bar_talk.focus_mode = Control.FOCUS_NONE
	bar_talk.pressed.connect(_bar_talk_pressed)
	bar_row.add_child(bar_talk)
	_bar_barter = Button.new()
	_bar_barter.text = "Barter"
	_bar_barter.focus_mode = Control.FOCUS_NONE
	_bar_barter.pressed.connect(_bar_barter_pressed)
	bar_row.add_child(_bar_barter)
	$HUD.add_child(_bar)
	talk = TalkPanel.new()
	talk.line_added.connect(_line_sound)
	talk.anchor_left = 0.0
	talk.anchor_top = 1.0
	talk.anchor_bottom = 1.0
	talk.offset_left = UiTheme.constant("margin")
	talk.offset_bottom = -UiTheme.constant("margin")
	talk.grow_vertical = Control.GROW_DIRECTION_BEGIN
	$HUD.add_child(talk)
	_chat_box = LineEdit.new()
	_chat_box.name = "ChatBox"
	_chat_box.max_length = CHAT_MAX_CHARS
	_chat_box.placeholder_text = "say it aloud (Tab: party; Enter sends, Esc cancels)"
	_chat_box.visible = false
	_chat_box.text_submitted.connect(_send_chat)
	_chat_box.gui_input.connect(func(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key != null and key.pressed and key.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
		elif key != null and key.pressed and Keys.matches(key.keycode, "talk_log"):
			# The channel swapped, the cursor kept: the key never leaves the box.
			_swap_chat_channel()
			_chat_box.accept_event())
	talk.set_box(_chat_box)
	counter_panel = CounterPanel.new()
	counter_panel.order_pressed.connect(_order_at_counter)
	counter_panel.collect_pressed.connect(_collect_at_counter)
	$HUD.add_child(counter_panel)
	counter_told.connect(_on_counter_told)
	world_map_panel = WorldMapPanel.new()
	world_map_panel.guide_asked.connect(_ask_guide)  # The map's "ask her to lead you there" (551).
	$HUD.add_child(world_map_panel)
	if has_signal("world_changed"):
		connect("world_changed", _refresh_world_map)
	card_page = CardPage.new()
	$HUD.add_child(card_page)
	if has_signal("world_changed"):
		connect("world_changed", _refresh_card)  # 618: her page follows the world message while open.
	town_panel = TownSheet.new()
	$HUD.add_child(town_panel)
	deal_panel = DealPanel.new()
	$HUD.add_child(deal_panel)
	admin_panel = AdminPanel.new()  # 672.
	admin_panel.ran.connect(send_admin)
	$HUD.add_child(admin_panel)
	tuning_panel = TuningPanel.new()  # 673, ui's side.
	tuning_panel.player = _local_player
	tuning_panel.reset_hall.connect(_reset_hall)
	tuning_panel_toggled.connect(tuning_panel.toggle)
	$HUD.add_child(tuning_panel)
	deal_panel.offered.connect(_offer_deal)  # 629, ui's side: a button sends his deal's id with its sum.
	note_sheet = NoteSheet.new()  # 643, ui's side: a note on a door, read.
	$HUD.add_child(note_sheet)
	_note_hover = Label.new()
	_note_hover.name = "NoteHover"
	_note_hover.theme_type_variation = &"Caption"
	_note_hover.text = NoteSheet.HOVER_WORD
	_note_hover.visible = false
	_note_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_note_hover)
	world_map_panel.town_clicked.connect(open_town)  # 624: a town's row on the map opens its sheet.
	if has_signal("world_changed"):
		connect("world_changed", _refresh_town)  # 624: the sheet follows the world message while open.
	_context_hint = Label.new()
	_context_hint.name = "ContextHint"
	_context_hint.theme_type_variation = &"Outlined"
	_context_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_context_hint.visible = false
	$HUD.add_child(_context_hint)


## Tab in the chat box: a line for the party becomes one said aloud and
## back (PARTY_PREFIX), the caret at the end.
func _swap_chat_channel() -> void:
	if _chat_box.text.begins_with(PARTY_PREFIX.strip_edges()):
		_chat_box.text = _chat_box.text.trim_prefix(PARTY_PREFIX.strip_edges()).strip_edges()
	else:
		_chat_box.text = PARTY_PREFIX + _chat_box.text
	_chat_box.caret_column = _chat_box.text.length()


## --test-show=hidden: registers "ui_meadow", a grass field with a patch of
## tall grass (tall_grass_test's shape) and no monster, and starts there,
## so a shot can show the cover cue: --test-contest walks the player into
## the patch (x 4 to 7, y 2 to 5) and the HUD says it once they stand.
func _register_test_meadow() -> void:
	var rows: Array[String] = []
	for y in 2 * 8 - 1:
		rows.append(".".repeat(2 * 12 - 1))
	var markers := {Vector2i(1, 4): "start"}
	var patch := Rect2i(4, 2, 4, 4)
	for y in range(1, 7):
		for x in range(2, 10):
			markers[Vector2i(x, y)] = "tall_grass" if patch.has_point(Vector2i(x, y)) else "grass"
	Level.register("ui_meadow", Level.image_from_rows(rows, markers), null, {"name": "The Meadow", "outdoor": true})
	Net.map_name = "ui_meadow"


## Whether the HUD says "hidden in the grass" (decision 515): enemy-ai's
## rule read from Senses (508, hidden_by_cover), not copied. Standing on
## cover (World.cover_at > 0), still for Senses.STILL_TICKS, no monster
## within Senses.NOTICE_ALWAYS (cover never hides from the adjacent), and
## no carried light where it would show (emit_light with the cell darker
## than Senses.DARK without it; a lantern by day gives nothing away).
func _hidden_in_cover(player: GridEntity, tick: int) -> bool:
	if player.tile != _still_tile:
		_still_tile = player.tile
		_still_since = tick
	var nearest := 1000000
	for entity in World.get_entities():
		if entity is Monster and entity.spawned:
			nearest = mini(nearest, World.distance(player.tile, entity.tile))
	return hidden_words_due(World.cover_at(player.tile), tick - _still_since, player.emit_light > 0.0,
			World.light_at(player.tile, false), nearest)


## The cover cue's rule on its inputs (decision 515; Senses' numbers):
## [param cover] where they stand, [param still] ticks since their last
## step, whether they carry a light and the cell's light without it, and
## the nearest monster's distance.
static func hidden_words_due(cover: float, still: int, carries_light: bool, light_without: float, nearest_monster: int) -> bool:
	if cover <= 0.0 or still < Senses.STILL_TICKS or nearest_monster <= Senses.NOTICE_ALWAYS:
		return false
	return not (carries_light and light_without < Senses.DARK)


## What a ground pile's hint calls what lies there (decision 515): the
## first thing's short name in lower case, counted when more of its kind
## lie there ("5 herbs", 619 ui's side), "and N more" for the rest.
static func pile_words(ids: PackedStringArray, gold := 0) -> String:
	var things := ""
	if not ids.is_empty():
		var first := Items.short_of(ids[0]).to_lower()
		var same := ids.count(ids[0])
		if same > 1:
			first = "%d %s" % [same, first]
		things = first if ids.size() == same else "%s and %d more" % [first, ids.size() - same]
	if gold <= 0:
		return things
	# Its gold first, a count (601 amended): "12 gold", "12 gold and herbs".
	return "%d gold" % gold if things.is_empty() else "%d gold and %s" % [gold, things]


## What the keys do on [param thing] under the cursor (an entity or a
## door), for the context hint: "" for nothing to say. The owners' verbs
## (items' E and F, doors' E).
func context_hint_for(thing: Node) -> String:
	var player := _local_player()
	if thing == null or player == null or not Net.hints:
		return ""  # Jeff (2026-10-22): no control hints over things; settings.cfg hints=on brings them back for a test.
	if thing is Chest:
		return "%s  open the shop" % Keys.name_of("open") if (thing as Chest).shop else "E  open"
	if thing is Cargo:
		return "%s  open" % Keys.name_of("open")
	if thing is Door:
		return "%s  open or close" % Keys.name_of("open")
	if thing is Companion:
		return "LMB  talk   E  her pack" if _is_own_companion(thing) else "LMB  talk"
	if thing is Resident:
		# Decision 454: Shift+LMB attacks, said in the controls list. 515 amended: in bed, their ailment (npc's Resident.ailing).
		var ailing := str((thing as Resident).ailing)
		# 560, ui's side (Jeff): the click interacts; they stop and address you.
		return "LMB  interact   in bed with %s" % ailing if not ailing.is_empty() else "LMB  interact"
	if thing is Monster and World.can_target(player, thing):
		return "%s hold  draw   LMB  loose" % Keys.name_of("stand") if World.off_hand(player) == "draw" else "LMB  attack"
	if thing is Player and thing != player:
		return "LMB  talk   E hold  bandage"
	return ""


## The place the player stands in, for the compass: the level's place
## whose disc covers their cell (the nearest centre of several; maps'
## rule) and the zone's name; the zone alone outside every place.
func place_text(player: GridEntity) -> String:
	var zone_name := str(level.get("display_name", level.get("name", "")))
	if player == null:
		return zone_name
	var best := ""
	var best_distance := INF
	var listed: Dictionary = level.get("places", {})
	for key: String in listed:
		var place: Dictionary = listed[key]
		var cell: Vector2i = place.get("cell", Vector2i(-1000, -1000))
		var radius := maxi(int(place.get("radius", 1)), 1)
		var away := Vector2(player.tile - cell).length_squared()
		if away <= radius * radius and away < best_distance:
			best_distance = away
			best = str(place.get("name", key))
	return "%s, %s" % [best, zone_name] if not best.is_empty() and not zone_name.is_empty() else best + zone_name


## Where speaker [param key]'s bubble points on screen (see SpeechBubbles).
func _bubble_anchor(key: int) -> Variant:
	if _client3d != null:
		return _client3d.bubble_anchor(key)
	var entity := instance_from_id(key) as GridEntity
	if entity == null or not entity.is_inside_tree() or not entity.visible:
		return null
	return entity.get_global_transform_with_canvas() * Vector2(0.0, -BUBBLE_OVER_2D)


func _bubble_tile_px() -> float:
	if _client3d != null:
		return _client3d.tile_px()
	var camera := get_viewport().get_camera_2d()
	return Iso.TILE_SIZE.x * (camera.zoom.x if camera != null else 1.0)


## The chat box is open: the game's keys are the box's.
func is_typing() -> bool:
	return _chat_box != null and _chat_box.visible or _builder_ui != null and _builder_ui.is_typing() \
			or admin_panel != null and admin_panel.is_typing() or tuning_panel != null and tuning_panel.is_typing()


func _open_chat() -> void:
	if _local_player() == null:
		return
	_chat_box.text = ""
	_chat_box.visible = true
	_chat_box.grab_focus()


func _close_chat() -> void:
	_chat_box.release_focus()
	_chat_box.visible = false


## Enter in the chat box: send the line (as a command, so the server checks
## and spreads it), at most one per CHAT_INTERVAL from here as well.
## [param phrase]: the quick phrase it is (1-4), 0 for typed words.
func _send_chat(text: String, phrase := 0) -> void:
	_close_chat()
	var me := _local_player()
	var line := text.strip_edges().left(CHAT_MAX_CHARS)
	if me == null or line.is_empty():
		return
	if Time.get_ticks_msec() - _chat_sent_at < CHAT_INTERVAL * 1000.0:
		hud.text = "wait a moment before saying more"
		return
	_chat_sent_at = Time.get_ticks_msec()
	if line.begins_with(PARTY_PREFIX.strip_edges()) and (line.length() == 2 or line[2] == " "):
		var words := line.substr(2).strip_edges()
		if not words.is_empty():
			World.command(me, "party", {"text": words})
		return
	World.command(me, "say", {"text": line, "phrase": phrase})
	# Said to a town's person in earshot (decision 336's rule): the server answers as
	# their speech, and takes a word that accepts their standing offer (536).


## This peer's own companion in the world, or null.
func _own_companion() -> Companion:
	for entity in World.get_entities():
		if _is_own_companion(entity):
			return entity
	return null


## [param body]'s offers asked for (the client's "offers" command names the
## body; the server answers with the list, its "open" ones and "standing"):
## the pack's Promised line and the HUD's standing line follow (536, ui's side).
func ask_offers(body: GridEntity) -> void:
	var player := _local_player()
	if body != null and player != null and "offers" in Net.MESSAGE_KINDS:
		World.command(player, "offers", {"entity": str(body.get_path())})


## npc's "offers" message (536, ui's side: no panel): the open commissions
## become the pack's "Promised" line, and "standing" (the offer that
## stands with that resident, npc's 536) the HUD's title; absent, none.
func _on_offers_message(data: Dictionary) -> void:
	var owed: Array[String] = []
	for each: Variant in data.get("offers", []):
		if each is Dictionary and bool(each.get("open", false)):
			owed.append(str(each.get("title", each.get("words", ""))))
	if pack_panel != null:
		pack_panel.promised = owed
	standing_title = str((data["standing"] as Dictionary).get("title", "")) if data.get("standing") is Dictionary else ""
	# A talking monster's deals (629, ui's side): the window, while he is peaceable; empty closes it.
	var who := get_node_or_null(str(data.get("entity", ""))) as GridEntity
	if who is Monster and deal_panel != null:
		if talks_peaceably(who) and data.get("offers") is Array:
			deal_panel.show_deals(str(data.get("speaker", "")), data["offers"], gold, who.get_instance_id())
		else:
			deal_panel.close()


## Whether [param entity] is a talking monster at peace (629, ui's side):
## one whose talks and replicated peaceable (npc's 648) are true, so
## E greets him and the deal window may open; false once he fights.
func talks_peaceably(entity: GridEntity) -> bool:
	return entity is Monster and (entity as Monster).talks and (entity as Monster).peaceable


## Where one is talked to from (573 amended (4)): a gone draugr at his
## remains (Draugr.pile_at), anyone else where they stand.
static func talk_cell(entity: GridEntity) -> Vector2i:
	if entity is Draugr and (entity as Draugr).gone and (entity as Draugr).pile_at != Draugr.NO_TILE:
		return (entity as Draugr).pile_at
	return entity.tile


## The gone draugr whose remains lie at [param cell] (573 amended (4)), for
## a click or E there; null if none.
func remains_at(cell: Vector2i) -> GridEntity:
	for entity in World.entities():
		if entity is Draugr and entity.spawned and (entity as Draugr).gone and (entity as Draugr).pile_at == cell:
			return entity
	return null


## A deal button pressed (629, ui's side): the "offer" command with his
## deal's [param id] and [param amount] of gold, as a typed sum would send.
func _offer_deal(id: String, amount: int) -> void:
	var player := _local_player()
	if player != null and not id.is_empty() and amount >= 0:  # 0: the free deal (548 amended, ui's side).
		World.command(player, "offer", {"id": id, "gold": amount})


## The deal window watched (629, ui's side): closed when he is gone, no
## longer peaceable or out of hearing; its buttons follow the purse.
func _update_deal() -> void:
	if deal_panel == null or not deal_panel.visible:
		return
	var who := instance_from_id(deal_panel.entity_id) as GridEntity
	var player := _local_player()
	if who == null or not is_instance_valid(who) or not who.spawned or not talks_peaceably(who) \
			or player == null or World.distance(player.tile, talk_cell(who)) > HEARING_RANGE:
		deal_panel.close()
	elif deal_panel.purse != gold:
		deal_panel.set_purse(gold)


## The HUD's words while an offer stands (536, ui's side): how to take it, and what it is.
static func standing_words(title: String) -> String:
	return 'say "yes" to take it: %s' % title if not title.is_empty() else ""


## A boss's telegraph begins (combat's 602: the "telegraph" message {id,
## source, kind, shape, from_tick, lands_tick}; Main.telegraph_started):
## its cells from combat's Telegraph.cells, the same cells that hit, drawn
## on the ground filling toward lands_tick (Client3D.telegraph_show).
func _on_telegraph_started(id: Variant, data: Dictionary) -> void:
	if _client3d == null:
		return
	# The message carries the exact cells the blow will strike (clipped by the
	# server); without them, combat's Telegraph.cells on the shape.
	var cells: Variant = data.get("cells")
	if not cells is Array:
		var shape: Variant = data.get("shape", {})
		cells = telegraph_cells(shape if shape is Dictionary else {})
	var from_tick := int(data.get("from_tick", World.tick))
	var drawn: Variant = data.get("shape", {})
	_client3d.telegraph_show(str(id), cells, from_tick, int(data.get("lands_tick", from_tick)), drawn if drawn is Dictionary else {})


## A telegraph ends: landed, it flashes and goes; called off, it goes at once.
func _on_telegraph_ended(id: Variant, landed: bool) -> void:
	if _client3d != null:
		_client3d.telegraph_land(str(id), landed)


## The cells combat's Telegraph.cells gives for [param shape], the class
## found by name in the global class list (so this parses before combat's
## side lands); [] without it.
static func telegraph_cells(shape: Dictionary) -> Array:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == "Telegraph":
			var script: Variant = load(str(entry.get("path", "")))
			if script is GDScript and (script as GDScript).has_method("cells"):
				var cells: Variant = (script as GDScript).call("cells", shape)
				return cells if cells is Array else []
	return []


## Whether [param body] is winded (combat's replicated GridEntity.winded,
## read by name: false on a body without it).
static func is_winded(body: GridEntity) -> bool:
	var flag: Variant = body.get("winded") if body != null else null
	return flag is bool and flag


## The HUD's words while the local player lies dead (396 amended, ui's
## side; Jeff's "not respawning"): who is bringing them back and where,
## with the seconds left, "soon" when the wait is not known ([param
## seconds] under 0); nobody named, the old respawn: "coming back: n s".
static func return_words(by: String, where: String, seconds: int) -> String:
	var when := ": %d s" % seconds if seconds >= 0 else " soon"
	if by.is_empty():
		return "coming back" + when
	return "%s is bringing you back to %s%s" % [by, return_place_words(where), when]


## The place's words for a return message's where: the kind of place.
static func return_place_words(where: String) -> String:
	match where:
		"healers_hut":
			return "the healer's hut"
		"temple":
			return "the temple"
	return "a holy place"


## Everyone's wait now (587): the seconds the return message gave, counted
## down on the client's clock; 0 when none stands.
func all_fallen_left() -> int:
	if _fallen_wait <= 0:
		return 0
	return maxi(ceili(_fallen_wait - (Time.get_ticks_msec() / 1000.0 - _fallen_wait_at)), 0)


## The down screen's hold: companions' "slow_heart" {held}, on press and
## release; its Bleed Out: "bleed_out".
func _ask_slow_heart(held: bool) -> void:
	var player := _local_player()
	if player != null:
		World.command(player, "slow_heart", {"held": held})


func _ask_bleed_out() -> void:
	var player := _local_player()
	if player != null:
		World.command(player, "bleed_out", {})


## The return line now: the message's seconds counted down on the client's
## clock since it came; past zero, "soon" (the keeper may have stepped
## away). "" with no message.
func return_shown() -> String:
	if _return_told.is_empty():
		return ""
	var seconds := int(_return_told.get("seconds", -1))
	if seconds >= 0:
		seconds = ceili(seconds - (Time.get_ticks_msec() / 1000.0 - _return_at))
		if seconds <= 0:
			seconds = -1
	if bool(_return_told.get("near_death", false)) and not str(_return_told.get("by", "")).is_empty():
		return "%s brought you back from near death" % _return_told["by"]  # 587: the at-once return.
	var fallen := all_fallen_left()
	if fallen > 0:
		return "all have fallen: all come back in %d s" % fallen
	return return_words(str(_return_told.get("by", "")), str(_return_told.get("where", "")), seconds)


## The HUD's words while the local player lies downed (544, ui's side): the
## seconds left before they are gone for good, unless brought back.
static func downed_words(seconds: int) -> String:
	return "You are down: %d s" % maxi(seconds, 0)


## The HUD's words while the local player brings [param name] back (544).
static func channel_words(name: String, seconds: int) -> String:
	return "bringing %s back: %d s" % [name, maxi(seconds, 0)]


## How far a channel has run (0 to 1): from [param seen], the tick this view
## first saw it, to [param until], at [param tick].
static func channel_fraction(seen: int, until: int, tick: int) -> float:
	return 1.0 if until <= seen else clampf(float(tick - seen) / float(until - seen), 0.0, 1.0)


## The spawned entity whose node name is [param name] (a replicated
## channel_of names a body so), or null.
func _entity_named(name: String) -> GridEntity:
	for entity in World.get_entities():
		if entity.spawned and String(entity.name) == name:
			return entity
	return null


## The channel's ring on the body being brought back (544, ui's side): the
## first channeler in view (channel_of and channel_until are replicated),
## the ring on its body, closing in as the channel runs; none, hidden.
func _show_channel_ring() -> void:
	if _client3d == null:
		return
	var tick := World.tick
	for entity in World.get_entities():
		if not entity.spawned or entity.channel_of.is_empty() or tick >= entity.channel_until:
			continue
		var body := _entity_named(entity.channel_of)
		if body == null:
			continue
		var id := entity.get_instance_id()
		var seen: Array = _channel_seen.get(id, [])
		if seen.is_empty() or int(seen[1]) != entity.channel_until:
			seen = [tick, entity.channel_until]
			_channel_seen[id] = seen
		_client3d.channel_ring(body.tile, channel_fraction(int(seen[0]), int(seen[1]), tick))
		return
	_client3d.channel_ring(Vector2i.ZERO, 0.0, false)
	if not _channel_seen.is_empty():
		_channel_seen.clear()


## The latest blow (_narrate_damage): who was struck and by whom, so a
## death right after it knows its killer (decision 332).
var _blow_target: GridEntity = null
var _blow_source: GridEntity = null


## Server: a creature or a breakable thing was killed. Every view hears of
## it ("death"), with what it was and where, since its node goes at once;
## a companion says a last line.
## A grave robber fallen in the barrow: his share of the band's purse
## (Economy.band_share) laid where he fell as a gold count (601 amended:
## World.drop_gold, never a thing).
func _robber_fell(entity: GridEntity, _cause: StringName) -> void:
	if not entity is Monster or World.economy == null:
		return
	var rule: Dictionary = World.economy.rules.get("robbers", {})
	var kinds: Array = rule.get("kinds", [])
	var kind := str(entity.spawn_spec.get("kind", ""))
	var barrow := str(rule.get("barrow", ""))
	if kind not in kinds or entity.zone != barrow:
		return
	var standing := World.get_entities().filter(func(each: GridEntity) -> bool:
		return each is Monster and str(each.spawn_spec.get("kind", "")) in kinds and each.zone == barrow and (each == entity or each.hp > 0)).size()
	World.drop_gold(entity.zone, entity.tile, World.economy.band_share(barrow, standing))  # A count, never a thing (601 amended).


func _on_entity_died(entity: GridEntity, cause: StringName) -> void:
	var kind := "object"
	if entity is Player:
		kind = "player"
	elif entity is Companion:
		kind = "companion"
	elif entity.is_creature():
		kind = "monster"
	for pet: Companion in _companions.values():
		if is_instance_valid(pet) and pet.spawned and pet != entity and entity.is_creature() \
				and (entity == pet.keeper or pet.witnessed(entity)):
			pet.note_death(_display_name(entity), entity == pet.keeper, entity,
				_blow_source if _blow_target == entity and is_instance_valid(_blow_source) else null)
	if entity is Resident and not (entity as Resident).sought.is_empty() and World.towns != null:
		# A sought one dead (bled out unroused on the way home, 613): lost, sought again somewhere after economy's days.
		World.towns.sought_lost((entity as Resident).sought)
	var line := ""
	if entity is Companion:
		# Always said: last words never wait on the speech rate limit.
		line = COMPANION_DEATH_LINES[randi() % COMPANION_DEATH_LINES.size()]
		party_log.add("%s said: \"%s\"" % [entity.name, line])
		# Her last words are hers: in her transcript like any line.
		Transcript.record(String(entity.name), String(entity.name), line)
	# To those it is sent to (decision 217): a death far off is nobody's to
	# see. The host's own client has every entity.
	var told: Array[int] = []
	told.assign(World.peers_in(World.zone.name).filter(func(peer: int) -> bool:
		return peer == Net.local_id or entity._visible_to(peer)))
	Net.broadcast_to(told, "death", {"entity": String(entity.name),
		"tile": [entity.tile.x, entity.tile.y], "kind": kind, "cause": String(cause), "say": line})


## Server: a player walked into their own companion; she gets out of the
## way (see Companion.bumped). Logged once per bump, not per key repeat.
func _on_bumped(mover: GridEntity, occupant: GridEntity, direction: Vector2i) -> void:
	var pet := occupant as Companion
	if pet == null or pet.keeper != mover:
		return
	if pet.bumped(direction):
		party_log.add("%s bumped into %s." % [_display_name(mover), pet.name])
		print("[mind] %s bumped into %s going %s" % [_display_name(mover), pet.name, direction])


## Server: [param player] clicked their own companion beside them (the
## "make_way" command): she steps aside at once, as for a bump, no mind
## asked. Another's companion, or one out of reach: nothing.
func _make_way(player: Player, pet: Companion) -> void:
	if pet == null or pet.keeper != player or not World.can_melee(player.tile, pet.tile):
		return
	var way := pet.tile - player.tile
	if pet.bumped(Vector2i(signi(way.x), signi(way.y))):
		party_log.add("%s bumped into %s." % [_display_name(player), pet.name])


## Server: [param player] said [param text] (the chat box). At most
## CHAT_MAX_CHARS, one line per CHAT_INTERVAL; to everyone as chat, into
## the party log, and to their companion as a decision, the words as data.
## A whisper ("/w words") carries WHISPER_RANGE, not HEARING_RANGE; a line in
## capitals is a shout, heard farther by monsters (Senses.speech_radius).
func _player_said(player: Player, text: String, phrase := 0) -> void:
	var line := text.strip_edges().left(CHAT_MAX_CHARS)
	if World.is_downed(player):
		return  # Downed (decision 544): no word.
	var whisper := line.begins_with(WHISPER_PREFIX.strip_edges()) and (line.length() == 2 or line[2] == " ")
	if whisper:
		line = line.substr(2).strip_edges()
	if line.is_empty():
		return
	var earshot := WHISPER_RANGE if whisper else HEARING_RANGE
	var id := player.get_instance_id()
	if World.tick - _chat_tick.get(id, -100000) < roundi(CHAT_INTERVAL * World.TICK_RATE):
		print("[chat] %s: too soon after the last line; dropped" % _display_name(player))
		return
	_chat_tick[id] = World.tick
	var pet: Companion = _companions.get(_peer_ids.get(player.owner_peer, ""))
	# She hears it only in the same zone and within earshot.
	var hears := is_instance_valid(pet) and pet.spawned and pet.zone == player.zone \
			and World.distance(pet.tile, player.tile) <= earshot
	var to := String(pet.name) if hears else ""
	# A resident beside them, or named, takes typed words (decision 336);
	# their companion hears them as said to someone else.
	var resident := _resident_addressed(player, line, pet if hears else null) if phrase == 0 else null
	if resident != null:
		to = resident.person
	# Or a monster that talks (the draugr, 548; decision 546, npc's side): named, or nearest within earshot.
	var talker: GridEntity = _monster_addressed(player, line) if resident == null and phrase == 0 else null
	if talker != null:
		to = _display_name(talker)
	# Every other companion within earshot hears it too, labelled; her voice
	# decides whether it was meant for her.
	for entity in World.get_entities():
		var other := entity as Companion
		if other != null and other != pet and other.spawned and World.distance(other.tile, player.tile) <= earshot:
			other.overheard(_display_name(player), line)
	party_log.add("%s %s%s: \"%s\"" % [_display_name(player), "whispered" if whisper else "said",
		" to " + to if to != "" else "", line])
	_heard_near(player, _display_name(player), line, resident)
	World.noise(player.tile, WHISPER_RANGE if whisper else Senses.speech_radius(line), &"speech", player)
	Net.broadcast_to(hearers(player.tile, earshot), "chat", {"entity": String(player.get_path()), "from": _display_name(player),
		"to": to, "text": line})
	if resident != null:
		if _recruit_said(resident, player, line) or _resident_recruit_said(resident, player, line):
			pass  # Their companion who left, asked and willing, or a resident who trusts them: they go with them (581 amended (2), 686).
		elif not _offer_said(resident, player, line):  # An ask for wares, work or news, or a word taking the offer standing (decision 536).
			_ask_resident(resident, _display_name(player), line, player)
		if hears:
			pet.overheard(_display_name(player), line, false)
	elif talker != null:
		_monster_said(talker, player, line)
		if hears:
			pet.overheard(_display_name(player), line, false)
	elif not hears and _calls_absent(player, pet, line, phrase):
		pass  # Told where she is (the barrow: he called for Pip, who worked in town).
	elif to != "":
		if phrase == 0 and _part_said(player, pet, line):
			return  # They part for a while (581 amended (3)): she answers as she sets off.
		if phrase == 0:
			_guide_said(player, pet, line)  # An ask to lead the way (decision 551).
		pet.owner_spoke(line, phrase)


## Whether [param player] called for their companion where she is not
## ([param line] names her, or a quick phrase, [param phrase] not 0, meant
## her): if she is elsewhere (_companion_whereabouts), they are told where,
## at most every WHERE_AGAIN_MS. True if told.
func _calls_absent(player: Player, pet: Companion, line: String, phrase: int) -> bool:
	if is_instance_valid(pet) and pet.spawned and pet.zone == player.zone:
		return false
	var record: PlayerRecord = _records.get(_peer_ids.get(player.owner_peer, ""))
	if record == null or not (phrase != 0 or Companion._named(line, str(record.companion.get("name", "")))):
		return false
	var words := _companion_whereabouts(record, player.zone)
	if words.is_empty() or Time.get_ticks_msec() - int(_where_told.get(player.owner_peer, -WHERE_AGAIN_MS)) < WHERE_AGAIN_MS:
		return false
	Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": words})
	_where_told[player.owner_peer] = Time.get_ticks_msec()
	return true


## The peers whose players can hear something said at [param at] in the
## zone World is in: there, within HEARING_RANGE; a fallen player, waiting
## to rise, hears from where they fell (but has no body to speak with).
func hearers(at: Vector2i, earshot := HEARING_RANGE) -> Array[int]:
	var peers: Array[int] = []
	for peer in World.peers_in(World.zone.name):
		var player: Player = _players.get(peer)
		var standing := is_instance_valid(player) and player.spawned and player.zone == World.zone.name
		var from: Vector2i = player.tile if standing else _fell_at.get(peer, NONE)
		if (standing or _fell_at.has(peer)) and World.distance(from, at) <= earshot:
			peers.append(peer)
	return peers


## Server: [param player]'s party chat (/p): to every player on the server
## in every zone, marked as party chat; never to a companion, nor into a
## zone's party log. The same rate limit as speech.
func _party_said(player: Player, text: String) -> void:
	var line := text.strip_edges().left(CHAT_MAX_CHARS)
	if line.is_empty():
		return
	var id := player.get_instance_id()
	if World.tick - _chat_tick.get(id, -100000) < roundi(CHAT_INTERVAL * World.TICK_RATE):
		print("[party] %s: too soon after the last line; dropped" % _display_name(player))
		return
	_chat_tick[id] = World.tick
	var everyone: Array[int] = []
	everyone.assign(World.peer_zone.keys())
	print("[party] %s: %s" % [_display_name(player), line])
	Net.broadcast_to(everyone, "party", {"from": _display_name(player), "zone": player.zone, "text": line})


## Keys 1-4: the quick phrase in that slot (settings.cfg phrase1= ...),
## said exactly as a typed line is, rate limit and all.
func say_phrase(slot: int) -> void:
	if slot >= 1 and slot <= Net.phrases.size():
		_send_chat(Net.phrases[slot - 1], slot)


func _on_companion_said(text: String, pet: Companion) -> void:
	# The other companions within earshot hear her, labelled; it is no ask.
	for entity in World.get_entities():
		var other := entity as Companion
		if other != null and other != pet and other.spawned and World.distance(other.tile, pet.tile) <= HEARING_RANGE:
			other.overheard(String(pet.name), text, false)
	party_log.add("%s said: \"%s\"" % [pet.name, text])
	_heard_near(pet, String(pet.name), text)
	var record: PlayerRecord = _records.get(pet.keeper_id)
	if record != null:
		record.companion["said"] = pet.said_lines()
	Net.broadcast_to(hearers(pet.tile), "speech", {"entity": String(pet.get_path()), "speaker": String(pet.name), "text": text})


func _on_message(kind: String, data: Dictionary) -> void:
	if kind == "world":
		if data.get("guide_route") is Dictionary:
			_guide_route(data["guide_route"])
		world_state = WorldNews.merge(world_state, data)
		world_changed.emit()
		return
	if kind == "terrain":
		_on_terrain(data)
		return
	if kind == "telegraph":
		_on_telegraph(data)
		return
	if kind == "clearing":
		_on_clearing(data)
		return
	if kind == "folds":
		var counts: Variant = data.get("counts", {})
		if counts is Dictionary:
			for id: Variant in counts:
				fold_counts[str(id)] = int(counts[id])
			_show_folds()
		return
	if kind == "town":
		var town := str(data.get("town", ""))
		var buildings: Variant = data.get("buildings", {})
		if not town.is_empty() and data.get("awake") is Dictionary:
			town_awake[town] = data["awake"]
			if _client3d != null and _client3d.has_method("set_awake"):
				_client3d.call("set_awake", town, data["awake"])
		if not town.is_empty() and buildings is Dictionary:
			town_states[town] = buildings
			World.towns_seen[town] = buildings
			World.open_roofs(town.get_slice("/", 0))
			if _client3d != null:
				_client3d.set_town(town, buildings)
		if not town.is_empty() and data.has("stage"):
			town_stages[town] = str(data["stage"])  # 591; the sheet's heading (624).
		_refresh_town()
		return
	if kind == "town_sheet":
		# Economy's rows for the sheet (624, economy's side), kept by town.
		var for_town := str(data.get("town", ""))
		if not for_town.is_empty():
			town_sheets[for_town] = data
			_refresh_town()
		return
	if kind == "grass":
		if not Net.is_authority() and not str(data.get("level", "")).is_empty():
			World.grass_told(str(data["level"]), data)
		return
	if kind == "roofs":
		var level := str(data.get("level", ""))
		var damaged: Variant = data.get("damaged", [])
		if not level.is_empty() and damaged is Array:
			roof_states[level] = damaged
			if not Net.is_authority():
				World.roofs_told(level, damaged)
			if _client3d != null:
				_client3d.set_roofs(level, damaged)
		return
	if kind == "sky":
		if not Net.is_authority():
			DayNight.from_dict(data)
			if data.get("climates") is Dictionary:
				Weather.use(data["climates"])
			Weather.overrides = data["overrides"] if data.get("overrides") is Dictionary else {}
		return
	if kind == "builder":
		if _builder_ui != null:
			_builder_ui.on_message(data)
		return
	if kind == "admin":
		is_admin = bool(data.get("admin", false))  # 672: the server says this player is an admin.
		return
	if kind == "admin_reply":
		if admin_panel != null:
			admin_panel.on_reply(data)
		return
	if kind == "return":
		if data.has("all_fallen"):
			# 587: everyone is down and all come back in so many seconds; 0 calls the wait off.
			_fallen_wait = int(data["all_fallen"])
			_fallen_wait_at = Time.get_ticks_msec() / 1000.0
			return
		# 396 amended, ui's side: who brings the dead player back, where, in how long.
		_return_told = data
		_return_at = Time.get_ticks_msec() / 1000.0
		return
	if kind == "shop":
		_on_shop_message(data)
	elif kind == "barter":
		barter_data = data
		if data.has("gold"):
			gold = int(data["gold"])
		barter_told.emit(data)
		return
	elif kind == "counter":
		_on_counter_message(data)
		return
	if kind == "map":
		# The zone this client's player is in: it draws and predicts on that
		# map, and its entities arrive under that zone's node.
		_end_title_music()  # The world starts loading: the title screen's music goes (656).
		var wanted := str(data.get("name", ""))
		Net.server_version = str(data.get("server", Net.server_version))
		map_generation = int(data.get("generation", 0))
		if not Net.is_authority() and Net.newer_version(Net.server_version, Net.claimed_version()) and not _told_newer:
			# The same protocol, so it plays; the next start updates it.
			_told_newer = true
			print("[update] the server runs v%s, newer than this v%s: launch.bat updates it" % [Net.server_version, Net.claimed_version()])
			talk.add_line("Server", "A newer game, v%s, is out: start the game again with launch.bat to update." % Net.server_version, true, true)
		if not Net.is_authority() and wanted != map_name and Level.exists(wanted):
			_client_zone(wanted)
		return
	if kind == "death":
		if _client3d != null:
			_client3d.on_death(data)
		var last_words := str(data.get("say", ""))
		if not last_words.is_empty():
			print("[speech] %s: %s" % [data.get("entity", ""), last_words])
			talk.add_line(str(data.get("entity", "")), last_words)
		return
	if kind == "chat":
		var heard := "%s%s" % [data.get("from", ""), " (to %s)" % data["to"] if str(data.get("to", "")) != "" else ""]
		print("[chat] %s: %s" % [heard, data.get("text", "")])
		talk.add_line(heard, str(data.get("text", "")), true)
		# Shown over the speaker, as a companion's speech is.
		var speaker := get_node_or_null(NodePath(str(data.get("entity", "")))) as GridEntity
		if speaker != null:
			bubbles.show_line(speaker.get_instance_id(), str(data.get("text", "")))
		return
	if kind == "party":
		print("[party] %s: %s" % [data.get("from", ""), data.get("text", "")])
		if str(data.get("from", "")) == "Town":
			town_notes[zone_name_here()] = str(data.get("text", ""))  # The big map's box, not the log.
			return
		talk.add_line(str(data.get("from", "")), str(data.get("text", "")), true, true)
		return
	if kind == "speech":
		var entity := get_node_or_null(NodePath(str(data.get("entity", "")))) as GridEntity
		var speaker := str(data.get("speaker", entity.name if entity != null else "?"))
		print("[speech] %s: %s" % [speaker, data.get("text", "")])
		talk.add_line(speaker, str(data.get("text", "")), false, false, str(data.get("aside", "")))  # The aside dim after it (336 amended); the bubble the words alone.
		if entity != null:
			bubbles.show_line(entity.get_instance_id(), str(data.get("text", "")))
	if kind == "offers":
		_on_offers_message(data)
		return
	if kind == "notes":
		_on_notes_message(data)  # 643, ui's side.


## A name for the party log: players by record name, residents by the label
## over their head ("Bram [smith]"), everything else by its node name.
## Server: the "give_gold" command (decision 614; Jeff: gold traded in
## game, never an item). {to: path, amount}: [param player]'s gold to
## another player or to their own companion; {from: her path, amount}: the
## keeper takes it back from their companion's purse
## (Economy.companion_purse). The other must be in the zone, standing,
## within World.COMPANION_REACH and in sight. Both are told by a party
## line; a refusal goes to the giver alone. The gold given.
func give_gold(player: Player, args: Dictionary) -> int:
	var taking := args.has("from")
	var other := get_node_or_null(NodePath(str(args.get("from" if taking else "to", "")))) as GridEntity
	var amount := int(args.get("amount", 0))
	var mine := str(_peer_ids.get(player.owner_peer, ""))
	var why := ""
	var other_id := ""
	var other_name := ""
	if other == null or other == player or not other.spawned or other.zone != player.zone or other.hp <= 0 			or World.distance(player.tile, other.tile) > World.COMPANION_REACH or not World.has_line_of_sight(player.tile, other.tile):
		why = "They are too far away."
	elif other is Companion and (other as Companion).keeper_id == mine:
		other_id = Economy.companion_purse(mine)
		other_name = str(_records[mine].companion.get("name", "your companion")) if _records.has(mine) else "your companion"
	elif other is Player and not taking:
		other_id = str(_peer_ids.get(other.owner_peer, ""))
		other_name = _display_name(other)
	else:
		why = "You can only give gold to another player or your own companion."
	if why.is_empty() and other_id.is_empty():
		why = "They are too far away."
	if why.is_empty() and amount < 1:
		why = "Say how much."
	var from_id := other_id if taking else mine
	if why.is_empty() and amount > World.gold_of(from_id):
		why = "%s %d gold." % ["She has only" if taking else "You have only", World.gold_of(from_id)]
	var given := 0
	if why.is_empty():
		var my_name := _display_name(player)
		given = World.give_gold(from_id, mine if taking else other_id, amount, other_name if taking else my_name, my_name if taking else other_name)
	if given <= 0:
		Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": why if not why.is_empty() else "No gold changes hands."})
		return 0
	var line := "%s takes %d gold from %s." % [_display_name(player), given, other_name] if taking 		else "%s gives %s %d gold." % [_display_name(player), other_name, given]
	var peers: Array[int] = [player.owner_peer]
	if other is Player and other.owner_peer != player.owner_peer:
		peers.append(other.owner_peer)
	Net.broadcast_to(peers, "party", {"from": "Server", "text": line})
	print("[economy] %s" % line)
	return given


## Server: the "town_sheet" command (decision 624, economy's side; ui's
## town status sheet) {town}: [param player] is answered "town_sheet"
## (town_panel) for a town in their zone or among their known places, else
## {town, why}. The answer sent.
func ask_town_sheet(player: Player, args: Dictionary) -> Dictionary:
	var town := str(args.get("town", ""))
	var record: PlayerRecord = _records.get(_peer_ids.get(player.owner_peer, ""))
	var sheet := {"town": town, "why": "you don't know that town"}
	if World.towns != null and World.towns.to_dict().has(town) \
			and (town.begins_with(player.zone + "/") or record != null and town in record.known_places):
		sheet = town_sheet(town)
	Net.message_to(player.owner_peer, "town_sheet", sheet)
	return sheet


## [param town]'s status sheet (decision 624): {town, name, population,
## trades {trade: residents}, treasury, officials [{name, trade, paid}],
## dole and hungry (residents fed by the town, not fed, at their last
## meal), sick, needs [{id, short 0..1, bring}] (raw goods under comfort,
## worst first), builds [{kind, progress}], season, day, stage, faction
## {name}, mood (its safety: "safe", "uneasy", "on guard"), sought
## [{trade, where}] (613), next_stage (Towns.next_stage), strain {days,
## of, why} (Towns.strain: toward falling back a stage, 649)}.
func town_sheet(town: String) -> Dictionary:
	var production := World.production
	var people := World.towns.residents(town)
	var trades := {}
	var officials: Array[Dictionary] = []
	var fed := {"dole": 0, "hungry": 0}
	var sick := 0
	var official_rules: Dictionary = World.economy.rules.get("official", {})
	for id in people:
		var who := production.worker(id)
		var theirs: Array = who.get("trades", [])
		if not theirs.is_empty():
			trades[str(theirs[0])] = int(trades.get(str(theirs[0]), 0)) + 1
		var office: Array = theirs.filter(func(trade: Variant) -> bool: return official_rules.has(str(trade)))
		if not office.is_empty():
			officials.append({"name": str(who.get("name", id)), "trade": str(office[0]), "paid": int(who.get("owed", 0)) <= 0})
		if not bool(who.get("away", false)) and fed.has(str(who.get("fed", ""))):
			fed[str(who["fed"])] += 1
		if Townsfolk.is_sick(production, id):
			sick += 1
	var needs: Array[Dictionary] = []
	var comfort: Dictionary = World.economy.rules.get("comfort", {})
	for what: String in comfort:
		var want := int(comfort[what])
		var have := World.stockpile.count(town, what)
		if what != "gold" and want > 0 and have < want:
			needs.append({"id": what, "short": clampf(1.0 - float(have) / want, 0.0, 1.0), "bring": want - have})
	needs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["short"] > b["short"] or a["short"] == b["short"] and a["id"] < b["id"])
	var builds: Array[Dictionary] = []
	var houses := World.towns.buildings_of(town)
	for kind: String in houses:
		if houses[kind].has("progress"):
			builds.append({"kind": kind, "progress": float(houses[kind]["progress"])})
	var safety := str(production.signals_of(town, production.catalog.call())["safety"])
	var place := World.holdings.place(town) if World.holdings != null else {}
	var holder := World.holdings.holder(town) if World.holdings != null else Stockpile.TOWN
	return {"town": town, "name": str(place.get("name", town)), "population": people.size(), "trades": trades,
		"treasury": World.stockpile.count(town, "gold"), "officials": officials, "dole": fed["dole"], "hungry": fed["hungry"],
		"sick": sick, "needs": needs, "builds": builds, "season": Season.name_at(World.steps), "day": Townsfolk.day_of(World.steps),
		"stage": World.towns.stage(town),
		"faction": {"name": World.holdings.factions.display_name(holder) if World.holdings != null else "the town"},
		"mood": {Production.SAFE: "safe", Production.UNEASY: "uneasy"}.get(safety, "on guard"),
		"sought": World.towns.sought(town).map(func(entry: Dictionary) -> Dictionary: return {"trade": entry["trade"], "where": entry.get("where", "")}),
		"next_stage": World.towns.next_stage(town), "strain": World.towns.strain(town)}


func _display_name(entity: GridEntity) -> String:
	if entity is Player:
		var record: PlayerRecord = _records.get(_peer_ids.get(entity.owner_peer, ""))
		if record != null:
			return record.name
	if entity is Resident and not entity.label.is_empty():
		return entity.label
	return String(entity.name)


func _narrate_push(entity: GridEntity, by: GridEntity, _direction: Vector2i, tiles: int, impact: int, stopped_by: String) -> void:
	var line := "%s shoved %s" % [_display_name(by), _display_name(entity)]
	if tiles > 0:
		line += " %d tiles" % tiles
	if not stopped_by.begins_with("nothing"):
		line += " into %s" % stopped_by
	if impact > 0:
		line += " for %d" % impact
	party_log.add(line + ".")


## A charge stopped on a braced spear (World.braced_against).
func _narrate_brace(holder: GridEntity, charger: GridEntity) -> void:
	party_log.add("%s's charge breaks on %s's spear." % [_display_name(charger), _display_name(holder)])


## A thing carried long took its name (World.item_named; decision 365).
func _narrate_named(entity: GridEntity, uid: int, text: String) -> void:
	party_log.add("%s's %s is %s now." % [_display_name(entity), Items.name_of(World.items.id_of(uid)), text])


## Her card's facts of her things and her player (293 amended, Jeff: "it
## may strengthen the bond between player and companion"): a thing named
## for her (365), a gift either way between her and her player, her named
## thing kept from her by her player (370) and back with her. Facts only,
## never lines to say.
func _card_named(entity: GridEntity, uid: int, text: String) -> void:
	if entity is Companion:
		(entity as Companion).note_fact("%s is named for %s now, after long use." % [text, entity.name])


func _card_kept(entity: GridEntity, uid: int, kept: bool) -> void:
	var namer := str(World.items.name_of(uid).get("who", ""))
	for pet: Companion in _companions.values():
		if not is_instance_valid(pet) or World.holder_key(pet) != namer:
			continue
		var thing := World.item_title(uid).get_slice(" (", 0)
		if kept and entity == pet.keeper:
			pet.note_fact("%s kept %s from her." % [pet.keeper_name(), thing])
			_bond(_record_of(pet), "kept_from", "kept %s from you" % thing)
		elif not kept and entity == pet:
			pet.note_fact("%s came back to %s." % [thing, pet.name])


func _card_given(from: GridEntity, to: GridEntity, uid: int) -> void:
	var id := World.items.id_of(uid)
	var named := World.item_title(uid).get_slice(" (", 0)
	if str(Items.def(id).get("use", "")) == "eat":
		# Food from her player moves her bond (444), though no card fact.
		for pet: Companion in _companions.values():
			if is_instance_valid(pet) and from == pet.keeper and to == pet:
				_bond(_record_of(pet), "fed", "shared food with you")
	if _grave_goods(uid):
		# Grave goods put on her, superstitious and short of devoted: she
		# carries them (turns_down let her, close), and it costs her (555 amended).
		for pet: Companion in _companions.values():
			if is_instance_valid(pet) and from == pet.keeper and to == pet and not pet.bond_at_least("devoted") \
					and pet.superstition >= int(Companion.loyalty().get("grave_superstition", 6)):
				_bond(_record_of(pet), "grave", "made you carry grave goods")
	if named.is_empty() and (not Items.is_gear(id) or not str(Items.def(id).get("use", "")).is_empty()):
		return  # A bandage or a meal handed over (used up) is no event of the card.
	var thing := named if not named.is_empty() else Companion._a(Items.name_of(id).to_lower())
	for pet: Companion in _companions.values():
		if not is_instance_valid(pet) or not is_instance_valid(pet.keeper):
			continue
		if from == pet.keeper and to == pet:
			pet.note_fact("%s gave %s %s." % [pet.keeper_name(), pet.name, thing])
			if not _grave_goods(uid):
				_bond(_record_of(pet), "gift", "gave you %s" % thing)
		elif from == pet and to == pet.keeper:
			var hers := str(World.items.name_of(uid).get("who", "")) == World.holder_key(pet)
			pet.note_fact("%s gave %s %s%s." % [pet.name, pet.keeper_name(), thing, ", the thing named for her" if hers else ""])


## Her bond with her player (decision 444, on npc's Standing, 443: her
## record holds "standing", the COMPANION ladder) moved by [param event]
## (companion_traits.json "bond") for [param why], what they did, without
## their name ("bandaged your wounds"); logged. A raise (its "deeds" tier,
## decision 621) goes through _bond_raise; a drop costs what "drops" says.
func _bond(record: PlayerRecord, event: String, why: String) -> void:
	if record == null or record.companion.is_empty():
		return
	var table: Dictionary = CompanionCard.tables().get("bond", {})
	var tier := str((table.get("deeds", {}) as Dictionary).get(event, ""))
	var delta := int((table.get("drops", {}) as Dictionary).get(event, 0))
	if not tier.is_empty():
		if not _bond_raise(record, event, tier, why):
			return
	elif delta == 0:
		return
	else:
		Standing.bump(record.companion, record.player_id, delta, why, World.steps)
	_set_mood(record)
	if delta < 0:
		_check_leaving(record, event, why)  # The bottom step, or the last straw (decision 581).
	# A hurt she says so of, as it happens (decision 555): told her voice once.
	var pet: Companion = _companions.get(record.player_id)
	if delta < 0 and is_instance_valid(pet) and pet.spawned:
		pet._ask_voice("%s just %s." % [record.name, why], "", true)  # Past the rate limit: a hurt is told.
	MindLog.record({"kind": "bond", "companion": str(record.companion.get("name", "")), "mind": "hands", "trigger": event,
		"note": why, "outcome": "%s (%d)" % [Standing.words(record.companion, record.player_id, Standing.COMPANION),
			Standing.score(record.companion, record.player_id)]})


## A raise of her bond by [param event] of [param tier] (decision 621):
## once a game day each deed, the tier's "each" (halves carried on her
## record, bond_carry), never past bond_cap. Whether it counted.
func _bond_raise(record: PlayerRecord, event: String, tier: String, why: String) -> bool:
	var card := record.companion
	var id := record.player_id
	var day := int(World.steps / maxi(DayNight.day_steps, 1))
	var today: Dictionary = card.get("bond_today", {})
	if int(today.get("day", -1)) != day:
		today = {"day": day, "deeds": []}
	var score := Standing.score(card, id)
	var cap := bond_cap(card, id, tier)
	if event in today["deeds"] or score >= cap:
		return false
	today["deeds"].append(event)
	card["bond_today"] = today
	var each := float((((CompanionCard.tables().get("bond", {}) as Dictionary).get("tiers", {}) as Dictionary).get(tier, {}) as Dictionary).get("each", 1))
	var carry := float(card.get("bond_carry", 0.0)) + each
	var whole := mini(floori(carry), cap - score)
	card["bond_carry"] = carry - floori(carry) if whole == floori(carry) else 0.0
	Standing.bump(card, id, whole, why, World.steps)
	card["bond_best"] = maxi(int(card.get("bond_best", 0)), Standing.score(card, id))
	return true


## The most a deed of [param tier] raises her bond to (decision 621): the
## tier's up_to, or, repairing, her best (bond_best) but never past the top
## of the step she is at (one short of close, or of devoted; devoted, the
## ladder's most).
static func bond_cap(card: Dictionary, player_id: String, tier: String) -> int:
	var tiers: Dictionary = (CompanionCard.tables().get("bond", {}) as Dictionary).get("tiers", {})
	var own := int((tiers.get(tier, {}) as Dictionary).get("up_to", 0))
	var score := Standing.score(card, player_id)
	var here := Standing.setting("trusted") - 1
	if score >= Standing.setting("top"):
		here = Standing.setting("most")
	elif score >= Standing.setting("trusted"):
		here = Standing.setting("top") - 1
	return maxi(own, mini(maxi(int(card.get("bond_best", 0)), score), here))


## The record of the player whose companion [param pet] is; null for none.
func _record_of(pet: Companion) -> PlayerRecord:
	return _records.get(pet.keeper_id) if is_instance_valid(pet) else null


## Her bond's slow changes (decision 444), once a world tick: a day
## travelling together counts once a day, a deed of warmth (decision 621:
## it stops at close). Apart from her player it stands: no decay (Jeff).
func _tend_bonds() -> void:
	var day := int(World.steps / maxi(DayNight.day_steps, 1))
	for player_id: String in _records:
		var record: PlayerRecord = _records[player_id]
		if record.companion.is_empty() or not record.companion.get("alive", true):
			continue
		var pet: Companion = _companions.get(player_id)
		if not (is_instance_valid(pet) and pet.spawned and is_instance_valid(pet.keeper)):
			continue
		if int(record.companion.get("bond_day", -1)) == day:
			continue
		record.companion["bond_day"] = day
		_bond(record, "day", "kept you company for days")


## Bandaged by her player: warmth, or, under a third of her hp, tending
## her badly hurt, trust (decision 621).
func _bond_bandaged(by: GridEntity, patient: GridEntity, state: StringName) -> void:
	if state == &"started" and patient is Companion and by != null and by == (patient as Companion).keeper:
		if patient.hp * 3 < patient.max_hp:
			_bond(_record_of(patient), "tended", "tended your wounds when you were badly hurt")
		else:
			_bond(_record_of(patient), "bandaged", "bandaged your wounds")
		(patient as Companion).tended()


## Her player fell with her beside them (within her hearing, she standing):
## loyalty, once a fall (the coordinator, 444).
func _bond_stood_by(entity: GridEntity, _cause: StringName) -> void:
	if not entity is Player:
		return
	for pet: Companion in _companions.values():
		if is_instance_valid(pet) and pet.spawned and pet.hp > 0 and pet.keeper == entity \
				and World.distance(pet.tile, entity.tile) <= HEARING_RANGE:
			_bond(_record_of(pet), "stood_by", "fell with you at their side")


## A thing in her hands grew (417): "Isolde's dagger is imp-bane now.",
## "... holds a grudge against wolves.", "... has had its vengeance on wolves."
func _card_grew(entity: GridEntity, uid: int, mark: String, kind: String) -> void:
	if not entity is Companion:
		return
	var thing := World.item_title(uid).get_slice(" (", 0)
	if thing.is_empty():
		thing = "%s's %s" % [entity.name, Items.name_of(World.items.id_of(uid))]
	var words: String = {"bane": "is %s-bane now" % kind, "grudge": "holds a grudge against %s" % World._plural(kind),
		"avenged": "has had its vengeance on %s" % World._plural(kind)}.get(mark, "")
	if not words.is_empty():
		(entity as Companion).note_fact("%s %s." % [thing, words])


## Her card's fact of a return (293 amended, on 396): "Wren fell, and was
## brought back at the temple by Father Aldo."
static func return_fact(who: String, where: String, by: String) -> String:
	return "%s fell, and was brought back at %s%s." % [who, where, " by " + by if not by.is_empty() else ""]


## A thing grew (World.item_grew; decision 417): a bane, a grudge, avenged.
func _narrate_grew(entity: GridEntity, uid: int, mark: String, kind: String) -> void:
	var thing := World.item_title(uid)
	if thing.is_empty():
		thing = "%s's %s" % [_display_name(entity), Items.name_of(World.items.id_of(uid))]
	var kinds := World._plural(kind)
	match mark:
		"bane":
			party_log.add("%s has felled so many %s it is their bane." % [thing, kinds])
		"grudge":
			party_log.add("%s has seen its bearers hurt by %s enough: it holds a grudge against them." % [thing, kinds])  # Decision 473.
		"avenged":
			party_log.add("%s has had its vengeance on %s." % [thing, kinds])
		"character":
			party_log.add("%s has seen enough use to grow: it counts what it fells now." % thing)  # Decision 472.


## A named thing kept from its namer, or back with them (World.item_kept;
## decision 370).
func _narrate_kept(entity: GridEntity, uid: int, kept: bool) -> void:
	var name := World.items.name_of(uid)
	var title := World.item_title(uid).get_slice(" (", 0)
	if kept:
		party_log.add("%s keeps %s from %s." % [_display_name(entity), title, name.get("holder", "")])
	else:
		party_log.add("%s is back with %s." % [title, _display_name(entity)])


## A bundle of arrows swapped for one on the ground (World.bundle_swapped;
## decision 375): what was taken and what was left, with their condition.
func _narrate_swap(by: GridEntity, taken: int, left: int) -> void:
	party_log.add("%s takes up %s and puts down %s." % [_display_name(by), World.item_note(taken), World.item_note(left)])


## A bow held at full draw till their stamina ran out (World.draw_given_up,
## decision 669): let down, nothing loosed; the archer told.
func _tell_arms_gave(by: GridEntity) -> void:
	if by is Player and (by as Player).owner_peer != 0:
		Net.broadcast_to([(by as Player).owner_peer], "party", {"from": "Server", "text": "Your arms give out."})


## A blow that knocked someone down (World.knocked_down).
func _narrate_down(entity: GridEntity, source: GridEntity) -> void:
	party_log.add("%s knocks %s down." % [_display_name(source), _display_name(entity)])


## A shield bash (World.shield_bashed; decision 379).
func _narrate_bash(by: GridEntity, target: GridEntity, opened: bool) -> void:
	if opened:
		party_log.add("%s bashes %s's guard open." % [_display_name(by), _display_name(target)])
	else:
		party_log.add("%s shoves %s with a shield." % [_display_name(by), _display_name(target)])


## A blow taken on a guard, or one that broke it (World.guard_met).
func _narrate_guard(entity: GridEntity, source: GridEntity, broken: bool) -> void:
	if broken:
		party_log.add("%s breaks %s's guard." % [_display_name(source), _display_name(entity)])
	else:
		party_log.add("%s takes %s's blow on the guard." % [_display_name(entity), _display_name(source)])


func _narrate_damage(entity: GridEntity, amount: int, source: GridEntity, cause: StringName) -> void:
	_blow_target = entity
	_blow_source = source
	match cause:
		&"fire":
			party_log.add("%s burned for %d." % [_display_name(entity), amount])
		&"impact":
			party_log.add("%s took %d from the impact." % [_display_name(entity), amount])
		&"bleed":
			party_log.add("%s bled for %d." % [_display_name(entity), amount])
		&"shot":
			if source != null:
				party_log.add("%s shot %s for %d." % [_display_name(source), _display_name(entity), amount])
		_:
			if source != null:
				party_log.add("%s hit %s for %d." % [_display_name(source), _display_name(entity), amount])


## Distance from [param tile] to the nearest monster, or a large number.
func _nearest_hostile_distance(tile: Vector2i) -> int:
	var nearest := 999
	for entity in World.get_entities():
		if entity is Monster and entity.spawned:
			nearest = mini(nearest, World.distance(tile, entity.tile))
	return nearest


## The free start tile farthest from every monster; [param fallback] if no
## start tile is free.
func _safest_start_tile(fallback: Vector2i) -> Vector2i:
	var best := fallback
	var best_distance := -1
	for start in player_starts:
		if not World.is_free(start):
			continue
		var distance := _nearest_hostile_distance(start)
		if distance > best_distance:
			best = start
			best_distance = distance
	return best


## [param wanted] if it is free, else the closest free walkable tile that is
## not on fire, else a start tile.
func _nearest_free(wanted: Vector2i) -> Vector2i:
	var queue: Array[Vector2i] = [wanted]
	var seen: Dictionary[Vector2i, bool] = {wanted: true}
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		if World.is_free(tile) and not World.is_burning(tile):
			return tile
		if seen.size() > 2000:
			break
		# Out of a cell that is no ground (one builder mode made water, say)
		# through anything, to the nearest ground; along the ground after.
		var stuck := not World.is_walkable(tile)
		for direction in World.DIRECTIONS:
			var next := tile + direction
			if not seen.has(next) and (stuck or World.is_walkable(next)):
				seen[next] = true
				queue.append(next)
	return _free_start_tile()


func _free_start_tile() -> Vector2i:
	for tile in player_starts:
		if World.is_free(tile):
			return tile
	for cell: Vector2i in _terrain["floor"]:
		if World.is_free(cell) and not World.is_burning(cell):
			return cell
	return player_starts[0] if not player_starts.is_empty() else Vector2i.ZERO


## MultiplayerSpawner's spawn function: runs on the server and on every client
## with the same data, so static configuration never needs replicating.
func _build_entity(spec: Dictionary) -> Node:
	if spec.get("script") == DOOR:
		return Door.build(spec)
	if spec.get("script") == PILE:
		return GroundPile.build(spec)
	return EntityFactory.build(spec)


func _on_peer_authenticated(peer: int, id: String, player_name: String) -> void:
	_admit(peer, id, player_name)


func _on_peer_disconnected(peer: int) -> void:
	var player: Player = _players.get(peer)
	var id: String = _peer_ids.get(peer, "")
	var was := World.enter_named(World.peer_zone.get(peer, World.zone.name))
	_leave(peer, player, id)
	World.peer_zone.erase(peer)
	Net.interest.forget(peer)
	World.enter(was)


func _leave(peer: int, player: Player, id: String) -> void:
	_players.erase(peer)
	_peer_ids.erase(peer)
	_respawn_at.erase(peer)
	if id == "":
		print("[net] peer %d left before joining" % peer)
		return
	var record: PlayerRecord = _records.get(id)
	if is_instance_valid(player) and player.spawned:
		if record != null:
			record.remember(player)
			if World.is_downed(player):
				# Gone while downed (decision 544): fallen, brought back as ever.
				record.hp = 0
				_start_return(id, "player", player.tile)
		World.despawn(player)
	elif record != null:
		record.last_seen = int(Time.get_unix_time_from_system())
	# The companion stays, idle and of no interest to monsters, until its
	# owner is back.
	var pet: Companion = _companions.get(id)
	if is_instance_valid(pet) and pet.spawned:
		_remember_companion(id)
		pet.keeper = null
		pet.current_intent = Companion.Intent.IDLE
		# One from before the roll rests in town between trips only when her
		# player left on its ground (Jeff's barrow: a deploy's restart mid-dungeon
		# sent Pip home); elsewhere she waits, as any companion, and is beside
		# them when they are back.
		var town_ground := _town_ground(pet.zone, pet.tile)
		if record != null and not _stay_in_town(record, pet) and CompanionCard.is_legacy(str(record.companion.get("name", ""))) \
				and not town_ground.is_empty():
			_rest_in_town(record, pet, id, town_ground)
	print("[net] %s (%s) left" % [record.name if record != null else "?", id.left(8)])
	party_log.add("%s left." % (record.name if record != null else "someone"))


## A player that dies comes back after RESPAWN_TICKS, as long as its peer is
## still here. Placeholder rule so the test room stays usable.
func _on_entity_despawned(entity: GridEntity) -> void:
	# Whatever goes, no companion holds it once it is freed (decision 572).
	# Untyped: a freed one is never put in a typed variable.
	for pet: Variant in _companions.values():
		if is_instance_valid(pet) and pet != entity:
			pet.forget(entity)
	if _travelling:
		return  # Gone to another zone, not dead.
	if entity.spawn_spec.has("spawn"):
		var slot: int = entity.spawn_spec["spawn"]
		if _alive_slots.get(slot) == entity:
			_alive_slots.erase(slot)
			_dead_since[slot] = World.tick
	var peer := entity.owner_peer
	if entity is Player and _players.get(peer) == entity:
		_players.erase(peer)
		_fell_at[peer] = entity.tile
		if _start_return(str(_peer_ids.get(peer, "")), "player", entity.tile):
			print("[net] %s died; to be brought back" % entity.name)
		else:
			_respawn_at[peer] = World.tick + RESPAWN_TICKS
			_tell_return(peer, "", "", RESPAWN_TICKS)
			print("[net] %s died; respawning in %d ticks" % [entity.name, RESPAWN_TICKS])
	if entity is Companion:
		var record: PlayerRecord = _records.get(entity.keeper_id)
		if record != null and not record.companion.is_empty():
			record.companion["alive"] = false
			_start_return(entity.keeper_id, "companion", entity.tile)
		_companions.erase(entity.keeper_id)
	if entity is Resident and not (entity as Resident).worker_id.is_empty() and World.production != null:
		# Their town's record is their truth: away till brought back.
		var worker_id := (entity as Resident).worker_id
		if not World.production.worker(worker_id).is_empty() and _start_return(worker_id, "resident", entity.tile):
			World.production.set_away(worker_id, true)
	if entity.is_creature():
		party_log.add("%s died." % _display_name(entity))
	elif entity.body_material == GridEntity.BodyMaterial.WOOD:
		party_log.add("%s broke." % _display_name(entity))


## The world message's server side (decision 446): told who is in the game,
## their records, and where everyone is.
func _start_world_news() -> void:
	_world_news = WorldNews.new(World.holdings)
	_world_news.send = func(peer: int, data: Dictionary) -> void:
		if peer == Net.local_id:
			_on_message("world", data)  # A host's own map.
		else:
			Net.message_to(peer, "world", data)
	_world_news.peers = func() -> Dictionary: return _peer_ids
	_world_news.record_of = func(id: String) -> PlayerRecord: return _records.get(id)
	_world_news.members = _party_members
	_world_news.trade = func(areas: Array) -> Array: return World.trade.shown(areas) if World.trade != null else []


## Every player and companion in the game and where: WorldNews.members.
func _party_members() -> Array:
	var out: Array = []
	var peer_of := {}
	for peer: int in _peer_ids:
		var id: String = _peer_ids[peer]
		peer_of[id] = peer
		var record: PlayerRecord = _records.get(id)
		if record != null:
			out.append({"name": record.name, "area": World.peer_zone.get(peer, record.zone), "kind": "player", "peer": peer})
	for id: String in _companions:
		var pet: Companion = _companions[id]
		if is_instance_valid(pet) and pet.spawned:
			out.append({"name": pet.name, "area": pet.zone, "kind": "companion", "peer": int(peer_of.get(id, 0))})
	return out


## Each player's world map told what changed (decision 446): once a tick
## for all zones (Main hears each zone's tick), every CAMP_CHECK_TICKS.
func _tell_world(tick: int) -> void:
	if _world_news == null or tick == _news_tick:
		return
	_news_tick = tick
	for peer: int in _players:
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.spawned:
			_world_news.observe(peer, player.zone, player.tile)
	_observe_roads()  # Hers too (decision 551).
	_world_news.update()


## This zone's camps, each looked at (decision 429): one undefended, with a
## player in it, for CAMP_FALL_TICKS falls to nobody (Holdings.take, so
## place_taken: Towns.camp_taken frees who it held), told in the party log.
func _check_camps(tick: int) -> void:
	if World.holdings == null or World.zone == null:
		return
	var here := World.zone.name
	for camp: Dictionary in World.holdings.camps():
		var id: String = camp["id"]
		if camp["area"] != here:
			continue
		if not _camp_undefended(camp) or not _player_in(camp):
			_camp_clear_since.erase(id)
			continue
		var since: int = _camp_clear_since.get(id, tick)
		_camp_clear_since[id] = since
		if tick - since < CAMP_FALL_TICKS:
			continue
		_camp_clear_since.erase(id)
		var place := World.holdings.place(id)
		var held_by := World.holdings.factions.display_name(camp["faction"])
		if World.holdings.take(id, Factions.NOBODY):
			var named := str(place.get("name", ""))
			party_log.add("%s's camp%s falls." % [held_by.left(1).to_upper() + held_by.substr(1),
				" at %s" % named if not named.is_empty() and named.to_lower() != "camp" else ""])
			print("[holdings] %s falls: nobody of %s defends it, and players hold it" % [id, camp["faction"]])


## Fallen camps taken back by who held them (decision 429) once
## economy.json's rescue.restock_days (5) have passed since they fell, as
## economy restocks them (428), with no player standing in them; their
## slots then come back. Returns how many.
func _retake_camps() -> int:
	if World.holdings == null:
		return 0
	var days := 5.0
	if World.towns != null:
		days = float(World.towns.rules.get("rescue", {}).get("restock_days", days))
	var after := roundi(days * maxi(DayNight.day_steps, 1))
	var count := 0
	for fallen: Dictionary in World.holdings.fallen_camps():
		if int(fallen["age"]) < after or _anyone_in(fallen["id"]):
			continue
		if World.holdings.take(fallen["id"], fallen["faction"]):
			count += 1
			print("[holdings] %s is taken back by %s" % [fallen["id"], fallen["faction"]])
	return count


## Whether a player of any zone stands within place [param id]'s radius.
func _anyone_in(id: String) -> bool:
	var place := World.holdings.place(id)
	for peer: int in _players:
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.zone == place.get("area") and _within(player.tile, place["cell"], int(place["radius"])):
			return true
	return false


## Whether no living monster of [param camp]'s holder's side stands within
## its radius + CAMP_DEFEND_MARGIN.
func _camp_undefended(camp: Dictionary) -> bool:
	var place := World.holdings.place(camp["id"])
	var reach: int = int(place.get("radius", 1)) + CAMP_DEFEND_MARGIN
	var factions := World.holdings.factions
	for entity in World.get_entities():
		if not entity is Monster or entity is Animal:
			continue
		var kind := str(entity.spawn_spec.get("kind", ""))
		if factions.same_side(factions.of_kind(kind), camp["faction"]) and _within(entity.tile, camp["cell"], reach):
			return false
	return true


## Whether a player stands within [param camp]'s radius.
func _player_in(camp: Dictionary) -> bool:
	var radius: int = int(World.holdings.place(camp["id"]).get("radius", 1))
	for peer: int in _players:
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.zone == World.zone.name and _within(player.tile, camp["cell"], radius):
			return true
	return false


static func _within(tile: Vector2i, centre: Vector2i, radius: int) -> bool:
	var d := tile - centre
	return d.x * d.x + d.y * d.y <= radius * radius


## Whether the monster of [param spec] may come back where it lay: not in
## a camp of this zone that its side no longer holds (decision 429), so a
## cleared camp stays cleared till it is retaken.
func _camp_lets_back(spec: Dictionary) -> bool:
	if World.holdings == null or World.zone == null:
		return true
	var factions := World.holdings.factions
	var side := factions.of_kind(str(spec.get("kind", "")))
	if side == Factions.NOBODY:
		return true
	for id in World.holdings.places_in(World.zone.name):
		var place := World.holdings.place(id)
		if place.get("kind") != "camp" or factions.same_side(side, World.holdings.holder(id)):
			continue
		if _within(spec["tile"], place["cell"], int(place["radius"])):
			return false
	return true


## The sought (613 amended, economy's Towns.place_sought): where [param
## variant]'s story ({place: its tag, where, holder, story}) waits for
## [param town]'s newcomer of [param trade]: the refuge keyed by the tag in
## any level, {place: its id, where}; "" while none is laid (economy tries
## the next variant, then the next day).
func _place_sought(_town: String, _trade: String, variant: Variant, _id: String) -> Variant:
	var tag := str(variant.get("place", "")) if variant is Dictionary else ""
	if tag.is_empty():
		return ""
	var areas: Array = _world_map.areas.keys()
	areas.sort()
	for area: String in areas:
		var place: Dictionary = _world_map.areas[area].get("places", {}).get(tag, {})
		if place.get("kind") == "refuge":
			return {"place": "%s/%s" % [area, tag], "where": str(place.get("where", ""))}
	return ""


## A place changed hands (Holdings.place_taken): a camp's fall frees who it
## held (Towns.camp_taken, decision 428).
func _on_place_taken(id: String, from: String, to: String) -> void:
	if World.towns != null and World.holdings.place(id).get("kind") == "camp":
		World.towns.camp_taken(id, from, to)
	_bond_cleared(id, from, to)
	_favour_camp(id, from, to)


## A camp taken from a side hostile to the town in the area she warned her
## player of and left over (581 amended): the "camp" repair.
func _favour_camp(id: String, from: String, to: String) -> void:
	var factions := World.holdings.factions if World.holdings != null else null
	if factions == null or not factions.hostile(from, "town") or factions.hostile(to, "town"):
		return
	var area := str(World.holdings.place(id).get("area", ""))
	for record: PlayerRecord in _records.values():
		if has_left(record) and not area.is_empty() and str(record.companion["left"].get("area", "")) == area:
			_favour_repaired(record, "camp")


## A place taken from a side hostile to the town by one that is not (555
## amended, Jeff: "areas affect loyalty"): each companion out with her
## player in its area cleared it with them.
func _bond_cleared(id: String, from: String, to: String) -> void:
	var factions := World.holdings.factions if World.holdings != null else null
	if factions == null or not factions.hostile(from, "town") or factions.hostile(to, "town"):
		return
	var place := World.holdings.place(id)
	for pet: Companion in _companions.values():
		if is_instance_valid(pet) and pet.spawned and pet.zone == str(place.get("area", "")) and is_instance_valid(pet.keeper) \
				and pet.keeper.zone == pet.zone:
			_bond(_record_of(pet), "cleared", "cleared %s with you" % str(place.get("name", "the camp")))
			if _area_freed(pet.zone):
				_bond(_record_of(pet), "finished", "freed this whole place of its camps with you")


## Whether no place in [param area] is held by a faction hostile to the
## towns (decision 621: an area finished together).
func _area_freed(area: String) -> bool:
	var factions := World.holdings.factions if World.holdings != null else null
	if factions == null:
		return false
	for id: String in World.holdings.places_in(area):
		if factions.hostile(World.holdings.holder(id), "town"):
			return false
	return true


## Who has landed a blow on each monster, by its instance id (decision 621).
var _blows: Dictionary = {}


## A blow on a monster: who landed it, kept till it dies.
func _bond_blow(entity: GridEntity, amount: int, source: GridEntity, _cause: StringName) -> void:
	if amount > 0 and entity is Monster and source != null and (source is Player or source is Companion):
		var hitters: Dictionary = _blows.get_or_add(entity.get_instance_id(), {})
		if hitters.is_empty() and source is Player:
			# Her player's first blow on it: a fight they started, if it
			# was not already after them (Companion.struck_first).
			for pet: Companion in _companions.values():
				if is_instance_valid(pet) and pet.spawned and pet.keeper == source:
					pet.struck_first(entity)
		hitters[source.get_instance_id()] = true


## A monster died: a fight won together for each companion who landed a
## blow on it as her player did (decision 621).
func _bond_won(entity: GridEntity, _cause: StringName) -> void:
	if not entity is Monster:
		return
	var hitters: Dictionary = _blows.get(entity.get_instance_id(), {})
	_blows.erase(entity.get_instance_id())
	for pet: Companion in _companions.values():
		if is_instance_valid(pet) and is_instance_valid(pet.keeper) and hitters.has(pet.get_instance_id()) \
				and hitters.has(pet.keeper.get_instance_id()):
			_bond(_record_of(pet), "fought", "won a fight beside you")


## Her voice felt her player's words (decision 621): "hurt", harsh words,
## a drop at most harsh_a_day times a game day; "sorry", the same day,
## takes one back.
func _bond_felt(kind: String, pet: Companion) -> void:
	var record := _record_of(pet)
	if record == null or record.companion.is_empty():
		return
	var day := int(World.steps / maxi(DayNight.day_steps, 1))
	var said: Dictionary = record.companion.get("bond_said", {})
	if int(said.get("day", -1)) != day:
		said = {"day": day, "hurt": 0, "sorry": 0}
	record.companion["bond_said"] = said
	var most := int((CompanionCard.tables().get("bond", {}) as Dictionary).get("harsh_a_day", 2))
	if kind == "hurt" and int(said["hurt"]) < most:
		said["hurt"] = int(said["hurt"]) + 1
		_bond(record, "harsh", "spoke harshly to you")
	elif kind == "sorry" and int(said["sorry"]) < int(said["hurt"]):
		said["sorry"] = int(said["sorry"]) + 1
		Standing.bump(record.companion, record.player_id, -int((CompanionCard.tables().get("bond", {}) as Dictionary).get("drops", {}).get("harsh", -1)),
			"said sorry for their harsh words", World.steps)
		_set_mood(record)


## A game of knucklebones played out (decision 621): her tally against her
## player ("games" {hers, theirs}, for her run summary), and the deed.
func _bond_played(won: bool, pet: Companion) -> void:
	var record := _record_of(pet)
	if record == null or record.companion.is_empty():
		return
	var games: Dictionary = record.companion.get("games", {"hers": 0, "theirs": 0})
	games["hers" if won else "theirs"] = int(games.get("hers" if won else "theirs", 0)) + 1
	record.companion["games"] = games
	party_log.add("%s %s at knucklebones (%d games to %d)." % [pet.name, "wins" if won else "loses", int(games.get("hers", 0)), int(games.get("theirs", 0))])
	_bond(record, "game", "played knucklebones with you")


## Whether [param cell] lies on a road of the zone ticking now (decision
## 621, her days on the roads): its terrain's "roads" curves' cells.
func _on_road(cell: Vector2i) -> bool:
	var zone := String(World.zone.name)
	if not _road_cells.has(zone):
		var cells := {}
		for road: Dictionary in (World.zone.main.get("terrain", {}) as Dictionary).get("roads", []):
			for each: Vector2i in Curves.cells(road["curve"], false):
				cells[each] = true
		_road_cells[zone] = cells
	return (_road_cells[zone] as Dictionary).has(cell)


## Each zone's road cells, as _on_road found them.
var _road_cells: Dictionary = {}


## She went down, or died (555 amended): with her player nowhere near
## (out of hearing, or gone), left to fall alone; bled out downed while
## her player, blessed with uses left, stood within hearing, let bleed.
func _bond_left_down(entity: GridEntity, _source: GridEntity, _ticks: int) -> void:
	if entity is Companion and not _near_keeper(entity as Companion):
		_bond(_record_of(entity), "left_alone", "left you to fall alone")


func _bond_fell(entity: GridEntity, cause: StringName) -> void:
	var pet := entity as Companion
	if pet == null:
		return
	var record := _record_of(pet)
	if record == null:
		return
	if cause == &"bled":
		if _near_keeper(pet) and World.totem_charges(World.totem_of(record.player_id)) > 0:
			_bond(record, "let_bleed", "let you bleed out")
	elif not _near_keeper(pet):
		_bond(record, "left_alone", "left you to fall alone")


## Whether [param uid] is grave goods (555, items' side: World.items.is_grave;
## false before it).
func _grave_goods(uid: int) -> bool:
	return World.items != null and World.items.has_method("is_grave") and bool(World.items.call("is_grave", uid))


## Whether [param pet]'s player stands within her hearing.
func _near_keeper(pet: Companion) -> bool:
	return is_instance_valid(pet.keeper) and pet.keeper.spawned and pet.keeper.zone == pet.zone \
		and World.distance(pet.keeper.tile, pet.tile) <= HEARING_RANGE


## Her player took her into an area she refused as unsafe that day (555
## amended; 551 phase 2's refusals): once a refusal.
func _bond_warned(pet: Companion) -> void:
	var refused: Dictionary = _guide_refused.get(pet.keeper_id, {})
	var day := Townsfolk.day_of(World.steps)
	for key: String in refused:
		var entry: Dictionary = refused[key]
		if int(entry.get("day", -1)) == day and str(entry.get("area", "")) == pet.zone and not entry.get("walked", false):
			entry["walked"] = true
			var record := _record_of(pet)
			if record != null:
				record.companion["warned_area"] = pet.zone  # Which road, if she leaves over it (581 amended).
			_bond(record, "warned", "ignored your warning and took you there")


## Each temple counter in the zone shows what is held for the first player
## within reach of it, or nothing with nobody there (World.show_held,
## decision 434).
func _temple_counters() -> void:
	for entity: GridEntity in World.get_entities():
		if not (entity is Chest and (entity as Chest).temple):
			continue
		var at: GridEntity = null
		for peer: int in _players:
			var player: Player = _players[peer]
			if is_instance_valid(player) and player.spawned and World.reaches(player, entity):
				at = player
				break
		World.show_held(entity, at)




# --- Talk with no panel (decision 536) ------------------------------------------------

## Server: [param line], said by [param player] to [param body], handled
## without the mind when it is an ask or an answer: an ask for wares, work
## or news speaks the matching offer's words back, exactly, and keeps it as
## the offer standing for the player (asked again, the next); a yes word, an
## amount, or the name of a thing or person takes the offer named, else the
## one standing, through the accept path (an amount over the purse or the
## cap is refused in words); a no clears what stands, nothing said back.
## True when handled; false for a line of the player's own, the mind's.
func _offer_said(body: Resident, player: Player, line: String) -> bool:
	if World.production == null or body == null or player == null or body.worker_id.is_empty():
		return false
	var player_id := player.player_id
	var ask := Offers.ask_kind(line)
	var amount := Offers.amount_said(line)
	var standing := _standing_for(player_id, body.worker_id)
	if ask in ["wares", "work", "news"]:
		var offer := Offers.to_speak(body.worker_id, player_id, ask, str(standing.get("id", "")))
		if offer.is_empty():
			return false  # Nothing of that kind: the mind answers as it would.
		Transcript.record(body.person, _display_name(player), line)
		_speak_offer(body, body.worker_id, body.person, player, offer)
		return true
	var target := Offers.named(body.worker_id, player_id, line)
	if target.is_empty() and (ask == "yes" or amount > 0) and not standing.is_empty():
		for offer: Dictionary in Offers.of(body.worker_id, player_id):
			if str(offer.get("id", "")) == str(standing["id"]) and not bool(offer.get("open", false)):
				target = offer
	if ask == "no" and not standing.is_empty():
		_standing.erase(player_id)
		Transcript.record(body.person, _display_name(player), line)
		_send_offers(body, player_id, player.owner_peer)
		return true
	if target.is_empty():
		return false
	Transcript.record(body.person, _display_name(player), line)
	var gold := amount
	if gold <= 0 and str(target.get("accept", "")) == Offers.LEND:
		gold = mini(int(target.get("cost", 0)), World.gold_of(player_id))  # A yes to a debt: what is owed, or all they have.
	var refusal := Offers.amount_refusal(target, amount, World.gold_of(player_id))
	if not refusal.is_empty():
		_say_plain(body, body.person, refusal)
		return true
	_accept_offer(player, str(target["id"]), gold)
	return true


## [param body] speaks [param offer]'s words to [param player], exactly, as
## its speech and the party log's line, and it stands for them.
func _speak_offer(speaker: GridEntity, key: String, name: String, player: Player, offer: Dictionary) -> void:
	var words := str(offer.get("words", ""))
	if words.is_empty():
		words = str(offer.get("title", ""))
	_standing[player.player_id] = {"worker": key, "id": str(offer.get("id", "")), "title": str(offer.get("title", "")),
		"at": World.steps, "zone": speaker.zone, "offer": offer.duplicate(true)}
	MindLog.record({"kind": "offer", "companion": name, "mind": "resident" if speaker is Resident else "monster", "say": words, "outcome": "spoken"})
	if speaker is Resident and _resident_quiet(speaker, player):
		_held_tongue("offer")  # The offer stands, unspoken (675, npc's side).
	else:
		_say_plain(speaker, name, words, "[offer] ")
	if speaker is Resident:
		_send_offers(speaker, player.player_id, player.owner_peer)
	else:
		_send_monster_offers(speaker, player.player_id, player.owner_peer)


## [param body] says [param words] with no mind asked: the transcript (with
## [param note]), the party log, those near, the speech bubble.
func _say_plain(speaker: GridEntity, name: String, words: String, note := "") -> void:
	if speaker is Resident and _resident_quiet(speaker):
		_held_tongue("say")  # 675, npc's side.
		return
	Transcript.record(name, name, note + words)
	party_log.add("%s said: \"%s\"" % [name, words])
	if speaker is Resident:
		_heard_near(speaker, name, words)
	Net.broadcast_to(hearers(speaker.tile), "speech", {"entity": String(speaker.get_path()), "speaker": name, "text": words})


## The offer standing for [param player_id] with [param worker_id], {} for
## none: one spoken within a day whose body is still within hearing in this
## zone; else it is let go.
func _standing_for(player_id: String, worker_id: String) -> Dictionary:
	var standing: Dictionary = _standing.get(player_id, {})
	if standing.is_empty():
		return {}
	if str(standing.get("worker", "")) != worker_id:
		return {}
	var player: Player = null
	for each: Player in _players.values():
		if is_instance_valid(each) and each.player_id == player_id:
			player = each
	var body: GridEntity = null
	if worker_id.begins_with("/"):
		var node := get_node_or_null(worker_id)  # A talking monster, by its path (548).
		body = node if node is GridEntity and (node as GridEntity).spawned else null
	else:
		for entity: GridEntity in World.townsfolk():
			if entity is Resident and (entity as Resident).worker_id == worker_id:
				body = entity
	if World.steps - int(standing.get("at", 0)) > maxi(DayNight.day_steps, 1) or body == null or player == null \
			or body.zone != player.zone or World.distance(body.tile, player.tile) > HEARING_RANGE:
		_standing.erase(player_id)
		return {}
	return standing



## The talking monsters hooked (instance id -> true), so each is hooked once.
var _talkers: Dictionary = {}


## Server: the monster that talks (Monster.talks, with offers_for: the
## draugr, 548) that [param line] from [param player] is for: one named in
## it within hearing, else the nearest within RESIDENT_EARSHOT; null for
## none. Residents are looked at first (_resident_addressed).
func _monster_addressed(player: Player, line: String) -> GridEntity:
	var nearest: GridEntity = null
	for entity: GridEntity in World.get_entities():
		if not entity is Monster or not (entity as Monster).talks or not entity.has_method("offers_for") or entity.zone != player.zone:
			continue
		var d := World.distance(entity.tile, player.tile)
		if d > HEARING_RANGE:
			continue
		if Companion._named(line, _display_name(entity)):
			return entity
		if d <= RESIDENT_EARSHOT and (nearest == null or d < World.distance(nearest.tile, player.tile)):
			nearest = entity
	return nearest


## Server: [param line] said to talking monster [param monster] (decision
## 546, npc's side; the draugr, 548): an ask for wares, work or news speaks
## its first offer (offers_for; asked again, the next) and it stands; a yes
## word or an amount said goes to its accept_offer with the gold (0 for a
## bare yes: the monster's own refusal), after Main's one check, the purse;
## its reply is spoken, its line logged, and on ok nothing stands; a no
## clears what stands. True when handled.
func _monster_said(monster: GridEntity, player: Player, line: String) -> bool:
	if monster == null or player == null or not monster.has_method("offers_for"):
		return false
	var key := String(monster.get_path())
	var name := _display_name(monster)
	var player_id := player.player_id
	var ask := Offers.ask_kind(line)
	var amount := Offers.amount_said(line)
	var standing := _standing_for(player_id, key)
	if ask in ["wares", "work", "news"]:
		var offers: Array = monster.offers_for(player_id)
		if offers.is_empty():
			return false
		var pick: Dictionary = offers[0]
		for i in offers.size():
			if str(offers[i].get("id", "")) == str(standing.get("id", "")):
				pick = offers[(i + 1) % offers.size()]
		Transcript.record(name, _display_name(player), line)
		_speak_offer(monster, key, name, player, pick)
		return true
	if ask == "no" and not standing.is_empty():
		_standing.erase(player_id)
		Transcript.record(name, _display_name(player), line)
		_send_monster_offers(monster, player_id, player.owner_peer)
		return true
	if not (ask == "yes" or amount > 0):
		return false
	Transcript.record(name, _display_name(player), line)
	if standing.is_empty():
		# Nothing standing (629 amended; Jeff: "yes didn't do anything"): words back, never silence. A sum goes
		# to his first offer as the deal; a bare yes is asked for the sum and his offer stands; with nothing to
		# offer (a pact on), his word that nothing stands.
		var offers: Array = monster.offers_for(player_id)
		if offers.is_empty():
			_say_plain(monster, name, NOTHING_STANDS)
		elif amount > 0 or Offers.free_deal(offers[0]):
			# A sum, or a deal already paid for (548 amended: the draugr's "again"): a yes takes it.
			_monster_accepts(monster, player, offers[0], amount)
		else:
			_say_plain(monster, name, YES_TO_WHAT)
			_speak_offer(monster, key, name, player, offers[0])
		return true
	var offer: Dictionary = standing.get("offer", {})
	_monster_accepts(monster, player, offer, amount)
	return true


## Server: [param player] gives [param gold] on talking [param monster]'s
## [param offer] (the typed path's amount, or ui's button through
## accept_offer, decision 629): Main's one check, the purse; then his
## accept_offer, his reply spoken, his line logged, nothing standing on ok,
## and his offers sent again.
func _monster_accepts(monster: GridEntity, player: Player, offer: Dictionary, gold: int) -> void:
	var name := _display_name(monster)
	var player_id := player.player_id
	if Offers.free_deal(offer):
		gold = 0  # Paid for already (548 amended): no purse asked, nothing taken, whatever sum was said.
	if gold > World.gold_of(player_id):
		_say_plain(monster, name, "You have but %d gold." % World.gold_of(player_id))
		return
	var result: Variant = monster.accept_offer(player, offer, gold)
	if not result is Dictionary:
		return
	if not str(result.get("say", "")).is_empty():
		_say_plain(monster, name, str(result["say"]))
	if not str(result.get("line", "")).is_empty():
		party_log.add(str(result["line"]))
	if bool(result.get("ok", false)):
		_standing.erase(player_id)
	_send_monster_offers(monster, player_id, player.owner_peer)


## Server: E on talking [param monster] by [param player] (the "greet"
## command with his path, decision 629; Jeff: "no way to give gold to
## draugr"): within hearing, his first offer is spoken and stands (the next
## one each time, as a typed ask for wares does), and the "offers" message
## carries his deals for ui's buttons; with nothing to offer (a pact on)
## the message alone, empty.
func _monster_greeted(player: Player, monster: GridEntity) -> void:
	if monster == null or player == null or not monster.spawned or monster.zone != player.zone \
			or World.distance(talk_cell(monster), player.tile) > HEARING_RANGE:
		return
	var key := String(monster.get_path())
	var name := _display_name(monster)
	var offers: Array = monster.offers_for(player.player_id)
	Transcript.record(name, _display_name(player), "[greets]")
	if offers.is_empty():
		if monster.has_method("resting") and monster.call("resting"):
			# The draugr at rest (573 amended (3)): silent; the one who asked is told how long.
			Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": str(monster.call("rest_words"))})
		_send_monster_offers(monster, player.player_id, player.owner_peer)
		return
	var standing := _standing_for(player.player_id, key)
	var pick: Dictionary = offers[0]
	for i in offers.size():
		if str(offers[i].get("id", "")) == str(standing.get("id", "")):
			pick = offers[(i + 1) % offers.size()]
	_speak_offer(monster, key, name, player, pick)


## The "offers" message for a talking monster: its offers_for, under its
## path and name, with the offer standing (548's revision 25 covers it).
func _send_monster_offers(monster: GridEntity, player_id: String, peer: int) -> void:
	if monster == null or not is_instance_valid(monster) or player_id.is_empty() or peer < 0 or not monster.has_method("offers_for"):
		return
	var data := {"entity": String(monster.get_path()), "speaker": _display_name(monster), "offers": monster.offers_for(player_id)}
	var standing := _standing_for(player_id, String(monster.get_path()))
	if not standing.is_empty():
		data["standing"] = {"id": standing["id"], "title": standing["title"]}
	Net.message_to(peer, "offers", data)


## [param monster] talks (offers_for): its offer_spoken (it talks first:
## the words spoken and standing for that player) and offer_withdrawn
## (nothing stands) are heard; once per instance.
func _hook_talker(monster: GridEntity) -> void:
	if monster == null or _talkers.has(monster.get_instance_id()):
		return
	_talkers[monster.get_instance_id()] = true
	if monster.has_signal("offer_spoken"):
		monster.connect("offer_spoken", func(player_id: String, offer: Dictionary) -> void: _on_offer_spoken(monster, player_id, offer))
	if monster.has_signal("offer_withdrawn"):
		monster.connect("offer_withdrawn", func(player_id: String) -> void: _on_offer_withdrawn(monster, player_id))
	if monster.has_signal("hall_door"):
		# The draugr's (573 amended): false shuts his hall's door, true opens it.
		monster.connect("hall_door", func(open: bool) -> void: _hold_hall_door(monster.zone, not open))
	if monster.has_signal("ossuary_sealed"):
		# The draugr's (666): whether any of his zone's dead stands, the hall sealed while one does.
		monster.connect("ossuary_sealed", func(sealed: bool) -> void: _seal_hall(monster.zone, sealed))
	if monster.has_signal("said"):
		# His unasked lines (573 amended: why one entered, the win, his respect).
		monster.connect("said", func(text: String) -> void:
			if is_instance_valid(monster) and monster.spawned:
				_say_plain(monster, _display_name(monster), text))


func _on_offer_spoken(monster: GridEntity, player_id: String, offer: Dictionary) -> void:
	if not is_instance_valid(monster) or not monster.spawned:
		return
	for player: Player in _players.values():
		if is_instance_valid(player) and player.player_id == player_id and player.zone == monster.zone:
			_speak_offer(monster, String(monster.get_path()), _display_name(monster), player, offer)
			return


func _on_offer_withdrawn(monster: GridEntity, player_id: String) -> void:
	if not is_instance_valid(monster):
		return
	var standing: Dictionary = _standing.get(player_id, {})
	if str(standing.get("worker", "")) != String(monster.get_path()):
		return
	_standing.erase(player_id)
	for player: Player in _players.values():
		if is_instance_valid(player) and player.player_id == player_id:
			_send_monster_offers(monster, player_id, player.owner_peer)



# --- Pip's alms run (decision 546, npc's side) ----------------------------------------

## The runner's rules (townsfolk.json "runner").
func _runner_rule() -> Dictionary:
	return Townsfolk.rules().get("runner", {})


## [param town]'s priest (the temple's official), "" for none.
func _priest_of(town: String) -> String:
	if World.production == null:
		return ""
	var trade := str(World.production.rules.get("return", {}).get("places", {}).get("temple", {}).get("trade", "priest"))
	var ids := World.production.worker_ids(town)
	ids.sort()
	for id: String in ids:
		if trade in World.production.worker(id).get("trades", []):
			return id
	return ""


## Server: [param town]'s runner, Pip (decision 546, npc's side): the
## priest's apprentice, else the resident of that name, else seated now
## as a settled resident of the town (Towns.move_in, origin "settled": his
## own, not the town's growth) and made the priest's apprentice. His card
## reads the companion table's Pip (CompanionCard: his look, his leanings:
## superstition 2, intellect 4), not a roll, so the resident and the
## companion are one person. "" with no priest (no temple, no runs).
func _runner_of(town: String) -> String:
	var priest := _priest_of(town)
	if priest.is_empty():
		return ""
	var rule := _runner_rule()
	var name := str(rule.get("name", "Pip"))
	var who := str(World.production.worker(priest).get("apprentice", ""))
	if who.is_empty() or World.production.worker(who).is_empty():
		who = ""
		for id: String in World.production.worker_ids(town):
			if str(World.production.worker(id).get("name", "")) == name:
				who = id
				break
	var trade := str(rule.get("trade", "acolyte"))
	if who.is_empty():
		who = "runner:" + town
		if World.production.worker(who).is_empty():
			if World.towns == null or not World.towns.move_in(town, who, name, trade, "settled"):
				return ""
			print("[runner] %s, the priest's apprentice, lives in %s" % [name, town])
	elif trade not in World.production.worker(who).get("trades", []):
		# The town's own Pip (the box's carpenter, 2026-10-20): the acolyte in place, his
		# name, card and home kept, his bench left for the town to fill again.
		World.production.retrain(who, trade)
		print("[runner] %s leaves his bench to be the priest's acolyte in %s" % [name, town])
	if str(World.production.worker(who).get("master", "")).is_empty() and str(World.production.worker(priest).get("apprentice", "")).is_empty():
		World.production.set_apprentice(priest, who)
	_runner_card(who, name, rule)
	return who


## Pip's card and leanings from the companion table, once.
func _runner_card(who: String, name: String, rule: Dictionary) -> void:
	var card := Townsfolk.card_of(World.production, who)
	if card.is_empty() or bool(card.get("runner", false)):
		return
	card["runner"] = true
	var look: Dictionary = CompanionCard.legacy_look(name)
	if not look.is_empty():
		var kept: Dictionary = card.get("look", {})
		for key: String in look:
			kept[key] = look[key]
		card["look"] = kept
	var leanings: Dictionary = rule.get("leanings", {})
	for key: String in leanings:
		World.production.set_mind(who, key, int(leanings[key]))
	World.production.set_card(who, card)


## Whether the runner [param who] is about: not away, not sick, and no
## player's companion of his name is alive and untaken (companions' ctx
## companion_named: then the resident is away, his companion body being
## the Pip people see); such a companion gone, he is back.
func _runner_here(who: String, name: String) -> bool:
	var record := World.production.worker(who)
	if record.is_empty() or Townsfolk.is_sick(World.production, who):
		return false
	var taken: Variant = Offers._call(Offers.ctx, "companion_named", [name])
	var out_with_a_player: bool = taken is Dictionary and not taken.is_empty() and str(taken.get("where", "")) != "taken"
	var on_a_run := _alms_runs.values().any(func(run: Dictionary) -> bool: return str(run.get("who", "")) == who)
	if out_with_a_player and not bool(record.get("away", false)):
		World.production.set_away(who, true)
		_runner_out[who] = true
	elif not out_with_a_player and not on_a_run and bool(record.get("away", false)) and _runner_out.has(who):
		World.production.set_away(who, false)
		_runner_out.erase(who)
	return not out_with_a_player and not on_a_run and not bool(World.production.worker(who).get("away", false))


## Server, on the world tick: Pip's run (decision 546, npc's side). Once a
## day from the rule's hour, with gold at the altar (economy's altar_gold)
## and the runner about, he takes it (take_altar) and is away hours_each_way
## there and back, bodiless; home, it is laid below (altar_down). At the
## altar, once any player has learned Aldous's secret, lost_chance a run:
## he stays below with the gold until a player comes within found_reach of
## the barrow's niche place; the priest's card says he has not been seen
## (gossip carries it). Found: the gold goes down, he comes home, his card
## keeps the lived fact, the finder is told.
## A resident told [param player_id] a secret (Resident.world_facts, ctx
## "secret_told"): one of the crypt's marks them as knowing (Main._crypt_told:
## Pip's runs may go wrong from then, and Aldous's commissions open to them).
func _altar_down(town: String, gold: int) -> void:
	if World.economy != null and World.economy.has_method("altar_down"):
		World.economy.altar_down(town, gold)


## Server: the medicine man [param healer_id]'s retainer paid in person
## (Offers' CARE accept; 584 amended; the client's _retain is ui's button): economy's retain command with the two bodies,
## which sends the barter again with its why. {"ok"}.
func _retain_care(player_id: String, healer_id: String, pay: String) -> Dictionary:
	var player: Player = null
	for entity in World.get_entities():
		if entity is Player and entity.spawned and (entity as Player).player_id == player_id:
			player = entity
			break
	if player == null:
		return {"ok": false, "why": ""}
	for entity: GridEntity in World.townsfolk():
		if entity is Resident and (entity as Resident).worker_id == healer_id:
			return {"ok": not retain(player, {"resident": str(entity.get_path()), "pay": pay}).is_empty(), "why": ""}
	return {"ok": false, "why": ""}


## Server: a made thing [param item_id] from [param from_name] into
## [param player_id]'s free hand or pack, else on the ground at their feet
## (the medicine man's brew, 584 amended). False if they are not here.
func _hand_item(player_id: String, item_id: String, from_name: String) -> bool:
	if not Net.is_authority() or World.items == null or player_id.is_empty():
		return false
	for entity in World.get_entities():
		if not (entity is Player and entity.spawned and (entity as Player).player_id == player_id):
			continue
		var uid := World.items.mint(item_id, "made", from_name, World.zone.name, entity.tile)
		var slot := World.room_for(entity, uid)  # Onto a stack of its kind first (decision 619).
		if slot < 0 or not World.put_item(entity, entity, slot, uid):
			World.put_on_ground(uid, entity.tile)
		return true
	return false


func _give_gold(player_id: String, gold: int, why: String) -> void:
	if World.economy != null and gold > 0:
		World.economy.add_gold(player_id, gold, why)


func _secret_told(player_id: String, fact_id: String) -> void:
	# The crypt's secrets and the old gods' (lore's old_gods.*, the same secret's deeper why) both mark it.
	if (fact_id.begins_with("crypt.") or fact_id.begins_with("old_gods.")) and not player_id.is_empty() and not _crypt_told.get(player_id, false):
		_crypt_told[player_id] = true
		print("[crypt] %s has been told %s" % [player_id, fact_id])


## What Aldous may ask of [param player_id] now (Offers._crypt_offers, ctx
## "crypt_asks"): the offering's gold while gold waits at the altar and Pip
## is not carrying it; the lost runner's name while he is lost below; both
## only to one told the secret.
func _crypt_asks(town: String, player_id: String) -> Dictionary:
	if not _crypt_told.get(player_id, false):
		return {}
	var run: Dictionary = _alms_runs.get(town, {})
	var gold := 0
	if run.is_empty() and World.economy != null and World.economy.has_method("altar_gold"):
		gold = int(World.economy.altar_gold(town))
	var runner := ""
	if bool(run.get("lost", false)):
		runner = str(World.production.worker(str(run.get("who", ""))).get("name", "Pip")) if World.production != null else "Pip"
	return {"offering": gold, "runner": runner}


## Server, on the world tick: a player with a crypt commission standing
## within reach of the barrow's Altar (the offering laid) or of the Runner's
## pack (the runner's fate found) has met it (Offers.crypt_done).
## Residents speaking unprompted (decision 554, narrowing 336): every
## HAIL_CHECK_TICKS, a resident out and about with something to say
## (Resident.hail_cue: a plea, the town's news, a ruling, the sky, a
## greeting) hails the first player within TALK_REACH it has not hailed
## today, as the lowest ask of all: none while any ask waits or is out, or
## the mind's last answer came slower than hail.slow_ticks, and none to a
## player led, fighting, in a talk, or hailed within hail.minute_seconds.
## One a tick. The card remembers (Resident.hail_done); the answer takes
## 336's spoken path (_resident_answered: the words and the aside).
func _hails_tick() -> void:
	if World.production == null or not Net.is_authority():
		return
	var rules: Dictionary = Townsfolk.rules().get("hail", {})
	if not bool(rules.get("on", true)):
		return
	if not _resident_asks.is_empty() or not _resident_out.is_empty() or _mind_last_ticks > int(rules.get("slow_ticks", 50)):
		return
	var now_msec := Time.get_ticks_msec()
	var now := World.production.now()
	var day := Townsfolk.day_of(now)
	var sky := _sky_now()
	for entity in World.townsfolk():
		var body := entity as Resident
		if not _hail_able(body):
			continue
		for other in World.get_entities():
			var player := other as Player
			if player == null or not player.spawned or player.player_id.is_empty() or World.distance(player.tile, body.tile) > TALK_REACH:
				continue
			if _resident_quiet(body, player):
				continue  # No hail near a fight (675, npc's side).
			if _hail_now(body, player, rules, now_msec, now, day, sky):
				return


## Whether [param body] is one to hail or greet at all: spawned, out and
## about (not strayed, escorting, hiding, in bed), a townsperson (not a
## companion resting in town, who speaks for herself).
func _hail_able(body: Resident) -> bool:
	return body != null and is_instance_valid(body) and body.spawned and not body.strayed and body.escort_of.is_empty() and body.card.is_empty() \
			and body.doing not in [Resident.Doing.HIDE, Resident.Doing.BED, Resident.Doing.STRAYED, Resident.Doing.ESCORT]


## Whether [param body] holds its tongue now (675, npc's side): a hostile
## within Companion.COMBAT_RANGE of it or of [param player] (its listener,
## null for none), or within Companion.QUIET_AFTER ticks of one. A fight
## just begun drops its ask still waiting for the mind.
func _resident_quiet(body: Resident, player: GridEntity = null) -> bool:
	if not Companion.hold_tongue or body == null or not is_instance_valid(body):
		return false
	var last := int(_resident_fight_at.get(body.worker_id, -100000))
	if last != World.tick and _fight_near(body, player):
		if World.tick - last > Companion.QUIET_AFTER:
			var id := body.get_instance_id()
			var waiting := _resident_asks.size()
			_resident_asks = _resident_asks.filter(func(each: Dictionary) -> bool: return each["body"] != id)
			if _resident_asks.size() < waiting:
				_held_tongue("ask")
		last = World.tick
		_resident_fight_at[body.worker_id] = last
	return World.tick - last <= Companion.QUIET_AFTER


## A monster or beast within Companion.COMBAT_RANGE of [param body] or
## [param player] that would fight either (enemy-ai's threatens, 551): a
## raider, a predator, a charging boar, a draugr only while he would.
func _fight_near(body: Resident, player: GridEntity) -> bool:
	for entity in World.get_entities():
		var monster := entity as Monster
		if monster == null or not monster.spawned or monster.zone != body.zone:
			continue
		var listener := player != null and is_instance_valid(player)
		var reach := Companion.COMBAT_RANGE
		if World.distance(body.tile, monster.tile) > reach and not (listener and World.distance(player.tile, monster.tile) <= reach):
			continue
		if monster.threatens(body) or (listener and monster.threatens(player)):
			return true
	return false


## A resident's line held back near a fight, counted in the mind log (675,
## npc's side): by kind ("greet", "heard", "voice", "say", "offer", "song",
## "ask"), no words, no names.
func _held_tongue(what: String) -> void:
	MindLog.record({"kind": "voice", "mind": "resident", "trigger": what, "outcome": "held tongue", "note": ""})


## The sky as a hail's cue: its sentence when there is weather in it or
## snow on the ground, "" for a clear sky (554 amended: it drew the
## invented lines).
func _sky_now() -> String:
	if World.fields == null:
		return ""
	var now_words := DayNight.describe(World.fields.region, DayNight.now())
	var kind := str(Weather.at(World.fields.region, DayNight.now()).get("kind", "clear"))
	if (kind != "clear" and not str(now_words.get("weather", "")).is_empty()) or not str(now_words.get("ground", "")).is_empty():
		return str(now_words.get("sentence", ""))
	return ""


## One hail of [param body] to [param player] now, under 554's limits (the
## player not blocked, not hailed by them today, a cue left, the heard and
## greeting caps); [param clicked] (560) skips only the pause after a pair
## found nothing. True when an ask was queued.
func _hail_now(body: Resident, player: Player, rules: Dictionary, now_msec: int, now: int, day: int, sky: String, clicked := false) -> bool:
	if _hail_blocked(player, now_msec, rules):
		return false
	var card := Townsfolk.card_of(World.production, body.worker_id)
	if card.is_empty() or Resident.hailed_today(card, player.player_id, day):
		return false
	var tried := body.worker_id + "|" + player.player_id
	if not clicked and World.tick - int(_hail_tried.get(tried, -World.WORLD_TICK_STEPS)) < World.WORLD_TICK_STEPS:
		return false
	var heard: Dictionary = _hail_heard.get_or_add(player.player_id, {})
	for text: Variant in heard.keys():
		if int(heard[text]) != day:
			heard.erase(text)
	var greeted: Dictionary = _hail_greetings.get_or_add(player.player_id, {"day": day, "n": 0})
	if int(greeted.get("day", -1)) != day:
		greeted["day"] = day
		greeted["n"] = 0
	var greeting_ok := int(greeted["n"]) < int(rules.get("greetings_a_day", 3))
	var cue := Resident.hail_cue(body.worker_id, body.town, player.player_id, _display_name(player), World.production, now, sky, Offers.ctx, heard.keys(), greeting_ok)
	if cue.is_empty():
		_hail_tried[tried] = World.tick
		return false
	if str(cue.get("kind", "")) == "greeting":
		greeted["n"] = int(greeted["n"]) + 1
	heard[str(cue.get("text", ""))] = day
	Resident.hail_done(World.production, body.worker_id, player.player_id, cue, day, sky)
	_write_resident_card(body)
	_resident_serial += 1
	_resident_asks.append({"body": body.get_instance_id(), "ask": body.hail_ask(_display_name(player), cue, _resident_serial, "greet" if clicked else "hail"), "at": World.tick,
		"player": player.player_id, "peer": player.owner_peer})
	_hail_at[player.player_id] = now_msec
	print("[%s] %s to %s: %s" % ["greet" if clicked else "hail", body.person, _display_name(player), cue.get("kind", "")])
	return true


# --- Visible work (decision 566, npc's side) ---------------------------------------------

## Every second: each townsperson's task from the sim's state (Resident.task,
## read by its own tick for the goal and the activity), and each house's
## waking for the lamp (economy's Towns.set_awake, by building code).
func _visible_work_tick() -> void:
	if World.production == null or not Net.is_authority():
		return
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned or body.strayed or not body.escort_of.is_empty() or not body.card.is_empty():
			continue
		body.task = _task_for(body)
	_awake_tick()


## What [param body]'s work looks like now, from the sim: a woodcutter on
## 521's trip (economy's Production.trip: the outbound half to the woodlot's
## spot, chopping; the return half home with a log), a carpenter whose
## build job is working (at the woodpile sawing in the pad stage, inside
## hammering after, by Towns.build_progress); and 566 amended, phase 2: a
## hunter on their hunt (_hunter_task), a farmer at the field (_farmer_task),
## a shepherd at the pasture or the hill herder at the fold (_herd_task); {}
## when the routine's work place is the place. Only a site or a building in
## the body's own area. The words are the sim's; a client draws the ones it
## knows (Client3D.ACTIVITIES) and shows nothing for the rest.
func _task_for(body: Resident) -> Dictionary:
	if body.trade == "woodcutter":
		var site: Dictionary = World.production.site_of(body.town, body.trade)
		if site.is_empty() or str(site.get("area", "")) != World.zone.name:
			return {}
		var trip := _trip_of(body.worker_id)
		if trip.is_empty():
			return {}
		var now := World.production.now()
		var from := int(trip.get("from", -1))
		var back_at := int(trip.get("back_at", -1))
		var spot := _site_spot(site, body.town)
		var store_cell: Vector2i = World.holdings.place(body.town).get("cell", body.tile)
		# At the site until it must leave to be home when the yield lands (521 amended): the walk home at its own
		# pace over the real route, not the trip's straight-line half, so the spell at the site is what the trip
		# leaves over the walk there and back.
		if from < 0 or back_at < 0 or now < back_at - _walk_home(body, spot["cell"], store_cell):
			return {"kind": "chop", "cell": spot["cell"], "face": spot["face"], "walking": false}
		var pile := _pile_spot(body.town, store_cell)
		return {"kind": "carry_log", "cell": pile.get("cell", _nearest_free(store_cell)), "face": pile.get("face", Resident.NO_CELL), "walking": true}
	# The trades by their names in economy.json (hunter.trade, buildings' field and pasture trades, herder.trade).
	if body.trade == "hunter":
		return _hunter_task(body)
	if body.trade == "farmer":
		return _farmer_task(body)
	if body.trade == "shepherd" or body.trade == "herder":
		return _herd_task(body)
	var build := _build_of(body)
	if not build.is_empty():
		return _build_task(build["building"], float(build["progress"]))
	return {}


## Steps for [param body] to walk home from [param spot] to [param store]
## over the real route at its pace (the trip's turn, 521 amended); the
## straight line's cells when no route is found. Kept by body and spot.
func _walk_home(body: Resident, spot: Vector2i, store: Vector2i) -> int:
	var key := "home:%s:%s" % [body.worker_id, spot]
	if not _site_spots.has(key):
		var path := World.find_path(spot, store, true)
		var cells := path.size() if not path.is_empty() else World.distance(spot, store)
		_site_spots[key] = ceili(float(cells) * body.move_ticks * WALK_HOME_SLACK)
	return int(_site_spots[key])


## Economy's trip for [param worker_id] ({site, from, back_at}; {} off a
## trip), or the tests' stand-in; before economy's Production.trip lands,
## 521's turn alone: WALKING counts as the outbound half.
func _trip_of(worker_id: String) -> Dictionary:
	if _trip_stub.has(worker_id):
		return _trip_stub[worker_id]
	return World.production.trip(worker_id)


## The hunter's hunt (566 amended, phase 2; economy's trip, its "catch" the
## kind rolled when it set out, "" for none): the outbound half stalking at
## the hunting ground's spot (_stalk_spot), the turn by the walk home as the
## woodcutter's; the return half, with a catch, the game carried to the
## store; without one nothing, a plain walk home. {} off a trip, or with the
## ground elsewhere.
func _hunter_task(body: Resident) -> Dictionary:
	var site: Dictionary = World.production.site_of(body.town, body.trade)
	if site.is_empty() or str(site.get("area", "")) != World.zone.name:
		return {}
	var trip := _trip_of(body.worker_id)
	if trip.is_empty():
		return {}
	var now := World.production.now()
	var from := int(trip.get("from", -1))
	var back_at := int(trip.get("back_at", -1))
	var store_cell: Vector2i = World.holdings.place(body.town).get("cell", body.tile)
	var spot := _stalk_spot(site, store_cell)
	if from < 0 or back_at < 0 or now < back_at - _walk_home(body, spot["cell"], store_cell):
		return {"kind": "stalk", "cell": spot["cell"], "face": spot["face"], "walking": false}
	if str(trip.get("catch", "")).is_empty():
		return {}
	return {"kind": "carry_game", "cell": _store_side(body.town, store_cell), "face": Resident.NO_CELL, "walking": true}


## Where a hunter stalks at [param site] (a Holdings place with a radius):
## the walkable cell within the radius farthest from [param store] (the deep
## end of the ground, its game beyond), facing on away from the store; the
## site's own cell when none can be walked. Kept by site id.
func _stalk_spot(site: Dictionary, store: Vector2i) -> Dictionary:
	var key := "stalk:" + str(site.get("id", ""))
	if _site_spots.has(key):
		return _site_spots[key]
	var centre: Vector2i = site.get("cell", Vector2i.ZERO)
	var radius := int(site.get("radius", 2))
	var best := centre
	var best_d := -1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := centre + Vector2i(dx, dy)
			if not World.is_walkable(cell):
				continue
			var d := (cell - store).length_squared()
			if d > best_d:
				best_d = d
				best = cell
	var away := best - store
	var face: Vector2i = best + Vector2i(signi(away.x), signi(away.y)) if away != Vector2i.ZERO else Resident.NO_CELL
	_site_spots[key] = {"cell": best, "face": face}
	return _site_spots[key]


## Where a load is set down at [param town]'s store (566 amended, phase 2:
## the hunter's game, the farmer's sack): the store's cell when it can be
## walked, else the nearest that can. Kept by town, so a body standing on
## it is still there.
func _store_side(town: String, store_cell: Vector2i) -> Vector2i:
	var key := "side:" + town
	if not _site_spots.has(key):
		_site_spots[key] = store_cell if World.is_walkable(store_cell) else _nearest_free(store_cell)
	return _site_spots[key]


## The farmer's field (566 amended, phase 2): while economy's Towns.field_work
## says his work counts toward the crop (spring unsown, autumn sown, the farm
## his and worked), hoeing along the field's rows cell by cell (_row_cells,
## _rows), shown once he is in the field; the crop brought in (crop.stage
## "harvested"), one sack carried to the store first (_sacks, once a
## harvest, gone when the stage turns); else {}, the routine's place. The
## field is the standing building of his trade's kind in his town here.
func _farmer_task(body: Resident) -> Dictionary:
	var field := _use_rect(body.town, World.towns.kind_for(body.trade))
	if field.size == Vector2i.ZERO:
		return {}
	var stage := str(World.towns.crop(body.town).get("stage", ""))
	if stage != "harvested":
		_sacks.erase(body.worker_id)
	elif str(_sacks.get(body.worker_id, "")) != stage:
		var store_cell: Vector2i = World.holdings.place(body.town).get("cell", body.tile)
		var at := _store_side(body.town, store_cell)
		if World.distance(body.tile, at) <= 1:
			_sacks[body.worker_id] = stage
		else:
			return {"kind": "carry_sack", "cell": at, "face": Resident.NO_CELL, "walking": true}
	if not _field_work(body.town):
		return {}
	var cells := _row_cells(field)
	if cells.is_empty():
		return {}
	var i := int(_rows.get(body.worker_id, 0)) % cells.size()
	if body.tile == cells[i]:
		i = (i + 1) % cells.size()
	_rows[body.worker_id] = i
	return {"kind": "hoe", "cell": cells[i], "face": Resident.NO_CELL, "walking": field.has_point(body.tile)}


## Whether [param town]'s farmer's work counts toward the crop now (economy's
## Towns.field_work), or the tests' stand-in.
func _field_work(town: String) -> bool:
	if _field_work_stub.has(town):
		return bool(_field_work_stub[town])
	return World.towns.field_work(town)


## The shepherd's pasture and the hill herder's fold (566 amended, phase 2):
## herding, a slow round of the ground (one of its cells by the body and
## the HERD_DWELL-step spell, facing its middle); the shepherd in a shearing
## season with the flock unshorn (economy's flock: season, sheared) shears at
## the pasture's middle instead. The pasture is the standing building of
## his trade's kind in his town here; the fold the herder's work place
## (640), and in a town (on his drove) he herds nothing. {} with neither.
func _herd_task(body: Resident) -> Dictionary:
	var ground := Rect2i()
	var shearing := false
	if body.trade == "herder":
		if World.towns.is_town(body.town):
			return {}
		ground = body.places.get("work", Rect2i())
	else:
		ground = _use_rect(body.town, World.towns.kind_for(body.trade))
		var flock: Dictionary = World.towns.flock(body.town)
		shearing = not flock.is_empty() and str(flock.get("season", "")) in SHEARING_SEASONS and not bool(flock.get("sheared", false))
	if ground.size == Vector2i.ZERO:
		return {}
	var cells := _row_cells(ground)
	if cells.is_empty():
		return {}
	var middle := ground.get_center()
	if shearing:
		return {"kind": "shear", "cell": middle if World.is_walkable(middle) else cells[0], "face": Resident.NO_CELL, "walking": false}
	var turn := int(float(World.production.now()) / float(HERD_DWELL))
	var cell: Vector2i = cells[posmod(turn * 7 + body.worker_id.hash(), cells.size())]
	return {"kind": "herd", "cell": cell, "face": middle, "walking": false}


## The inside of [param town]'s standing building of [param use] in this zone
## (its world-map record by the town's key; Rect2i(), size zero, for none):
## the farmer's field, the shepherd's pasture.
func _use_rect(town: String, use: String) -> Rect2i:
	if use.is_empty() or str(World.towns.building(town, use).get("state", "")) != Towns.STANDING:
		return Rect2i()
	var key := str(World.holdings.place(town).get("key", ""))
	for building: Dictionary in _world_map.areas.get(World.zone.name, {}).get("buildings", []):
		if str(building.get("town", "")) == key and str(building.get("use", "")) == use and building.get("rect") is Rect2i:
			return building["rect"]
	return Rect2i()


## [param ground]'s walkable cells row by row, each row the other way from
## the last (the hoeing's furrows, the herding's round).
func _row_cells(ground: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(ground.position.y, ground.end.y):
		var xs: Array = range(ground.position.x, ground.end.x)
		if (y - ground.position.y) % 2 == 1:
			xs.reverse()
		for x: int in xs:
			if World.is_walkable(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## Where a body works [param site] (a Holdings place with a radius): beside
## the chopping block standing within the radius (566 amended), the
## walkable neighbour nearest the town's store, facing the block; with no
## block, the walkable cell within the radius with something to fell beside
## it (a cell that cannot be walked: the forest, a tree), nearest the store,
## facing it; the site's own cell when none. Kept by site id.
func _site_spot(site: Dictionary, town: String) -> Dictionary:
	var id := str(site.get("id", ""))
	if _site_spots.has(id):
		return _site_spots[id]
	var centre: Vector2i = site.get("cell", Vector2i.ZERO)
	var radius := int(site.get("radius", 2))
	var store: Vector2i = World.holdings.place(town).get("cell", centre)
	var block := _prop_spot(CHOPPING_BLOCK, centre, radius, store)
	if not block.is_empty():
		_site_spots[id] = block
		return block
	var best := {"cell": centre, "face": Resident.NO_CELL}
	var best_d := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := centre + Vector2i(dx, dy)
			if not World.is_walkable(cell):
				continue
			for side: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				if World.is_walkable(cell + side):
					continue
				var d := float((cell - store).length_squared())
				if d < best_d:
					best_d = d
					best = {"cell": cell, "face": cell + side}
				break
	_site_spots[id] = best
	return best


## Where [param town]'s carried logs land: beside the woodpile standing
## within WOODPILE_REACH of [param store_cell] (566 amended), facing it;
## {} with none (the store's cell then). Kept by town.
func _pile_spot(town: String, store_cell: Vector2i) -> Dictionary:
	var key := "pile:" + town
	if not _site_spots.has(key):
		_site_spots[key] = _prop_spot(WOODPILE, store_cell, WOODPILE_REACH, store_cell)
	return _site_spots[key]


## Where a body stands at a prop of [param slot] in this zone within
## [param within] cells of [param around]: {cell: the prop's walkable
## 4-neighbour nearest [param near], face: the prop's cell}, the prop
## nearest [param near] when several stand; {} when none stands or none
## can be stood beside.
func _prop_spot(slot: String, around: Vector2i, within: int, near: Vector2i) -> Dictionary:
	var best := {}
	var best_d := INF
	for building: Dictionary in _world_map.areas.get(World.zone.name, {}).get("buildings", []):
		if str(building.get("slot", "")) != slot or not building.get("rect") is Rect2i:
			continue
		var at: Vector2i = (building["rect"] as Rect2i).position
		if World.distance(at, around) > within:
			continue
		for side: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if not World.is_walkable(at + side):
				continue
			var d := float((at + side - near).length_squared()) + 0.5 * float((at - near).length_squared())
			if d < best_d:
				best_d = d
				best = {"cell": at + side, "face": at}
	return best


## The building [param body] is building now: a working build job of its
## trade in its town whose use has a map building here, with its rect,
## facing and progress (Towns.build_progress when economy's is in, else the
## job's worked over needed); the tests' stand-in first; {} for none.
func _build_of(body: Resident) -> Dictionary:
	var use := ""
	var progress := -1.0
	if _build_stub.has(body.worker_id):
		use = str(_build_stub[body.worker_id].get("use", ""))
		progress = float(_build_stub[body.worker_id].get("progress", 0.0))
	else:
		for id: int in World.production.jobs():
			var job := World.production.job(id)
			if str(job.get("kind", "")) != "build" or str(job.get("state", "")) != "working" or str(job.get("town", "")) != body.town:
				continue
			if str(job.get("worker", "")) != body.worker_id and str(job.get("trade", "")) != body.trade:
				continue
			use = str(job.get("recipe", ""))
			progress = float(job.get("worked", 0)) / maxf(float(job.get("needed", 1)), 1.0)
			var told: float = World.towns.build_progress(body.town, use)
			if told >= 0.0:
				progress = told
			break
	if use.is_empty():
		return {}
	var key := str(World.holdings.place(body.town).get("key", ""))
	for building: Dictionary in _world_map.areas.get(World.zone.name, {}).get("buildings", []):
		if str(building.get("town", "")) == key and str(building.get("use", "")) == use and building.get("rect") is Rect2i:
			return {"building": building, "progress": progress}
	return {}


## The carpenter's task at a build [param building] (a world map record):
## on buildings' Level.site_cells (566, buildings' side, fd167d4b: work,
## woodpile, sawbuck, saw) for a composed kind with a door, sawing on the
## "saw" cell facing the sawbuck through the plot and the frame (progress
## under 0.35, buildings' walls stage) so the stroke crosses its log, and
## hammering on the "work" cell after, facing the building's middle; for a
## slot building with no door record (the kinds carry doors and seed), the
## woodpile just outside the front cell, one to the side, and the cell
## inside it, as before.
func _build_task(building: Dictionary, progress: float) -> Dictionary:
	var rect: Rect2i = building["rect"]
	if not (building.get("doors", []) as Array).is_empty():
		var cells: Dictionary = Level.site_cells(building)
		if progress < 0.35:
			return {"kind": "saw", "cell": cells["saw"], "face": cells["sawbuck"], "walking": false}
		return {"kind": "hammer", "cell": cells["work"], "face": rect.get_center(), "walking": false}
	var facing: Vector2i = building.get("facing", Vector2i(0, 1))
	var front := Level.front_cell(rect, facing)
	var side := Vector2i(facing.y, -facing.x)
	var woodpile := front + side if World.is_walkable(front + side) else front
	var inside := front - facing
	var work := inside if rect.has_point(inside) and World.is_walkable(inside) else (_nearest_free(rect.get_center()) if World.is_walkable(_nearest_free(rect.get_center())) else front)
	if progress < 0.35:
		return {"kind": "saw", "cell": woodpile, "face": rect.get_center(), "walking": false}
	return {"kind": "hammer", "cell": work, "face": rect.get_center(), "walking": false}


## Each house with someone inside: awake when any of them is not asleep
## (the lamp and the chimney's smoke, buildings' by building code;
## economy's Towns.set_awake carries it), under the building's own town
## (its town_id, as the "town" message and the view name it), a building
## of no town (a home) under its level's name (Client3D.awake_town); told
## only when it changes, a house emptied told not awake, a house no body
## has been in not told (the client falls back to the hour).
func _awake_tick() -> void:
	var now := _awake_map()
	for building: Dictionary in _world_map.areas.get(World.zone.name, {}).get("buildings", []):
		var code := str(building.get("code", ""))
		var town := str(building.get("town_id", ""))
		if town.is_empty():
			town = World.zone.name
		var key := town + "|" + code
		if code.is_empty() or not (now.has(code) or _awake_sent.has(key)):
			continue
		var awake := bool(now.get(code, false))
		if _awake_sent.get(key) != awake:
			_awake_sent[key] = awake
			World.towns.set_awake(town, code, awake)


## Building code -> whether anyone inside it is awake, for the bodies in
## this zone's buildings now.
func _awake_map() -> Dictionary:
	var out := {}
	var buildings: Array = _world_map.areas.get(World.zone.name, {}).get("buildings", [])
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned:
			continue
		for building: Dictionary in buildings:
			if building.get("rect") is Rect2i and (building["rect"] as Rect2i).has_point(body.tile) and not str(building.get("code", "")).is_empty():
				var code := str(building["code"])
				out[code] = bool(out.get(code, false)) or body.activity != "sleep"
				break
	return out


## A click on [param body] by [param player] (decision 560, npc's side;
## Jeff: "the resident stops, turns to face the player and addresses
## them"). Within TALK_REACH: one greeting a greet.again_seconds for the
## pair (a click within it only turns them again); in bed, hiding, strayed,
## escorting, a companion resting, or with an ask of theirs waiting or out:
## no stop, the greet.refuse word at most; else they stop and face the
## player for greet.stop_seconds (Resident.address, addressing replicated
## for the look), say the table's word at once through the spoken path
## (no mind, no aside), and if they have something real to say today the
## hail follows, brought forward under 554's limits (_hail_now, clicked).
func _greeted(player: Player, body: Resident) -> void:
	if player == null or body == null or not is_instance_valid(body) or not body.spawned or player.player_id.is_empty() \
			or World.distance(player.tile, body.tile) > TALK_REACH or World.production == null:
		return
	var rules: Dictionary = Townsfolk.rules().get("greet", {})
	var now_msec := Time.get_ticks_msec()
	var key := body.worker_id + "|" + player.player_id
	if now_msec - int(_greet_at.get(key, -1000000)) < int(float(rules.get("again_seconds", 10)) * 1000.0):
		if not body.addressing.is_empty():
			body.address(player, int(float(rules.get("stop_seconds", 8)) * World.TICK_RATE))  # Turned to them again, nothing new said.
		return
	if _resident_quiet(body, player):
		_held_tongue("greet")  # No word, no turning to them near a fight (675, npc's side).
		return
	_greet_at[key] = now_msec
	if body.worker_id.begins_with(Offers.VISITOR):
		_visitor_greeted(player, body, int(float(rules.get("stop_seconds", 8)) * World.TICK_RATE))
		return
	var busy := false
	for each: Dictionary in _resident_asks:
		if int(each["body"]) == body.get_instance_id():
			busy = true
	for serial: Variant in _resident_out:
		if int(_resident_out[serial].get("body", 0)) == body.get_instance_id():
			busy = true
	if not _hail_able(body) or busy:
		var refuse := str(rules.get("refuse", "Not now."))
		if not refuse.is_empty() and body.card.is_empty():  # A companion resting in town speaks for herself.
			_resident_says(body, refuse, "", player)
		return
	body.address(player, int(float(rules.get("stop_seconds", 8)) * World.TICK_RATE))
	var card := Townsfolk.card_of(World.production, body.worker_id)
	var now := World.production.now()
	var day := Townsfolk.day_of(now)
	var word := Resident.greet_word(body.trade, Standing.words(card, player.player_id) if not card.is_empty() else "stranger", rules, hash(body.worker_id + ":" + str(day)))
	if body.trade == "medicine_man" and in_care(player.player_id, _care_hut_of(body.worker_id)):
		word = str(rules.get("care", word))  # One in his care hears it (584 amended, npc's side).
	_resident_says(body, word, "", player)
	var rumour := _rumour_for(body.town, player.player_id, day)
	if not rumour.is_empty():
		_resident_says(body, rumour, "", player)  # The town's word of its sought, once a day (decision 643).
	if body.trade == str(World.production.rules.get("herder", {}).get("trade", "herder")):
		var shelter := _shelter_words(str(World.production.worker(body.worker_id).get("town", "")))
		if not shelter.is_empty():
			_resident_says(body, shelter, "", player)  # A sought one sheltering at his fold (640, npc's side).
	_hail_now(body, player, Townsfolk.rules().get("hail", {}), now_msec, now, day, _sky_now(), true)


## [param line] said by [param body] to [param player] without the mind
## (560's greeting word, its refusal): the transcript, the party log, the
## neighbours' hearing, the "speech" message with [param aside] ("" for
## none), and the player's offers (536).
func _resident_says(body: Resident, line: String, aside: String, player: Player) -> void:
	if _resident_quiet(body, player):
		_held_tongue("say")  # Held near a fight; the panel still comes (675, npc's side).
		_send_offers(body, player.player_id, player.owner_peer)
		return
	Transcript.record(body.person, body.person, line)
	if not aside.is_empty():
		Transcript.record(body.person, body.person, "[aside] " + aside)
	party_log.add("%s said: \"%s\"%s" % [body.person, line, (" (%s)" % aside) if not aside.is_empty() else ""])
	_heard_near(body, body.person, line)
	_own_tale(body, line, _display_name(player))
	Net.broadcast_to(hearers(body.tile), "speech", {"entity": String(body.get_path()), "speaker": body.person, "text": line, "aside": aside})
	_send_offers(body, player.player_id, player.owner_peer)


## Why [param player] hears no hail now (decision 554): led by a companion,
## a blow given or taken within hail.quiet_seconds, a resident's answer to
## them within the minute (a talk), or a hail within hail.minute_seconds.
func _hail_blocked(player: Player, now_msec: int, rules: Dictionary) -> bool:
	var pid := player.player_id
	if _guides.has(pid):
		return true
	var quiet := int(float(rules.get("quiet_seconds", 10)) * World.TICK_RATE)
	if World.tick - player.hurt_tick < quiet or World.tick - int(_blow_at.get(pid, -100000)) < quiet:
		return true
	var minute := int(float(rules.get("minute_seconds", 60)) * 1000.0)
	return now_msec - int(_hail_at.get(pid, -minute)) < minute


## A blow given by a player (World.entity_damaged): remembered for _hail_blocked.
func _hail_struck(_target: GridEntity, _amount: int, source: GridEntity, _cause: StringName) -> void:
	var player := source as Player
	if player != null and not player.player_id.is_empty():
		_blow_at[player.player_id] = World.tick


## Visitors (decision 711, npc's side; economy's Towns.visitors): strangers
## passing through a town, a body while a player is near as its folk have,
## "visitor:" + their id (Offers.VISITOR), no worker and no card. A body
## going on walks to the road's edge, at most this long, then is gone.
const VISITOR_WALK_OUT_SECONDS := 60
## Visitors walking out (711): body key -> {town, name, edge, until (tick)}.
var _visitors_leaving: Dictionary = {}
## "body key|player id" -> true: a visitor's news told that player this visit (711).
var _visitor_told: Dictionary = {}


## [param worker_id]'s Towns.visitors entry with its "town", {} for none
## (or one already on their way out): Offers' ctx "visitor".
func _visitor_of(worker_id: String) -> Dictionary:
	if World.towns == null or not worker_id.begins_with(Offers.VISITOR):
		return {}
	var id := worker_id.trim_prefix(Offers.VISITOR)
	for town: String in World.towns._towns:
		for entry: Dictionary in World.towns.visitors(town):
			if str(entry.get("id", "")) == id:
				entry["town"] = town
				return entry
	return {}


## What a pedlar asks for [param item]: economy's own sum in
## Economy.visitor_sale (its value times merchant.sell, at least 1), so
## the panel's price is the one taken. Offers' ctx "visitor_price".
func _visitor_price(item: String) -> Variant:
	if World.economy == null:
		return null
	return maxi(roundi(World.economy.value_of(item) * float(World.economy.rules.get("merchant", {}).get("sell", 1.15))), 1)


## A visitor came to [param town] (Towns.visitor_came): what they carry to
## tell, drawn once (set_visitor_news).
func _on_visitor_came(town: String, id: String) -> void:
	for entry: Dictionary in World.towns.visitors(town):
		if str(entry.get("id", "")) == id:
			World.towns.set_visitor_news(town, id, _visitor_news(town, entry))


## A visitor went on from [param town] (Towns.visitor_left): a body of
## theirs here walks out to the road's edge; whom they told is let go.
func _on_visitor_left(town: String, id: String) -> void:
	var key := Offers.VISITOR + id
	for told: String in _visitor_told.keys():
		if told.begins_with(key + "|"):
			_visitor_told.erase(told)
	var body := _resident_body(key)
	if body != null and body.spawned:
		_visitors_leaving[key] = {"town": town, "name": body.person, "edge": _town_edge(World.holdings.place(town)),
			"until": World.tick + VISITOR_WALK_OUT_SECONDS * World.TICK_RATE}


## The news a visitor to [param town] carries: the newest happening of up
## to two other towns ("In Westfold, the wagon came home."), else a word of
## the road from where they came (townsfolk.json visitors.road).
func _visitor_news(town: String, entry: Dictionary) -> Array:
	var out: Array = []
	var others: Array = World.towns._towns.keys()
	others.sort()
	for other: String in others:
		if other == town or out.size() >= 2:
			continue
		var newest := {}
		for said: Variant in _town_memory(other):
			if said is Dictionary and bool(said.get("event", false)) and str(said.get("tier", "")) != TownMemory.LEFT \
					and int(said.get("first_said", -1)) >= int(newest.get("first_said", -1)):
				newest = said
		if not newest.is_empty():
			out.append({"kind": "town", "text": "In %s, %s." % [_town_words(other), Resident._lead(str(newest.get("text", ""))).trim_suffix(".")]})
	var road: Array = Townsfolk.rules().get("visitors", {}).get("road", [])
	if out.is_empty() and not road.is_empty():
		var line := str(road[absi(hash(str(entry.get("id", "")))) % road.size()])
		out.append({"kind": "road", "text": line % str(entry.get("from", "the road")) if line.contains("%s") else line})
	return out


## The visitors of [param place_id] wanted here as bodies (_sync_residents):
## a pedlar at the store, a pilgrim at the temple, the rest at the inn (else
## the square), one just come walking in from the road's edge; and those
## going on, walking out to it till they reach it or their time is up.
func _visitors_wanted(area: Dictionary, place_id: String, place: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var no_homes: Array[Rect2i] = []
	var base := _resident_places(area, place, "", no_homes, 0)
	var store: Vector2i = place.get("cell", Vector2i.ZERO)
	for entry: Dictionary in World.towns.visitors(place_id):
		var kind := str(entry.get("kind", ""))
		var spot: Rect2i = base.get("inn", base["square"])
		if kind == "pedlar":
			spot = Rect2i(store - Vector2i(2, 2), Vector2i(5, 5))
		elif kind == "pilgrim" and base.has("temple"):
			spot = base["temple"]
		var each := {"key": Offers.VISITOR + str(entry.get("id", "")), "name": str(entry.get("name", "")), "trade": "", "player": "",
			"town": place_id, "places": _visitor_places(spot)}
		if World.towns.now() - int(entry.get("came", 0)) < maxi(DayNight.day_steps, 1) / 12:
			each["enter_at"] = _town_edge(place)
		out.append(each)
	for key: String in _visitors_leaving.keys():
		var going: Dictionary = _visitors_leaving[key]
		if str(going["town"]) != place_id:
			continue
		var body := _resident_body(key)
		if body == null or World.tick > int(going["until"]) or World.distance(body.tile, going["edge"]) <= 1:
			_visitors_leaving.erase(key)
			continue
		out.append({"key": key, "name": str(going["name"]), "trade": "", "player": "", "town": place_id,
			"places": _visitor_places(Rect2i(going["edge"], Vector2i.ONE))})
	return out


## Every place of a routine at [param spot]: a visitor keeps to it all day.
func _visitor_places(spot: Rect2i) -> Dictionary:
	return {"work": spot, "home": spot, "square": spot, "inn": spot, "temple": spot, "well": spot, "visit": spot}


## The relics [param player_id] carries (decision 714; ctx "relics", the
## priest's offers): [{uid, knight}].
func _relics_held(player_id: String) -> Array:
	var out: Array = []
	for entity in World.get_entities():
		if entity is Player and entity.spawned and (entity as Player).player_id == player_id:
			for slot in entity.slots.size():
				var relic := World.relic_of(World.slot_uid(entity, slot))
				if not relic.is_empty():
					out.append({"uid": World.slot_uid(entity, slot), "knight": str(relic.get("knight", ""))})
			break
	return out


## Server: [param by] moving a relic from their own slot [param from_slot]
## into the priest's hands, or onto his temple's counter (decision 714): it
## goes to the altar (_relic_returned) before World's hand-over, which
## would refuse a soulbound thing. Whether it was a relic for a priest.
func _relic_handed(by: GridEntity, from: GridEntity, from_slot: int, to: GridEntity) -> bool:
	if not by is Player or from != by or from_slot < 0 or from_slot >= from.slots.size():
		return false
	var uid := World.slot_uid(from, from_slot)
	if World.relic_of(uid).is_empty():
		return false
	var priest: Resident = null
	if to is Resident and World.production != null and "priest" in World.production.worker((to as Resident).worker_id).get("trades", []):
		priest = to
	elif to is Chest and (to as Chest).temple and World.reaches(by, to):
		priest = _resident_body(_priest_of(World.temple_town(to)))
	if priest == null:
		return false
	_relic_returned(by as Player, priest, uid)
	return true


## Server: [param player] gives the priest [param body] the relic
## [param uid] (decision 714, npc's side): read (World.relic_of) before it
## ends, consumed off them (World.consume), and only then their amulet
## charged by its tier (dungeon's charge_from_relic, which mints one for a
## player with none). He thanks them by the knight's name and the charge;
## his card keeps it (the player through Offers.name_of) and his standing
## rises ("relic"). False, nothing done, when the body is no priest, is out
## of hearing, or they do not hold it.
func _relic_returned(player: Player, body: Resident, uid: int) -> bool:
	if not Net.is_authority() or player == null or body == null or World.production == null:
		return false
	if "priest" not in World.production.worker(body.worker_id).get("trades", []) or World.distance(body.tile, player.tile) > HEARING_RANGE:
		return false
	var relic := World.relic_of(uid)
	if relic.is_empty() or not World.consume(player, uid, "laid on the altar"):
		return false
	var knight := str(relic.get("knight", "the knight"))
	var added := charge_from_relic(player, int(relic.get("tier", 0)))
	var held := World.totem_charges(World.totem_of(player.player_id))
	var who := Offers.name_of(Offers.ctx, player.player_id)
	Offers._regard(World.production, body.worker_id, player.player_id, Standing.setting("relic"), "brought home the remains of %s" % knight)
	Townsfolk.learn(World.production, body.worker_id, "%s brought the remains of %s up from the barrow, and you laid them on the altar." % [who, knight])
	var thanks := "%s is home at last. Bless you." % knight
	var charge := ("The blessing is on your amulet: it holds %d now." % held) if added > 0 else "The knight rests now, though your amulet takes no more of the blessing."
	_say_plain(body, body.person, thanks + " " + charge)
	print("[relic] the remains of %s laid on the altar in %s, %d charge(s) added" % [knight, body.town, added])
	return true


## The body of [param worker_id] among the townsfolk here, null for none.
func _resident_body(worker_id: String) -> Resident:
	for entity: GridEntity in World.townsfolk():
		if entity is Resident and (entity as Resident).worker_id == worker_id:
			return entity
	return null


## Where the road leaves [param place]'s area nearest its store: an edge
## the area joins another by (the cell on it across from the store), or a
## link's cell; the store's cell for none.
func _town_edge(place: Dictionary) -> Vector2i:
	var store: Vector2i = place.get("cell", Vector2i.ZERO)
	var area_name := str(place.get("area", World.zone.name))
	var size: Vector2i = _world_map.areas.get(area_name, {}).get("size", Vector2i.ZERO)
	var best := Companion.NONE
	for way: Dictionary in _world_map.ways_from(area_name):
		var cell := Companion.NONE
		if str(way["kind"]) == "edge":
			match str(way["side"]):
				"east": cell = Vector2i(size.x - 2, store.y)
				"west": cell = Vector2i(1, store.y)
				"south": cell = Vector2i(store.x, size.y - 2)
				"north": cell = Vector2i(store.x, 1)
		else:
			cell = way["at"]
		if cell != Companion.NONE and (best == Companion.NONE or World.distance(cell, store) < World.distance(best, store)):
			best = cell
	return store if best == Companion.NONE else best


## [param player] clicked visitor [param body] (_greeted, 711): a greeting
## by their kind and where they came from, and once a visit one piece of
## the news they carry (the neighbours hear it: hearsay); their wares come
## with the panel. One going on only says so.
func _visitor_greeted(player: Player, body: Resident, stop_ticks: int) -> void:
	body.address(player, stop_ticks)
	var words: Dictionary = Townsfolk.rules().get("visitors", {})
	var entry := _visitor_of(body.worker_id)
	if entry.is_empty():
		var leaving: Array = words.get("leaving", [])
		if not leaving.is_empty():
			_resident_says(body, str(leaving[absi(hash(body.worker_id)) % leaving.size()]), "", player)
		return
	var from := str(entry.get("from", "the road"))
	var greetings: Array = words.get("greetings", {}).get(str(entry.get("kind", "")), [])
	if not greetings.is_empty():
		var line := str(greetings[absi(hash(body.worker_id + player.player_id)) % greetings.size()])
		_resident_says(body, line % from if line.contains("%s") else line, "", player)
	var told := body.worker_id + "|" + player.player_id
	var news: Array = entry.get("news", [])
	if _visitor_told.has(told) or news.is_empty():
		return
	_visitor_told[told] = true
	var item: Variant = news[absi(hash(told)) % news.size()]
	var text := str(item.get("text", "")) if item is Dictionary else str(item)
	if not text.is_empty():
		_resident_says(body, text, "", player)


## [param player] bought [param item] from pedlar [param body] (711):
## economy takes the gold, the tax and the stock (Towns.visitor_sell); the
## thing is minted into their hands; the pedlar says how it went.
func _visitor_sells(player: Player, body: Resident, item: String) -> void:
	var done := World.towns.visitor_sell(body.worker_id.trim_prefix(Offers.VISITOR), player.player_id, item)
	if bool(done.get("ok", false)):
		_hand_item(player.player_id, item, body.person)
	var say := str(done.get("say", ""))
	if not say.is_empty():
		_resident_says(body, say, "", player)


## How many ways from a named one's zone a town hears of its rising (716).
const NAMED_NEWS_WAYS := 3
## A named one's meeting lines at most one a minute (716): msec of its last, by id.
var _named_said_at: Dictionary = {}


## A named enemy's event (decision 716, npc's side; enemy-ai's
## World.named_event): kept on its record (NamedMind: its card rolled once,
## a memory, the player's count). Met is its line to them (an emote for a
## kind that doesn't talk); rose is news in the towns near it.
func _on_named_event(named_id: String, kind: String, player_id: String) -> void:
	var record := World.named_record(named_id).duplicate(true)
	if record.is_empty():
		return
	var body := _named_body(named_id)
	NamedMind.ensure_card(record, named_id)
	# Its words for them as they stood before this meeting.
	var line := NamedMind.meeting_line(record, named_id, player_id) if NamedMind.speaks(record) else ""
	var act := NamedMind.emote(record, named_id, player_id) if not NamedMind.speaks(record) else ""
	NamedMind.remember(record, kind, player_id, World.steps, body.zone if body != null else "")
	World.set_named_record(named_id, record)
	if kind == "rose":
		_named_rose_news(named_id, record, body)
	elif kind == "met" and body != null and body.spawned:
		var now := Time.get_ticks_msec()
		if _named_said_at.has(named_id) and now - int(_named_said_at[named_id]) < 60000:
			return
		_named_said_at[named_id] = now
		var name := str(record.get("name", named_id))
		if not line.is_empty():
			_say_plain(body, name, line)
		elif not act.is_empty():
			party_log.add("%s %s." % [name, act])


## The named one [param named_id]'s body in the world, null for none.
func _named_body(named_id: String) -> Monster:
	for zone_name: String in World.zones:
		for entity: Variant in World.zones[zone_name].entities:
			if entity is Monster and is_instance_valid(entity) and (entity as Monster).named_id == named_id:
				return entity
	return null


## The towns within NAMED_NEWS_WAYS of [param body]'s zone remember its
## rising as the day's news (a hail's "news" cue tells it once, 554).
func _named_rose_news(named_id: String, record: Dictionary, body: Monster) -> void:
	if body == null or World.towns == null or _world_map == null:
		return
	var text := NamedMind.rose_news(record, named_id)
	if text.is_empty():
		return
	var near := _zones_within(body.zone, NAMED_NEWS_WAYS)
	for town: String in World.towns._towns:
		if near.has(town.get_slice("/", 0)):
			Townsfolk._remember(town, text, "", false, World.steps)


## The zones within [param most] ways of [param from], either way: {zone: ways}.
func _zones_within(from: String, most: int) -> Dictionary:
	var seen := {from: 0}
	var frontier: Array[String] = [from]
	for depth in most:
		var next: Array[String] = []
		for area: String in frontier:
			for way: Dictionary in _world_map.ways_from(area) + _world_map.ways_into(area):
				var other := str(way["to"]) if str(way["from"]) == area else str(way["from"])
				if not seen.has(other):
					seen[other] = depth + 1
					next.append(other)
		frontier = next
	return seen


## The admin's quest reset (ui's _quests_reset_all; Jeff: "allow everything
## to be reset"), npc's side: what the townsfolk keep of [param player_id]
## outside their record and the cards' asks. Their hails today (the marks
## on each card and Main's caps), the greeting and rumour marks, a
## refusal to travel (686), and with [param standing] what each resident
## thinks of them (443) and what each named enemy remembers of them (716),
## else kept. What was cleared, as words.
func quests_forget(player_id: String, standing := false) -> Array[String]:
	var cleared: Array[String] = []
	if player_id.is_empty():
		return cleared
	var marks := 0
	for key: Variant in _hail_tried.keys() + _greet_at.keys():
		if str(key).ends_with("|" + player_id):
			_hail_tried.erase(key)
			_greet_at.erase(key)
			marks += 1
	for key: Variant in _visitor_told.keys():
		if str(key).ends_with("|" + player_id):
			_visitor_told.erase(key)  # A visitor's news, told again (711).
			marks += 1
	for key: Variant in _rumour_said.keys():
		if str(key).contains("|%s|" % player_id):
			_rumour_said.erase(key)
			marks += 1
	for each: Dictionary in [_hail_at, _blow_at, _hail_heard, _hail_greetings]:
		if each.erase(player_id):
			marks += 1
	var hailed := 0
	var refused := 0
	var known := 0
	if World.production != null:
		for id: String in World.production.worker_ids():
			if not World.production.worker(id).get("asked", {}).get(player_id, "").is_empty():
				World.production.set_asked(id, player_id, "")
				refused += 1
			var card: Dictionary = World.production.worker(id).get("card", {})  # Stored only: none rolled to be cleared.
			var changed := false
			if card.get("hails") is Dictionary and card["hails"].get("to") is Dictionary and card["hails"]["to"].erase(player_id):
				hailed += 1
				changed = true
			if standing and card.get("standing") is Dictionary and card["standing"].erase(player_id):
				known += 1
				changed = true
			if changed:
				World.production.set_card(id, card)
	var grudges := 0
	if standing:
		for named_id: String in World.named:
			var record := World.named_record(named_id).duplicate(true)
			if record.get("track") is Dictionary and (record["track"] as Dictionary).erase(player_id):
				record["memories"] = (record.get("memories", []) as Array).filter(func(memory: Variant) -> bool:
					return not memory is Dictionary or str(memory.get("player", "")) != player_id)
				World.set_named_record(named_id, record)
				grudges += 1
	if marks + hailed > 0:
		cleared.append("hails and greetings")
	if refused > 0:
		cleared.append("%d refusal%s to travel" % [refused, "" if refused == 1 else "s"])
	if known > 0:
		cleared.append("standing with %d resident%s" % [known, "" if known == 1 else "s"])
	if grudges > 0:
		cleared.append("memories of %d named enem%s" % [grudges, "y" if grudges == 1 else "ies"])
	return cleared


func _crypt_asks_tick() -> void:
	if World.production == null:
		return
	var rule := _runner_rule()
	var barrow := str(rule.get("barrow", "barrow"))
	for peer: int in _players:
		var player: Player = _players[peer]
		if player == null or not is_instance_valid(player) or not player.spawned or player.zone != barrow:
			continue
		for pair: Array in Offers._asks(World.production):
			var ask: Dictionary = pair[1]
			if str(ask.get("by", "")) != player.player_id:
				continue
			var sub := str(ask.get("sub", ""))
			if sub != Offers.OFFERING and sub != Offers.RUNNER:
				continue
			var chest := _chest_named(barrow, "Altar" if sub == Offers.OFFERING else str(rule.get("pack", "Runner's pack")))
			if chest != null and World.reaches(player, chest):
				Offers.crypt_done(str(ask.get("town", "")), player.player_id, sub)


## The chest called [param chest_name] in zone [param zone_name], null for none
## (the level.json entry's name is the entity's; dungeon's 542).
func _chest_named(zone_name: String, chest_name: String) -> Chest:
	var found: Array = World.zones[zone_name].entities if World.zones.has(zone_name) else World.get_entities()
	for entity: Variant in found:
		if entity is Chest and entity.spawned and entity.zone == zone_name and String(entity.name) == chest_name:
			return entity as Chest
	return null


func _alms_runs_tick() -> void:

	if not Net.is_authority() or World.economy == null or World.production == null or not World.economy.has_method("altar_gold"):
		return
	var rule := _runner_rule()
	if rule.is_empty():
		return
	var name := str(rule.get("name", "Pip"))
	var hour_steps := maxi(DayNight.day_steps, 24) / 24
	var today := Townsfolk.day_of(World.steps)
	for town: String in World.towns.towns() if World.towns != null and World.towns.has_method("towns") else _towns_with_priests():
		var run: Dictionary = _alms_runs.get(town, {})
		if not run.is_empty():
			if bool(run.get("lost", false)):
				_runner_found(town, run, rule)
				continue
			if not bool(run.get("rolled", false)) and World.steps >= int(run.get("at_altar", 0)):
				run["rolled"] = true
				var rng := RandomNumberGenerator.new()
				rng.seed = hash("run:%s:%d" % [town, int(run.get("started", 0))])
				if not _crypt_told.is_empty() and rng.randf() < float(rule.get("lost_chance", 0.0)):
					run["lost"] = true
					var priest := _priest_of(town)
					if not priest.is_empty():
						Townsfolk.learn(World.production, priest, "%s has not been seen since morning." % name)
					MindLog.record({"kind": "runner", "companion": name, "mind": "resident", "say": "lost below with %d gold" % int(run.get("gold", 0)), "outcome": "lost"})
					print("[runner] %s is lost below %s's barrow with %d gold" % [name, town, int(run.get("gold", 0))])
					continue
			if World.steps >= int(run.get("back_at", 0)):
				World.economy.altar_down(town, int(run.get("gold", 0)))
				_runner_home(town, run)
				print("[runner] %s is home: %d gold laid at %s's altar" % [name, int(run.get("gold", 0)), town])
			continue
		if int(_runs_day.get(town, -1)) == today or DayNight.hour(World.steps) < float(rule.get("hour", 6)):
			continue
		var gold := int(World.economy.altar_gold(town))
		if gold <= 0:
			continue
		var who := _runner_of(town)
		if who.is_empty() or not _runner_here(who, name):
			continue
		_runs_day[town] = today
		gold = int(World.economy.take_altar(town))
		if gold <= 0:
			continue
		var each_way := int(float(rule.get("hours_each_way", 2)) * hour_steps)
		_alms_runs[town] = {"who": who, "gold": gold, "started": World.steps, "at_altar": World.steps + each_way, "back_at": World.steps + 2 * each_way, "rolled": false, "lost": false}
		World.production.set_away(who, true)
		_runner_out[who] = true
		print("[runner] %s takes %d gold down from %s's temple, step %d" % [name, gold, town, World.steps])


## The towns with a priest, when Towns lists none itself.
func _towns_with_priests() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for id: String in World.production.worker_ids():
		var town := str(World.production.worker(id).get("town", ""))
		if not town.is_empty() and not seen.has(town) and not _priest_of(town).is_empty():
			seen[town] = true
			out.append(town)
	out.sort()
	return out


## The runner of [param run] is home: back on the streets, the run over.
func _runner_home(town: String, run: Dictionary) -> void:
	var who := str(run.get("who", ""))
	_alms_runs.erase(town)
	_runner_out.erase(who)
	if not World.production.worker(who).is_empty():
		World.production.set_away(who, false)


## A lost runner found: a player within found_reach of the barrow's niche
## place ("<barrow>/<niche>" in Holdings). The gold goes down, he comes
## home with the lived fact, the priest's card says so, the finder is told.
func _runner_found(town: String, run: Dictionary, rule: Dictionary) -> void:
	if World.holdings == null:
		return
	var place := World.holdings.place("%s/%s" % [rule.get("barrow", "barrow"), rule.get("niche", "niche")])
	if place.is_empty():
		return
	var finder: Player = null
	for player: Player in _players.values():
		if is_instance_valid(player) and player.spawned and player.zone == str(place.get("area", "")) and World.distance(player.tile, place["cell"]) <= int(rule.get("found_reach", 2)):
			finder = player
			break
	if finder == null:
		return
	var who := str(run.get("who", ""))
	var name := str(World.production.worker(who).get("name", rule.get("name", "Pip")))
	World.economy.altar_down(town, int(run.get("gold", 0)))
	_runner_home(town, run)
	Townsfolk.learn(World.production, who, "%s was lost below the barrow, saw the draugr bargain for gold, and lived." % name)
	var priest := _priest_of(town)
	if not priest.is_empty():
		Townsfolk.learn(World.production, priest, "%s came up from the barrow, found by %s, and would not say what he saw." % [name, _display_name(finder)])
	party_log.add("%s finds %s in a niche in the wall, shaking; he makes his way up." % [_display_name(finder), name])
	Net.broadcast_to([finder.owner_peer], "party", {"from": name, "text": "You find %s in a niche in the wall, shaking. He will not say what he saw, and makes his way up." % name})
	MindLog.record({"kind": "runner", "companion": name, "mind": "resident", "say": "found by %s" % _display_name(finder), "outcome": "found"})
	print("[runner] %s is found below %s's barrow by %s: %d gold laid at the altar" % [name, town, _display_name(finder), int(run.get("gold", 0))])


# --- A level-placed captive (decision 518) ------------------------------------------

## Words a hold may use for its resident: "a <trade>'s <word>".
const HOLD_WORDS := "^an? (.+?)'s (son|daughter|brother|sister|father|mother|cousin)$"


## Server: every camp place with level.json "holds" (decision 518; builder's
## "a goblin camp holding a captive") that a faction holds takes its
## captives, once: each hold's resident is found in the town (a worker id,
## or a name among its residents) or minted into it (Towns.move_in, origin
## "placed", the trade given or a hauler) with kin from the role words ("a
## woodcutter's son": the town's woodcutter, first by id, any resident when
## it has none), then taken by the camp through Towns.resident_taken and
## captive_held, the path a raid uses, so the kin's plea (331), the camp's
## fall, the carried-home and the memory run unchanged; Townsfolk says it
## without a raid or a date. _placed_captives remembers what is placed; a
## camp in [param gone] (a regeneration dropped it) frees its placed held
## home (Towns.free_held, as a fallen camp does) and is forgotten. Called
## after the towns are seeded and after a regeneration; builder may call
## it after an accepted change. How many were placed.
func _place_captives(world_map: WorldMap, gone: Array[String] = []) -> int:
	if not Net.is_authority() or World.towns == null or World.holdings == null or World.production == null or world_map == null:
		return 0
	for camp_id: String in gone:
		if _placed_captives.has(camp_id):
			var freed := World.towns.free_held(camp_id)
			print("[captive] %s is gone from the levels: %s come home" % [camp_id, ", ".join(freed) if not freed.is_empty() else "nobody held there"])
			_placed_captives.erase(camp_id)
	var placed := 0
	var areas: Array = world_map.areas.keys()
	areas.sort()
	for area_name: String in areas:
		var places: Dictionary = world_map.areas[area_name].get("places", {})
		var keys: Array = places.keys()
		keys.sort()
		for key: String in keys:
			var place: Dictionary = places[key]
			if place.get("kind") != "camp" or not place.get("holds") is Array:
				continue
			var camp_id := "%s/%s" % [area_name, key]
			var holder := World.holdings.holder(camp_id)
			if holder.is_empty() or holder == Factions.NOBODY or holder == Stockpile.TOWN:
				continue
			var done: Dictionary = _placed_captives.get(camp_id, {})
			var holds: Array = place["holds"]
			for i in holds.size():
				if done.has(str(i)):
					continue  # Placed before (this boot or an earlier one).
				var who := _place_captive(camp_id, holder, holds[i], i)
				if who.is_empty():
					continue  # Not yet (a town with nobody to be kin to, or none): the next pass tries again.
				done[str(i)] = who
				placed += 1
			if not done.is_empty():
				_placed_captives[camp_id] = done
	return placed


## One hold of camp [param camp_id] (held by [param holder]): the resident
## found or minted, with kin, and taken. The worker id, "" if nothing could
## be placed (no such town: said in the log).
func _place_captive(camp_id: String, holder: String, hold: Dictionary, index: int) -> String:
	var town := str(hold.get("town", ""))
	var wanted := str(hold.get("resident", ""))
	if town.is_empty() or wanted.is_empty() or World.holdings.place(town).is_empty():
		print("[captive] %s holds %s of %s: no such town, nothing placed" % [camp_id, wanted, town])
		return ""
	var raiders := ResidentCard.faction_name(holder)
	var who := ""
	var kin_id := ""
	var relation := ""
	var role := RegEx.create_from_string(HOLD_WORDS).search(wanted.to_lower())
	if role == null and not World.production.worker(wanted).is_empty() and str(World.production.worker(wanted).get("town", "")) == town:
		who = wanted  # A worker id.
	elif role == null:
		for id: String in World.towns.residents(town):
			if str(World.production.worker(id).get("name", "")).to_lower() == wanted.to_lower():
				who = id  # A resident by name.
				break
	if who.is_empty() and World.towns.residents(town).is_empty():
		return ""  # Nobody to be kin to yet (a town not peopled at this pass): waits for the next.
	if who.is_empty():
		var trade := str(hold.get("trade", ""))
		if trade.is_empty():
			trade = str(World.production.rules.get("haul", {}).get("trade", "hauler"))
		var name := str(hold.get("name", ""))
		if name.is_empty():
			var names: Array = World.towns.rules.get("rescue", {}).get("names", ["Someone"])
			name = str(names[absi(hash("%s/%d" % [camp_id, index])) % names.size()])
		who = "placed_%s_%d" % [camp_id.replace("/", "_").replace(":", "_"), index]
		if not World.production.worker(who).is_empty():
			return who  # Minted on an earlier boot whose marker was lost: theirs already.
		if not World.towns.move_in(town, who, name, trade, "placed"):
			print("[captive] %s holds %s of %s: the town would not take them" % [camp_id, wanted, town])
			return ""
	var card := Townsfolk.card_of(World.production, who)
	if role != null:
		var word := role.get_string(2)
		var of_trade := role.get_string(1).replace(" ", "_")
		card["traits"]["pronoun"] = "she" if word in ["daughter", "sister", "mother"] else "he"
		World.production.set_card(who, card)
		var others: Array = World.towns.residents(town).filter(func(id: String) -> bool:
			return id != who and not id.begins_with("companion:") and not str(World.production.worker(id).get("origin", "")).begins_with("companion:"))
		others.sort()
		var of_it: Array = others.filter(func(id: String) -> bool: return of_trade in World.production.worker(id).get("trades", []))
		if of_it.is_empty() and not others.is_empty():
			print("[captive] %s: %s has no %s; %s is kin to %s instead" % [camp_id, town, of_trade.replace("_", " "), who, others[0]])
		kin_id = str(of_it[0]) if not of_it.is_empty() else (str(others[0]) if not others.is_empty() else "")
		if not kin_id.is_empty():
			var theirs := Townsfolk.card_of(World.production, kin_id)
			var kind := "cousin" if word == "cousin" else ("sister or brother" if word in ["brother", "sister"] else "parent and child")
			# kin_facts' first card is the child of a parent-and-child pair.
			var both: Array[String] = ResidentCard.kin_facts(theirs, card, kind) if word in ["father", "mother"] else ResidentCard.kin_facts(card, theirs, kind)
			var now := World.production.now()
			if word in ["father", "mother"]:
				ResidentCard.add_fact(theirs, now, both[0])
				ResidentCard.add_fact(card, now, both[1])
			else:
				ResidentCard.add_fact(card, now, both[0])
				ResidentCard.add_fact(theirs, now, both[1])
			card.get_or_add("kin", {})[kin_id] = kind
			theirs.get_or_add("kin", {})[who] = kind
			World.production.set_card(kin_id, theirs)
			World.production.set_card(who, card)
			relation = word
	if not World.towns.resident_taken(town, who, "placed:" + camp_id, holder):
		print("[captive] %s could not take %s of %s" % [camp_id, who, town])
		return ""
	World.towns.captive_held(who, camp_id)
	Townsfolk.placed_captive(World.production, town, who, kin_id, relation, raiders)
	print("[captive] %s holds %s of %s from the start%s" % [camp_id, World.production.worker(who).get("name", who), town,
		", %s of %s" % [relation, World.production.worker(kin_id).get("name", kin_id)] if not kin_id.is_empty() else ""])
	return who


# --- The fallen brought back (decision 396) -----------------------------------------

## Each healer's hut (a Holdings place of kind healers_hut, maps' 372) given
## its medicine man if it has none: a workshop of the place's own, a worker
## outside any town's purse (rules' return.places "outside"), named by the
## place.
func _seat_healers() -> void:
	if World.holdings == null or World.production == null:
		return
	var places: Dictionary = World.production.rules.get("return", {}).get("places", {})
	for kind: String in places:
		var rule: Dictionary = places[kind]
		if not bool(rule.get("outside", false)):
			continue
		var trade := str(rule.get("trade", ""))
		var names: Array = rule.get("names", [])
		var ids := World.holdings.all_places()
		ids.sort()
		for id: String in ids:
			if World.holdings.place(id).get("kind") != kind or not World.production.workshop(id).is_empty():
				continue
			var who := "%s:%s" % [trade, id]
			# A name no other of the trade has (641: two huts, two healers).
			var taken: Array = World.production.worker_ids().map(func(other: String) -> String:
				return str(World.production.worker(other).get("name", "")) if trade in World.production.worker(other).get("trades", []) else "")
			var name := trade.capitalize()
			for k in names.size():
				var pick := str(names[(absi(hash(id)) + k) % names.size()])
				if pick not in taken:
					name = pick
					break
			World.production.add_worker(who, name, [trade], id, "wilds")
			World.production.add_workshop(id, trade, id)
			World.production.assign(id, who)
			print("[return] %s the %s keeps %s" % [name, trade.replace("_", " "), id])


## What workshop [param workshop_id] makes (Production.workshop_makes,
## 641): for a place of a return.places kind with "makes" (the healer's
## hut), the list under the place's key, else its area's (a hut a building
## makes has its cell in its key), else "_default"; [] (every recipe of its
## trade) for any other.
func _workshop_makes(workshop_id: String) -> Array:
	var place := World.holdings.place(workshop_id) if World.holdings != null else {}
	var makes: Variant = World.production.rules.get("return", {}).get("places", {}).get(str(place.get("kind", "")), {}).get("makes")
	if place.is_empty() or not makes is Dictionary:
		return []
	return makes.get(str(place.get("key", "")), makes.get(str(place.get("area", "")), makes.get("_default", [])))


## Towns.placed (649): [param town]'s [param kind] on the world map (the
## building of that use linked to the town): {zone, cells (its rect's),
## distance (its rect's centre from the town's store)}; {} if the map has none.
func _town_placed(town: String, kind: String) -> Dictionary:
	var area := town.get_slice("/", 0)
	if _world_map == null or not _world_map.areas.has(area):
		return {}
	for house: Dictionary in _world_map.areas[area].get("buildings", []):
		if str(house.get("use", "")) != kind or "%s/%s" % [area, house.get("town", "")] != town or not house.get("rect") is Rect2i:
			continue
		var rect: Rect2i = house["rect"]
		var cells: Array[Vector2i] = []
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				cells.append(Vector2i(x, y))
		var store: Vector2i = World.holdings.place(town).get("cell", rect.get_center()) if World.holdings != null else rect.get_center()
		return {"zone": area, "cells": cells, "distance": float(World.distance(rect.get_center(), store))}
	return {}


## A town's ruin is gone (649): its ground given back to the forest
## (terrain's Clearing.unbuild: a plot under it dropped, stumps from today).
func _on_town_ruined(_town: String, _kind: String, zone: String, cells: Array[Vector2i]) -> void:
	if World.clearing != null and not zone.is_empty() and not cells.is_empty():
		World.clearing.unbuild(zone, cells, World.towns.now() / maxi(DayNight.day_steps, 1))


## A town builds a gone kind again (649 amended): its ground taken back
## from the forest (Clearing.build: built over, never growing).
func _on_town_reclaimed(_town: String, _kind: String, zone: String, cells: Array[Vector2i]) -> void:
	if World.clearing != null and not zone.is_empty() and not cells.is_empty():
		World.clearing.build(zone, cells)


## The workshop of Holdings place [param id] where the fallen are brought
## back ("" if none): a hut's own; a temple's, its town's in its area.
func _return_workshop(id: String) -> String:
	if not World.production.workshop(id).is_empty():
		return id
	var place := World.holdings.place(id)
	if World.towns == null or place.is_empty():
		return ""
	for town: String in World.towns.to_dict():
		if str(World.holdings.place(town).get("area", "")) == str(place.get("area", "")) \
				and not World.production.workshop("%s:%s" % [town, place["kind"]]).is_empty():
			return "%s:%s" % [town, place["kind"]]
	return ""


## The place someone who fell at [param cell] of the zone World is in is
## brought back at: the nearest of the return places that is manned, by
## walking across the levels ({place, workshop}); {} if none is.
func _return_place(cell: Vector2i, player_id := "") -> Dictionary:
	if World.holdings == null or World.production == null:
		return {}
	var kinds: Array[String] = []
	kinds.assign(World.production.rules.get("return", {}).get("places", {}).keys())
	var routes: WorldRoutes = World.raid_groups.routes if World.raid_groups != null else null
	var ranked := World.holdings.ranked(kinds, World.zone.name, cell, routes)
	# In care, the carer's hut first (decision 630; Jeff came back at the temple in Hob's care): the nearest
	# manned hut in their care by the same ranking (routed across zones when routes are known), else the first
	# manned one in their care wherever it stands (the return travels: _on_returned); only then the rest.
	var record: PlayerRecord = _records.get(player_id) if not player_id.is_empty() else null
	if record != null and not record.care.is_empty():
		for id: String in ranked:
			if record.care.has(id):
				var shop := _return_workshop(id)
				if not shop.is_empty() and World.production.manned(shop):
					return {"place": id, "workshop": shop}
		for id: String in record.care:
			if not World.holdings.place(id).is_empty():
				var shop := _return_workshop(id)
				if not shop.is_empty() and World.production.manned(shop):
					return {"place": id, "workshop": shop}
	# The nearest that is manned, of any kind, routed once (decision 503).
	for id: String in ranked:
		var shop := _return_workshop(id)
		if not player_id.is_empty() and World.holdings.place(id).get("kind") == "healers_hut" and not in_care(player_id, id):
			continue  # A healer's hut brings back only a player in its care (584 amended).
		if not shop.is_empty() and World.production.manned(shop):
			return {"place": id, "workshop": shop}
	return {}


## [param who] ([param kind]: player (their id), companion (her player's),
## resident (the worker)), fallen at [param cell], to be brought back at
## the nearest manned place: true if a return job was opened.
func _start_return(who: String, kind: String, cell: Vector2i) -> bool:
	if who.is_empty() or not returns:
		return false
	var at := _return_place(cell, who if kind == "player" else "")
	# A player comes back at once, from near death (decision 587: Mortally
	# Wounded's Bleed Out, or the blood run out); others after the keeper's work.
	var id := World.production.open_return(at["workshop"], who, kind, at["place"], kind == "player") if not at.is_empty() else 0
	if id != 0 and kind == "player":
		var keeper := World.production.worker(str(World.production.job(id).get("worker", "")))
		_tell_return(_peer_of(who), str(keeper.get("name", "")), str(World.holdings.place(at["place"]).get("kind", "")),
			World.production.return_left(id), {"near_death": true})
	return id != 0


## Tells the fallen player on [param peer] who brings them back, where (a
## kind of rules' return.places; "" and "" for the plain respawn) and in how
## many [param steps] (-1 not known): the "return" message (396 amended,
## for ui's countdown), {by, where, seconds}, and [param more] (decision
## 587: near_death).
func _tell_return(peer: int, by: String, where: String, steps: int, more := {}) -> void:
	if peer == 0:
		return
	var data := {"by": by, "where": where, "seconds": ceili(steps / float(World.TICK_RATE)) if steps >= 0 else -1}
	data.merge(more)
	Net.message_to(peer, "return", data)


## Server: everyone in a zone is down (companions' detection, decision 587):
## the players on [param peers] are told they all come back in
## return.everyone_s seconds ("return" {all_fallen: seconds}). The seconds.
func tell_all_fallen(peers: Array) -> int:
	var seconds := int(World.production.rules.get("return", {}).get("everyone_s", 20)) if World.production != null else 20
	for peer: Variant in peers:
		if int(peer) != 0:
			Net.message_to(int(peer), "return", {"all_fallen": seconds})
	return seconds


## The peer [param player_id] plays on now; 0 if none.
func _peer_of(player_id: String) -> int:
	for peer: int in _peer_ids:
		if _peer_ids[peer] == player_id:
			return peer
	return 0


## A return job done (Production.returned): [param job]'s who brought back
## at its place, said to them by whoever brought them back; on a fallback,
## as before (a player at a start tile, a companion beside her player).
func _on_returned(job: Dictionary) -> void:
	var who := str(job.get("who", ""))
	var place := World.holdings.place(str(job.get("place", "")))
	var area := str(place.get("area", ""))
	var cell: Vector2i = place.get("cell", World.NO_CELL)
	if bool(job.get("fallback", false)) or place.is_empty():
		cell = World.NO_CELL
	var where := "the temple" if place.get("kind") == "temple" else "the healer's hut" if place.get("kind") == "healers_hut" \
			else "a holy place"
	var by := str(job.get("by", ""))
	var was := World.zone
	# The temple's offering (decision 546): its town's, from the job's workshop ("<town>:temple").
	var temple_town := str(job.get("workshop", "")).get_slice(":", 0) if place.get("kind") == "temple" and cell != World.NO_CELL else ""
	match str(job.get("who_kind", "")):
		"player":
			var record: PlayerRecord = _records.get(who)
			if record == null:
				return
			var peer := _peer_of(who)
			if _players.has(peer):
				return  # Back already (a rejoin).
			record.hp = 0  # Full stats.
			var offered := World.economy.temple_offering(temple_town, who, _offering_waived(record.marks), "") if World.economy != null else 0
			if peer == 0:
				# Not playing now: they come in there next time.
				if cell != World.NO_CELL:
					record.zone = area
					record.tile = cell
				return
			if cell == World.NO_CELL:
				# Given up on (the keeper stopped, or too long): the plain respawn.
				_respawn_at[peer] = World.tick + RESPAWN_TICKS
				_tell_return(peer, "", "", RESPAWN_TICKS)
				return
			if str(World.peer_zone.get(peer, record.zone)) == area:
				World.enter_named(area)
				_join_player(peer, who, record.name, true, cell)
			else:
				travel(peer, area, "", {}, cell)
			var words := "%s brought you back from near death" % by if bool(job.get("near_death", false)) \
				else "%s is brought back at %s by %s" % [record.name, where, by]  # Decision 587.
			Net.broadcast_to([peer], "party", {"from": by, "text": "%s%s." % [words, ", for an offering of %d gold" % offered if offered > 0 else ""]})
		"companion":
			var record: PlayerRecord = _records.get(who)
			if record == null or record.companion.is_empty():
				return
			var peer := _peer_of(who)
			var player: Player = _players.get(peer)
			var with_them := is_instance_valid(player) and player.spawned
			record.companion["alive"] = true
			record.companion["hp"] = 0  # Full stats.
			# Her player makes her offering, waived by her own mark (544).
			var offered := World.economy.temple_offering(temple_town, who, _offering_waived(record.companion.get("marks", [])),
				str(record.companion.get("name", ""))) if World.economy != null else 0
			record.companion["tile"] = [cell.x, cell.y] if with_them and player.zone == area and cell != World.NO_CELL else null
			if cell != World.NO_CELL:
				# Her card takes it (293 amended): the one who brought her back.
				var grown := CompanionFacts.from_record(record.companion.get("facts", []), record.companion.get("beliefs", []))
				grown.add_fact(return_fact(str(record.companion.get("name", "She")), where, by), "event", who)
				record.companion["facts"] = grown.facts
			if with_them:
				World.enter_named(player.zone)
				_join_companion(record, player)
				if cell != World.NO_CELL:
					Net.broadcast_to([peer], "party", {"from": by, "text": "%s is brought back at %s by %s%s." % [
						record.companion.get("name", "Your companion"), where, by, ", for an offering of %d gold" % offered if offered > 0 else ""]})
		"resident":
			if World.production.worker(who).is_empty():
				return
			World.production.set_away(who, false)
			print("[return] %s is back%s" % [World.production.worker(who)["name"], "" if cell == World.NO_CELL else " at %s by %s" % [where, by]])
	World.enter(was)


## Whether the temple's offering is waived for one carrying [param marks]
## (a player's record.marks, a companion's own "marks": return.waived_by,
## the draugr's mark, decisions 540 and 544).
func _offering_waived(marks: Variant) -> bool:
	var mark := str(World.production.rules.get("return", {}).get("waived_by", "draugr")) if World.production != null else "draugr"
	return marks is Array and mark in (marks as Array)


func _respawn_due_players(tick: int) -> void:
	for peer: int in _respawn_at.keys():
		if World.peer_zone.get(peer, World.zone.name) != World.zone.name:
			continue  # Its own zone's tick brings it back.
		if tick >= _respawn_at[peer]:
			_respawn_at.erase(peer)
			var id: String = _peer_ids.get(peer, "")
			if id != "" and _records.has(id):
				_join_player(peer, id, _records[id].name, true)


# --- HUD, logging, test hooks -------------------------------------------------

func _on_world_ticked(tick: int) -> void:
	if Net.is_authority():
		var t := Time.get_ticks_usec()  # Each part's time for a slow tick's line (decision 469).
		if tick % World.WORLD_TICK_STEPS == 0 and _world_map != null:
			# Storms break roofs (Weather.break_roofs).
			for broke: Dictionary in Weather.break_roofs(_world_map.areas, World.steps):
				print("[weather] %s broke roof %d of %s" % [broke["storm"], broke["index"], broke["level"]])
			_seat_settled()  # A settled person whose town has since been founded (decision 471).
			_visits_due()  # The medicine man's visits that have run their hours (decision 501).
			_sickness_in_party()  # A sick companion with her player gets well (decision 501).
			_gather_herbs()  # The medicine man takes herbs on his way (decision 502, npc's side).
			_alms_runs_tick()  # Pip's run with the alms (decision 546, npc's side).
			_crypt_asks_tick()  # Aldous's commissions met at the altar or the pack (part 3).
		if tick % HAIL_CHECK_TICKS == 0:
			_hails_tick()  # Residents speaking unprompted (decision 554).
		if tick % WORK_CHECK_TICKS == 0:
			_visible_work_tick()  # The bodies at the work the sim does (decision 566).
		_respawn_due_players(tick)
		_tend_hearts()  # Mortally Wounded: the downed's hearts, and all of them fallen.
		_all_fallen_tick()
		_leaving_tick()  # A companion leaving her player (decision 581).
		if tick % World.WORLD_TICK_STEPS == 0:
			_favour_tick()  # Winning back one who left (581 amended).
		_check_respawns(tick)
		t = World.part("respawns", t)
		if tick % CAMP_CHECK_TICKS == 0:
			_check_camps(tick)
			_tell_world(tick)
		if tick % World.WORLD_TICK_STEPS == 0:
			_retake_camps()
			if _lawspeaker_client != null and World.production != null:
				Lawspeaker.tick(World.production.now(), _lawspeaker_client)  # His daily rulings (decision 448); a coroutine, not awaited.
		t = World.part("camps, lawspeaker", t)
		if tick % RESIDENT_SYNC_TICKS == 0:
			_sync_residents()
			_sync_bands()
		t = World.part("residents", t)
		if tick % World.WORLD_TICK_STEPS == 0 and World.zone == World.home():
			_tend_bonds()
		_recall_due()
		if tick % RETIRE_EVERY_TICKS == 0:
			_retire_and_recall()
		t = World.part("retire and recall", t)
		if tick % TEMPLE_COUNTER_TICKS == 0:
			_temple_counters()
		_resident_voices()
		World.part("temple, voices", t)
	if World.zone != World.home():
		return  # Another zone's tick: the HUD and the test hooks are this view's.
	var player := _local_player()
	var hp_text := "no player" if Net.mode == Net.Mode.SERVER else "dead, respawning"
	if player == null and not _return_told.is_empty():
		hp_text = return_shown()  # 396 amended, ui's side: who brings them back, in how long.
	if player != null:
		_return_told = {}  # Back.
		hp_text = ""  # No HP number (Jeff, 2026-10-22: "we dont need an hp number on the HUD"): hurt reads from the body; F3 has it.
		for kind: String in player.buffs:
			var amount := float(player.buffs[kind][0])  # Speed as a share: "Quick 25%" (decision 562).
			hp_text += "   %s %s %ds" % [Items.BUFF_KINDS.get(kind, kind),
				"%d%%" % roundi(amount * 100.0) if kind == "speed" else "+" + str(snappedf(amount, 0.1)),
				ceili(maxi(int(player.buffs[kind][1]) - tick, 0) * World.TICK_DT)]
		if player.raised == "block":
			hp_text += "   shield raised"
		elif player.raised == "draw":
			hp_text += "   bow drawn"  # How far: the body, the ring and the creak (decision 475); F3 has the number.
		if _hidden_in_cover(player, tick):
			hp_text += "   hidden in the grass"  # Decision 515: the one cue that the cover works.
		if is_winded(player):
			hp_text += "   winded"  # Combat's stamina (step 2), ui's side: the one word, no bar; the body and the breath say the rest.
		_watch_bond()
		if not _bond_hint.is_empty() and Time.get_ticks_msec() / 1000.0 < _bond_hint_until:
			hp_text += "   " + _bond_hint  # 555, ui's side: her step dropped, said for BOND_HINT_SECONDS.
		if not standing_title.is_empty():
			hp_text += "   " + standing_words(standing_title)  # 536: an offer stands; "yes" (Y) takes it.
		if not player.led_by.is_empty():  # 551, ui's side: she leads; the place from led_to when it is on the wire.
			hp_text += "   " + led_words(player.led_by, world_map_panel.place_words(led_to_of(player)) if world_map_panel != null else "")
		if World.is_downed(player):
			hp_text += "   " + downed_words(ceili((player.downed_until - tick) * World.TICK_DT))  # 544, ui's side.
		elif not player.channel_of.is_empty() and tick < player.channel_until:
			var body := _entity_named(player.channel_of)
			hp_text += "   " + channel_words(_display_name(body) if body != null else player.channel_of,
					ceili((player.channel_until - tick) * World.TICK_DT))
	if down_screen != null:
		# 587, ui's side: the screen while downed; the heart and the blessing read by name.
		var downed := player != null and World.is_downed(player)
		var heart: Variant = player.get("heart") if downed else null
		var room: Variant = player.get("charge_room") if downed else null
		down_screen.show_state(downed, ceili((player.downed_until - tick) * World.TICK_DT) if downed else 0,
				int(heart) if heart is int else 0, room is int and int(room) > 0, all_fallen_left())
	_hud_tick = tick
	hud.text = hp_text.strip_edges()
	if player != null and _connect_joining and connect_screen != null:
		_connect_joining = false
		connect_screen.visible = false  # In: the world shows.
	if hint_panel != null:
		hint_panel.set_lines(hint_lines())
	if player != null:
		_had_player = true
		_already_tries = 0
	if player != null:
		player.enable_prediction()
	_run_test_move(player)
	_run_test_contest(player, tick)
	_run_test_reset(player, tick)
	if player != null and Net.test_builder != "" and _builder_ui != null and tick > 20:
		_builder_ui.test_ask(Net.test_builder)
		Net.test_builder = ""
	_run_test_door(player, tick)
	_run_test_chest(player)
	_run_test_show(player)
	_run_test_offer(player)
	_run_test_channel(player)
	if world_map_panel != null and world_map_panel.visible:
		_refresh_world_map()
	_first_talk_hint(player)


## The controls for the HUD's list, a line each, "key\twhat it does".
func hint_lines() -> Array[String]:
	var lines: Array[String] = []
	if Net.controls == "wasd":
		lines.append_array(["%s\twalk" % Keys.walk_names(), "Mouse\taim", "LMB\tattack (far: walk); a friend: talk", "%s+LMB\tswing where you stand" % Keys.name_of("stand"),
			"RMB\toff hand; empty: grab (drag to toss)"])
		if _client3d != null:
			lines.append_array(["MMB drag\tturn, look up / down", "Ctrl+MMB drag\tpan (springs back)", "Wheel\tzoom (MMB click: 1x)"])
	else:
		lines.append_array(["LMB\tmove / attack (hold to steer); a friend: talk", "%s+LMB\tswing where you stand" % Keys.name_of("stand"),
			"RMB\toff hand; empty: shove (drag to toss)"])
		if _client3d != null:
			lines.append_array(["%s / %s\toverhead / normal view" % [Keys.name_of("forward"), Keys.name_of("back")],
				"%s / %s\tturn" % [Keys.name_of("left"), Keys.name_of("right")], "MMB drag\tturn, look up / down", "Ctrl+MMB drag\tpan (springs back)", "Wheel\tzoom"])
	for i in Net.phrases.size():
		lines.append("%s\t%s" % [Keys.name_of("phrase_%d" % (i + 1)), Net.phrases[i]])
	lines.append_array(["%s+LMB\tyour weapon's own move (a shield bashes)" % Keys.name_of("signature"), "RMB, shield\tblock toward the cursor while held",
		"%s held, bow\tstand firm and draw: LMB release looses, let go lowers it (arrow kept), walk keys turn" % Keys.name_of("stand"),
		"RMB, bow\thold to aim at the sky, let go to lob onto the circle: over walls, knocks down",
		"%s\topen a chest, crate, cart, door; your companion's pack" % Keys.name_of("open"), "%s\tyour pack" % Keys.name_of("pack"),
		"%s\tyour companion's card" % Keys.name_of("card"),
		"%s\tthe town sheet" % Keys.name_of("town"),
		"%s\tpick up" % Keys.name_of("pick_up"), "%s\tput down (hand, else pack)" % Keys.name_of("drop"), "%s\tthrow at the cursor" % Keys.name_of("throw"),
		"%s\ta bandage on the cursor: click yourself or an ally beside you (a kit, out of combat)" % Keys.name_of("bandage"),
		"%s hold\tbandage an ally beside you, else yourself" % Keys.name_of("open"),
		"RMB in pack\tuse it (eat, open a purse, bandage)",
		"%s\ttalk (/w whisper)" % Keys.name_of("talk"), "%s\ttalk log" % Keys.name_of("talk_log"), "%s\tmap" % Keys.name_of("map"), "%s\tlantern" % Keys.name_of("lantern"),
		"%s\treset the room" % Keys.name_of("reset"), "%s\toptions" % Keys.name_of("options"), "%s\tdebug" % Keys.name_of("debug"), "%s\tfullscreen" % Keys.name_of("fullscreen"),
		"%s\tscreenshot, saved under %s" % [Keys.name_of("screenshot"), ProjectSettings.globalize_path(str(screenshot_folder()[0]))],
		"%s\tsay yes to an offer that stands (or type it)" % Keys.name_of("yes"), "%s\thide these" % Keys.name_of("hints")])
	if Net.mode == Net.Mode.HOST:
		lines.append("%s\tbuilder mode" % Keys.name_of("builder"))
	return lines


## M: the zone's big map; M again, the world map in its place; M again, closed.
func press_m() -> void:
	if world_map_panel != null and world_map_panel.visible:
		world_map_panel.close()
	elif minimap.big:
		minimap.toggle()
		open_world_map()
	else:
		minimap.toggle()


## The world map opened on the player's area, with this zone's party and
## maps' world_state (holdings, what is known, the party elsewhere) when
## it is there.
func open_world_map() -> void:
	if world_map_panel == null:
		return
	_refresh_world_map()
	world_map_panel.open()


func _refresh_world_map() -> void:
	if world_map_panel == null:
		return
	var player := _local_player()
	world_map_panel.own_area = zone_name_here()  # 538 amended: the same read, so a joined client's own area is marked.
	world_map_panel.own_cell = player.tile if player != null else Vector2i(-1, -1)
	world_map_panel.led = {"by": player.led_by if player != null else "", "to": led_to_of(player)}  # 551, ui's side.
	world_map_panel.notes = town_notes
	world_map_panel.towns = town_states  # 624: a town's row opens its sheet.
	var here: Array[Dictionary] = []
	for entity in World.get_entities():
		if entity is Player and entity != player and entity.spawned:
			here.append({"name": _display_name(entity), "area": world_map_panel.own_area, "kind": "player"})
		elif entity is Companion and entity.spawned:
			# 555, ui's side: her bond's step on her line, the reason for the hover.
			here.append({"name": String(entity.name), "area": world_map_panel.own_area, "kind": "companion",
				"mood": bond_shown(str(entity.bond_step)), "why": reason_short(str(entity.bond_why))})
	var state: Variant = get("world_state")
	world_map_panel.set_world_state(state if state is Dictionary else {}, here)


## The map's ask (551, ui's side): the "guide" command for [param to], a
## place id or area name she knows the way to; the map closes, the HUD
## line and her own words say the rest.
func _ask_guide(to: String) -> void:
	var player := _local_player()
	if player != null and not to.is_empty():
		World.command(player, "guide", {"to": to})
	if world_map_panel != null:
		world_map_panel.close()


## Where the companion leads [param player] (companions' Player.led_to, a
## place id or area name; "" when not led or before that field is on main:
## read by name, so this compiles either way).
static func led_to_of(player: Player) -> String:
	if player == null:
		return ""
	var to: Variant = player.get("led_to")
	return to if to is String else ""


## The HUD's words while led (551, ui's side): who leads, where to when the
## wire says, and how to take the lead back (any step or order does).
static func led_words(name: String, place: String) -> String:
	if place.is_empty():
		return "Following %s - move to take the lead" % name
	return "Following %s to %s - move to take the lead" % [name, place]


## Her bond's step, watched for a drop (555, ui's side; companions'
## Companion.bond_step and bond_why on the wire): the first sight of a
## companion seeds what was seen, so a join says nothing; a colder step than
## last seen puts her words on the HUD for BOND_HINT_SECONDS and one party
## log line with the reason; warming says nothing here (her voice and her
## line's word say it).
func _watch_bond() -> void:
	var pet := _own_companion()
	if pet == null:
		return
	var name := String(pet.name)
	var step := str(pet.bond_step)
	# A drop to a warm step (devoted to close, close to fond) has no words:
	# nothing on the HUD and no log line (companions' still showed ": you
	# struck her" with nothing before the colon, 2026-10-21).
	if _bond_seen.has(name) and bond_dropped(str(_bond_seen[name]), step) and not bond_words(name, step).is_empty():
		_bond_hint = bond_words(name, step)
		_bond_hint_until = Time.get_ticks_msec() / 1000.0 + BOND_HINT_SECONDS
		if talk != null:
			var why := reason_short(str(pet.bond_why))
			talk.add_line("Party", _bond_hint + (": " + why if not why.is_empty() else ""), true, true)
	_bond_seen[name] = step


## Her step as her line shows it (555, ui's side): the word companions send,
## warm or cold, and "" at fond (the start), so the plain read stays plain.
static func bond_shown(step: String) -> String:
	return "" if step == "fond" else step


## Whether [param now] is a colder step than [param last] (Companion.STEPS,
## coldest first); an unknown word on either side is no drop.
static func bond_dropped(last: String, now: String) -> bool:
	var was := Companion.STEPS.find(last)
	var is_now := Companion.STEPS.find(now)
	return was >= 0 and is_now >= 0 and is_now < was


## The HUD's words as her step drops to [param step] (BOND_WORDS); "" for a
## warm step.
static func bond_words(name: String, step: String) -> String:
	return str(BOND_WORDS[step]) % name if BOND_WORDS.has(step) else ""


## A reason cut to one row: [param limit] characters, an ellipsis at the end
## (a gift's reason names the thing, and a long title can run past a row).
static func reason_short(why: String, limit := 60) -> String:
	return why if why.length() <= limit else why.left(limit - 1).strip_edges() + "…"


## The item action [param keycode] is bound to (Keys), "" for none.
func _item_action_of(keycode: int) -> String:
	for action in ITEM_ACTIONS:
		if Keys.matches(keycode, action):
			return action
	return ""


## The quick phrase 1 to 4 [param keycode] is bound to (Keys), 0 for none.
func _phrase_of(keycode: int) -> int:
	for i in 4:
		if Keys.matches(keycode, "phrase_%d" % (i + 1)):
			return i + 1
	return 0


## Esc: whatever is open closes first (the options, an open chest or
## companion's pack, the menu itself); with nothing open, the game menu.
func escape() -> void:
	if tuning_panel != null and tuning_panel.visible and not tuning_panel.picking.is_empty():
		tuning_panel.picking = ""  # 673, ui's side: a cell pick let go, the panel kept.
	elif admin_panel != null and admin_panel.visible:
		admin_panel.close()  # 672: the admin panel first.
	elif tuning_panel != null and tuning_panel.visible:
		tuning_panel.close()
	elif _bar != null and _bar.visible:
		_close_bar()  # 560, ui's side: the talk bar, then the barter window.
	elif barter_panel != null and barter_panel.is_open():
		close_other()
	elif deal_panel != null and deal_panel.visible:
		deal_panel.close()  # 629, ui's side: the deal window.
	elif note_sheet != null and note_sheet.visible:
		note_sheet.close()  # 643, ui's side: the note put back.
	elif card_page != null and card_page.visible:
		card_page.visible = false  # 618: her card page.
	elif town_panel != null and town_panel.visible:
		town_panel.visible = false  # 624: the town sheet.
	elif world_map_panel != null and world_map_panel.visible:
		world_map_panel.close()
	elif game_menu != null and game_menu.visible:
		game_menu.open(false)
	elif options_panel != null and options_panel.visible:
		toggle_options()
	elif pack_panel != null and pack_panel.other != null:
		close_other()
	elif main_menu == null or not main_menu.visible:
		if game_menu == null:
			game_menu = GameMenu.new()
			game_menu.close_pressed.connect(func() -> void: game_menu.open(false))
			game_menu.options_pressed.connect(toggle_options)
			game_menu.leave_pressed.connect(_leave_game)
			game_menu.quit_pressed.connect(_quit_game)
			$HUD.add_child(game_menu)
		game_menu.open(true, str(level.get("display_name", level.get("name", ""))))


## N: the town sheet (624, ui's side) shown or hidden, for the town whose
## ground the player stands on (town_here).
func toggle_town() -> void:
	if town_panel == null:
		return
	if town_panel.visible:
		town_panel.visible = false
		return
	open_town(town_here())


## The sheet for town [param id] (one told in a "town" message; the known
## world's row click, 624): "" or an untold town shows "No town".
func open_town(id: String) -> void:
	if town_panel == null:
		return
	town_panel.town = id
	town_panel.visible = true
	_ask_town_sheet(id)
	_refresh_town()


## Economy's rows for town [param id] asked of the server as the sheet
## opens: the "town_sheet" command {town} (624, economy's side), answered
## by its "town_sheet" message (town_sheets, the sheet refreshed); once per
## TOWN_SHEET_ASK_MSEC a town. The host answers itself (a message to its
## own peer goes nowhere).
func _ask_town_sheet(id: String) -> void:
	var player := _local_player()
	if id.is_empty() or player == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_town_sheet_asked.get(id, -TOWN_SHEET_ASK_MSEC)) < TOWN_SHEET_ASK_MSEC:
		return
	_town_sheet_asked[id] = now
	if Net.is_authority():
		town_sheets[id] = ask_town_sheet(player, {"town": id})
	else:
		World.command(player, "town_sheet", {"town": id})


## The first town told for the zone the player is in, "" for none.
func town_here() -> String:
	var zone := zone_name_here()
	for id: String in town_states:
		if id.begins_with(zone + "/"):
			return id
	return ""


## The sheet's facts gathered from what the client has (624, ui's side):
## the "town" message's stage and buildings, world_state "holdings" in the
## known world's words, the Resident bodies seen while on the town's ground
## (their trades; null from elsewhere), the dole line (353), the season and
## day, and economy's "town_sheet" message when it has come.
func _refresh_town() -> void:
	if town_panel == null or not town_panel.visible:
		return
	var id := town_panel.town
	if id.is_empty() or not town_states.has(id):
		town_panel.show_town("", "", "", "", {}, null, "", "", 0)
		return
	var zone := id.get_slice("/", 0)
	var trades: Variant = null
	if zone == zone_name_here():
		var seen: Array = []
		for entity in World.entities():
			if entity is Resident and entity.spawned:
				seen.append(str((entity as Resident).trade))
		trades = seen
	var holder := ""
	var holdings: Variant = world_state.get("holdings", {})
	var held: Variant = holdings.get(id) if holdings is Dictionary else null
	if held is Array and not (held as Array).is_empty() and world_map_panel != null:
		holder = str(world_map_panel.faction_look(str(held[0]))["name"])
	var town_name := world_map_panel.place_words(id) if world_map_panel != null else id
	if town_name == id or town_name == id.get_slice("/", 1) or town_name.is_empty():
		town_name = id.get_slice("/", 1).replace("_", " ").capitalize()  # No place of that key known: its key as a name.
	town_panel.show_town(id, town_name, str(town_stages.get(id, "")), holder, town_states[id], trades,
		str(town_notes.get(zone, "")), Season.name_at(World.steps), Townsfolk.day_of(World.steps), town_sheets.get(id, {}))


## C: her card page shown or hidden (618, ui's side), fed world_state's
## "capabilities" and "focus" (companions' 576, 577) and her name from her
## body here when it is.
func toggle_card() -> void:
	if card_page == null:
		return
	if card_page.visible:
		card_page.visible = false
		return
	_refresh_card()
	card_page.visible = true


func _refresh_card() -> void:
	if card_page == null or not card_page.is_node_ready():
		return
	var pet := _own_companion()
	card_page.show_state(world_state, String(pet.name) if pet != null else "",
		pet.bond_step if pet != null else "", pet.bond_why if pet != null else "")  # Her bond (555) is on her node.


## O: the options shown or hidden; hiding writes what changed. Closed
## from the main menu's Options, the menu comes back (Jeff, 2026-10-22:
## "main menu doesn't stays open when you select options so that's
## blocking the options screen": the menu steps aside while they show).
func toggle_options() -> void:
	if options_panel == null:
		return
	var closing := options_panel.visible
	options_panel.toggle()
	if closing and _options_from_menu:
		_options_from_menu = false
		if main_menu != null:
			main_menu.show_front(true)


## The main menu's Options: the menu steps aside, the options on top; Esc
## or O brings the menu back.
func _menu_options() -> void:
	if options_panel == null:
		return
	_options_from_menu = true
	if main_menu != null:
		main_menu.show_front(false)  # The backdrop stays: the world and its names never show through the options' dim.
	if not options_panel.visible:
		options_panel.toggle()


## I: the player's pack shown or hidden (with its sack sound); with a
## chest or a companion's pack open, that closed.
func toggle_pack() -> void:
	if pack_panel == null:
		return
	if pack_panel.other != null:
		close_other()
		return
	pack_panel.shown = not pack_panel.shown
	if pack_panel.shown and _local_player() != null:
		_sound("sfx.pack_open", _local_player())


## A right click on a chest, or on the player's own companion: open it
## within reach (World.reaches); from afar, walk to the nearest free cell
## beside it, and open on arrival (_update_pack). On the one already open,
## it closes.
func _open_pack(player: Player, target: GridEntity) -> void:
	if pack_panel != null and pack_panel.other == target:
		close_other()
		return
	if World.reaches(player, target):
		open_other(target)
		return
	var beside := _beside(target.tile, player.tile)
	if beside == NONE:
		return
	_move_click(player, beside)
	_pack_wanted = target


## A left click on a chest: walk to the nearest free cell beside it.
func _walk_to_chest(player: Player, chest: GridEntity) -> void:
	if World.can_melee(player.tile, chest.tile):
		return
	var beside := _beside(chest.tile, player.tile)
	if beside != NONE:
		_move_click(player, beside)


## The free floor cell next to [param at], reachable from it for a hand
## (World.can_melee), nearest [param from]; NONE if there is none.
func _beside(at: Vector2i, from: Vector2i) -> Vector2i:
	var best := NONE
	for direction in World.DIRECTIONS:
		var cell := at + direction
		var mine := cell == from
		if (mine or World.is_free(cell)) and World.can_melee(cell, at) \
				and (best == NONE or World.distance(from, cell) < World.distance(from, best)):
			best = cell
	return best


## [param player] searches the cache [param chest] (decision 599; Jeff:
## "old farmstead in the wilds - abandoned, tools and bandages found
## inside"; Chest.cache, its loot table): the first time, what the table
## gives, rolled by the player and the cache (the same if tried again), is
## minted worn (half its condition: nothing fine), "cached" from the
## chest's label, and put in their hands and pack, the rest on the ground
## at their feet; the cache goes on their record (PlayerRecord.caches), so
## it is once per player for life. They are told what they found, or
## "Nothing more here." Companions don't search. True if anything was found.
func search(player: Player, chest: Chest) -> bool:
	if not Net.is_authority() or player == null or not is_instance_valid(chest) or chest.cache.is_empty() \
			or not World.reaches(player, chest):
		return false
	var record: PlayerRecord = _records.get(str(player.player_id))
	if record == null:
		return false
	var tell := func(text: String) -> void:
		if player.owner_peer != 0:
			Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": text})
	if chest.cache in record.caches:
		tell.call("Nothing more here.")
		return false
	record.caches.append(chest.cache)
	var place := chest.cache_place if not chest.cache_place.is_empty() else World._label_of(chest)
	var found := Items.roll_loot(chest.cache, "%s:%s" % [record.player_id, chest.cache], 64)
	var counts := {}
	for id in found:
		var uid := World.items.mint(id, "cached", place, chest.zone, chest.tile)
		if Items.condition_max(id) > 1:
			World.items.set_condition(uid, maxi(1, Items.condition_max(id) / 2))
		var slot := World.room_for(player, uid)  # Onto a stack of its kind first (decision 619).
		if slot < 0 or not World.put_item(player, player, slot, uid):
			World.put_on_ground(uid, player.tile)
		counts[id] = int(counts.get(id, 0)) + 1
	var words := PackedStringArray()
	for id: String in counts:
		words.append(str(Items.def(id).get("name", id)) + (" (%d)" % counts[id] if counts[id] > 1 else ""))
	print("[cache] %s searched %s at %s: %s" % [player.name, chest.cache, place, ", ".join(words)])
	tell.call("You find in %s: %s." % [place, ", ".join(words)] if not words.is_empty() else "Nothing here.")
	return not found.is_empty()


## Opens [param target]'s row (a chest, or a companion's pack), with its sound.
func open_other(target: GridEntity) -> void:
	_pack_wanted = null
	if target is Chest and not (target as Chest).cache.is_empty():
		# A cache is searched, not opened (decision 599): the server hands over the find.
		if _local_player() != null:
			World.command(_local_player(), "search", {"target": str(target.get_path())})
		return
	if pack_panel != null:
		if pack_panel.other != target:
			_sound(SoundKit.opening(target), target)
		pack_panel.open(target)
	if shop_panel != null and target is Chest and (target as Chest).shop and shop_panel.shop != target:
		# The "shop" read stays (the gold caption, economy_test) until economy retires
		# the message; its goods box is not shown (560, ui's side: the barter window is).
		shop_panel.open(target)
		var player := _local_player()
		if player != null:
			World.command(player, "shop", {"shop": str(target.get_path())})
	if barter_panel != null and target is Chest and (target as Chest).shop and barter_panel.with != target:
		# 560, ui's side: the counter opens the barter window, fed by economy's "barter".
		barter_panel.open(target, "")
		var player := _local_player()
		if player != null:
			World.command(player, "barter", {"shop": str(target.get_path())})
	if counter_panel != null and target != null and not World.counter_kind(target).is_empty():
		var player := _local_player()
		if player != null:
			World.command(player, "counter", {"counter": str(target.get_path()), "do": "look"})


func close_other() -> void:
	_pack_wanted = null
	if pack_panel != null:
		pack_panel.open(null)
	if shop_panel != null:
		shop_panel.open(null)
	if barter_panel != null:
		barter_panel.close()


## A line in the talk panel: someone else's chat pings, a party line
## chimes; what is said around you (speech) has its own voice.
func _line_sound(speaker: String, is_chat: bool, party: bool) -> void:
	var me := _local_player()
	if me != null and speaker == String(me.name):
		return
	if party:
		ui_sounds.play("ui.notify")
	elif is_chat:
		ui_sounds.play("ui.chat_ping")


## The shop panel's Buy on [param uid] at [param shop]: asked of the server,
## which answers with the shop again (and the gold).
func _buy(shop: GridEntity, uid: int) -> void:
	var player := _local_player()
	if player != null and is_instance_valid(shop):
		World.command(player, "shop", {"do": "buy", "shop": str(shop.get_path()), "uid": uid})


## Each frame: the panel follows the local player; a chest or companion
## walked to opens, and an open one closes once out of reach.
func _update_pack() -> void:
	if pack_panel == null:
		return
	var player := _local_player()
	pack_panel.player = player
	if player == null:
		close_other()
		return
	if is_instance_valid(_pack_wanted) and World.reaches(player, _pack_wanted):
		open_other(_pack_wanted)
	var other := pack_panel.other
	if other != null and (not is_instance_valid(other) or not World.reaches(player, other)):
		close_other()


## Sound slot [param slot] from [param entity], in the 3D view (the 2D one
## has none).
func _sound(slot: String, entity: GridEntity) -> void:
	sounds.append("%s %s" % [slot, entity.name])
	if _client3d != null and is_instance_valid(entity) and DisplayServer.get_name() != "headless":
		_client3d.play_at(slot, entity)


## A right click on [param slot] of the local player's pack: use what is
## there (World.try_use, on the server).
func use_slot(slot: int) -> void:
	var me := _local_player()
	if me != null:
		World.command(me, "use", {"slot": slot})


## F, G or T ([param what]: pick_up, drop, throw): a command for the local
## player, with the cell under the cursor; the server decides (_item_command).
func item_key(what: String) -> void:
	var me := _local_player()
	if me == null:
		return
	var args := {}
	if what != "drop":
		var cell := _mouse_tile()
		if cell != NONE:
			args["cell"] = [cell.x, cell.y]
	World.command(me, what, args)


## Server: [param player]'s F, G or T. Picking up takes from the cell asked
## for if it is in reach, else their own, else one beside with something on
## it; putting down and throwing use the right hand, else the left (putting
## down: else the last thing in the pack).
func _item_command(player: Player, what: String, args: Dictionary) -> void:
	var cell: Variant = Snapshot.vector(args.get("cell"))
	var held := Player.RIGHT_HAND if not player.slots[Player.RIGHT_HAND].is_empty() else Player.LEFT_HAND
	match what:
		"pick_up":
			var cells: Array[Vector2i] = []
			if cell != null:
				cells.append(cell)
			cells.append(player.tile)
			for direction: Vector2i in World.DIRECTIONS:
				cells.append(player.tile + direction)
			for each in cells:
				# Its gold first (601 amended: into the record's, no slot), then a thing.
				var gold := World.try_pick_up_gold(player, each)
				if gold > 0:
					Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": "Picked up %d gold." % gold})
					return
				if not World.ground_uids(each).is_empty() and World.try_pick_up(player, each):
					return
			for each in cells:
				if Array(World.ground_uids(each)).all(func(uid: int) -> bool: return World.axe_bound(uid)) and not World.ground_uids(each).is_empty():
					party_log.add(BOUND_AXE_WORDS)  # 603 amended: his, till the pact is won.
					return
		"drop":
			var slot := held
			if player.slots[slot].is_empty():
				slot = -1
				for i in Items.PACK:
					if not player.slots[i].is_empty():
						slot = i
			if slot >= 0:
				World.try_drop(player, slot, null, int(args.get("count", 0)))  # A count of a stack (decision 619).
		"throw":
			if cell != null:
				World.try_throw(player, held, cell)


## Server: what lay on the ground in a snapshot's zone section, back where
## it was, each thing its saved instance where the book still has it.
func _restore_ground(ground: Array) -> void:
	for pile: Dictionary in ground:
		var ids: Array = pile["ids"]
		var uids: Array = pile.get("items", [])
		World.drop_gold(World.zone.name, pile["cell"], int(pile.get("gold", 0)))  # 601 amended.
		for i in ids.size():
			var id := str(ids[i])
			if id == World.OLD_PURSE:
				# An old coin purse on the ground: its gold, as a count (601 amended).
				var old := int(uids[i]) if i < uids.size() and (uids[i] is float or uids[i] is int) else 0
				World.drop_gold(World.zone.name, pile["cell"], World.purse_gold(old) if World.items.id_of(old) == id else World.OLD_PURSE_GOLD)
				if World.items.has(old):
					World.items.end(old, "migrated", "into gold (601 amended)", World.zone.name, pile["cell"])
				continue
			if not Items.exists(id):
				continue
			var uid := int(uids[i]) if i < uids.size() and (uids[i] is float or uids[i] is int) else 0
			var at := World.items.at_of(uid)
			if World.items.id_of(uid) != id or not at in ["", "%s@%d,%d" % [World.zone.name, pile["cell"].x, pile["cell"].y]]:
				uid = World.items.mint(id, "migrated", "the ground", World.zone.name, pile["cell"])
			World.put_on_ground(uid, pile["cell"])


## What lies on [param zone]'s ground, for a save: one entry a cell, {cell,
## items (uids), ids, gold (601 amended)}. World must be in [param zone].
static func ground_entries(zone: Zone) -> Array[Dictionary]:
	var ground: Array[Dictionary] = []
	var cells: Array[Vector2i] = zone.ground.keys()
	for cell: Vector2i in zone.ground_gold:
		if not cell in cells:
			cells.append(cell)
	for cell in cells:
		var entry := {"cell": [cell.x, cell.y], "items": Array(zone.ground.get(cell, PackedInt32Array())), "ids": Array(World.ground_at(cell))}
		if int(zone.ground_gold.get(cell, 0)) > 0:
			entry["gold"] = int(zone.ground_gold[cell])
		ground.append(entry)
	return ground


## Server: World's ground changed on [param cell] (of the zone World is
## in): its GroundPile spawned,
## changed or freed (the spawner does the same on the clients that see it).
func _on_ground_changed(_zone_name: String, cell: Vector2i, thrown_from: Vector2i) -> void:
	var ids := World.ground_at(cell)
	var gold := World.ground_gold(cell)
	var pile: GroundPile = World.zone.piles.get(cell)
	if ids.is_empty() and gold <= 0:
		if is_instance_valid(pile):
			World.zone.piles.erase(cell)
			Net.interest.remove(pile)
			# Out of the tree now, so a new pile on the cell can take its name.
			pile.get_parent().remove_child(pile)
			pile.queue_free()
		return
	if is_instance_valid(pile):
		if thrown_from != World.NO_CELL:
			pile.thrown_from = thrown_from
			pile.thrown_tick = World.tick
		pile.ids = ids
		pile.gold = gold
		return
	var spec := {"script": PILE, "name": GroundPile.name_for(cell), "tile": [cell.x, cell.y], "zone": World.zone.name,
		"ids": Array(ids), "gold": gold}
	if thrown_from != World.NO_CELL:
		spec["thrown_from"] = [thrown_from.x, thrown_from.y]
		spec["thrown_tick"] = World.tick
	Net.interest.add(spawner.spawn(spec))


## The pack panel's drop: a command, so the server decides (World.try_transfer);
## [param count] units of a stack (a shift-drag's one), 0 for the whole slot (619).
func _transfer(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int, count := 0) -> void:
	var player := _local_player()
	if player == null:
		return
	var args := {"from": str(from.get_path()), "from_slot": from_slot, "to": str(to.get_path()), "to_slot": to_slot}
	if count > 0:
		args["count"] = count
	World.command(player, "transfer", args)


## Server: a player's or a companion's pack changed: their record has it at
## once, so it survives a death, a trip and a restart.
func _on_slots_changed(entity: GridEntity) -> void:
	if entity is Player:
		var record: PlayerRecord = _records.get(_peer_ids.get(entity.owner_peer, ""))
		if record != null and _players.get(entity.owner_peer) == entity:
			record.slots = entity.slots.duplicate()
			record.slot_items = World.slot_uids(entity)
	elif entity is Companion:
		var keeper: PlayerRecord = _records.get((entity as Companion).keeper_id)
		if keeper != null and _companions.get(keeper.player_id) == entity:
			keeper.companion["slots"] = Array(entity.slots)
			keeper.companion["items"] = Array(World.slot_uids(entity))


## H: the controls list shown or hidden, and remembered.
func toggle_hints() -> void:
	Net.hints = not Net.hints
	if hint_panel != null:
		hint_panel.visible = Net.hints
	Net.save_view_settings()


## Which way the level's north points on screen (unit, y down), in
## whichever view is showing.
## The minimap's door marks, made again every DOOR_MARKS_FRAMES frames.
const DOOR_MARKS_FRAMES := 30
var _door_marks: Array = []
var _door_marks_at := -1


## The minimap's marks, from what is replicated: you (pointing where the
## camera looks), your companion, the other players in their tints, and the
## doors. No monsters.
func _minimap_marks() -> Array:
	var out: Array = []
	var me := _local_player()
	for entity in World.sought():  # The players and companions: no copy of every entity.
		if not is_instance_valid(entity) or not entity.spawned:
			continue
		if entity is Player:
			if entity == me:
				out.append({"cell": Vector2(entity.tile), "kind": "you", "facing": Vector2(entity.facing)})  # The body's own facing (535).
			else:
				out.append({"cell": Vector2(entity.tile), "kind": "player", "colour": entity.tint})
		elif entity is Companion and entity.keeper_peer == Net.local_id:
			out.append({"cell": Vector2(entity.tile), "kind": "companion",
				"colour": me.tint.lightened(0.35) if me != null else Color(0.8, 0.9, 1.0)})
	if _door_marks_at < 0 or Engine.get_process_frames() - _door_marks_at >= DOOR_MARKS_FRAMES:
		# The doors stay where they are: their marks made again now and then
		# (one opened up or broken shows a moment late), not every frame.
		_door_marks_at = Engine.get_process_frames()
		_door_marks = []
		for door: Door in World.get_doors():
			if is_instance_valid(door):
				_door_marks.append({"cell": Vector2(door.key.x, door.key.y), "kind": "door"})
	out.append_array(_door_marks)
	return out


## The grid direction the camera looks (screen up), for the map's pointer.
func view_forward() -> Vector2:
	return Vector2(World.north).rotated(screen_north().angle_to(Vector2.UP))


func screen_north() -> Vector2:
	var north := Vector2(World.north)
	if _client3d != null:
		return _client3d.screen_direction(north)
	return (Iso.project(north) - Iso.project(Vector2.ZERO)).normalized()


func _debug_text() -> String:
	var lines: Array[String] = ["%s   tick %d   peer id: %d" % [
		Net.Mode.keys()[Net.mode].to_lower() if Net.online else "offline", _hud_tick, Net.local_id]]
	var player := _local_player()
	if player != null:
		lines.append("stamina: %d / %d" % [player.stamina, player.max_stamina])
		if player.raised == "draw":
			lines.append("draw: %d%%" % roundi(World.draw_of(player) * 100.0))
	if _client3d != null:
		lines.append("yaw: %.1f deg   pitch: %.1f deg   zoom: %.2fx" % [_client3d.yaw, _client3d.pitch, _client3d.zoom])
	else:
		lines.append("azimuth: %.1f deg" % Iso.azimuth)
	lines.append("camera facing: %s" % HudCompass.facing(screen_north()))
	lines.append("controls: %s" % Net.controls)
	if Net.mode == Net.Mode.CLIENT:
		lines.append("rtt: %d ms" % roundi(Net.rtt_ms()))
		lines.append("mispredicts: %d / min (%d total)" % [
			Net.mispredicts_per_minute(), Net.mispredicts_total])
		lines.append("snaps: %d / min (%d total)" % [Net.snaps_per_minute(), Net.snaps_total])
		lines.append("worst correction: %.2f tiles this minute (%.2f ever)" % [
			Net.stats.worst_correction(), Net.stats.worst_correction_ever])
		lines.append("display delay: %d ms" % roundi(World.display_delay_ticks * 1000.0 / World.TICK_RATE))
		lines.append("build: v%s %s%s" % [Net.version, Net.protocol(),
			", server v%s" % Net.server_version if Net.server_version not in ["", Net.version] else ""])
	else:
		lines.append("rtt: n/a (this peer is the authority)")
		lines.append("mispredicts: n/a (nothing is predicted here)")
	return "\n".join(lines)


func _log_player_move(entity: GridEntity, from: Vector2i, to: Vector2i) -> void:
	if entity is Player:
		print("[net] %s (peer %d) moved %s -> %s occupancy_consistent=%s" % [
			entity.name, entity.owner_peer, from, to, World.is_occupancy_consistent()])


func _on_join_rejected(reason: String, server_version: String) -> void:
	if reason == "already connected" and _already_tries < ALREADY_TRIES:
		# An older server (before decision 721) refusing while it still
		# holds this player's dropped link: tried again till it lets go.
		_already_tries += 1
		_rejected = true
		_connect_status("the server still holds your last connection; trying again")
		get_tree().create_timer(ALREADY_RETRY_SECONDS).timeout.connect(_retry_connect)
		return
	_already_tries = 0
	_rejected = true
	if reason == "client out of date":
		# An exported game updates itself and starts again (decision 241).
		var dir := SelfUpdate.game_dir()
		var why_not := SelfUpdate.refusal(reason, server_version, dir, int(Time.get_unix_time_from_system()))
		if why_not.is_empty():
			# Fetched here, shown as it goes (decision 430), then installed by
			# update.ps1 -Stage once the game has quit.
			_download_update(server_version, dir)
			return
		print("[update] not updating itself: %s" % why_not)
		_update_failed(server_version)
	elif reason == "server out of date":
		_connect_status("the server is out of date: it runs v%s, this is v%s. It will be updated soon; try again later." % [
			server_version, Net.version], true)
	else:
		_connect_status(reason, true)


## The server's v[param version] downloaded beside the game in
## [param dir] with the connect screen showing how far (set_progress;
## its Cancel stops it), then update.ps1 -Stage started and the game quit.
func _download_update(version: String, dir: String) -> void:
	print("[update] the server runs v%s: fetching it for this v%s" % [version, Net.claimed_version()])
	var download := SelfUpdate.Download.new()
	add_child(download)
	var screen := _connect_screen()
	_connect_status("fetching the server's v%s" % version)
	download.progress.connect(func(fraction: float, text: String) -> void:
		if screen.has_method("set_progress"):
			screen.set_progress(fraction, text))
	if screen.has_signal("cancel_pressed"):
		screen.connect("cancel_pressed", download.cancel, CONNECT_ONE_SHOT)
	var result: Array = []  # [ok, why], once finished (begin can fail at once).
	download.finished.connect(func(ok: bool, why: String) -> void: result.assign([ok, why]))
	download.begin(version, dir)
	while result.is_empty():
		await get_tree().process_frame
	if screen.has_signal("cancel_pressed") and screen.is_connected("cancel_pressed", download.cancel):
		screen.disconnect("cancel_pressed", download.cancel)
	if screen.has_method("set_progress"):
		screen.set_progress(-1.0, "")
	download.queue_free()
	if result[0] and SelfUpdate.start(dir, download.stage_path):
		print("[update] v%s is unpacked: update.ps1 installs it and starts the game again" % version)
		_connect_status("updating to the server's v%s: the game closes and starts again" % version)
		# Drawn before the window goes (update.ps1 is already running).
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()
		return
	print("[update] not updating itself: %s" % (result[1] if not result[1].is_empty() else "update.ps1 could not be started"))
	_update_failed(version, result[1])


func _update_failed(server_version: String, why := "") -> void:
	_connect_status("this game is out of date: the server runs v%s, this is v%s%s. Run launch.bat to update." % [
		server_version, Net.version, " (%s)" % why if not why.is_empty() else ""], true)


func _on_server_disconnected() -> void:
	if _rejected:
		return  # The reason is already on screen.
	if _had_player:
		_reconnect()
	else:
		_connect_status("the server did not let you in: check the token", true)
		print("[net] authentication failed: disconnected before a player was spawned")


## Client: the server it played on went away (a restart, a crash): its
## zone's entities go, and it connects again every RECONNECT_EVERY seconds
## for RECONNECT_FOR; once it is back in, the server sends the zone as on a
## first join (decision 240).
func _reconnect() -> void:
	if _reconnecting:
		return
	_reconnecting = true
	print("[net] lost the server; reconnecting every %d s for %d s" % [RECONNECT_EVERY, RECONNECT_FOR])
	_drop_zone_entities()
	var started := Time.get_ticks_msec()
	var tries := 0
	_connect_status("the server is restarting; trying again")
	while Time.get_ticks_msec() - started < RECONNECT_FOR * 1000.0:
		await get_tree().create_timer(RECONNECT_EVERY).timeout
		tries += 1
		_connect_status("the server is restarting; trying again (%d)" % tries)
		if Net.reconnect() and await _connection_settled():
			print("[net] reconnected (try %d)" % tries)
			_reconnecting = false
			return
	print("[net] gave up reconnecting after %d tries" % tries)
	_connect_status("the server is gone", true)
	_reconnecting = false


## Whether the connection Net.reconnect began got through (false when it
## failed or is still trying after 10 s).
func _connection_settled() -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	var link := multiplayer.multiplayer_peer
	while link.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING \
			and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	return link.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Client: the zone's entities go, as on a change of zone, with the map left
## as it is; the server sends them again when the player is back.
func _drop_zone_entities() -> void:
	if entities != null:
		entities.free()
	if spawner != null:
		spawner.free()
	World.mirror_reset()
	_zone_nodes(map_name)
	World.mirror_terrain(_terrain)
	_repaint()


# --- Restart (decision 240) ------------------------------------------------------

## Server: the console's restart and stop. In [param seconds] the world is
## saved, the players let go and the server exits: restart with
## RESTART_EXIT_CODE, for systemd to start it again; stop with 0, which
## systemd leaves down, for deploy.sh to install the new build and start it
## (the running server reads its .pck as it goes, so it must not be replaced
## under it). Clients reconnect by themselves either way. Players hear it from
## "Server" in the party chat now and at RESTART_WARNINGS seconds left: three
## lines at most.
func _restart_command(words: PackedStringArray) -> String:
	if words.size() >= 2 and words[1] == "cancel":
		if _restart_at < 0:
			return "no restart is due"
		_restart_at = -1
		_server_says("The restart is off.")
		return "restart cancelled"
	var seconds := 60
	var why_from := 1
	if words.size() >= 2 and words[1].is_valid_int():
		seconds = maxi(0, words[1].to_int())
		why_from = 2
	_restart_why = " ".join(words.slice(why_from))
	_restart_at = Time.get_ticks_msec() + seconds * 1000
	_restart_exit = RESTART_EXIT_CODE if words[0].to_lower() == "restart" else 0
	_restart_told.clear()
	for left in RESTART_WARNINGS:
		if left >= seconds:
			_restart_told.append(left)
	var because := " (%s)" % _restart_why if not _restart_why.is_empty() else ""
	if seconds > 0:
		_server_says("Restarting in %d s%s; you'll be reconnected." % [seconds, because])
	return "restarting in %d s%s, %d connected, then exiting %d%s (restart cancel to call it off)" % [
		seconds, because, _players.size(), _restart_exit,
		"" if _restart_exit != 0 else ": down until started"]


## Server: tells the players what is left of a restart, and restarts when
## it is time. Every frame.
func _count_down_restart() -> void:
	if _restart_at < 0:
		return
	var left := (_restart_at - Time.get_ticks_msec()) / 1000.0
	for warning in RESTART_WARNINGS:
		if left <= warning and warning not in _restart_told:
			_restart_told.append(warning)
			_server_says("Restarting in %d s." % warning)
	if left > 0.0:
		return
	_restart_at = -1
	print("[admin] restarting%s: saving, letting %d players go, exiting %d" % [
		" (%s)" % _restart_why if not _restart_why.is_empty() else "", _players.size(), _restart_exit])
	_save_state()
	# Each client is let go, so it hears at once rather than when it times
	# out, and reconnects; the disconnects go out before the server quits,
	# and nobody new comes in meanwhile (a reconnect would find it going).
	multiplayer.multiplayer_peer.refuse_new_connections = true
	for peer in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer)
	await get_tree().create_timer(0.5).timeout
	_release_zones()
	get_tree().quit(_restart_exit)


## Server: the console's raids (decision 328): on, off, the groups out, or
## one sent at once from a camp at a town.
## The console's "regenerate now <level>" (541 amended, Jeff meets the wider
## barrow at the deploy): the level laid again at once, due or not, the
## switch on or off, so long as nobody is in it (release runs it after a
## deploy that changes a template, players checked first); never in a
## test run on the shared overlay. Says what it did.
func _regenerate_now(level_name: String) -> String:
	if not Net.is_authority():
		return "regenerate now: the server's alone"
	if not Regen.marked(level_name):
		return "regenerate now: %s is no shifting level (%s)" % [level_name, ", ".join(Regen.marked_levels())]
	if not Regen.overlay_safe():
		return "regenerate now: refused in a test run on the shared overlay"
	var zone: Zone = World.zones.get(level_name)
	if zone != null and World.zone_awake(zone):
		return "regenerate now: %s is awake, someone is in it; again when it sleeps" % level_name
	if _regenerate(level_name, Regen.config_of(level_name)):
		return "regenerate now: %s laid again, generation %d" % [level_name, generation_of(level_name)]
	return "regenerate now: %s could not be laid (%d tries, or its overlay copy is edited)" % [level_name, Regen.TRIES]


## The console's "regenerate [on|off|now <level>]" (decision 542; 541 amended): whether the shifting
## levels are laid again on this server (Net.regenerate; --regenerate sets
## it from the start), and which levels are marked, each with its generation.
func _regenerate_command(words: PackedStringArray) -> String:
	if words.size() >= 3 and words[1] == "now":
		return _regenerate_now(words[2])
	if words.size() >= 2 and words[1] in ["on", "off"]:
		Net.regenerate = words[1] == "on"
		return "regenerate %s: %s" % [words[1], "the shifting levels are laid again when due" if Net.regenerate else "the shifting levels stay as they are"]
	var lines: Array[String] = ["regenerate %s" % ("on" if Net.regenerate else "off")]
	for level_name in Regen.marked_levels():
		lines.append("%s: generation %d, every %d days" % [level_name, generation_of(level_name), int(Regen.config_of(level_name).get("every_days", 0))])
	return "\n".join(lines)


func _raids_command(words: PackedStringArray) -> String:
	var groups := World.raid_groups
	if groups == null:
		return "no raid groups here"
	if words.size() >= 2 and words[1] in ["on", "off"]:
		groups.set_on(words[1] == "on")
		return "raids %s: %s" % [words[1], "camps send groups at their towns" if groups.on else "nothing is sent and nothing moves"]
	if words.size() >= 4 and words[1] == "send":
		var id := groups.send(words[2], words[3])
		return "sent %s" % id if id != "" else "no camp %s, no town %s, or no way between" % [words[2], words[3]]
	var lines: Array[String] = ["raids %s; %d camps, %d groups out" % ["on" if groups.on else "off", groups.camps().size(), groups.groups.size()]]
	for group: Dictionary in groups.groups.values():
		lines.append("%s %s, %s at %s %s, strength %.1f, carries %s" % [group["id"], group["state"], group["faction"],
			group["area"], group["cell"], group["strength"], group["carries"]])
	return "\n".join(lines)


## Server: a line to every player, from "Server", in the party chat.
func _server_says(text: String) -> void:
	print("[admin] told everyone: %s" % text)
	Net.broadcast("party", {"from": "Server", "text": text})


# --- Server console -----------------------------------------------------------
# Lines from stdin (a dedicated server, or --console) and from a localhost
# TCP port (--admin-port), one command per line. See admin_command().

func _start_console() -> void:
	if Net.is_authority():
		print("[admin] %d admins configured" % Net.admins.size())  # 672: a count, never who.
	if Net.mode == Net.Mode.SERVER or Net.console:
		_stdin_thread = Thread.new()
		_stdin_thread.start(_read_stdin)
	if Net.admin_port > 0:
		_admin = TCPServer.new()
		var error := _admin.listen(Net.admin_port, "127.0.0.1")
		if error == OK:
			print("[admin] console on 127.0.0.1:%d" % Net.admin_port)
		else:
			push_warning("[admin] cannot listen on 127.0.0.1:%d (%s)" % [Net.admin_port, error_string(error)])
			_admin = null


## Runs on its own thread: stdin reads block. Lines go to _stdin_lines for
## the main thread. Ends when stdin is closed or empty (a service's is).
func _read_stdin() -> void:
	var empties := 0
	while not _stdin_stop:
		# One read may hold several lines (piped input), or nothing (EOF).
		var chunk: String = OS.read_string_from_stdin()
		if chunk.strip_edges().is_empty():
			empties += 1
			if empties >= 20:
				return
			OS.delay_msec(100)
			continue
		empties = 0
		_stdin_mutex.lock()
		for line in chunk.split("\n", false):
			if not line.strip_edges().is_empty():
				_stdin_lines.append(line.strip_edges())
		_stdin_mutex.unlock()


func _poll_console() -> void:
	if _stdin_thread != null:
		_stdin_mutex.lock()
		var lines := _stdin_lines.duplicate()
		_stdin_lines.clear()
		_stdin_mutex.unlock()
		for line in lines:
			print(admin_command(line))
	if _admin == null:
		return
	while _admin.is_connection_available():
		_admin_clients.append(_admin.take_connection())
	for client in _admin_clients.duplicate():
		client.poll()
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_admin_clients.erase(client)
		elif client.get_available_bytes() > 0:
			var line: String = client.get_utf8_string(client.get_available_bytes()).strip_edges()
			if not line.is_empty():
				client.put_data((admin_command(line) + "\n").to_utf8_buffer())
			client.disconnect_from_host()
			_admin_clients.erase(client)


## "companion facts <player>": what has become true of that player's
## companion (decision 294), by id; "companion forget <player> <id>": one
## of them gone (her live self too, if she is in the world).
func _companion_command(words: PackedStringArray) -> String:
	if words.size() < 3 or words[1] not in ["facts", "forget"]:
		return "companion facts <player> | companion forget <player> <id>"
	var record: PlayerRecord = null
	for each: PlayerRecord in _records.values():
		if each.name.to_lower() == words[2].to_lower():
			record = each
	if record == null or record.companion.is_empty():
		return "no companion for %s" % words[2]
	var pet: Companion = _companions.get(record.player_id)
	var live := is_instance_valid(pet) and pet.spawned
	var grown := pet.grown if live else CompanionFacts.from_record(record.companion.get("facts", []), record.companion.get("beliefs", []))
	if words[1] == "forget":
		if words.size() < 4 or not grown.forget(words[3]):
			return "%s has no fact %s" % [record.companion.get("name", "?"), words[3] if words.size() > 3 else "?"]
		if live:
			pet.facts_changed.emit()
		else:
			record.companion["facts"] = grown.facts
			record.companion["beliefs"] = grown.beliefs
		return "%s: %s forgotten" % [record.companion.get("name", "?"), words[3]]
	var lines: Array[String] = []
	for entry in grown.facts:
		lines.append("%s (%s) %s" % [entry["id"], entry["from"], entry["text"]])
	for entry in grown.beliefs:
		lines.append("%s (believes) %s" % [entry["id"], entry["text"]])
	return "%s: %d facts, %d beliefs\n%s" % [record.companion.get("name", "?"), grown.facts.size(), grown.beliefs.size(), "\n".join(lines)]


# --- The admin panel (672) ----------------------------------------------------------

## Whether F10 opens the admin panel: the server said so, or this is the host
## with a player of its own.
func admin_allowed() -> bool:
	return is_admin or Net.is_authority() and _local_player() != null


## Server: whether [param peer] (player id [param id]) may run panel commands:
## the host's own player, or an id on Net.admins.
static func admin_peer_allowed(peer: int, id: String) -> bool:
	return peer == Net.local_id or not id.is_empty() and id in Net.admins


## F10: the panel, told the zone and its quest givers for its buttons.
func open_admin() -> void:
	if admin_panel == null:
		return
	if not admin_panel.visible:
		admin_panel.zone = zone_name_here()
		var names: Array[String] = []
		for each: GridEntity in World.townsfolk():
			var resident := each as Resident
			if resident != null and resident.player_id.is_empty() and not resident.person.is_empty() and resident.person not in names:
				names.append(resident.person)
		names.sort()
		admin_panel.givers = names
	admin_panel.toggle()


## The panel's line to the server, as the "admin" command.
func send_admin(line: String) -> void:
	var player := _local_player()
	if player != null:
		World.command(player, "admin", {"line": line})


## Server: [param line] from [param player]'s panel: run as the console runs
## it (admin_command, the player the caller) and answered with "admin_reply";
## refused with "not allowed" for anyone else, counted in the journal.
func _admin_from(player: Player, line: String) -> void:
	var peer := player.owner_peer
	var id: String = _peer_ids.get(peer, Net.player_id if peer == Net.local_id else "")
	var text := ""
	if not admin_peer_allowed(peer, id):
		_admin_refused += 1
		print("[admin] refused %d" % _admin_refused)
		text = "not allowed"
	else:
		var words := line.strip_edges().split(" ", false)
		print("[admin] %s ran" % (words[0].to_lower() if not words.is_empty() else "nothing"))
		text = admin_command(line, player)
	Net.message_to(peer, "admin_reply", {"line": line, "text": text})


## The player called [param wanted] (as "players" lists them) and their id,
## online or off: {player (null when away), id}; {} for none or two.
func _admin_player(wanted: String) -> Dictionary:
	var found: Array[Dictionary] = []
	for id: String in _records:
		var record: PlayerRecord = _records[id]
		if record.name.to_lower() == wanted.to_lower():
			found.append({"player": _player_of_id(id), "id": id})
	for peer: int in _players:
		var player: Player = _players[peer]
		var id: String = _peer_ids.get(peer, Net.player_id if peer == Net.local_id else "")
		if is_instance_valid(player) and player.name.to_lower() == wanted.to_lower() and not found.any(func(each: Dictionary) -> bool: return each["id"] == id):
			found.append({"player": player, "id": id})
	return found[0] if found.size() == 1 else {}


## The spawned player whose id is [param id], or null.
func _player_of_id(id: String) -> Player:
	for peer: int in _players:
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.spawned and _peer_ids.get(peer, Net.player_id if peer == Net.local_id else "") == id:
			return player
	return null


## go <zone> [player]: the player (the panel's own, without one) and their
## companion to that zone's first start, as zone move does.
func _go_command(words: PackedStringArray, caller: Player) -> String:
	if words.size() < 2:
		return "go <zone> [player]"
	var who := ""
	if words.size() >= 3:
		who = " ".join(words.slice(2))
	elif caller != null:
		var record: PlayerRecord = _records.get(_peer_ids.get(caller.owner_peer, Net.player_id if caller.owner_peer == Net.local_id else ""))
		who = record.name if record != null else caller.name
	else:
		return "go <zone> <player>: from the console, name the player"
	return _zone_command(PackedStringArray(["zone", "move", who, words[1]]))


## quests reset [all|<giver>] [player] (672): the player's quests (the
## panel's own player, without one) undone, all of them or one quest
## giver's (a resident by name in the player's zone). Their trust, his
## memory of them and their companion's story stay.
func _quests_command(words: PackedStringArray, caller: Player) -> String:
	if words.size() < 2 or words[1] != "reset":
		return "quests reset [all|<giver>] [player]"
	var rest := words.slice(2)
	var target := {}
	if not rest.is_empty():
		var named := _admin_player(rest[rest.size() - 1])
		if not named.is_empty() and (rest.size() > 1 or caller == null):
			target = named
			rest = rest.slice(0, rest.size() - 1)
	if target.is_empty():
		if caller == null:
			return "quests reset [all|<giver>] <player>: from the console, name the player"
		target = {"player": caller, "id": _peer_ids.get(caller.owner_peer, Net.player_id if caller.owner_peer == Net.local_id else "")}
	var id: String = target["id"]
	var record: PlayerRecord = _records.get(id)
	if record == null:
		return "quests reset: no record for that player"
	var giver := " ".join(rest).strip_edges()
	if giver.is_empty() or giver.to_lower() == "all":
		return _quests_reset_all(record, id, target["player"])
	var player: Player = target["player"]
	var zone := player.zone if player != null else World.zone.name
	var workers := _givers_named(giver, zone)
	if workers.is_empty():
		return "quests reset: no quest giver %s in %s" % [giver, zone]
	if workers.size() > 1:
		return "quests reset: %d in %s are called %s; not reset" % [workers.size(), zone, giver]
	var cleared := _quests_reset_giver(record, id, workers[0])
	_resend_offers(id, player)
	return "%s: %s's quests reset (%s)" % [record.name, giver, ", ".join(cleared) if not cleared.is_empty() else "nothing was held"]


## The worker ids of the residents called [param giver] in [param zone].
func _givers_named(giver: String, zone: String) -> Array[String]:
	var out: Array[String] = []
	var was := World.zone
	if World.zones.has(zone):
		World.enter(World.zones[zone])
	for each: GridEntity in World.townsfolk():
		var resident := each as Resident
		if resident != null and resident.player_id.is_empty() and resident.person.to_lower() == giver.to_lower() \
				and not resident.worker_id.is_empty() and resident.worker_id not in out:
			out.append(resident.worker_id)
	World.enter(was)
	return out


## One giver's quests for player [param id] undone: his card's asks they
## took (and the record's mirror of them), his once-only care done for
## them (the medicine man's brew and walk, with the brew's tally), the
## priest's told secrets, the standing offer if it is his. What was cleared.
func _quests_reset_giver(record: PlayerRecord, id: String, worker_id: String) -> Array[String]:
	var cleared: Array[String] = []
	if World.production == null:
		return cleared
	var card := Townsfolk.card_of(World.production, worker_id)
	var dropped := card_without(card, id)
	if not dropped.is_empty():
		cleared.append("%d asks" % dropped.size())
		record.commissions = record.commissions.filter(func(entry: Variant) -> bool:
			return not (entry is Dictionary and str(entry.get("id", "")) in dropped))
	if card.get("care_done") is Dictionary and (card["care_done"] as Dictionary).has(id):
		(card["care_done"] as Dictionary).erase(id)
		cleared.append("care done")
		if worker_id.begins_with("medicine_man:"):
			care_clear(id, worker_id.trim_prefix("medicine_man:"), ["brew_herbs", "brew_antlers"])
	World.production.set_card(worker_id, card)
	if "priest" in World.production.worker(worker_id).get("trades", []) and _crypt_told.has(id):
		_crypt_told.erase(id)
		cleared.append("secrets told")
	if _standing.has(id) and str(_standing[id].get("worker", "")) == worker_id:
		_standing.erase(id)
		cleared.append("the standing offer")
	return cleared


## [param card]'s asks taken by player [param id] taken out of it; their ids.
static func card_without(card: Dictionary, id: String) -> Array[String]:
	var dropped: Array[String] = []
	var kept: Array = []
	for entry: Variant in card.get("asks", []):
		if entry is Dictionary and str(entry.get("by", "")) == id:
			dropped.append(str(entry.get("id", "")))
		else:
			kept.append(entry)
	if card.has("asks"):
		card["asks"] = kept
	return dropped


## Every quest of player [param id] undone (672 amended; Jeff: "allow
## everything to be reset, this is so that things can be tested properly"):
## each giver's (as _quests_reset_giver), the standing offer, the sought they
## freed (sent back to wait, a led one's body taken away), the draugr's paid
## deals, their companion held by raiders let go (she comes at the next
## join; companion_let_go), the barrow's (reset_barrow), the amulet
## (World.reset_totem), every draugr's asking and pact (Draugr.forget_player),
## the caches searched, the healer's care, and the townsfolk's hails,
## refusals and standing (quests_forget). Money, debts, plots, bonds and
## stories stay; the world's own (a niche opened) is "zone reset"'s.
func _quests_reset_all(record: PlayerRecord, id: String, player: Player) -> String:
	var cleared: Array[String] = []
	var givers := 0
	if World.production != null:
		for worker_id: String in World.production.worker_ids():
			if not _quests_reset_giver(record, id, worker_id).is_empty():
				givers += 1
	if givers > 0:
		cleared.append("%d quest givers" % givers)
	if not record.commissions.is_empty():
		record.commissions = []
	if _standing.erase(id):
		cleared.append("the standing offer")
	if _crypt_told.erase(id):
		cleared.append("secrets told")
	var sought := _sought_freed_by(id)
	for each: String in sought:
		_sought_back(each, id)
	if not sought.is_empty():
		cleared.append("%d sought" % sought.size())
	if "paid_deals" in record and not (record.get("paid_deals") as Dictionary).is_empty():
		record.set("paid_deals", {})
		cleared.append("the draugr's paid deals")
	cleared.append_array(companion_let_go(id))  # Let go; she comes at the next join (Jeff: "allow everything to be reset").
	cleared.append_array(reset_barrow(id))  # The draugr's blessing, the deal won, the totem's charges, the draft line.
	cleared.append_array(World.reset_totem(id))  # The amulet itself, wherever it is (items').
	var asked := 0
	var was := World.zone
	for each: Zone in World.zones.values():
		World.enter(each)
		for entity in World.get_entities():
			if entity is Draugr:
				asked += (entity as Draugr).forget_player(id).size()
	World.enter(was)
	if asked > 0:
		cleared.append("the draugr's asking and pact")
	if not record.caches.is_empty():
		record.caches = []
		cleared.append("caches searched")
	if not record.care.is_empty() or not record.care_given.is_empty():
		record.care = {}
		record.care_given = {}
		cleared.append("the healer's care")
	cleared.append_array(quests_forget(id, true))  # Hails, refusals to travel, standing: a stranger again.
	_resend_offers(id, player)
	return "%s: quests reset (%s)" % [record.name, ", ".join(cleared) if not cleared.is_empty() else "nothing was held"]


## The sought ids player [param id] is leading home.
func _sought_freed_by(id: String) -> Array[String]:
	var out: Array[String] = []
	if World.towns == null:
		return out
	for town: String in World.towns._towns:
		var held: Dictionary = World.towns._towns[town].get("sought", {})
		for each: String in held:
			if str(held[each].get("freed_by", "")) == id:
				out.append(each)
	return out


## Sought [param sought_id] back to waiting (Towns.sought_lost), as one taken
## on the way is (_resident_taken): its led body, in the leader's zone, taken
## away, not killed.
func _sought_back(sought_id: String, leader: String) -> void:
	World.towns.sought_lost(sought_id)
	var player := _player_of_id(leader)
	if player == null or not World.zones.has(player.zone):
		return
	var was := World.enter(World.zones[player.zone])
	for each: GridEntity in World.townsfolk():
		var resident := each as Resident
		if resident != null and resident.sought == sought_id and resident.escort_of == leader:
			_travelling = true
			World.despawn(resident)
			_travelling = false
	World.enter(was)


## Player [param id]'s offers sent again by every quest giver in their zone,
## if they are on.
func _resend_offers(id: String, player: Player) -> void:
	if player == null or not World.zones.has(player.zone):
		return
	var was := World.enter(World.zones[player.zone])
	for each: GridEntity in World.townsfolk():
		var resident := each as Resident
		if resident != null and resident.player_id.is_empty() and not resident.worker_id.is_empty() \
				and World.distance(resident.tile, player.tile) <= HEARING_RANGE:
			_send_offers(resident, id, player.owner_peer)
	World.enter(was)


## The console's commands, one a line ("name args: what it does"), for
## "help" and the admin panel's list (672). Other replies keep their shapes:
## release's scripts read "version" (protocol <hex>), "stop"/"restart"
## (starts "restarting") and "players" (its count line).
const CONSOLE_HELP: Array[String] = [
	"players: who is on, where, their hp",
	"zones: each loaded zone, awake or asleep, and who is in it",
	"go <zone> [player]: you (or that player) and the companion to that zone's start",
	"quests reset [all|<giver>] [player]: your quests (or that player's) undone, all or one quest giver's here",
	"zone reset <name>: that zone rebuilt from its map",
	"zone move <player> <zone>: that player and their companion to that zone's start",
	"gold <player or id prefix> <amount> [why]: give that player gold (why: admin grant unless said)",
	"move <player> <x> <y> [zone] | move <player> <building code> [zone]: a player to a cell",
	"mark <player> <mark>|-<mark>: a mark on a player, or one taken off",
	"reset: this room rebuilt from its map",
	"respawn: every zone's dead brought back now",
	"regenerate [on|off|now <level>]: the levels' regeneration",
	"reload <zone>|all: a zone's map read again",
	"raids [on|off|send <camp> <town>]: the raids",
	"hour [<h>] | day_minutes [<m>]: the time of day, the day's length",
	"season [<name>] | season_days [<n>]: the season, its length",
	"weather [<kind>|auto|reload] [<minutes>] [<region>|all]: the weather",
	"companions | companion facts <player> | companion forget <player> <id>: the companions",
	"mind scripted|ollama | mind log on|off | mind last <name>: the residents' minds",
	"perception list|grid|both: what the minds are told",
	"transcript <name> [<date>]: a mind's talk",
	"builder | builder export | builder drop <name>: builder mode",
	"map: the map's name",
	"net: the server's traffic and each peer's round trip",
	"save: the world saved now",
	"version: the build and its protocol",
	"restart|stop [<seconds>] [<why>] | restart cancel: a restart, or calling it off",
	"help: these lines",
]


## One console command; the reply is what the operator sees. [param caller]:
## the player whose admin panel sent it (672), null from stdin and the port.
func admin_command(line: String, caller: Player = null) -> String:
	if not Net.is_authority():
		return "not the authority"
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	match words[0].to_lower():
		"map":
			return "map load is now zone reset <name>; zones: %s" % ", ".join(World.zones.keys())
		"zones":
			return _zones_text()
		"hour", "day_minutes":
			return _sky_command(words)
		"season", "season_days":
			return _season_command(words)
		"weather":
			return _weather_command(words)
		"zone":
			return _zone_command(words)
		"go":
			return _go_command(words, caller)
		"quests":
			return _quests_command(words, caller)
		"builder":
			if _builder != null:
				return _builder.admin(words)
			if words.size() > 1:
				return BuilderHost.overlay_command(words, self)
			return "builder mode is off (no ANTHROPIC_API_KEY, no --builder-stub); edited levels: %s" % ", ".join(Level.overlay_names())
		"reset":
			var reset_zone := World.zone.name
			_start_level()
			return "%s rebuilt from the map; %d player records kept; %s" % [reset_zone, _records.size(),
				"no dead companions to bring back" if _revived.is_empty()
				else "companions brought back: %s" % ", ".join(_revived)]
		"respawn":
			var count := 0
			var was := World.zone
			for each: Zone in World.zones.values():
				World.enter(each)
				count += _check_respawns(World.tick, true)
			World.enter(was)
			return "respawned %d" % count
		"free_walk":
			# Decision 689: free movement for every player, live (no release,
			# no restart), kept in the --state file.
			if words.size() >= 2 and words[1] in ["on", "off"]:
				World.set_free_walk(words[1] == "on")
				if Net.state_path != "":
					_save_state()
			elif words.size() >= 2:
				return "usage: free_walk on|off (now %s)" % ("on" if World.free_walk else "off")
			return "free walk %s" % ("on" if World.free_walk else "off")
		"players":
			var lines: Array[String] = []
			for peer: int in _players:
				var player: Player = _players[peer]
				if not is_instance_valid(player) or not player.spawned:
					continue
				var id: String = _peer_ids.get(peer, "")
				var record: PlayerRecord = _records.get(id)
				lines.append("%s %s (%s) peer %d in %s at %s hp %d/%d" % [
					player.name, record.name if record != null else "?", id.left(8), peer, player.zone,
					player.tile, player.hp, player.max_hp])
			return "%d connected\n%s" % [lines.size(), "\n".join(lines)] if not lines.is_empty() else "0 connected"
		"move":
			return _move_command(words)
		"mark":
			return _mark_command(words)
		"save":
			if Net.state_path == "":
				return "no --state file to save to"
			_save_state()
			return "saved %s at tick %d" % [Net.state_path, World.tick]
		"companion":
			return _companion_command(words)
		"companions":
			var lines: Array[String] = []
			for id: String in _companions:
				var pet: Companion = _companions[id]
				if not is_instance_valid(pet) or not pet.spawned:
					continue
				var record: PlayerRecord = _records.get(id)
				lines.append("%s, with %s (%s) in %s at %s hp %d/%d stance %s intent %s%s mind %s, stance set by %s" % [
					pet.name, record.name if record != null else "?", id.left(8), pet.zone, pet.tile, pet.hp, pet.max_hp,
					pet.stance_name(), pet.intent_name(), " " + pet.intent_target.name if pet.intent_target != null else "",
					pet.mind.kind if pet.mind != null else "none", pet.last_mind])
			return "%d companions\n%s" % [lines.size(), "\n".join(lines)] if not lines.is_empty() else "0 companions"
		"mind":
			if words.size() >= 2 and words[1] == "log":
				if words.size() >= 3 and words[2] in ["on", "off"]:
					MindLog.enabled = words[2] == "on"
				return "mind log %s (%s)" % ["on" if MindLog.enabled else "off",
					Net.mind_log_path if Net.mind_log_path != "" else "no file: --mind-log"]
			if words.size() >= 2 and words[1] == "last":
				var who := " ".join(words.slice(2))
				if not MindLog.last.has(who):
					return "no decision of %s's logged yet (companions: %s)" % [who, ", ".join(MindLog.last.keys())]
				return JSON.stringify(MindLog.last[who], "  ")
			if words.size() >= 2 and words[1] == "claude":
				return _mind_claude(words.slice(2))
			if words.size() < 2 or words[1] not in ["scripted", "ollama"]:
				return "usage: mind scripted|ollama | mind claude [<name>|all haiku|sonnet|off] | mind log on|off | mind last <name> (now %s)" % mind_kind
			if words[1] == "ollama" and (Net.llm_url == "" or Net.llm_model == ""):
				return "no --llm-model configured"
			mind_kind = words[1]
			for id: String in _companions:
				var pet: Companion = _companions[id]
				if is_instance_valid(pet):
					pet.mind = _make_mind()
					if _claude_voices.has(id):
						pet.mind = ClaudeMind.new(pet.mind, _claude_voices[id], self)
					pet.mind.warm()
			return "companion minds: %s" % mind_kind
		"perception":
			if words.size() >= 2:
				if words[1] not in Net.PERCEPTIONS:
					return "usage: perception list|grid|both (now %s)" % Net.perception
				Net.perception = words[1]
			return "perception: %s" % Net.perception
		"transcript":
			if words.size() < 2:
				return "usage: transcript <name> [<YYYY-MM-DD>] | transcript rebuild"
			if words[1] == "rebuild":
				if Net.mind_log_path.is_empty():
					return "no mind log to rebuild from"
				var logs: Array[String] = [Net.mind_log_path + ".1", Net.mind_log_path]
				return Transcript.rebuild(logs)
			var who := words[1]
			for pet: Companion in _companions.values():
				if is_instance_valid(pet) and String(pet.name).to_lower() == who.to_lower():
					who = String(pet.name)
			return Transcript.show(who, words[2] if words.size() >= 3 else "")
		"version":
			return "v%s protocol %s" % [Net.version, Net.protocol()]
		"restart", "stop":
			return _restart_command(words)
		"raids":
			return _raids_command(words)
		"regenerate":
			return _regenerate_command(words)
		"reload":
			return _reload_command(words)
		"net":
			var peers: Array[String] = []
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			for peer: int in _players:
				var link := enet.get_peer(peer) if enet != null else null
				if link != null:
					peers.append("%s rtt %d ms" % [_players[peer].name, roundi(link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))])
			return "%s\n%s" % [Net.stats.server_text(), ", ".join(peers) if not peers.is_empty() else "no peers"]
		"gold":
			return _gold_command(words)
		"help":
			return "\n".join(CONSOLE_HELP)  # 672: one line a command.
	return "unknown command %s (try help)" % words[0]


## "gold <player or id prefix> <amount> [why]" (decision 709): the admin gives
## a player gold, online or off, why "admin grant" unless said; never a
## negative amount. The player by name, else by the one id starting so.
func _gold_command(words: PackedStringArray) -> String:
	if words.size() < 3 or not words[2].is_valid_int():
		return "usage: gold <player or id prefix> <amount> [why]"
	var amount := words[2].to_int()
	if amount <= 0:
		return "gold: the amount must be above 0 (gold is only ever given here)"
	if World.economy == null:
		return "gold: no economy"
	var id := str(_admin_player(words[1]).get("id", ""))
	if id.is_empty():
		var ids := _records.keys().filter(func(each: String) -> bool: return each.begins_with(words[1]))
		if ids.size() == 1:
			id = ids[0]
		elif ids.size() > 1:
			return "gold: %d players' ids start %s; give more of it" % [ids.size(), words[1]]
	if id.is_empty():
		return "no player %s" % words[1]
	var why := " ".join(words.slice(3)) if words.size() > 3 else "admin grant"
	_give_gold(id, amount, why)
	print("[economy] the admin gave %d gold (%s)" % [amount, why])
	var record: PlayerRecord = _records.get(id)
	return "%s: %d gold given (%s), %d now" % [record.name if record != null else id.left(8), amount, why, World.economy.gold(id)]


## The console's zones: each loaded zone, awake or asleep, its tick, and who
## is in it.
func _zones_text() -> String:
	var lines: Array[String] = []
	for each: Zone in World.zones.values():
		var who: Array[String] = []
		for peer in World.peers_in(each.name):
			var record: PlayerRecord = _records.get(_peer_ids.get(peer, ""))
			who.append(record.name if record != null else "peer %d" % peer)
		var count := World.get_entities().size() if each == World.zone else each.entities.size()
		lines.append("%s: %s, tick %d, %d entities, %s" % [each.name, "awake" if each.awake else "asleep",
			each.tick if each != World.zone else World.tick, count, ", ".join(who) if not who.is_empty() else "nobody"])
	return "%d zones\n%s" % [lines.size(), "\n".join(lines)]


## zone reset <name>: that zone rebuilt from its map (loaded if it was not);
## zone move <player> <zone>: that player (by name, or PlayerN) and their
## companion to that zone's first start.
func _zone_command(words: PackedStringArray) -> String:
	if words.size() >= 3 and words[1] == "reset":
		if not Level.exists(words[2]):
			return "no map %s in %s" % [words[2], Level.DIR]
		var opened := World.zones.has(words[2])
		var was := World.enter(_open_zone(words[2]))
		if opened:
			_start_level()
		var reply := "zone %s %s: %d cells, %d entities" % [words[2], "rebuilt" if opened else "loaded",
			_terrain["floor"].size(), level_entities.size()]
		World.enter(was)
		return reply
	if words.size() >= 4 and words[1] == "move":
		var wanted := words[2].to_lower()
		var to := words[3]
		if not Level.exists(to):
			return "no map %s in %s" % [to, Level.DIR]
		for peer: int in _peer_ids:
			var record: PlayerRecord = _records.get(_peer_ids[peer])
			var player: Player = _players.get(peer)
			if record != null and (record.name.to_lower() == wanted
					or is_instance_valid(player) and String(player.name).to_lower() == wanted):
				if not travel(peer, to):
					return "could not move %s to %s" % [record.name, to]
				return "%s moved to %s" % [record.name, to]
		return "no player %s online" % words[2]
	return "usage: zone reset <name> | zone move <player> <zone>"


## --test-move: order the local player once, then report when the move shows
## up in this peer's own view of the world.
func _run_test_move(player: Player) -> void:
	if Net.test_move == Vector2i.ZERO or _test_arrived or player == null:
		return
	if not _test_ordered:
		if Net.free_walk and not World.free_body(player):
			return  # 703: its free state not heard yet (the server not ticking): a click would go to the grid.
		_test_ordered = true
		_test_target = player.tile + Net.test_move
		_move_click(player, _test_target, false)  # 703 step 1: as a click, free or grid.
		print("[test] %s ordered from %s to %s" % [player.name, player.tile, _test_target])
	elif player.tile == _test_target:
		_test_arrived = true
		print("[test] %s arrived at %s occupancy_consistent=%s" % [
			player.name, player.tile, World.is_occupancy_consistent()])


## --test-contest: at a fixed server tick, order the local player to a given
## tile. Two clients doing this for the same tile race for it on the server.
## --test-door: at that tick, work the door the local player stands beside.
func _run_test_door(player: Player, tick: int) -> void:
	if Net.test_door_tick <= 0 or _test_door_sent or player == null or tick < Net.test_door_tick:
		return
	_test_door_sent = true
	for door in World.get_doors():
		if player.tile in Terrain.edge_cells(door.key):
			World.command(player, "door", {"edge": [door.key.x, door.key.y, door.key.z]})
			print("[test] %s works %s at tick %d" % [player.name, door.name, tick])
			return


## --test-chest=take|put: walk to the chest nearest the local player, open
## it, and drag its first item into the player's pack's first empty slot
## (take), or the player's first item into the chest's first empty slot
## (put), through the pack panel as a drag would.
func _run_test_chest(player: Player) -> void:
	if Net.test_chest.is_empty() or _test_chest_done or player == null or pack_panel == null:
		return
	var chest: GridEntity = null
	for entity in World.get_entities():
		if entity is Chest and (chest == null or World.distance(player.tile, entity.tile) < World.distance(player.tile, chest.tile)):
			chest = entity
	if chest == null:
		return
	if not World.can_melee(player.tile, chest.tile):
		if not _test_chest_walking:
			_test_chest_walking = true
			_open_pack(player, chest)
			print("[test] %s walks to %s" % [player.name, chest.name])
		return
	open_other(chest)
	var take := Net.test_chest == "take"
	var from: GridEntity = chest if take else player
	var to: GridEntity = player if take else chest
	var from_slot := Array(from.slots).find_custom(func(item: String) -> bool: return not item.is_empty())
	var to_slot := Array(to.slots).find("")
	_test_chest_done = true
	if from_slot < 0 or to_slot < 0:
		print("[test] %s: nothing to %s (%s, %s)" % [player.name, Net.test_chest, Array(from.slots), Array(to.slots)])
		return
	print("[test] %s drags %s from %s %d to %s %d" % [player.name, from.slots[from_slot], from.name, from_slot, to.name, to_slot])
	pack_panel.drop(from, from_slot, to, to_slot)


## The first time a townsperson stands within hearing: one line, once, for
## a few seconds at the top of the screen, then remembered (hinted_talk=on).
func _first_talk_hint(player: Player) -> void:
	if _talk_hint != null and _talk_hint.visible and Time.get_ticks_msec() / 1000.0 > _talk_hint_until:
		_talk_hint.visible = false
	if player == null or Net.hinted_talk or not Net.hints or DisplayServer.get_name() == "headless":
		return  # The first-time talk hint only with hints=on (Jeff, 2026-10-22: "it's going to be intuitive").
	for entity in World.townsfolk():
		if entity is Resident and World.distance(entity.tile, player.tile) <= RESIDENT_EARSHOT + 2:
			_show_top_hint("Click a townsperson to interact, or press %s" % Keys.name_of("open"))  # 560: interact.
			Net.set_hinted_talk(true)
			return


## One line at the top of the screen for a few seconds (the first-time
## hints: talking, 453; the screenshot folder, 538).
func _show_top_hint(text: String) -> void:
	if _talk_hint == null:
		_talk_hint = Label.new()
		_talk_hint.theme_type_variation = &"Hud"
		_talk_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_talk_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_talk_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_talk_hint.offset_top = 120
		_talk_hint.offset_left = -1100  # A box in the middle, clear of the compass and its place name; long lines wrap.
		_talk_hint.offset_right = 1100
		_talk_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_talk_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$HUD.add_child(_talk_hint)
	_talk_hint.text = text
	_talk_hint.visible = true
	_talk_hint_until = Time.get_ticks_msec() / 1000.0 + 8.0


## Where screenshots go (decision 538) and a note when it is not the folder
## asked for: settings.cfg screenshot_dir= when it exists or can be made,
## else the game's own DEFAULT_SCREENSHOT_DIR with why (the NAS away). The
## game's own folder is made only when a screenshot is saved there.
static func screenshot_folder() -> Array:
	var wanted := Net.screenshot_dir
	if wanted.is_empty():
		return [DEFAULT_SCREENSHOT_DIR, ""]
	if DirAccess.dir_exists_absolute(wanted) or (_folder_makeable(wanted) and DirAccess.make_dir_recursive_absolute(wanted) == OK):
		return [wanted, ""]
	return [DEFAULT_SCREENSHOT_DIR, " (%s can't be written, so the game's own folder)" % wanted]


## Whether [param path] could be made as a folder: some ancestor of it is
## a folder, and no ancestor is a file. Asked before the engine's maker,
## which prints an error for a folder it cannot make (a share away, a file
## in the way), and an error line fails a test.
static func _folder_makeable(path: String) -> bool:
	var at := path
	while not at.is_empty() and not DirAccess.dir_exists_absolute(at):
		if FileAccess.file_exists(at):
			return false
		var up := at.get_base_dir()
		if up == at or up.is_empty():
			return false
		at = up
	return not at.is_empty()


## A screenshot's file name (538): the zone, the player's cell, the game
## hour and the clock; nothing of who took it.
static func screenshot_name(zone_name: String, cell: Vector2i, hour: float, stamp: String) -> String:
	return "%s_%d-%d_%02dh_%s.png" % [zone_name, cell.x, cell.y, int(hour), stamp]


## The talk log's one short line for a saved shot: the file's name without
## its stamp and ".png" ("screenshot saved: wilds_128-16_17h"); the path is
## the console's (Jeff's castle F12 wrapped three lines, 2026-10-22).
static func screenshot_words(file: String) -> String:
	var short := file.get_basename()
	var cut := short.rfind("_")
	if cut > 0:
		short = short.left(cut)
	return "screenshot saved: %s" % short


## F12 (decision 538, Jeff: "a folder for screenshot feedback"): the
## viewport saved as PNG in screenshot_folder(), said in the talk log with
## the path; the first time, the folder in a line at the top. A folder
## that will not take the file falls back to the game's own and says so.
func take_screenshot() -> void:
	var player := _local_player()
	var zone_name := zone_name_here()  # 538 amended: a joined client's World.zone has no name.
	var cell := player.tile if player != null else Vector2i.ZERO
	var stamp := Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "-")
	var file := screenshot_name(zone_name, cell, DayNight.hour(DayNight.now()), stamp)
	var where := screenshot_folder()
	var image := get_viewport().get_texture().get_image()
	var usable := image != null and not image.is_empty()
	var path := str(where[0]).path_join(file)
	if where[0] == DEFAULT_SCREENSHOT_DIR:
		DirAccess.make_dir_recursive_absolute(DEFAULT_SCREENSHOT_DIR)
	var error := image.save_png(path) if usable else ERR_UNAVAILABLE
	if error != OK and usable and where[0] != DEFAULT_SCREENSHOT_DIR:
		where = [DEFAULT_SCREENSHOT_DIR, " (%s can't be written, so the game's own folder)" % where[0]]
		DirAccess.make_dir_recursive_absolute(DEFAULT_SCREENSHOT_DIR)
		path = DEFAULT_SCREENSHOT_DIR.path_join(file)
		error = image.save_png(path)
	last_screenshot = path if error == OK else ""
	var shown := ProjectSettings.globalize_path(path)
	print("[game] %s%s" % ["screenshot saved: %s" % shown if error == OK else "screenshot not saved: %s (%s)" % [shown, error_string(error)], where[1]])
	if talk != null:
		talk.add_line("Game", screenshot_words(file) if error == OK else "screenshot not saved (%s)" % error_string(error), true, true)
	if error == OK and not Net.hinted_shot:
		_show_top_hint("Screenshots go to %s. Set screenshot_dir= in settings.cfg to send them elsewhere." % ProjectSettings.globalize_path(str(where[0])))
		Net.set_hinted_shot(true)


## --test-show=offer and sick (536, ui's side): once a resident is there,
## the player walks to their side; then (offer) asks them for work after
## TEST_OFFER_ASK seconds and says "yes" after TEST_OFFER_YES, the server
## speaking the offer and taking the word (npc's 536), the HUD line
## between; (sick) their ailing set and the hint on them.
var _test_offer_due := false
var _test_offer_since := 0.0
var _test_offer_body: GridEntity
var _test_offer_asked := false
var _test_offer_said_yes := false
const TEST_OFFER_ASK := 5.0
const TEST_OFFER_YES := 11.0
## How long (seconds from the start) the offer state waits for the merchant before taking whoever is nearest.
const TEST_OFFER_MERCHANT_WAIT := 75.0  # He is seated on the first world tick, about a minute in.
## --test-show=channel: the companion laid downed, to be brought back once the player stands beside her.
var _test_channel_body: GridEntity


## --test-show=channel, each tick (544, ui's side): a step to a cell beside
## the downed companion (a channel needs a neighbouring cell, not a
## corner), then the channel, once.
func _run_test_channel(player: Player) -> void:
	if not is_instance_valid(_test_channel_body) or not Net.is_authority() or not World.is_downed(_test_channel_body):
		return
	var body := _test_channel_body
	if World.can_melee(player.tile, body.tile):
		if player.channel_of.is_empty():
			World.try_channel(player, body, 8 * World.TICK_RATE)
		return
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_walkable(body.tile + step) and World.is_free(body.tile + step):
			_move_click(player, body.tile + step, false)  # 703 step 1: as a click, free or grid.
			break


func _run_test_offer(player: Player) -> void:
	if not _test_offer_due or player == null:
		return
	if _test_offer_body == null:
		var nearest: GridEntity = null
		var merchant: GridEntity = null
		for entity in World.get_entities():
			if entity is Resident and ("Snagfin" in str(entity.get("person")) or "Snagfin" in str(entity.get("label"))):
				merchant = entity  # The merchant: a shop offer whenever the counter holds a good (npc's 536).
			if entity is Resident and (nearest == null
					or World.distance(player.tile, entity.tile) < World.distance(player.tile, nearest.tile)):
				nearest = entity
		if nearest == null:
			return
		if merchant == null and Time.get_ticks_msec() / 1000.0 < TEST_OFFER_MERCHANT_WAIT:
			return  # He is seated on a world tick after the town's people come: a moment's wait.
		_test_offer_body = merchant if merchant != null else nearest
		if "sick" in Net.test_show:
			nearest.ailing = "a fever"  # The sick read's shot (515 amended): the hint says it.
			_test_hint_thing = nearest
	if "offer" not in Net.test_show or not is_instance_valid(_test_offer_body):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var body := _test_offer_body
	if not _test_offer_asked:
		if World.distance(player.tile, body.tile) > RESIDENT_EARSHOT:
			# Walking to their side (the goal renewed each second: they move on their day).
			if now - _test_offer_since >= 1.0:
				_test_offer_since = now
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if World.is_walkable(body.tile + step):
						_move_click(player, body.tile + step, false)  # 703 step 1: as a click, free or grid.
						break
			return
		_test_offer_asked = true
		_test_offer_since = now
		if talk != null and not talk.pinned:
			talk.toggle_pin()  # The exchange stays up for the shot.
		_send_chat("what do you sell?" if "Snagfin" in str(body.get("person")) else "any work for me?")  # In earshot: addressed by nearness.
	elif now - _test_offer_since >= 1.5 and standing_title.is_empty() and not _test_offer_said_yes:
		standing_title = "(a test offer) Bring Bram home"  # Nothing stood with them: a sample, so the shot shows the HUD's line.
	elif now - _test_offer_since >= TEST_OFFER_YES - TEST_OFFER_ASK and not _test_offer_said_yes:
		_test_offer_said_yes = true
		_send_chat("yes")


## --test-show: the named HUD panels opened once the player is in, for
## screenshots of them (the ui tree's audit); the talk log gets a few
## marked test lines so there is something to see.
func _run_test_show(player: Player) -> void:
	if Net.test_show.is_empty() or _test_show_done or player == null:
		return
	_test_show_done = true
	for what: String in Net.test_show:
		match what:
			"hints":
				hint_panel.visible = true
			"options":
				if not options_panel.visible:
					options_panel.toggle()
			"pack":
				pack_panel.shown = true
			"telegraph":
				# 602, ui's side: a sample cone ahead of the player, landing in 3 s, for the shot.
				if player != null:
					var cells: Array = []
					for dx in range(1, 6):
						for dy in range(-(dx / 2), dx / 2 + 1):
							cells.append([player.tile.x + dx, player.tile.y + dy])
					_on_telegraph_started(1, {"id": 1, "kind": "spin", "shape": {"kind": "cone", "origin": [player.tile.x, player.tile.y],
						"facing": [1, 0], "length": 5, "half_angle": 30}, "cells": cells, "from_tick": World.tick, "lands_tick": World.tick + 30})
			"aim":
				# The archery aim, for the shot: a bow in the right hand and arrows in
				# the left (the quiver check wants them in hand, as controls_test puts
				# them), then the host draws (the server's stance), the aim fixed
				# down the screen from the archer, the arc at the step.
				if Net.is_authority() and player != null and player.slots.size() > Items.LEFT_HAND:
					player.slots[Items.RIGHT_HAND] = "bow"
					player.slots[Items.LEFT_HAND] = "arrows"
					# From the tile: the body's 2D position is not yet placed at spawn (it read (0, 0)
					# and aimed the sample at the map's corner).
					_aim_fixed = Vector2(player.tile) + Vector2(-4.0, 6.0)  # Down the screen, clear of the pack.
					World.try_stance(player, "draw")
			"charges":
				# 573, ui's side: the pack's charges line, for the shot (the host sets the
				# replicated pair as the server would after a win).
				pack_panel.shown = true
				if Net.is_authority() and player != null:
					player.set("charges", 23)
					player.set("charge_room", 50)
			"talk":
				talk.add_line("Wren", "(a test line) The door's barred from the other side.")
				talk.add_line("Aldous", "(a test line) I've been meaning to thank you for the food you brought.", false, false, "his voice steady despite the rain")  # 336 amended: the aside.
				talk.add_line(player.label, "(a test line) hold here", true)
				talk.add_line(player.label, "(a test line) anyone near the well?", true, true)
				if not talk.pinned:
					talk.toggle_pin()
			"chat":
				_open_chat()
			"debug":
				debug_overlay.visible = true
			"say":
				_send_chat("(a test line) Stay close, the gate's watched.")
			"game_menu":
				escape()
			"counter":
				# The counter screen with sample data in economy's shape (a test's words).
				pack_panel.shown = true
				_test_counter_shown = pack_panel
				counter_panel.show_counter({"kind": "temple", "why": "",
					"jobs": [{"slot": 0, "uid": 1, "id": "dagger", "effect": "bless", "price": 6, "ok": true},
						{"slot": 1, "uid": 2, "id": "hammer", "effect": "reforge", "to_id": "sword", "price": 12,
							"materials": {"ore": 2}, "ok": false, "why": "the town lacks 2 ore"}],
					"working": [{"uid": 3, "id": "bow", "effect": "bless", "left": 900, "left_seconds": 90}],
					"waiting": [{"uid": 4, "id": "shield", "effect": "bless"}]},
					func(slot: int) -> String: return ["Wren's dagger", "hammer"][slot])
			"shot":
				get_tree().create_timer(3.0).timeout.connect(take_screenshot)  # The log line and the first-time hint, in the shot.
			"led", "guide_map":
				# 551, ui's side, for the shots: she leads the player to the first
				# place of this area (the HUD line), or knows the way there and the
				# map's ask box stands beside it. The guide itself is companions'.
				var pet := _own_companion()
				var her := String(pet.name) if pet != null else "Wren"
				world_map_panel._ensure_world()
				var own_places: Variant = (world_map_panel.world.areas.get(zone_name_here(), {}) as Dictionary).get("places", {})
				var there := ""
				if own_places is Dictionary and not (own_places as Dictionary).is_empty():
					there = "%s/%s" % [zone_name_here(), (own_places as Dictionary).keys()[0]]
				if what == "led":
					player.led_by = her
					if "led_to" in player:
						player.set("led_to", there)
				else:
					world_state = WorldNews.merge(world_state, {"full": false, "guide": {"companion": her, "places": [there], "areas": []}})
					open_world_map()
					world_map_panel.show_ask(there)
			"greet", "barter":
				# 560, ui's side, for the shots: a resident's greeting bubble with the
				# talk bar under it (greet), or the barter window with a sword taken
				# and a hide given (barter; a sample message, economy's shape).
				var who := _nearest_resident(player)
				if what == "greet":
					# The town's people spawn a moment after the level: the greeting
					# waits for the first of them, up to GREET_SHOT_TRIES seconds.
					_greet_sample(player, 0)
				elif what == "barter" and barter_panel != null and player != null:
					var counter := _shop_counter_near(who if who != null else player)
					if player.slots.size() >= 2:
						player.slots[0] = "hide"
						player.slots[1] = "dagger"
					var person := str(who.get("person")) if who != null and who.get("person") != null else "Snagfin"
					barter_panel.open(counter, person)
					barter_panel.show_barter({"shop": str(counter.get_path()) if counter != null else "", "town": zone_name_here(), "gold": 12,
						"goods": [{"uid": 101, "id": "sword", "price": 10}, {"uid": 102, "id": "bandaging_kit", "price": 1}],
						"buys": {"hide": {"gold": 20, "up_to": 2}, "dagger": {"gold": 6, "up_to": 1}}, "fenced": {},
						"pack": [{"slot": 0, "uid": 201, "id": "hide"}, {"slot": 1, "uid": 202, "id": "dagger"}], "why": ""})
					barter_panel.toggle_take(101)
					barter_panel.toggle_give(201)
			"bond", "bond_drop":
				# 555, ui's side, for the shots: her bond read on her pack's title
				# (bond), or the HUD's hint as her step drops (bond_drop). The bond
				# itself is companions'.
				var pet := _own_companion()
				if pet != null:
					_bond_seen[String(pet.name)] = "sullen" if what == "bond" else "fond"
					pet.bond_step = "sullen"
					pet.bond_why = "you left her to fall alone"
					if what == "bond":
						open_other(pet)
			"card":
				# 618, ui's side: her card page, for the shot. The sim's own words when
				# she is here and has sent them; a sample of each the server has not.
				var pet := _own_companion()
				var her := String(pet.name) if pet != null else "Wren"
				if not world_state.get("focus") is Dictionary:
					world_state = WorldNews.merge(world_state, {"full": false, "focus": {"companion": her, "fight": 32, "magic": 18, "stealth": 50}})
				if CardPage.held_of(world_state).is_empty():
					world_state = WorldNews.merge(world_state, {"full": false, "capabilities": {"companion": her,
						"held": [{"id": "draugr", "words": "the draugr's blessing", "teacher": "the draugr"}]}})
				toggle_card()
			"town_note":
				# 353 amended (2), ui's side: the town's read-out on its area box, for the shot.
				town_notes[zone_name_here()] = "3 in town are on the dole (fed by the town, or hungry): its kitchen works for food first."
				open_world_map()
			"world":
				open_world_map()
				if world_map_panel != null and world_map_panel.trade.is_empty() and world_map_panel.world != null:
					# A test wagon (decision 515) from this area to another the map knows, hovered.
					var areas: Array = world_map_panel.positions.keys()
					var own := world_map_panel.own_area
					var other := ""
					for area_name: String in areas:
						if area_name != own:
							other = area_name
							break
					if not other.is_empty():
						var route := {"id": "test", "from_area": own, "to_area": other, "areas": [own, other],
							"caravans": [{"area": own, "fraction": 0.4, "days": 2}]}
						world_map_panel.trade = [route]
						world_map_panel._hover_caravan = {"route": route, "caravan": route["caravans"][0]}
						world_map_panel.queue_redraw()
			"herbs":
				# Herbs laid beside the player (the hint over them) and a bunch in the hand (the pack).
				if Net.is_authority() and World.items != null:
					var beside := player.tile + Vector2i(1, 0)
					if not World.is_walkable(beside):
						beside = player.tile + Vector2i(0, 1)
					var uid := World.items.mint("herbs", "test", "the ground", World.zone.name, beside)
					World.put_on_ground(uid, beside)
					_test_hint_cell = beside
					var held := World.items.mint("herbs", "test", _display_name(player), World.zone.name, player.tile)
					var slots := player.slots.duplicate()
					var uids := World.slot_uids(player)
					if slots.size() > Items.RIGHT_HAND:
						slots[Items.RIGHT_HAND] = "herbs"
						uids[Items.RIGHT_HAND] = held
						World.set_slots(player, slots, uids)
				pack_panel.shown = true
			"credits":
				if not options_panel.visible:
					options_panel.toggle()
				options_panel.toggle_credits()
			"controls":
				# The Options scrolled to its Controls section (the key rows).
				if not options_panel.visible:
					options_panel.toggle()
				options_panel.begin_rebind("open")
				get_tree().create_timer(0.5).timeout.connect(func() -> void:
					options_panel._scroll.scroll_vertical = 2400)
			"offer", "sick":
				_test_offer_due = true  # Residents come with the town's sync: tried each tick.
			"downed":
				if Net.is_authority():
					World.lay_downed(player, 30 * World.TICK_RATE)  # 544, ui's side: the countdown on the HUD.
					player.set("heart", 120)  # 587: the screen's pulse, as the server would set it.
			"downed_blessed", "all_fallen":
				# 587, ui's side: the screen for the blessed (the hold theirs), and everyone's wait.
				if Net.is_authority():
					World.lay_downed(player, 30 * World.TICK_RATE)
					player.set("heart", 80)
					player.set("charge_room", 50)
					if what == "all_fallen":
						_on_message("return", {"all_fallen": 20})
			"return":
				# 396 amended, ui's side: the dead player's line. The sample stands
				# until economy's own message comes; the host's death path then runs.
				_return_told = {"by": "Hob", "where": "healers_hut", "seconds": 58}
				_return_at = Time.get_ticks_msec() / 1000.0
				if Net.is_authority() and player != null:
					World.despawn(player)
			"channel":
				if Net.is_authority():
					var pet := _own_companion()
					if pet != null:
						World.lay_downed(pet, 30 * World.TICK_RATE)
						_test_channel_body = pet  # Then, each tick: step to a cell beside her and channel (the ring, the HUD's line).
			"hint":
				for entity in World.get_entities():
					if entity is Cargo or entity is Chest:
						if _test_hint_thing == null or World.distance(player.tile, entity.tile) < World.distance(player.tile, _test_hint_thing.tile):
							_test_hint_thing = entity
			"tip":
				# A sample named dagger's tip over the pack's first slot: no named
				# thing exists in play until lore's holder form is agreed (365).
				pack_panel.shown = true
				if pack_panel.tip == null:
					pack_panel.tip = ItemTip.new()
					$HUD.add_child(pack_panel.tip)
				var sample := "Wren's dagger (quiet), imp-bane
felled 12 imps
story: carried by Wren for 3 days; named for Wren"
				pack_panel.tip.show_for("dagger", sample, pack_panel._player_row.get_child(0).get_global_rect().position)
			"menu":
				_show_menu()
			"menu_options":
				# The main menu's Options (Jeff, 2026-10-22): the menu aside, the options on top.
				_show_menu()
				_menu_options()
			"setup":
				_connect_screen().edit()
			"connect":
				_connect_screen().set_state("connecting to 100.64.0.5:7777")
			"failed":
				_connect_screen().has_menu = true
				_connect_screen().set_state("the server at 100.64.0.5:7777 did not answer", true)
			"shop":
				# The nearest shop counter opened from where the player stands (the
				# server may refuse the trade; the panel shows the same).
				var counter: GridEntity = null
				for entity in World.get_entities():
					if entity is Chest and (entity as Chest).shop and (counter == null
							or World.distance(player.tile, entity.tile) < World.distance(player.tile, counter.tile)):
						counter = entity
				if counter != null:
					open_other(counter)
	print("[test] shown: %s" % ", ".join(Net.test_show))


func _run_test_reset(player: Player, tick: int) -> void:
	if Net.test_reset_tick <= 0 or _test_reset_sent or player == null or tick < Net.test_reset_tick:
		return
	_test_reset_sent = true
	World.command(player, "reset", {})
	print("[test] %s asked for a room reset at tick %d" % [player.name, tick])


func _run_test_contest(player: Player, tick: int) -> void:
	if _test_contested and not _test_contest_reached and player != null \
			and player.tile == Net.test_contest_tile and player.shown_tile() == Net.test_contest_tile:
		_test_contest_reached = true
		print("[test] %s reached the contested tile %s at tick %d" % [player.name, player.tile, tick])
	if Net.test_contest_tick <= 0 or _test_contested or player == null \
			or tick < Net.test_contest_tick:
		return
	if Net.free_walk and not World.free_body(player):
		return
	_test_contested = true
	_move_click(player, Net.test_contest_tile, false)  # 703 step 1: as a click, free or grid.
	print("[test] contest: %s at %s ordered to %s, now showing %s" % [
		player.name, player.tile, Net.test_contest_tile, player.shown_tile()])


## --test-hold-near (678; Jeff: "placing the cursor to move on a diagonal 1
## square in front of me and if i keep that there the run camera stutter is
## reproducible"): the left button held, the cursor still on screen a
## diagonal cell ahead, so the ground under it moves with the camera; the
## orders, the steps sent and the times the walk stood still on the way,
## said at the end.
var _test_holding := false
var _test_hold_from := -1
var _test_hold_counts := {"orders": 0, "steps": 0, "stops": 0}
var _test_hold_walking := false
## The drawn walk, measured (Jeff on v0.1.177: "the body doesn't face the
## direction of travel"; "character keeps going"): [msec, grid] a frame, the
## last quarter second; the facing's error against the way travelled; after
## the flip, how far on the body went and when it came back.
var _test_hold_trail: Array = []
var _test_hold_facing := {"frames": 0, "sum": 0.0, "worst": 0.0, "off20": 0, "yaw_sum": 0.0, "yaw_worst": 0.0}
var _test_hold_flip := {}


func _test_hold_measure(player: Player, seconds: float) -> void:
	var now := Time.get_ticks_msec()
	var at := Iso.local_to_grid(player.position)
	_test_hold_trail.append([now, at])
	while _test_hold_trail.size() > 2 and now - int(_test_hold_trail[0][0]) > 250:
		_test_hold_trail.pop_front()
	var span := (now - int(_test_hold_trail[0][0])) / 1000.0
	var travel: Vector2 = (at - _test_hold_trail[0][1]) / span if span > 0.15 else Vector2.ZERO
	var turning := not _test_hold_flip.is_empty() and seconds - float(_test_hold_flip["at"]) < 0.75
	if travel.length() > 2.0 and not turning:
		var off := absf(rad_to_deg(angle_difference(player.shown_facing().angle(), travel.angle())))
		_test_hold_facing["frames"] += 1
		_test_hold_facing["sum"] += off
		_test_hold_facing["worst"] = maxf(_test_hold_facing["worst"], off)
		if off > 20.0:
			_test_hold_facing["off20"] += 1
		var puppet: Node3D = _client3d._puppets.get(player.get_instance_id()) if _client3d != null else null
		var facing := puppet.get_node_or_null("Facing") as Node3D if puppet != null else null
		if facing != null:
			var yaw_off := absf(rad_to_deg(angle_difference(facing.rotation.y, -travel.angle())))
			_test_hold_facing["yaw_sum"] += yaw_off
			_test_hold_facing["yaw_worst"] = maxf(_test_hold_facing["yaw_worst"], yaw_off)
	if _test_hold_flip.is_empty():
		return
	var way: Vector2 = _test_hold_flip["way"]
	var from: Vector2 = _test_hold_flip["from"]
	var on := (at - from).dot(way)
	if on > _test_hold_flip["on"]:
		_test_hold_flip["on"] = on
		_test_hold_flip["on_at"] = seconds
	elif _test_hold_flip["back_at"] < 0.0 and on < _test_hold_flip["on"] - 0.1:
		_test_hold_flip["back_at"] = seconds


func _run_test_hold_near() -> void:
	var player := _local_player()
	if Net.test_hold_near <= 0.0 or player == null or _test_hold_from == -2:
		return
	if _test_hold_from == -1:
		if World.tick < 30:
			return  # Settled in first.
		_test_hold_from = Time.get_ticks_msec()
	var seconds := (Time.get_ticks_msec() - _test_hold_from) / 1000.0
	if seconds > Net.test_hold_near:
		_test_holding = false
		_test_hold_from = -2
		print("[test] hold-near %.0f s%s: %d orders, %d steps sent, %d stops" % [Net.test_hold_near,
				" (routes)" if Net.test_hold_route else "", _test_hold_counts["orders"], _test_hold_counts["steps"], _test_hold_counts["stops"]])
		var f := _test_hold_facing
		var frames := maxi(int(f["frames"]), 1)
		print("[test] hold-near facing at %.0f degrees, %.1f cells: off the way travelled %.1f mean, %.1f worst, %d of %d frames over 20; the puppet's yaw %.1f mean, %.1f worst" % [
				Net.test_hold_angle, Net.test_hold_far, f["sum"] / frames, f["worst"], f["off20"], f["frames"], f["yaw_sum"] / frames, f["yaw_worst"]])
		if not _test_hold_flip.is_empty():
			print("[test] hold-near flip at %.1f s: on %.2f cells more, for %.0f ms; back after %.0f ms" % [_test_hold_flip["at"],
					_test_hold_flip["on"], (_test_hold_flip["on_at"] - _test_hold_flip["at"]) * 1000.0,
					(_test_hold_flip["back_at"] - _test_hold_flip["at"]) * 1000.0 if _test_hold_flip["back_at"] >= 0.0 else -1.0])
		return
	var seen := Iso.local_to_grid(player.position)
	if _client3d != null:
		seen = Vector2(_client3d._camera_target.x, _client3d._camera_target.z)
	var angle := Net.test_hold_angle
	if Net.test_hold_flip > 0.0 and seconds >= Net.test_hold_flip:
		if _test_hold_flip.is_empty():
			_test_hold_flip = {"at": seconds, "from": Iso.local_to_grid(player.position), "way": Vector2.from_angle(deg_to_rad(angle)),
					"on": 0.0, "on_at": seconds, "back_at": -1.0}
		angle += 180.0  # Swung behind.
	# Still on screen: the camera's point and the cursor's offset from it.
	_pick_grid = seen + Vector2.from_angle(deg_to_rad(angle)) * Net.test_hold_far
	_test_hold_measure(player, seconds)
	var walking := player.ready_for_step() == false or player.walk_end() != player.tile
	if _test_holding and _test_hold_walking and not walking:
		_test_hold_counts["stops"] += 1
	_test_hold_walking = walking
	if not _test_holding:
		_test_holding = true
		_move_click(player, _snap_to_floor(_pick_grid))


## --test-latency (Net.test_latency): rounds of a start from standing (a
## key, a click 8 cells east, or the left button held with the cursor
## LAT_HOLD cells east of the body), a turn mid-walk (the key at right
## angles, a click 8 cells north, or the held cursor swung north) and a stop
## (the key let go, a click on the body's own cell, or the button let go),
## each timed from the input to the first frame drawn with it: the body
## moved 0.02 cells (a), its frame's way 15 degrees off the way before or its
## facing 10 degrees (b), standing three frames (c); and to the response
## done: at 80% of the walking pace (a), going within 20 degrees of the new
## way (b). With each: the wait to the next tick, whether the prediction
## drew it from the input's frame, when the server's tile followed, what was
## left of the step under way, how far the body went on after a stop, and
## the biggest move in one frame (a leap). At most 60 frames a second, as a
## display shows them; a frame's time is when it began.
const LAT_HOLD := 2.0
var _lat_keys := ""
var _lat := {"phase": "", "round": 0, "at": 0, "rows": [], "trail": []}
## The held cursor's offset from the camera's point (ZERO: not held).
var _lat_hold := Vector2.ZERO


func _run_test_latency() -> void:
	var player := _local_player()
	if Net.test_latency <= 0 or player == null or World.tick < 30 or _lat["phase"] == "done":
		return
	Engine.max_fps = 60
	var now := Time.get_ticks_usec()
	var drawn := Iso.local_to_grid(player.position)
	var moved: Vector2 = drawn - _lat.get("last", drawn)
	_lat["last"] = drawn
	var trail: Array = _lat["trail"]
	trail.append([now, drawn])
	while trail.size() > 2 and now - int(trail[0][0]) > 100000:
		trail.pop_front()
	var span := (now - int(trail[0][0])) / 1000000.0
	var velocity: Vector2 = (drawn - trail[0][1]) / span if span > 0.05 else Vector2.ZERO
	var ms := (now - int(_lat["at"])) / 1000.0
	var keys := Net.controls == "wasd"
	var hold := Net.test_latency_hold and not keys
	if hold and _lat_hold != Vector2.ZERO:
		var seen := drawn
		if _client3d != null:
			seen = Vector2(_client3d._camera_target.x, _client3d._camera_target.z)
		_pick_grid = seen + _lat_hold
	_lat_count(player)
	if Net.test_latency_kick:
		_run_lat_kicks(player, now, moved)
		return
	match _lat["phase"]:
		"":
			_lat["phase"] = "settle"
			_lat["at"] = now
		"settle":
			if ms > 1500.0 and moved.length() < 0.0005:
				_lat_input(player, "start", now, drawn)
				_lat_keys = "d"
				if hold:
					_lat_hold = Vector2(LAT_HOLD, 0.0)
					_pick_grid = drawn + _lat_hold
					_test_holding = true
					_move_click(player, _snap_to_floor(_pick_grid))
				elif not keys:
					_move_click(player, player.tile + Vector2i(8, 0))
				_lat_note_predicted(player)
		"start":
			_lat_watch(player, now, drawn, moved, velocity)
			if _lat["row"].has("done_ms") and ms > 1200.0:
				_lat["way"] = moved.normalized()
				_lat["facing"] = player.shown_facing().angle()
				_lat_input(player, "turn", now, drawn)
				_lat_keys = "w"
				if hold:
					_lat_hold = Vector2(0.0, -LAT_HOLD)
					_pick_grid = drawn + _lat_hold
				elif not keys:
					_move_click(player, Vector2i(drawn.round()) + Vector2i(0, -8))
				_lat_note_predicted(player)
		"turn":
			_lat_watch(player, now, drawn, moved, velocity)
			if ms > 1000.0:
				_lat_turn_done()
				_lat_input(player, "stop", now, drawn)
				_lat_keys = ""
				if hold:
					_lat_hold = Vector2.ZERO
					_test_holding = false
				elif not keys:
					_move_click(player, Vector2i(drawn.round()))
				_lat_note_predicted(player)
		"stop":
			_lat_watch(player, now, drawn, moved, velocity)
			if _lat["row"].has("shown_ms") and ms > 800.0:
				_lat["rows"].append(_lat["row"])
				_lat["round"] += 1
				if _lat["round"] >= Net.test_latency:
					_lat["phase"] = "done"
					_lat_report()
				else:
					_lat["phase"] = "settle"
					_lat["at"] = now
	# A phase that never shows its input (a body stuck on something): given
	# up after 4 s, kept as "never".
	if _lat["phase"] in ["start", "turn", "stop"] and ms > 4000.0:
		_lat["rows"].append(_lat["row"])
		_lat["round"] += 1
		_lat_keys = ""
		_lat_hold = Vector2.ZERO
		_test_holding = false
		_lat["phase"] = "done" if _lat["round"] >= Net.test_latency else "settle"
		_lat["at"] = now
		if _lat["phase"] == "done":
			_lat_report()


## --test-latency=N,kick: walks east, then west after each push, holding
## the key while the server's --test-kicks pushes it back across its way.
## A push is the frames drawn going against the key held, from the first
## until 0.4 s without one; with each: the cells slid, the biggest move in a
## frame, the own body's corrections, and the times the view turned with
## the key again and then back with the slide (a rubber band).
func _run_lat_kicks(player: Player, now: int, moved: Vector2) -> void:
	if _lat["phase"] == "":
		_lat["phase"] = "kick"
		_lat["dir"] = 1.0
		_lat["at"] = now
		_lat_keys = "d"
	var own: Variant = player.free_view
	var corrections: int = own.corrections if own != null else 0
	var along: float = moved.x * float(_lat["dir"])
	var row: Dictionary = _lat.get("row", {})
	if row.is_empty():
		if along < -0.02:
			_lat["row"] = {"at": now, "last": now, "slid": -along, "leap": moved.length(), "frames": 1,
					"bands": 0, "resumed": false, "corrections": corrections}
		elif (now - int(_lat["at"])) / 1000.0 > 10000.0:
			_lat["phase"] = "done"
			print("[latency] kick: no push seen in 10 s")
		return
	row["frames"] += 1
	row["leap"] = maxf(float(row["leap"]), moved.length())
	if along < -0.002:
		row["slid"] += -along
		row["last"] = now
		if row["resumed"]:
			row["bands"] += 1
			row["resumed"] = false
	elif along > 0.002:
		row["resumed"] = true
	if now - int(row["last"]) > 400000:
		row["corrections"] = corrections - int(row["corrections"])
		row["ms"] = (int(row["last"]) - int(row["at"])) / 1000.0
		_lat["rows"].append(row)
		_lat["row"] = {}
		_lat["at"] = now
		_lat["dir"] = -float(_lat["dir"])
		_lat_keys = "d" if float(_lat["dir"]) > 0.0 else "a"
		if _lat["rows"].size() >= Net.test_latency:
			_lat["phase"] = "done"
			_lat_keys = ""
			var bands := 0
			for each: Dictionary in _lat["rows"]:
				bands += int(each["bands"])
				print("[latency] kick %d: slid %.2f cells over %.0f ms (%d frames), leap %.3f cells, %d own corrections, %d rubber bands" % [
						_lat["rows"].find(each), each["slid"], each["ms"], each["frames"], each["leap"], each["corrections"], each["bands"]])
			print("[latency] kicks: %d, rubber bands %d" % [_lat["rows"].size(), bands])


## --test-kicks=S,v..., the authority: every S seconds each player walking
## free is pushed back across its way, as a blow from ahead and aside, at the
## next of the speeds given.
var _test_kick_at := 0
var _test_kicks_given := 0


func _run_test_kicks() -> void:
	if Net.test_kicks <= 0.0 or not Net.is_authority():
		return
	var now := Time.get_ticks_msec()
	if now - _test_kick_at < Net.test_kicks * 1000.0:
		return
	_test_kick_at = now
	var speeds: Array[float] = Net.test_kick_speeds if not Net.test_kick_speeds.is_empty() else [2.0]
	var speed: float = speeds[_test_kicks_given % speeds.size()]
	for entity in World.get_entities():
		if entity is Player and entity.spawned and not (entity as Player).free_state.is_empty() 				and entity.free_way.length() > 0.01 and entity.free_kick_path.is_empty():
			var back := -entity.free_way.normalized()
			World._push(entity, entity, back + back.orthogonal() * 0.5, speed)
			_test_kicks_given += 1
			print("[kicks] pushed %s at %.1f from %s" % [entity.name, speed, entity.free_pos])



## same tile and bounces off"): the own body's corrections, those with the
## own companion within a cell, and swaps with her (679).
func _lat_count(player: Player) -> void:
	var her: GridEntity = null
	for entity in World.get_entities():
		if _is_own_companion(entity) and entity.spawned:
			her = entity
			break
	var total: int = Net.stats.corrections_total
	var seen: int = _lat.get("corrections_seen", total)
	if total > seen:
		_lat["corrections"] = int(_lat.get("corrections", 0)) + total - seen
		if her != null and World.distance(her.tile, player.tile) <= 1:
			_lat["corrections_near"] = int(_lat.get("corrections_near", 0)) + total - seen
	_lat["corrections_seen"] = total
	if her != null:
		if _lat.has("her_was") and player.tile == _lat["her_was"] and her.tile == _lat["me_was"] and player.tile != _lat["me_was"]:
			_lat["swaps"] = int(_lat.get("swaps", 0)) + 1
		_lat["her_was"] = her.tile
		_lat["me_was"] = player.tile
	_lat["companion"] = her != null


## An input of [param kind] given now: its row, with the parts known now.
func _lat_input(player: Player, kind: String, now: int, drawn: Vector2) -> void:
	if _lat.has("row") and _lat["phase"] != "settle":
		_lat["rows"].append(_lat["row"])
	var row := {"kind": kind, "round": _lat["round"], "from": drawn, "tile": player.tile, "frames": 0,
			"tick_wait_ms": (1.0 - World.tick_alpha) * World.TICK_DT * 1000.0}
	var prediction: Variant = player.get("_prediction")
	if prediction != null and prediction.is_active():
		var step: Variant = prediction._current()
		row["step_left_ms"] = maxf(step.start + step.duration - prediction._clock, 0.0) * World.TICK_DT * 1000.0
	_lat["row"] = row
	_lat["phase"] = kind
	_lat["at"] = now


## Right after the input's command: whether the prediction has a walk to draw from this frame on.
func _lat_note_predicted(player: Player) -> void:
	var prediction: Variant = player.get("_prediction")
	_lat["row"]["predicted"] = prediction != null and prediction.is_active()


func _lat_watch(player: Player, now: int, drawn: Vector2, moved: Vector2, velocity: Vector2) -> void:
	var row: Dictionary = _lat["row"]
	var ms := (now - int(_lat["at"])) / 1000.0
	row["frames"] += 1
	row["leap"] = maxf(float(row.get("leap", 0.0)), moved.length())
	if not row.has("server_ms") and player.tile != row["tile"]:
		row["server_ms"] = ms
	var pace := World.TICK_RATE / player.move_ticks
	match row["kind"]:
		"start":
			if not row.has("shown_ms") and drawn.distance_to(row["from"]) > 0.02:
				row["shown_ms"] = ms
				row["shown_frames"] = row["frames"]
			if row.has("shown_ms") and not row.has("done_ms") and velocity.length() >= 0.8 * pace:
				row["done_ms"] = ms
		"turn":
			var way: Vector2 = _lat["way"]
			if not row.has("shown_ms"):
				var off_way := moved.length() > 0.001 and absf(rad_to_deg(moved.angle_to(way))) > 15.0
				var off_facing := absf(rad_to_deg(angle_difference(player.shown_facing().angle(), float(_lat["facing"])))) > 10.0
				if off_way or off_facing:
					row["shown_ms"] = ms
					row["shown_frames"] = row["frames"]
					row["by"] = "path" if off_way else "facing"
			row.get_or_add("ways", []).append([ms, velocity])
		"stop":
			if row.has("shown_ms"):
				return
			if moved.length() < 0.0005:
				row["still"] = int(row.get("still", 0)) + 1
				if row["still"] == 1:
					row["still_ms"] = ms
					row["still_frames"] = row["frames"]
				if row["still"] >= 3:
					row["shown_ms"] = row["still_ms"]
					row["shown_frames"] = row["still_frames"]
					row["done_ms"] = row["still_ms"]
					row["moved_on"] = drawn.distance_to(row["from"])
			else:
				row["still"] = 0


func _lat_report() -> void:
	print("[latency] %s%s, %d rounds; ms from the input to the first frame showing it (frames) / to the response done, the next tick's wait, predicted from the input's frame, the server's tile after, the step under way's rest, the biggest move in a frame" % [
			Net.controls, " held" if Net.test_latency_hold and Net.controls != "wasd" else "", Net.test_latency])
	var by_kind := {}
	for row: Dictionary in _lat["rows"]:
		if not row.has("kind"):
			continue
		by_kind.get_or_add(row["kind"], []).append(row)
		print("[latency] %s %d: %s ms (%s frames)%s / done %s ms; tick wait %.0f ms; predicted %s; server %s ms; step left %s ms; leap %.3f cells%s" % [row["kind"], row["round"],
				"%.0f" % row["shown_ms"] if row.has("shown_ms") else "never", row.get("shown_frames", "-"), " by " + row["by"] if row.has("by") else "",
				"%.0f" % row["done_ms"] if row.has("done_ms") else "never",
				row["tick_wait_ms"], row.get("predicted", "?"), "%.0f" % row["server_ms"] if row.has("server_ms") else "-",
				"%.0f" % row["step_left_ms"] if row.has("step_left_ms") else "-", row.get("leap", 0.0),
				"; went on %.2f cells" % row["moved_on"] if row.has("moved_on") else ""])
	for kind: String in ["start", "turn", "stop"]:
		for field: String in ["shown_ms", "done_ms"]:
			var times: Array[float] = []
			var never := 0
			for row: Dictionary in by_kind.get(kind, []):
				if row.has(field):
					times.append(row[field])
				else:
					never += 1
			times.sort()
			if not times.is_empty():
				print("[latency] %s %s: median %.0f ms, worst %.0f, best %.0f (%d, %d never)" % [kind, "shown" if field == "shown_ms" else "done",
						times[times.size() / 2], times.back(), times.front(), times.size(), never])
	print("[latency] own corrections %d (%d with her within a cell), swaps with her %d; a companion %s" % [
			_lat.get("corrections", 0), _lat.get("corrections_near", 0), _lat.get("swaps", 0), "seen" if _lat.get("companion", false) else "none"])
	var own := _free_own(_local_player())
	if own != null:
		print("[latency] free body: %d replay corrections" % own.corrections)


## The turn's response done: from the frame on which the walk goes, and
## stays, within 20 degrees of the way it settles on at the phase's end (a
## key's way is the screen's, a click's the grid's).
func _lat_turn_done() -> void:
	var row: Dictionary = _lat["row"]
	var ways: Array = row.get("ways", [])
	if ways.is_empty():
		return
	var last: Vector2 = ways.back()[1]
	if last.length() < 0.5:
		return
	for i in range(ways.size() - 1, -1, -1):
		var v: Vector2 = ways[i][1]
		if v.length() < 0.5 or absf(rad_to_deg(v.angle_to(last))) > 20.0:
			if i + 1 < ways.size():
				row["done_ms"] = ways[i + 1][0]
			return
	row["done_ms"] = ways[0][0]


## --test-steer: hold-to-move with the cursor kept three cells from the
## player and swung a quarter turn every that many seconds, as a hand
## steering does (the 3D camera following makes every frame a new target).
var _test_chase_from := -1
var _test_chase_orders := 0
var _test_chase_said := false
var _test_chase_what := "nothing in sight"
var _test_chase_order_at := 0


func _run_test_steer() -> void:
	var player := _local_player()
	if Net.test_steer <= 0.0 or player == null:
		return
	if _run_test_fight(player):
		return
	var turns: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3)]
	var turn := int(Time.get_ticks_msec() / (Net.test_steer * 1000.0)) % turns.size()
	var want := player.shown_tile() + turns[turn]
	if World.is_walkable(want) and want != _test_target:
		_test_target = want
		_move_click(player, want, false)  # 703 step 1: as a click, free or grid.


## --test-chase: hold-to-move on the nearest animal as this view draws it
## (a deer if one is in sight), the order made again whenever the cell it
## is drawn on changes, as a cursor kept on a fleeing deer does; with none
## in sight, east to find one. For that many seconds, then it stands. Its
## counts at the end: the orders given, the cells the animal was drawn on.
func _run_test_chase() -> void:
	var player := _local_player()
	if Net.test_chase <= 0.0 or player == null:
		return
	if _test_chase_from < 0:
		_test_chase_from = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _test_chase_from > Net.test_chase * 1000.0:
		if not _test_chase_said:
			_test_chase_said = true
			print("[test] chase: %d orders, %s" % [_test_chase_orders, _test_chase_what])
		return
	var prey: GridEntity = null
	var best := INF
	for entity in World.entities():
		if entity is Animal and entity.spawned:
			# A deer before anything else, then the nearest.
			var rank := World.distance(entity.tile, player.tile) 					+ (0.0 if String(entity.name).contains("deer") or str(entity.spawn_spec.get("kind", "")).contains("deer") else 1000.0)
			if rank < best:
				best = rank
				prey = entity
	var want := _test_target
	if prey != null:
		want = prey.shown_tile()
		if _test_chase_what == "nothing in sight":
			print("[test] chase: %s in sight at %.1f s" % [prey.name, (Time.get_ticks_msec() - _test_chase_from) / 1000.0])
		_test_chase_what = "chasing %s" % prey.name
	elif _test_target == World.NO_CELL or player.shown_tile() == _test_target 			or Time.get_ticks_msec() - _test_chase_order_at > 3000:
		# None in sight: one far order east, kept, to find one (an order
		# every step would turn it back and forth round whatever is there).
		for reach in range(30, 4, -1):
			if World.is_walkable(player.tile + Vector2i(reach, 0)):
				want = player.tile + Vector2i(reach, 0)
				break
	if want != _test_target and World.is_walkable(want):
		_test_chase_order_at = Time.get_ticks_msec()
		_test_target = want
		_test_chase_orders += 1
		_move_click(player, want, false)  # 703 step 1: as a click, free or grid.


## --test-fight (with --test-steer): every that many seconds, a strike at
## the nearest monster within eight tiles, as a click on it does; it is
## closed in on, and the steering waits a second for it. True while it does.
func _run_test_fight(player: Player) -> bool:
	if Net.test_fight <= 0.0:
		return false
	var now := Time.get_ticks_msec()
	if now - _test_fight_at < 1000:
		return true
	if now - _test_fight_at < Net.test_fight * 1000.0:
		return false
	var nearest: GridEntity = null
	for entity in World.monsters():
		if entity.spawned and World.distance(entity.tile, player.tile) <= 8 \
				and (nearest == null or World.distance(entity.tile, player.tile) < World.distance(nearest.tile, player.tile)):
			nearest = entity
	if nearest == null:
		return false
	_test_fight_at = now
	World.command_attack(player, nearest)
	return true


## --test-walk: the keys of the entry being held, or "" once all are done.
func _test_walk_keys() -> String:
	if _local_player() == null:
		return ""
	if _walk_index == -1:
		if Net.test_walk_on_wind and not _wind_walk_started(_local_player()):
			return ""
		_walk_index = 0
		_walk_since = Time.get_ticks_msec()
	while _walk_index < Net.test_walk.size() \
			and Time.get_ticks_msec() - _walk_since >= Net.test_walk[_walk_index]["seconds"] * 1000.0:
		_walk_since += roundi(Net.test_walk[_walk_index]["seconds"] * 1000.0)
		_walk_index += 1
	if _walk_index >= Net.test_walk.size():
		return ""
	return Net.test_walk[_walk_index]["keys"]


## --test-smooth: this frame as drawn, to the meter. Main runs after the
## entities and the 3D view, so it sees the frame as it is shown. The camera
## is the 3D view's aim, or headless where the 3D camera would aim: the
## player as drawn, through the same easing (client3d/camera_ease.gd).
func _measure_smoothness(delta: float) -> void:
	if not Net.test_smooth or Net.is_authority():
		return
	var player := _local_player()
	if player == null:
		return
	if _smooth_meter == null:
		Engine.max_fps = 60
		_smooth_meter = preload("res://net/smooth_meter.gd").new()
	var drawn := Iso.local_to_grid(player.position)
	var eased: Vector3 = _smooth_camera.follow(Vector3(drawn.x, 0.0, drawn.y), delta)
	var aim := Vector2(eased.x, eased.z)
	if _client3d != null:
		aim = Vector2(_client3d._camera_target.x, _client3d._camera_target.z)
	_smooth_meter.sample(player, aim, delta)


## --test-foe: [param player] given the weapon in hand and the monster 3
## cells east (392 amended's wind-up on a real client).
func _test_foe(player: Player) -> void:
	if Net.test_foe.size() != 2:
		return
	World.set_slots(player, Items.tidy(["", "", "", "", Net.test_foe[1], ""], Items.CARRIED))
	var foe := _spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": Net.test_foe[0], "name": "Foe",
		"tile": _nearest_free(player.tile + Vector2i(3, 0))})
	print("[test] foe %s at %s, %s in hand at %s" % [Net.test_foe[0], foe.tile if foe != null else Vector2i.ZERO,
			Net.test_foe[1], player.tile])


## --test-walk-on-wind: true once the local player's own wind-up has begun;
## logs each winding (start and give-up) and each hurt from then on.
func _wind_walk_started(player: Player) -> bool:
	if not player.winding.is_connected(_on_test_wind):
		player.winding.connect(_on_test_wind)
		player.damaged.connect(func(amount: int) -> void: print("[test] wind-walk hurt %d at %d ms" % [amount, Time.get_ticks_msec()]))
	if _wind_at < 0:
		_run_test_fight(player)  # --test-fight: strike till the wind-up begins.
	return _wind_at >= 0


func _on_test_wind(_direction: Vector2i, ticks: int) -> void:
	var player := _local_player()
	print("[test] wind-walk winding ticks=%d at %d ms, shown %s" % [ticks, Time.get_ticks_msec(),
			Iso.local_to_grid(player.position) if player != null else Vector2.ZERO])
	if ticks > 0 and _wind_at < 0:
		_wind_at = Time.get_ticks_msec()


func _record_walk(player: Player) -> void:
	if not Net.test_walk.is_empty() and _walk_index != -1:
		_walk_samples.append([Time.get_ticks_msec(), Iso.local_to_grid(player.position)])
		if Net.test_walk_on_wind and _walk_samples.size() % 6 == 1:
			print("[test] wind-walk %d ms after: shown %s keys %s" % [Time.get_ticks_msec() - _wind_at,
					Iso.local_to_grid(player.position), _test_walk_keys()])


## --test-walk's report: the shown speed over the walk, frame by frame
## (cells per second), leaving out the first and last 150 ms, where the
## walk speeds up from and slows to a stand.
func _report_walk() -> void:
	if _walk_samples.size() < 3:
		return
	var first: int = _walk_samples[0][0]
	var last: int = _walk_samples.back()[0]
	var speeds: Array[float] = []
	var labels: Array[String] = []
	for i in range(1, _walk_samples.size()):
		var at: int = _walk_samples[i][0]
		var dt := (at - int(_walk_samples[i - 1][0])) / 1000.0
		if dt <= 0.0 or at - first < 150 or last - at < 150:
			continue
		var moved: float = (_walk_samples[i][1] as Vector2).distance_to(_walk_samples[i - 1][1])
		if moved > 0.0 or speeds.size() > 0:
			speeds.append(moved / dt)
			labels.append("%d ms at %s" % [at - first, _walk_samples[i][1]])
	while not speeds.is_empty() and speeds.back() == 0.0:
		speeds.pop_back()
		labels.pop_back()
	if speeds.is_empty():
		print("[test] walk: no motion")
		return
	var stops := 0
	var total := 0.0
	var slow_at: Array[String] = []
	for i in speeds.size():
		total += speeds[i]
		if speeds[i] < 1.0:
			stops += 1
			slow_at.append(labels[i])
	print("[test] walk: frames=%d speed min=%.2f max=%.2f mean=%.2f cells/s, frames under 1 cell/s=%d %s, ends at %s" % [
		speeds.size(), speeds.min(), speeds.max(), total / speeds.size(), stops, slow_at, _walk_samples.back()[1]])


## --test-exit-on: reports once that file exists (the test script makes it
## when what it waits for is in the logs) and quits. A client in the game
## first sees TEST_EXIT_SETTLE_TICKS more ticks (10 s at most), so what was
## just decided reaches it, and after reporting stays until the file
## "<path>.quit" exists (30 s at most), so the other clients' reports are
## made before anyone leaves their view.
func _exit_on_file() -> void:
	while not FileAccess.file_exists(Net.test_exit_on):
		await get_tree().create_timer(0.25).timeout
	var in_game := not Net.is_authority() and Net.online and _local_player() != null
	if in_game:
		var until := World.tick + TEST_EXIT_SETTLE_TICKS
		var deadline := Time.get_ticks_msec() + 10000
		while World.tick < until and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
	if _test_exiting:
		return
	_test_exiting = true
	_report_test()
	if in_game:
		var deadline := Time.get_ticks_msec() + 30000
		while not FileAccess.file_exists(Net.test_exit_on + ".quit") and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.25).timeout
	_release_zones()
	Net.shutdown()
	get_tree().quit()


func _on_test_exit() -> void:
	if _test_exiting:
		return
	_test_exiting = true
	_report_test()
	_release_zones()
	Net.shutdown()
	get_tree().quit()


## Godot asks before it quits for a window closed or a SIGTERM (systemctl
## stop): the zones go cleanly then too.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release_zones()


## The world saved, then every zone's entities freed while their spawners
## are still in the tree, before the tree goes (decision 299). A
## MultiplayerSpawner tracks each node it spawned by a one-shot tree_exiting
## connection; one that leaves the tree with nodes still tracked disconnects
## each, and on the box (Linux; not on Windows) every such disconnect fails:
## an ERROR an entity, some 60 on each exit, which stage.sh refuses. Freed
## here, each entity's leaving untracks it first, and a spawner leaves with
## nothing. The sim stops first, so nothing reaches for them after.
func _release_zones() -> void:
	if _released:
		return
	_save_state()
	_released = true
	# Nothing runs from here (the sim, a host's views): they would reach for
	# what is about to be freed.
	get_tree().paused = true
	World.set_process(false)
	set_process(false)
	# A host's 3D view answers each entity's going at once (not on its own
	# frame), reading the rest: it goes first.
	if _client3d != null:
		_client3d.free()
		_client3d = null
	for holder in $YSort/Entities.get_children():
		for entity in holder.get_children():
			entity.free()


## What a test reads at the end: the walk, where everything is, who holds what.
func _report_test() -> void:
	_report_walk()
	if _smooth_meter != null:
		print(_smooth_meter.report())
		print(_smooth_meter.bodies_report())
		print("[smooth] rtt %.0f ms, %s" % [Net.rtt_ms(), Net.stats.client_text()])
	if Net.screenshot_path != "":
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(Net.screenshot_path)
		print("[test] screenshot %s: %s" % [Net.screenshot_path, "saved" if error == OK else error_string(error)])
	print("[test] final tick=%d entities=%d occupancy_consistent=%s" % [
		World.tick, World.get_entities().size(), World.is_occupancy_consistent()])
	if Net.test_ui_cost:
		print(UiCost.report())
	var player := _local_player()
	if player != null and not Net.is_authority():
		print("[test] display: %s server_tile=%s shown_tile=%s mispredicts=%d snaps=%d color=%s" % [
			player.name, player.tile, player.shown_tile(), Net.mispredicts_total, Net.snaps_total,
			player.tint.to_html(false)])
	# This peer's view of where everything is, for comparing across instances.
	var tiles: Array[String] = []
	for entity in World.get_entities():
		tiles.append("%s=%s" % [entity.name, entity.tile])
	tiles.sort()
	print("[test] tiles: %s" % " ".join(tiles))
	var held: Array[String] = []
	for entity in World.get_entities():
		if entity is Chest or entity is Player:
			held.append("%s=[%s]" % [entity.name, ",".join(Array(entity.slots).filter(
				func(item: String) -> bool: return not item.is_empty()))])
	held.sort()
	print("[test] slots: %s" % " ".join(held))

