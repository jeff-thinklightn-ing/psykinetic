extends Node
## Launch mode and ENet setup (autoload "Net").
##
##   --host                       listen server: runs the sim, has a local player (default)
##   --server                     dedicated: runs the sim, no local player, fine with --headless
##   --client --address=<ip>      connects to a server; runs no sim
##   --port=<n>                   default 7777
##   --token=<string>             server: required; a peer must send it (Net.authenticate)
##                                within 5 s or it is disconnected. host: optional; without
##                                it anyone may join (local play). client: sent on connect
##   --state=<path>               server/host: JSON snapshot of entity state, written every
##                                30 ticks and on clean shutdown, loaded on start if present
##   --admin-port=<n>             server/host: accept console commands on 127.0.0.1:<n> (TCP)
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
## writes them back).
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
##   --screenshot=<path>          save the window as PNG when --test-exit-after quits
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
##   --test-walk=<keys:secs,...>  WASD: hold these keys (e.g. w:1.5,wd:1) in turn, then let go
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
## A peer has sent a good hello and may be given a player. Main spawns
## players on this, never on peer_connected.
signal peer_authenticated(peer: int, player_id: String, player_name: String)
## Client: the server turned this peer away and said why, just before
## disconnecting it.
signal join_rejected(reason: String, server_version: String)

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
const PROTOCOL_REVISION := 10
## The scripts whose RPCs are part of the wire.
const RPC_SCRIPTS: Array[String] = ["res://net/net.gd", "res://sim/world.gd", "res://sim/grid_entity.gd", "res://sim/monster.gd"]
## Every kind of message (message, message_to, broadcast, broadcast_to).
const MESSAGE_KINDS: Array[String] = ["builder", "chat", "death", "map", "party", "shop", "sky", "speech", "terrain", "town"]
## Properties entity subclasses add with replicate().
const SUBCLASS_REPLICATED: Array[String] = ["alert", "emit_light", "keeper_peer", "mending", "move_ticks", "pose", "slots"]
const SETTINGS_FILE := "settings.cfg"
## First launch: half the 3840x2160 base, windowed.
const DEFAULT_WINDOW_SIZE := Vector2i(1920, 1080)
const WINDOW_SAVE_DELAY := 0.5
const UNKNOWN_VERSION := "0.0.0"
## The identity a host run from the project uses, so its state persists too.
const DEV_PLAYER_ID := "dev-host"
const DEFAULT_NAME := "Player"
const MAX_NAME_LENGTH := 24

## From version.txt at the project root. Sent on join; must match the server.
var version := UNKNOWN_VERSION

var mode := Mode.HOST
var address := "127.0.0.1"
var port := DEFAULT_PORT
## Snapshot file for the authority, or "" for none.
var state_path := ""
## Localhost TCP port for console commands, or 0 for none.
var admin_port := 0
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
## --still-monsters: no monster idles (they stand where they are), for tests
## that stage what they need in a real level (Monster.idling).
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
## The HUD's list of controls shown (H toggles it); settings.cfg hints=on|off.
var hints := true
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
	"renderer", "controls", "phrase1", "phrase2", "phrase3", "phrase4", "hints"]
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
var test_wait_players := 0
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
	_apply_window_settings()
	if mode == Mode.SERVER and not _mind_log_given and DirAccess.dir_exists_absolute(DEFAULT_MIND_LOG.get_base_dir()):
		mind_log_path = DEFAULT_MIND_LOG
	if mode == Mode.SERVER and not _transcripts_given and DirAccess.dir_exists_absolute(DEFAULT_TRANSCRIPTS.get_base_dir()):
		transcripts_dir = DEFAULT_TRANSCRIPTS
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
		hints = str(settings.get("hints", "on")) != "off"
	if _test_yaw_given:
		camera_yaw = test_yaw
	var window := get_window()
	window.size = window_size
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.move_to_center()
	window.size_changed.connect(_on_window_size_changed)


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
	if online:
		online = false
		get_tree().multiplayer_poll = true
		multiplayer.multiplayer_peer.close()


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
		"protocol": _test_protocol if _test_protocol != "" else protocol()})


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
			"--no-player-reset":
				player_reset = false
			"--mind-why":
				mind_why = true
			"--no-interest":
				interest.enabled = false
			"--print-protocol":
				print_protocol = true
			"--world-map":
				world_map = true
			"--builder-stub":
				builder_stub = true
			"--address", "--port", "--state", "--admin-port", "--max-players", "--token", "--settings", "--player-id", "--name", "--renderer", "--controls", \
					"--llm-url", "--llm-model", "--voice-url", "--voice-model", "--perception", "--mind-log", "--map", "--day-minutes", "--hour", "--edit", "--edit-size", "--transcripts", \
					"--builders", "--builder-model", "--builder-effort", "--builder-max-cost", \
					"--test-move", "--test-contest", "--test-reset", "--test-builder", "--test-exit-after", "--test-exit-on", "--test-wait-players", "--test-hold", "--test-version", "--test-protocol", \
					"--screenshot", "--test-hover", "--test-door", "--test-chest", "--test-click", "--test-fullscreen", "--test-azimuth", "--test-yaw", \
					"--test-lag", "--test-steer", "--test-fight", "--test-walk", "--tick-send-hz":
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
		"--test-hold":
			var hold := value.split(",")
			if hold.size() == 2:
				test_hold_tick = hold[0].to_int()
				test_hold_orders = hold[1].to_int()
		"--screenshot":
			screenshot_path = value
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
