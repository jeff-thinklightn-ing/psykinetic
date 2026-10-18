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
const ITEM_KEYS := {KEY_F: "pick_up", KEY_G: "drop", KEY_T: "throw"}
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
const RESIDENT_ASK_TICKS := 150
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
const SPAWN_SAFE_DISTANCE := 5
## Ticks a newly spawned player is ignored by monsters, unless it moves or
## attacks first.
const SPAWN_GRACE_TICKS := 30
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
## For RESPAWN_ARRIVAL_TICKS (10 s) after a player joins or comes into the
## zone, nothing comes back within this many tiles of them.
const RESPAWN_JOIN_DISTANCE := 12
const RESPAWN_ARRIVAL_TICKS := 100
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
## Builder mode on this client (B): selecting, asking, the ghost.
var _builder_ui: BuilderUI
## Server only: everyone who has ever joined, by player_id. Saved in the
## snapshot, so a player comes back where they left off, in their colour.
var _records: Dictionary[String, PlayerRecord] = {}
## Server only: peer id -> tick at which its dead player comes back.
var _respawn_at: Dictionary[int, int] = {}
## Server only: player_id -> that player's live companion.
## The world map the towns' buildings are read from (_sync_residents).
var _world_map: WorldMap
## Residents' voices (decision 336): one mind for them all, made on first
## use; the asks waiting for it ({body: instance id, ask, at: tick}), one per
## resident; the ask out, by serial.
var _resident_mind: CompanionMind
var _resident_asks: Array[Dictionary] = []
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
## Peer -> the tick its player was last put down (a join, a zone entered, a
## respawn): the wider no-respawn radius while RESPAWN_ARRIVAL_TICKS last.
var _arrived_at: Dictionary[int, int] = {}
## Camp place id -> the tick it was first seen undefended with a player in
## it (decision 429); not saved, so a restart starts the clock again.
var _camp_clear_since: Dictionary[String, int] = {}
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

## The 3D view (the default; see Net.renderer); the 2D nodes are hidden.
var _client3d: Client3D
## Town id -> {kind: {state, level}}: the towns' buildings as the server
## last told ("town", decision 297), for the view's buildings.
var town_states := {}
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
## Esc's panel (PausePanel), the main menu (MainMenu) while it shows, and
## the join flow's screen (ConnectScreen) while it shows; null otherwise.
var pause_panel: PausePanel
var main_menu: MainMenu
var connect_screen: ConnectScreen
## _go_online was called (Play once; Change server reconnects instead).
var _went_online := false
## The connect screen shows the join in progress: it goes once the player is in.
var _connect_joining := false
## The last tick this view saw, for F3.
var _hud_tick := 0
## The hint over what the cursor is on ("E  open"), outlined, by the cursor.
var _context_hint: Label
## --test-show=hint: the thing the hint is shown on, as if the cursor were on it.
var _test_hint_thing: GridEntity
## The player's pack, and an open chest or companion's pack (I; a right
## click on a chest or your companion).
var pack_panel: PackPanel
## The map of the zone you are in: a corner one always, the big one on M (decision 321).
var minimap: Minimap
## Items' icons for the pack panel (none drawn headless).
var item_icons: ItemIcons
## An open shop's goods, and the player's gold over the pack (ShopPanel).
var shop_panel: ShopPanel
## The menus' sounds (UiSounds).
var ui_sounds: UiSounds
## The local player's gold, as the server last said ("shop" messages).
var gold := 0
## The last "counter" message, for ui's counter screen (decision 438).
var counter_data := {}
signal counter_told(data: Dictionary)
## A chest or companion right-clicked from afar: opened once in reach.
var _pack_wanted: GridEntity
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
	_load_level(Net.map_name if not Net.map_name.is_empty() else Level.DEFAULT_MAP)
	if Net.renderer == "3d" and Net.mode != Net.Mode.SERVER and DisplayServer.get_name() != "headless":
		_show_3d()
	GridEntity.draws_2d = _draws_2d()
	_paint_level()
	# The minimap was made (_build_talk) before there was a level, and a
	# host's boot draws this map no more (_view_zone): drawn here.
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
				_towns_near.erase(place_id))
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


## Play: online, by way of the connect screen for a client (the first run
## fills in the server's details first).
func _play() -> void:
	if main_menu != null:
		main_menu.visible = false
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


## The main menu over everything (MainMenu), made the first time.
func _show_menu() -> void:
	if main_menu == null:
		main_menu = MainMenu.new()
		main_menu.play_pressed.connect(_play)
		main_menu.options_pressed.connect(toggle_options)
		main_menu.quit_pressed.connect(_quit_game)
		add_child(main_menu)
	main_menu.visible = true
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
		return str(result.get("why", "no answer"))
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
		World.braced_against.connect(_narrate_brace)
		World.item_named.connect(_narrate_named)
		World.item_kept.connect(_narrate_kept)
		World.item_grew.connect(_narrate_grew)
		World.bundle_swapped.connect(_narrate_swap)
		World.shield_bashed.connect(_narrate_bash)
		World.entity_bumped.connect(_on_bumped)
		World.entity_died.connect(_on_entity_died)
		World.entity_taken.connect(_on_entity_taken)
		World.command_received.connect(_on_command)
		World.slots_changed.connect(_on_slots_changed)
		World.ground_changed.connect(_on_ground_changed)
		World.gold_changed.connect(_on_gold_changed)
		World.traded.connect(_on_traded)
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
	_measure_smoothness(delta)
	_show_home_zone()
	_follow_player(delta)
	if _client3d != null and DisplayServer.get_name() != "headless":
		# Alt shows every HP bar; the view only reads it.
		_client3d.show_all_bars = Input.is_key_pressed(KEY_ALT)
	_drag_yaw()
	_drive_camera_keys(delta)
	_update_pick()
	_test_hover()
	_drive_wasd()
	if not _stance.is_empty() and Net.controls != "wasd" and _local_player() != null:
		_aim_at_cursor(_local_player())  # A raised shield or a drawn bow turns to the cursor.
	_check_bandage_hold()
	_run_test_steer()
	# Hover is the floor cell under the cursor, on the ground plane alone:
	# nothing standing on the map intercepts it. In 3D a monster a click
	# would attack is outlined instead, and the cell is not shown.
	var tile := _mouse_tile()
	if _client3d != null:
		var foe := _foe_under_mouse()
		_client3d.target(foe)
		_client3d.hover(tile, foe == null and World.is_walkable(tile))
	else:
		cursor.visible = World.is_walkable(tile)
		cursor.position = Iso.tile_to_local(tile)
		cursor.polygon = PackedVector2Array([Iso.project(Vector2(-0.5, 0.5)), Iso.project(Vector2(-0.5, -0.5)),
				Iso.project(Vector2(0.5, -0.5)), Iso.project(Vector2(0.5, 0.5))])
	_retarget_held()
	_update_pack()
	if compass != null:
		compass.north_on_screen = screen_north()
		compass.place = place_text(_local_player())
	if _context_hint != null:
		var words := ""
		if not is_typing() and DisplayServer.get_name() != "headless":
			words = context_hint_for(_entity_under_mouse())
			if words.is_empty():
				words = context_hint_for(_door_under_mouse())
			if words.is_empty():
				# A prop on the cell under the cursor (the pick ray finds bodies, not chests).
				var under := _mouse_tile()
				for entity in World.get_entities():
					if entity.spawned and entity.tile == under and (entity is Chest or entity is Cargo or entity is Companion):
						words = context_hint_for(entity)
						break
			if words.is_empty() and _local_player() != null and not World.ground_at(_mouse_tile()).is_empty():
				words = "F  pick up"
		var at := get_viewport().get_mouse_position()
		if is_instance_valid(_test_hint_thing) and _client3d != null:
			# --test-show=hint: the hint as the cursor on that thing would show it.
			words = context_hint_for(_test_hint_thing)
			at = _client3d.screen_of_tile(_test_hint_thing.tile)
		_context_hint.visible = not words.is_empty()
		if not words.is_empty():
			_context_hint.text = words
			_context_hint.reset_size()
			_context_hint.position = at + Vector2(28.0, 28.0)
	if debug_overlay.visible:
		debug_overlay.text = _debug_text()
	_update_toss_aim()
	_poll_console()
	_count_down_restart()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if is_typing():
		return
	if _builder_ui != null and _builder_ui.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB:
		talk.toggle_pin()
		return
	if key != null and key.pressed and not key.echo and minimap != null \
			and (key.keycode == KEY_M or key.keycode == KEY_ESCAPE and minimap.big):
		minimap.toggle()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		escape()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_open_chat()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		debug_overlay.visible = not debug_overlay.visible
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F11:
		Net.toggle_fullscreen()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_H:
		toggle_hints()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_O:
		toggle_options()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_I:
		toggle_pack()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		# A command like any other, so it works from a client too; the
		# authority decides. With no player to send it for (dead, respawning)
		# only the authority's own window can still do it.
		var me := _local_player()
		if me != null:
			World.command(me, "reset", {})
		elif Net.is_authority():
			_start_level()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_L:
		var holder := _local_player()
		if holder != null:
			World.command(holder, "lantern", {})
		return
	if key != null and not key.echo and key.keycode == KEY_E:
		if key.pressed:
			_press_e()
		elif _e_held:
			_release_e()
		return
	if key != null and key.pressed and not key.echo and ITEM_KEYS.has(key.keycode):
		item_key(ITEM_KEYS[key.keycode])
		return
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_4:
		say_phrase(key.keycode - KEY_0)
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
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
				_begin_middle_drag(Vector2(DisplayServer.mouse_get_position()))
			elif not is_nan(_drag_from.x):
				_end_middle_drag()
		return
	var player := _local_player()
	if player == null:
		_toss_target = null
		_held_target = NONE
		return
	if click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		_lower_off_hand(player)
		_release_toss(player)
		return
	if click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		_held_target = NONE
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
	# Right: the off hand (decision 329): a shield raised, a bow drawn, while
	# held; empty-handed it shoves and tosses (below). Opening and
	# bandaging are E's (_press_e). Left: a chest is walked to.
	if click.button_index == MOUSE_BUTTON_RIGHT and _raise_off_hand(player):
		return
	if click.button_index == MOUSE_BUTTON_LEFT and target is Chest:
		_walk_to_chest(player, target)
		return
	var targetable := target != null and target != player and World.can_target(player, target)
	if Net.controls == "wasd" and not on_sprite:
		_wasd_click(player, click.button_index)
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			# A creature: go to it and attack. Anything else: walk there (and
			# push), to the nearest floor if the click was off it. Your own
			# companion is walked into, not hit: she steps aside.
			if targetable and target.is_creature() and not _is_own_companion(target):
				World.command_attack(player, target)
			else:
				_move_click(player, tile if target != null else _snap_to_floor(_mouse_grid()))
		MOUSE_BUTTON_RIGHT:
			# Any entity: go to it and shove. Sent on release, so that
			# dragging first can aim it.
			if targetable:
				_toss_target = target
				_toss_from = get_global_mouse_position()


## The right button pressed: what the off hand holds is raised (a
## "stance" command: a shield's block, a bow's draw), true; false with
## nothing for it, and the press shoves as ever.
func _raise_off_hand(player: Player) -> bool:
	_stance = World.off_hand(player)
	if _stance.is_empty():
		return false
	_toss_target = null
	World.command(player, "stance", {"kind": _stance})
	return true


## The right button released: a drawn bow is loosed at the cell under the
## cursor ("loose"), a raised shield lowered.
func _lower_off_hand(player: Player) -> void:
	if _stance == "draw":
		var at := _mouse_tile()
		World.command(player, "loose", {"at": [at.x, at.y]})
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
	var door := _e_door
	if is_instance_valid(door) and player.tile in Terrain.edge_cells(door.key):
		World.command(player, "door", {"edge": [door.key.x, door.key.y, door.key.z]})


## E held BANDAGE_HOLD_MSEC: a bandage command, on the player or companion
## under the cursor if it is beside you, else on yourself.
func _check_bandage_hold() -> void:
	if not _e_held or Time.get_ticks_msec() - _e_since < BANDAGE_HOLD_MSEC:
		return
	_e_held = false
	var player := _local_player()
	if player == null:
		return
	var patient: GridEntity = player
	var target := _e_target
	if is_instance_valid(target) and (target is Player or target is Companion) \
			and World.can_melee(player.tile, target.tile):
		patient = target
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
	_client3d.setup(_terrain, level_centre)
	_client3d.bubbles = bubbles
	_show_towns()


# --- WASD ---------------------------------------------------------------------------

## The grid direction WASD keys point at a camera yaw: [param keys] is
## (D - A, W - S); W is up the screen, D to its right. Eight directions;
## ZERO for none. At yaw 0, the 2D view's, W is (-1, -1).
static func wasd_direction(keys: Vector2, yaw_degrees: float) -> Vector2i:
	var yaw := deg_to_rad(yaw_degrees)
	# Up the screen is away from the camera along the ground; see
	# Client3D._camera_offset, which puts the camera on the +x +z side.
	var up := Vector3(-1, 0, -1).rotated(Vector3.UP, yaw)
	var right := Vector3(1, 0, -1).rotated(Vector3.UP, yaw)
	var along := up * keys.y + right * keys.x
	return grid_direction(Vector2(along.x, along.z))


## The nearest of the eight directions to [param vector] (grid units),
## or ZERO for a vector too short to point anywhere.
static func grid_direction(vector: Vector2) -> Vector2i:
	if vector.length() < 0.01:
		return Vector2i.ZERO
	var angle := snappedf(vector.angle(), PI / 4.0)
	return Vector2i(roundi(cos(angle)), roundi(sin(angle)))


## The movement keys held, as letters ("wd"), from the keyboard or from
## --test-walk while it runs.
func _held_key_names() -> String:
	return _held_letters([KEY_W, KEY_A, KEY_S, KEY_D])


## Which of [param keys] are held, as lower-case letters, from the
## keyboard or from --test-walk while it runs (which may name any).
func _held_letters(keys: Array[Key]) -> String:
	if not Net.test_walk.is_empty():
		return _test_walk_keys()
	if is_typing():
		return ""
	var held := ""
	if DisplayServer.get_name() != "headless":
		for key in keys:
			if Input.is_physical_key_pressed(key):
				held += OS.get_keycode_string(key).to_lower()
	return held


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


## The middle button went down at [param at] (screen px). What it is
## waits on which way, if any, it moves.
func _begin_middle_drag(at: Vector2) -> void:
	_drag_from = at
	_drag = Drag.UNDECIDED


## The drag is [param offset] (screen px) from where it went down. In the
## click scheme it pans the view, which springs back onto the player when
## let go; in WASD it is a turn or a pitch peek by the axis it first moves on.
func _middle_drag(offset: Vector2) -> void:
	if _drag == Drag.PAN:
		_client3d.pan_by(offset)
		return
	if _drag == Drag.UNDECIDED:
		if absf(offset.x) < DRAG_AXIS_PX and absf(offset.y) < DRAG_AXIS_PX:
			return
		if Net.controls == "click":
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


## Click scheme, 3D: W/S tilt (W up toward top-down, S toward level) and
## A/D turn the camera while held; letting go springs the tilt back and
## settles the turn on a diamond (saved). The keys do nothing else in this
## scheme (and nothing at all in 2D); Q/E are unbound.
func _drive_camera_keys(delta: float) -> void:
	if _client3d == null or Net.controls != "click":
		return
	var keys := _held_letters([KEY_W, KEY_A, KEY_S, KEY_D])
	var tilt := float("w" in keys) - float("s" in keys)
	var turn := float("d" in keys) - float("a" in keys)
	if tilt != 0.0:
		_client3d.tilt(tilt, delta)
		_tilting = true
	elif _tilting:
		_tilting = false
		_client3d.end_tilt()
	if turn != 0.0:
		_client3d.turn(turn, delta)
		_turning = true
	elif _turning:
		_turning = false
		_client3d.end_turn()


func _view_yaw() -> float:
	return _client3d.yaw if _client3d != null else 0.0


## WASD each frame: while a direction is held, the next step goes as the
## one on screen ends (and any click walk is dropped); standing still,
## the body faces the cursor.
func _drive_wasd() -> void:
	var player := _local_player()
	if player == null or Net.controls != "wasd":
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
	var direction := wasd_direction(key_vector(keys), _view_yaw())
	_record_walk(player)
	if direction == Vector2i.ZERO:
		_aim_at_cursor(player)
		return
	player.aim = Vector2.ZERO
	_held_target = NONE
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
	World.command_step(player, direction)


## WASD, standing still: the body turns to the cursor on this screen at
## once, and the facing others see follows, a few times a second at most.
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
func _move_click(player: Player, tile: Vector2i) -> void:
	_pack_wanted = null
	_held_target = tile
	if tile == NONE:
		return
	World.command_move(player, tile)
	if _client3d != null:
		_client3d.ripple(tile)
	else:
		ripple.start(Iso.tile_to_local(tile))


## Left button held after a move click: when the cursor reaches another
## cell, that is the new target, with its own ripple. Brought onto a
## monster, the hold is an attack on it instead (and ends): walking for the
## ground under it would go round it.
func _retarget_held() -> void:
	if _held_target == NONE or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
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
	var tile := _snap_to_floor(_mouse_grid())
	if tile != NONE and tile != _held_target:
		_move_click(player, tile)


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


## The player this peer's input controls, or null (dedicated server, dead,
## or not spawned yet).
func _local_player() -> Player:
	for entity in World.get_entities():
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
	_terrain = loaded["terrain"]
	level_entities.assign(loaded["entities"])
	_index_keys()
	player_starts.assign(loaded["starts"])
	level_centre = loaded["centre"]
	_level_stamps[map_name] = _level_stamp(map_name)
	print("[level] %s: %d cells, %d entities, %d starts, %d links" % [map_name, _terrain["floor"].size(),
		level_entities.size(), player_starts.size(), loaded["links"].size()])
	return true


## Server: zone [param zone_name] read again from its level (edited in the
## game: Level reads the overlay first) and rebuilt as "zone reset" does,
## but not healed: the players stay where they are, everything else is
## spawned again. Everyone in it is sent the new terrain. Nothing if the
## zone is not open (it reads the edited level when it opens).
func reload_zone(zone_name: String) -> void:
	if not Net.is_authority() or not World.zones.has(zone_name):
		return
	var was := World.enter_named(zone_name)
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


## Draws the terrain afresh in both views (a map loaded live).
func _repaint() -> void:
	_paint_level()
	if minimap != null:
		minimap.rebuild(level)
	if _client3d != null:
		_client3d.rebuild(_terrain, level_centre)
		_show_towns()


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
	# Who holds which place: as the levels start them, then as the snapshot
	# left them, on the world's clock.
	var world_map := WorldMap.build()
	World.holdings = Holdings.new(world_map, Factions.read(), snapshot.get("holdings", {}), func() -> int: return World.steps)
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
	World.towns.building_changed.connect(_on_town_building_changed)
	# The roofs storms broke and nobody has mended yet (decision 383).
	World.roofs_damaged.clear()
	for key: Variant in snapshot.get("roofs", []):
		World.roofs_damaged[str(key)] = true
	if not World.roof_changed.is_connected(_on_roof_changed):
		World.roof_changed.connect(_on_roof_changed)
	# The buildings the maps already have, for towns with no record of them.
	World.towns.seed_from(world_map)
	_world_map = world_map
	# Raid groups (decision 328): off until switched on (--raids, the console).
	World.raid_groups = WorldRaids.new(world_map, World.holdings, World.towns, snapshot.get("raid_groups", {}))
	World.raid_groups.clock = func() -> int: return World.steps
	World.raid_groups.live = func(area: String) -> bool: return World.zones.has(area) and (World.zones[area] as Zone).awake
	# A hungry camp raids sooner, for food (decision 410): how well it ate,
	# from the herds (made below, so read when asked).
	World.raid_groups.fed = func(camp_id: String) -> float: return World.herds.camp_fed(camp_id) if World.herds != null else 1.0
	World.raid_groups.hook(World.raids)
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
	# Wells and roofs (decision 426): a town's are its level's.
	World.towns.wells = func(town: String) -> int:
		var area: Dictionary = _world_map.areas.get(town.get_slice("/", 0), {})
		return (area.get("buildings", []) as Array).filter(func(house: Dictionary) -> bool:
			return str(house.get("slot", "")) == "building.well").size()
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
	# Residents' trade (decision 353): the inn's bed while it stands, and
	# players in a town's zone told how many it feeds.
	World.economy.building_stands = func(town: String, kind: String) -> bool:
		return World.towns.building(town, kind).get("state") == Towns.STANDING
	World.economy.dole_changed.connect(_on_dole_changed)
	# The fallen come back at a temple or a healer's hut (decision 396).
	World.production.returned = _on_returned
	if not World.production.work_done.is_connected(_on_counter_work_done):
		World.production.work_done.connect(_on_counter_work_done)
	_seat_healers()
	# Raiders come into a played zone as its level's monsters do.
	World.spawn_spec = _spawn
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
	World.keepers.erase(_herds_kept)
	_herds_kept = World.herds
	World.keepers.append(World.herds)
	# A town's hunter takes from its area's herds near its store (decision 407).
	World.production.hunt = func(town: String) -> String:
		var place := World.holdings.place(town)
		var cell: Vector2i = place.get("cell", Vector2i.ZERO)
		return World.herds.hunt_one(str(place.get("area", town.get_slice("/", 0))), cell) if World.herds != null else ""
	# A beaten raid's companion captives come back (decision 314).
	World.companion_freed = companion_freed
	_records.clear()
	for record: PlayerRecord in snapshot["players"]:
		_records[record.player_id] = record
	var saved: Dictionary = snapshot["zones"]
	var restored := 0
	for zone_name: String in saved:
		if not Level.exists(zone_name):
			print("[state] the snapshot's zone %s is no map here; left out" % zone_name)
			continue
		_open_zone(zone_name, saved[zone_name])
		restored += saved[zone_name]["entities"].size()
	_open_zone(default_zone())
	if snapshot["ok"]:
		print("[state] loaded %d entities and %d player records from %s (zones: %s)" % [
			restored, snapshot["players"].size(), Net.state_path, ", ".join(saved.keys())])
	World.enter(World.zones[default_zone()])
	if Net.mode != Net.Mode.SERVER:
		_admit(Net.local_id, Net.player_id, Net.player_name)


## Loads zone [param zone_name] if it is not loaded yet: its map, its doors,
## its level entities (as [param saved], a snapshot's section for it, has
## them, if it does). Zones stay loaded. Null for a map that is not there.
func _open_zone(zone_name: String, saved := {}) -> Zone:
	if World.zones.has(zone_name):
		return World.zones[zone_name]
	if not Level.exists(zone_name):
		return null
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
	_restore_ground(saved.get("ground", []))
	print("[zone] %s loaded%s" % [zone_name, " from the snapshot" if not saved.is_empty() else ""])
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
		_repaint()
		camera.position = Iso.tile_to_local(level_centre)
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
	_repaint()
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
	Net.message_to(peer, "map", {"name": zone_name, "server": Net.version})
	Net.message_to(peer, "sky", sky_message())
	_send_towns(peer, zone_name)
	Net.message_to(peer, "roofs", {"level": zone_name, "damaged": World.damaged_roofs(zone_name)})
	World.update_visibility(peer, zone_name)


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
		if pet.stays_put():
			_stay_in_town(record, pet)
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
	print("[zone] %s went from %s to %s" % [record.name, from_name, to_map])
	party_log.add("%s went to %s." % [record.name, str(level.get("display_name", to_map))])
	World.enter(World.home())
	return true


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
	for link: Dictionary in level.get("links", []):
		if link["tile"] == to:
			print("[level] %s took the link at %s to %s (%s)" % [_display_name(entity), to, link["to_map"], link["to_spawn"]])
			# After the tick: not mid-step.
			travel.call_deferred(entity.owner_peer, str(link["to_map"]), str(link["to_spawn"]))
			return


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
func _spawn_doors() -> void:
	var edges: Dictionary = _terrain["edges"]
	for key: Vector3i in edges:
		if edges[key] == Terrain.Edge.DOOR:
			Net.interest.add(spawner.spawn({"script": DOOR, "name": "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"],
				"edge": [key.x, key.y, key.z], "zone": World.zone.name,
				"props": {"max_hp": 20, "body_material": GridEntity.BodyMaterial.WOOD}}))


# --- Server: level and players ------------------------------------------------

## (Re)builds the zone World is in, from its level: the R restart, and
## the console's reset and zone reset. Removing the old entities and spawning
## new ones replicates to its clients through its spawner. With
## [param from_snapshot], entities (and every player record) come from the
## --state file when it has this zone; otherwise the room starts whole
## ([param whole]): its players healed and dead companions back. Everyone in
## the zone keeps their place; nobody in another zone is touched.
func _start_level(from_snapshot := false, whole := true) -> void:
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
	World.reset()
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
	var saved := {}
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
	# Monsters kept as records stay records, holding their slots (and their
	# things) till someone comes near (decision 352); none before them.
	if World.herds != null:
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
	for entry: Dictionary in saved:
		var spec := _level_spec_for(entry["spec"])
		var entity := _spawn(spec)
		if entity == null:
			continue
		World.restore(entity, entry["hp"], entry["stamina"], entry["facing"])
		if entry.get("slots") != null:
			World.set_slots(entity, entry["slots"], entry.get("items", []))
	# Slots with no entity and a saved timer are dead: pick their timers up.
	for respawn: Dictionary in section.get("respawns", []):
		var dead := _slot_for(int(respawn["spawn"]), str(respawn.get("spawn_key", "")))
		if dead >= 0 and not _alive_slots.has(dead) and not recorded.has(dead):
			_dead_since[dead] = World.tick - (RESPAWN_DELAY_TICKS - respawn["ticks_left"])
	# Slots with neither are new in the level since the save (every dead
	# slot's timer is saved): there now, or dead from now if their tile is taken.
	for slot in level_entities.size():
		if not _alive_slots.has(slot) and not _dead_since.has(slot) and not recorded.has(slot):
			print("[state] %s is new in the level since the save" % level_entities[slot]["name"])
			if _spawn(_slot_spec(slot)) == null:
				_dead_since[slot] = World.tick
	return true


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
func _slot_spec(slot: int) -> Dictionary:
	var spec: Dictionary = level_entities[slot].duplicate(true)
	spec["spawn"] = slot
	spec["spawn_key"] = _key_of(slot)
	return spec


## Each level entity's key by slot, and each key's slot (decision 433),
## made once as the level is read (_index_keys) and swapped with the zone.
var _slot_keys := PackedStringArray()
var _key_slots: Dictionary[String, int] = {}


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


## Brings dead level entities back: after RESPAWN_DELAY_TICKS, with no player
## within RESPAWN_MIN_DISTANCE of the spawn tile (RESPAWN_JOIN_DISTANCE of
## one just put down), onto a free tile; one a zone every
## RESPAWN_STAGGER_TICKS, the farthest from every player first (decision
## 382). A record (decision 352) is no dead slot, so never one of them. With
## [param force], all at once regardless of time and distance. Returns how
## many.
func _check_respawns(tick: int, force := false) -> int:
	var zone_name: String = World.zone.name if World.zone != null else ""
	if not force and _respawned_at.has(zone_name) and tick - _respawned_at[zone_name] < RESPAWN_STAGGER_TICKS:
		return 0
	var due: Array[Array] = []  # [steps from the nearest player, slot, spec]
	for slot: int in _dead_since.keys():
		if not force and tick - _dead_since[slot] < RESPAWN_DELAY_TICKS:
			continue
		var spec := _slot_spec(slot)
		var tile: Vector2i = spec["tile"]
		if not World.is_free(tile) or not _camp_lets_back(spec):
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
		if away <= RESPAWN_MIN_DISTANCE or arrived and away <= RESPAWN_JOIN_DISTANCE:
			return -1
		nearest = mini(nearest, away)
	return nearest


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
				"ticks_left": maxi(RESPAWN_DELAY_TICKS - (World.tick - _dead_since[slot]), 0)})
		for entity in World.get_entities():
			World.slot_uids(entity)  # A chest's things get their instances before the book is saved.
			if int(entity.spawn_spec.get("spawn", -1)) >= 0:
				level_held += 1
				keyed += 1 if str(entity.spawn_spec.get("spawn_key", "")) != "" else 0
		var ground: Array[Dictionary] = []
		for cell: Vector2i in each.ground:
			ground.append({"cell": [cell.x, cell.y], "items": Array(each.ground[cell]), "ids": Array(World.ground_at(cell))})
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
		"roofs": World.roofs_damaged.keys(),
		"raid_groups": World.raid_groups.to_dict() if World.raid_groups != null else {},
		"economy": World.economy.to_dict() if World.economy != null else {},
		"herds": World.herds.to_dict() if World.herds != null else {},
		"items": World.items.to_dict(),
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
	if Net.is_authority() and World.steps % SNAPSHOT_EVERY_TICKS == 0:
		_save_state(false)
	if Net.is_authority() and World.steps % World.WORLD_TICK_STEPS == 0:
		# The clients' clocks, kept from drifting off the world's.
		Net.broadcast("sky", sky_message())


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
	# Routes still being made on pool tasks would crash a server on its way out.
	if World.raid_groups != null:
		World.raid_groups.finish()
	if World.richness != null:
		World.richness.finish()
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
	var back := known and not respawn
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
		"peer": peer, "tint": record.color, "label": player_name,
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
	_fell_at.erase(peer)
	print("[net] %s (%s) joined as %s at %s%s" % [
		player_name, id.left(8), player.name, tile, " (back)" if back else ""])
	party_log.add("%s joined." % player_name)
	_join_companion(record, player)
	_on_gold_changed(id, World.gold_of(id))


# --- Towns -----------------------------------------------------------------------

## Server: a town's building was unlocked, built, raised, damaged or
## repaired (Towns.building_changed): every peer, and this one, is told the
## town's buildings ("town" {town, buildings}).
func _on_town_building_changed(town: String, _kind: String) -> void:
	Net.broadcast("town", {"town": town, "buildings": World.towns.buildings_of(town)})
	World.open_roofs(town.get_slice("/", 0))


## Server: a roof of [param level] was damaged or mended (World.damage_roof,
## repair_roof, decision 383): every peer, and this one, is told the level's
## damaged roofs ("roofs" {level, damaged: their indices}).
func _on_roof_changed(level: String) -> void:
	Net.broadcast("roofs", {"level": level, "damaged": World.damaged_roofs(level)})
	_show_towns()


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


## Server: [param peer], come to [param zone_name], is told the buildings of
## each town there.
func _send_towns(peer: int, zone_name: String) -> void:
	if World.towns == null:
		return
	for town: String in World.towns.to_dict():
		if town.begins_with(zone_name + "/"):
			Net.message_to(peer, "town", {"town": town, "buildings": World.towns.buildings_of(town)})


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
	for peer: int in _peer_ids:
		if _peer_ids[peer] == id:
			Net.message_to(peer, "shop", {"gold": gold})


## Server: [param by] traded at [param shop], or was refused ([param why]):
## they are sent the shop again, and the refusal.
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
		data["goods"] = World.economy.goods(place)
		data["offers"] = World.economy.offers(place, Array(player.slots))
	Net.message_to(player.owner_peer, "shop", data)


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

## Gives [param player] its record's companion: a new one on first join,
## spawned adjacent; the remembered one, where it was, if it is alive; none
## if it died. A companion that is already in the world (its owner was away)
## just gets its owner back.
func _join_companion(record: PlayerRecord, player: Player) -> void:
	if not Net.companions:
		return
	# Carried off by raiders (decision 314): held till she is freed.
	if record.companion.has("taken"):
		print("[net] %s's companion %s is held by raiders (%s); none spawned" % [record.name, record.companion.get("name", "?"),
			record.companion["taken"].get("by", "?")])
		Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": "%s was carried off by raiders and is held by them still." % [
			record.companion.get("name", "Your companion")]})
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
			# Told where she is, so she does not read as lost.
			var town := str(resident.get("zone", ""))
			var town_name := str(Level.load_level(town).get("display_name", town)) if Level.exists(town) else town
			Net.broadcast_to([player.owner_peer], "party", {"from": "Server", "text": "%s is %s in %s. Go there to travel together again." % [
				record.companion.get("name", "Your companion"), "working" if not str(resident.get("trade", "")).is_empty() else "resting", town_name]})
			return
		if World.towns != null:
			World.towns.note_companion_out(str(resident.get("place", "")), String(record.companion["name"]))
		record.companion.erase("resident")
		party_log.add("%s leaves her work in the town and goes with %s." % [record.companion["name"], record.name])
		# Her body in town goes; she comes as herself (decision 333 amended).
		for body: GridEntity in World.townsfolk().duplicate():
			if (body as Resident).player_id == record.player_id:
				_travelling = true
				World.despawn(body)
				_travelling = false
	var existing: Companion = _companions.get(record.player_id)
	if is_instance_valid(existing) and existing.spawned:
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
	pet.talk.assign(record.companion.get("talk", []))
	pet.facts_changed.connect(_on_facts_changed.bind(pet, record))
	pet.restore_said(record.companion.get("said", []))
	World.set_slots(pet, record.companion.get("slots", []), record.companion.get("items", []))
	pet.party_log = party_log
	pet.home = record.companion.get("home", {})
	pet.mind = _make_mind()
	if _claude_voices.has(record.player_id):
		pet.mind = ClaudeMind.new(pet.mind, _claude_voices[record.player_id], self)
	pet.mind.warm()  # The model loads now, not on her first ask.
	pet.write_card()  # Once: a plain card stands until it is written.
	pet.said.connect(_on_companion_said.bind(pet))
	if int(record.companion.get("hp", 0)) > 0:
		World.restore(pet, int(record.companion["hp"]), int(record.companion.get("stamina", pet.max_stamina)), pet.facing)
	_companions[record.player_id] = pet
	print("[net] %s's companion %s is at %s%s" % [
		record.name, pet.name, tile, " (new)" if is_new else ""])


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
					wanted[each["key"]] = each
		# The healer's hut (decision 404): whoever economy seats there (the
		# medicine man, a worker whose town is the hut's place id) has a body
		# at the hut as a town's folk have theirs, only while someone is near.
		for place_id: String in World.holdings.places_in(World.zone.name):
			var place := World.holdings.place(place_id)
			if place.get("kind") != "healers_hut" or not _town_near(place_id, place):
				continue
			var cell: Vector2i = place.get("cell", Vector2i.ZERO)
			var hut := Rect2i(cell - Vector2i.ONE, Vector2i(3, 3))
			for building: Dictionary in area.get("buildings", []):
				var rect: Rect2i = building.get("rect", Rect2i())
				if str(building.get("slot", "")) == "building.healers_hut" and rect.grow(1).has_point(cell):
					hut = rect
			var ids := World.production.worker_ids(place_id).filter(func(who: String) -> bool:
				return not who.begins_with("companion:") and not bool(World.production.worker(who).get("away", false)))
			for who: String in ids:
				if wanted.size() >= RESIDENTS_MAX:
					break
				var trades: Array = World.production.worker(who).get("trades", [])
				wanted[who] = {"key": who, "name": str(World.production.worker(who).get("name", who)),
					"trade": str(trades[0]) if not trades.is_empty() else "", "player": "", "town": place_id,
					"type": str(World.production.worker(who).get("type", "")),
					"places": {"work": hut, "home": hut, "square": Rect2i(cell - Vector2i(2, 2), Vector2i(5, 5))}}
	var have := {}
	for entity: GridEntity in World.townsfolk().duplicate():
		var body := entity as Resident
		if wanted.has(body.worker_id):
			have[body.worker_id] = true
			body.places = wanted[body.worker_id]["places"]
		else:
			_travelling = true
			World.despawn(body)
			_travelling = false
	for who: String in wanted:
		if not have.has(who):
			_spawn_resident(wanted[who])


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
		if body.doing == Resident.Doing.HIDE or d > HEARING_RANGE:
			continue
		if not body.person.is_empty() and Companion._named(line, body.person):
			return body
		if d <= RESIDENT_EARSHOT and (nearest == null or d < World.distance(nearest.tile, player.tile)):
			nearest = body
	return nearest


## Server: [param body] is asked [param line] by [param speaker]: an ask
## waits for the resident mind, replacing one of theirs still waiting.
func _ask_resident(body: Resident, speaker: String, line: String) -> void:
	_write_resident_card(body)
	_resident_serial += 1
	var id := body.get_instance_id()
	_resident_asks = _resident_asks.filter(func(each: Dictionary) -> bool: return each["body"] != id)
	_resident_asks.append({"body": id, "ask": body.voice_ask(speaker, line, _resident_serial), "at": World.tick})
	Transcript.record(body.person, speaker, line)


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
			"from": from, "line": line, "at": World.tick})


## Server: [param each] (_claims_asks') sent to the resident mind, with
## what it knows and holds now.
func _send_claims(each: Dictionary) -> void:
	var body := instance_from_id(int(each["body"])) as Resident
	if body == null or not is_instance_valid(body):
		return
	_claims_at[each["worker"]] = World.tick
	_resident_serial += 1
	each["ask"] = Hearsay.claims_ask(body.person, body.world_facts(), World.production.worker(body.worker_id).get("heard", []),
		str(each["from"]), str(each["line"]), _resident_serial)
	_claims_out[_resident_serial] = each
	var answer := _resident_mind.facts(each["ask"])
	if not answer.is_empty():
		_claims_out.erase(_resident_serial)
		_claims_answered(each, answer, "")


## Server: the claims [param answer] for [param each]: each claim weighed
## by the resident's intellect (Hearsay.hear), the held ones it shows false
## no longer believed; kept on its worker record; logged.
func _claims_answered(each: Dictionary, answer: Dictionary, error: String) -> void:
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
	for claim: Variant in claims if claims is Array else []:
		if claim is Dictionary:
			var text := str(claim.get("text", ""))
			var entry := Hearsay.hear(heard, str(each["worker"]), intellect, text, str(claim.get("fits", "")),
				str(each["from"]), World.production.now(), Hearsay.is_omen(text, claim.get("omen")), superstition)
			if not entry.is_empty():
				kept.append(entry)
	var gone: Variant = answer.get("overturns", [])
	var overturned := Hearsay.overturn(heard, gone if gone is Array else [])
	if not kept.is_empty() or not overturned.is_empty():
		World.production.set_heard(str(each["worker"]), heard)
	MindLog.record({"kind": "claims", "companion": str(each["person"]), "mind": "resident", "trigger": each.get("ask", {}).get("trigger", ""),
		"heard": each["line"], "from": each["from"], "claims": claims, "kept": kept, "overturned": overturned, "intellect": intellect, "superstition": superstition,
		"error": error, "outcome": "weighed" if error.is_empty() else "not weighed"})


## A resident's answer ([param out]: the ask waited for): said from its
## body, if it is still here and the answer is words; logged either way.
func _resident_answered(out: Dictionary, answer: Dictionary, error: String) -> void:
	var ask: Dictionary = out["ask"]
	var body := instance_from_id(int(out["body"])) as Resident
	var line := Companion.trim_line(str(answer.get("say", "")).strip_edges())
	var said := body != null and is_instance_valid(body) and body.spawned and not line.is_empty() and line != "..."
	MindLog.record({"kind": "voice", "companion": str(ask.get("speaker", "")), "mind": "resident", "trigger": ask.get("trigger", ""),
		"prompt": "%s\n\n%s" % [ask.get("system", ""), ask.get("user", "")], "say": line, "error": error,
		"outcome": "said" if said else "not said"})
	if not said:
		return
	Transcript.record(body.person, body.person, line)
	party_log.add("%s said: \"%s\"" % [body.person, line])
	_heard_near(body, body.person, line)
	Net.broadcast_to(hearers(body.tile), "speech", {"entity": String(body.get_path()), "speaker": body.person, "text": line})


## A body for [param each] (_sync_residents' entry: key, name, trade,
## player, town, places), where its day puts it now.
func _spawn_resident(each: Dictionary) -> Resident:
	var who: String = each["key"]
	var town: String = each["town"]
	var places: Dictionary = each["places"]
	var trade: String = each["trade"]
	var doing := Resident.doing_now(trade, str(each.get("type", "")), who)
	var area: Rect2i = places.get(Resident.PLACE_OF[doing], places.get("square", Rect2i()))
	var at := _nearest_free(area.get_center() if area.size != Vector2i.ZERO else World.holdings.place(town).get("cell", Vector2i.ZERO))
	var label := Resident.label_of(str(each["name"]), trade)
	var body := _spawn({"script": RESIDENT, "shape": "capsule", "name": ("Resident_" + who).validate_node_name(),
		"label": label, "tile": at}) as Resident
	if body == null:
		return null
	body.worker_id = who
	body.player_id = each["player"]
	body.person = str(each["name"])
	body.town_name = str(_world_map.areas.get(World.zone.name, {}).get("display_name", World.zone.name))
	var record: PlayerRecord = _records.get(each["player"])
	body.card = str(record.companion.get("card", "")) if record != null else ""
	body.town = town
	body.trade = trade
	body.type = str(each.get("type", ""))
	body.places = places
	body.doing = doing
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
		World.towns.note_companion_out(str(resident.get("place", "")), String(record.companion.get("name", "")))
	record.companion.erase("resident")
	record.companion["taken"] = {"by": by, "zone": World.zone.name if World.zone != null else "", "at": World.steps}
	record.companion["tile"] = null
	print("[raids] %s's companion %s is held by %s" % [record.name, record.companion.get("name", "?"), by])
	return true


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
	var pet_name := str(record.companion.get("name", "?"))
	var town := ""
	if not place.is_empty() and World.holdings != null and not World.holdings.place(place).is_empty():
		var trade := str(record.companion.get("traits", {}).get("trade", ""))
		var zone := str(World.holdings.place(place).get("area", ""))
		record.companion["resident"] = {"place": place, "zone": zone, "trade": trade}
		record.companion["home"] = record.companion["resident"].duplicate()
		if not trade.is_empty() and World.towns != null:
			World.towns.note_companion_in(place, pet_name, trade, player_id)
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


func _stay_in_town(record: PlayerRecord, pet: Companion) -> bool:
	if World.towns == null or World.holdings == null or record.companion.is_empty():
		return false
	var pet_name := String(record.companion.get("name", pet.name))
	var place := Stockpile.place_at(World.holdings, World.zone.name, pet.tile)
	var trade := str(record.companion.get("traits", {}).get("trade", ""))
	if place.is_empty() or trade.is_empty():
		return false
	World.towns.note_companion_in(place, pet_name, trade, record.player_id)
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
func _rest_in_town(record: PlayerRecord, pet: Companion, id: String) -> bool:
	if World.towns == null or World.holdings == null:
		return false
	var place := ""
	var places := World.holdings.places_of(Stockpile.TOWN)
	places.sort()
	for each in places:
		if World.holdings.place(each).get("kind") == Stockpile.KIND:
			place = each
			break
	if place.is_empty():
		return false
	var pet_name := String(record.companion.get("name", pet.name))
	var trade := str(record.companion.get("traits", {}).get("trade", ""))
	if not trade.is_empty():
		World.towns.note_companion_in(place, pet_name, trade, record.player_id)
	record.companion["resident"] = {"place": place, "zone": str(World.holdings.place(place).get("area", "")), "trade": trade}
	record.companion["home"] = record.companion["resident"].duplicate()
	record.companion["tile"] = null  # Wherever she rests: beside her player when they come.
	_travelling = true  # She leaves; she does not die.
	World.despawn(pet)
	_travelling = false
	_companions.erase(id)
	print("[town] %s's companion %s rests in %s between trips" % [record.name, pet_name, place])
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
	record.companion["alive"] = true
	record.companion["said"] = pet.said_lines()
	record.companion["slots"] = Array(pet.slots)
	record.companion["items"] = Array(World.slot_uids(pet))


## "say" {text}: chat, typed or a quick phrase (_player_said).
## "reset": rebuild the room, as the console's reset does. From the
## authority's own player always; from anyone else only while
## Net.player_reset is on.
func _on_command(entity: GridEntity, command_name: String, args: Dictionary) -> void:
	if command_name == "say" and entity is Player:
		_player_said(entity, str(args.get("text", "")), int(args.get("phrase", 0)))
	elif command_name == "party" and entity is Player:
		_party_said(entity, str(args.get("text", "")))
	elif command_name == "bandage" and entity is Player:
		var patient := get_node_or_null(NodePath(str(args.get("target", "")))) as GridEntity
		if patient != null:
			World.try_bandage(entity, patient)
	elif command_name == "use" and entity is Player:
		World.try_use(entity, int(args.get("slot", -1)))
	elif command_name == "stance" and entity is Player:
		World.try_stance(entity, str(args.get("kind", "")))
	elif command_name == "loose" and entity is Player:
		var at: Variant = args.get("at")
		if at is Array and (at as Array).size() == 2:
			World.try_loose(entity, Vector2i(int(at[0]), int(at[1])))
	elif command_name in ["pick_up", "drop", "throw"] and entity is Player:
		_item_command(entity, command_name, args)
	elif command_name == "lantern" and entity is Player:
		(entity as Player).toggle_lantern()
	elif command_name == "swing" and entity is Player:
		var swing := _direction_arg(args)
		if swing != Vector2i.ZERO:
			World.order_swing(entity, swing)
	elif command_name == "face":
		var facing := _direction_arg(args)
		if facing != Vector2i.ZERO:
			World.face(entity, facing)
	elif command_name == "transfer":
		var from := get_node_or_null(NodePath(str(args.get("from", "")))) as GridEntity
		var to := get_node_or_null(NodePath(str(args.get("to", "")))) as GridEntity
		if from != null and to != null:
			World.try_transfer(entity, from, int(args.get("from_slot", -1)), to, int(args.get("to_slot", -1)))
	elif command_name == "door":
		var edge: Variant = args.get("edge")
		if edge is Array and edge.size() == 3:
			World.try_toggle_door(entity, Vector3i(int(edge[0]), int(edge[1]), int(edge[2])))
	elif command_name == "shop" and entity is Player:
		var shop := get_node_or_null(NodePath(str(args.get("shop", "")))) as GridEntity
		if shop == null or not World.reaches(entity, shop):
			return
		if str(args.get("do", "")) == "buy":
			World.try_buy(entity, shop, int(args.get("uid", 0)))  # Answered by traded.
		else:
			_send_shop(entity as Player, shop)
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
	elif command_name == "reset" and entity is Player:
		var who := _display_name(entity)  # The rebuild frees the entity.
		if not Net.player_reset and entity.owner_peer != Net.local_id:
			print("[world] %s asked for a reset; players may not (--no-player-reset)" % who)
			return
		print("[world] %s reset the room" % who)
		_start_level()
		party_log.add("%s reset the room." % who)
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
	$HUD.add_child(options_panel)
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
		elif key != null and key.pressed and key.keycode == KEY_TAB:
			# The channel swapped, the cursor kept: Tab never leaves the box.
			_swap_chat_channel()
			_chat_box.accept_event())
	talk.set_box(_chat_box)
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


## What the keys do on [param thing] under the cursor (an entity or a
## door), for the context hint: "" for nothing to say. The owners' verbs
## (items' E and F, doors' E).
func context_hint_for(thing: Node) -> String:
	var player := _local_player()
	if thing == null or player == null:
		return ""
	if thing is Chest:
		return "E  open the shop" if (thing as Chest).shop else "E  open"
	if thing is Cargo:
		return "E  open"
	if thing is Door:
		return "E  open or close"
	if thing is Companion:
		return "E  her pack" if _is_own_companion(thing) else ""
	if thing is Monster and World.can_target(player, thing):
		return "LMB  attack"
	if thing is Player and thing != player:
		return "E hold  bandage"
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
	return _chat_box != null and _chat_box.visible or _builder_ui != null and _builder_ui.is_typing()


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


## The latest blow (_narrate_damage): who was struck and by whom, so a
## death right after it knows its killer (decision 332).
var _blow_target: GridEntity = null
var _blow_source: GridEntity = null


## Server: a creature or a breakable thing was killed. Every view hears of
## it ("death"), with what it was and where, since its node goes at once;
## a companion says a last line.
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


## Server: [param player] said [param text] (the chat box). At most
## CHAT_MAX_CHARS, one line per CHAT_INTERVAL; to everyone as chat, into
## the party log, and to their companion as a decision, the words as data.
## A whisper ("/w words") carries WHISPER_RANGE, not HEARING_RANGE; a line in
## capitals is a shout, heard farther by monsters (Senses.speech_radius).
func _player_said(player: Player, text: String, phrase := 0) -> void:
	var line := text.strip_edges().left(CHAT_MAX_CHARS)
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
		_ask_resident(resident, _display_name(player), line)
		if hears:
			pet.overheard(_display_name(player), line, false)
	elif to != "":
		pet.owner_spoke(line, phrase)


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
	if kind == "terrain":
		_on_terrain(data)
		return
	if kind == "town":
		var town := str(data.get("town", ""))
		var buildings: Variant = data.get("buildings", {})
		if not town.is_empty() and buildings is Dictionary:
			town_states[town] = buildings
			World.towns_seen[town] = buildings
			World.open_roofs(town.get_slice("/", 0))
			if _client3d != null:
				_client3d.set_town(town, buildings)
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
	if kind == "shop":
		_on_shop_message(data)
	elif kind == "counter":
		_on_counter_message(data)
		return
	if kind == "map":
		# The zone this client's player is in: it draws and predicts on that
		# map, and its entities arrive under that zone's node.
		var wanted := str(data.get("name", ""))
		Net.server_version = str(data.get("server", Net.server_version))
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
		talk.add_line(str(data.get("from", "")), str(data.get("text", "")), true, true)
		return
	if kind == "speech":
		var entity := get_node_or_null(NodePath(str(data.get("entity", "")))) as GridEntity
		var speaker := str(data.get("speaker", entity.name if entity != null else "?"))
		print("[speech] %s: %s" % [speaker, data.get("text", "")])
		talk.add_line(speaker, str(data.get("text", "")))
		if entity != null:
			bubbles.show_line(entity.get_instance_id(), str(data.get("text", "")))


## A name for the party log: players by record name, residents by the label
## over their head ("Bram [smith]"), everything else by its node name.
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
			party_log.add("%s holds a grudge against %s." % [thing, kinds])
		"avenged":
			party_log.add("%s has had its vengeance on %s." % [thing, kinds])


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
		if record != null and not _stay_in_town(record, pet) and CompanionCard.is_legacy(str(record.companion.get("name", ""))):
			_rest_in_town(record, pet, id)
	print("[net] %s (%s) left" % [record.name if record != null else "?", id.left(8)])
	party_log.add("%s left." % (record.name if record != null else "someone"))


## A player that dies comes back after RESPAWN_TICKS, as long as its peer is
## still here. Placeholder rule so the test room stays usable.
func _on_entity_despawned(entity: GridEntity) -> void:
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


## A place changed hands (Holdings.place_taken): a camp's fall frees who it
## held (Towns.camp_taken, decision 428).
func _on_place_taken(id: String, from: String, to: String) -> void:
	if World.towns != null and World.holdings.place(id).get("kind") == "camp":
		World.towns.camp_taken(id, from, to)


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
		for id: String in World.holdings.all_places():
			if World.holdings.place(id).get("kind") != kind or not World.production.workshop(id).is_empty():
				continue
			var who := "%s:%s" % [trade, id]
			var name := str(names[absi(hash(id)) % names.size()]) if not names.is_empty() else trade.capitalize()
			World.production.add_worker(who, name, [trade], id, "wilds")
			World.production.add_workshop(id, trade, id)
			World.production.assign(id, who)
			print("[return] %s the %s keeps %s" % [name, trade.replace("_", " "), id])


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
func _return_place(cell: Vector2i) -> Dictionary:
	if World.holdings == null or World.production == null:
		return {}
	var kinds: Array[String] = []
	kinds.assign(World.production.rules.get("return", {}).get("places", {}).keys())
	var routes: WorldRoutes = World.raid_groups.routes if World.raid_groups != null else null
	var tries: Array = [kinds]
	for kind in kinds:
		var one: Array[String] = [kind]
		tries.append(one)
	for each: Array[String] in tries:
		var id := World.holdings.nearest(each, World.zone.name, cell, routes)
		var shop := _return_workshop(id) if not id.is_empty() else ""
		if not shop.is_empty() and World.production.manned(shop):
			return {"place": id, "workshop": shop}
	return {}


## [param who] ([param kind]: player (their id), companion (her player's),
## resident (the worker)), fallen at [param cell], to be brought back at
## the nearest manned place: true if a return job was opened.
func _start_return(who: String, kind: String, cell: Vector2i) -> bool:
	if who.is_empty() or not returns:
		return false
	var at := _return_place(cell)
	return not at.is_empty() and World.production.open_return(at["workshop"], who, kind, at["place"]) != 0


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
	match str(job.get("who_kind", "")):
		"player":
			var record: PlayerRecord = _records.get(who)
			if record == null:
				return
			var peer := _peer_of(who)
			if _players.has(peer):
				return  # Back already (a rejoin).
			record.hp = 0  # Full stats.
			if peer == 0:
				# Not playing now: they come in there next time.
				if cell != World.NO_CELL:
					record.zone = area
					record.tile = cell
				return
			if cell == World.NO_CELL:
				_respawn_at[peer] = World.tick
				return
			if str(World.peer_zone.get(peer, record.zone)) == area:
				World.enter_named(area)
				_join_player(peer, who, record.name, true, cell)
			else:
				travel(peer, area, "", {}, cell)
			Net.broadcast_to([peer], "party", {"from": by, "text": "%s is brought back at %s by %s." % [record.name, where, by]})
		"companion":
			var record: PlayerRecord = _records.get(who)
			if record == null or record.companion.is_empty():
				return
			var peer := _peer_of(who)
			var player: Player = _players.get(peer)
			var with_them := is_instance_valid(player) and player.spawned
			record.companion["alive"] = true
			record.companion["hp"] = 0  # Full stats.
			record.companion["tile"] = [cell.x, cell.y] if with_them and player.zone == area and cell != World.NO_CELL else null
			if with_them:
				World.enter_named(player.zone)
				_join_companion(record, player)
				if cell != World.NO_CELL:
					Net.broadcast_to([peer], "party", {"from": by, "text": "%s is brought back at %s by %s." % [
						record.companion.get("name", "Your companion"), where, by]})
		"resident":
			if World.production.worker(who).is_empty():
				return
			World.production.set_away(who, false)
			print("[return] %s is back%s" % [World.production.worker(who)["name"], "" if cell == World.NO_CELL else " at %s by %s" % [where, by]])
	World.enter(was)


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
		if tick % World.WORLD_TICK_STEPS == 0 and _world_map != null:
			# Storms break roofs (Weather.break_roofs).
			for broke: Dictionary in Weather.break_roofs(_world_map.areas, World.steps):
				print("[weather] %s broke roof %d of %s" % [broke["storm"], broke["index"], broke["level"]])
		_respawn_due_players(tick)
		_check_respawns(tick)
		if tick % CAMP_CHECK_TICKS == 0:
			_check_camps(tick)
		if tick % RESIDENT_SYNC_TICKS == 0:
			_sync_residents()
		_recall_due()
		if tick % RETIRE_EVERY_TICKS == 0:
			_retire_and_recall()
		if tick % TEMPLE_COUNTER_TICKS == 0:
			_temple_counters()
		_resident_voices()
	if World.zone != World.home():
		return  # Another zone's tick: the HUD and the test hooks are this view's.
	var player := _local_player()
	var hp_text := "no player" if Net.mode == Net.Mode.SERVER else "dead, respawning"
	if player != null:
		hp_text = "HP %d/%d" % [player.hp, player.max_hp]
		for kind: String in player.buffs:
			hp_text += "   %s +%s %ds" % [Items.BUFF_KINDS.get(kind, kind), str(snappedf(float(player.buffs[kind][0]), 0.1)),
				ceili(maxi(int(player.buffs[kind][1]) - tick, 0) * World.TICK_DT)]
		if player.raised == "block":
			hp_text += "   shield raised"
		elif player.raised == "draw":
			hp_text += "   bow drawn %d%%" % roundi(World.draw_of(player) * 100.0)
	_hud_tick = tick
	hud.text = hp_text
	if player != null and _connect_joining and connect_screen != null:
		_connect_joining = false
		connect_screen.visible = false  # In: the world shows.
	if hint_panel != null:
		hint_panel.set_lines(hint_lines())
	if player != null:
		_had_player = true
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


## The controls for the HUD's list, a line each, "key\twhat it does".
func hint_lines() -> Array[String]:
	var lines: Array[String] = []
	if Net.controls == "wasd":
		lines.append_array(["WASD\twalk", "Mouse\taim", "LMB\tattack (far: walk)", "RMB\toff hand; empty: grab (drag to toss)"])
		if _client3d != null:
			lines.append_array(["MMB drag\tturn, look up / down", "Wheel\tzoom (MMB click: 1x)"])
	else:
		lines.append_array(["LMB\tmove / attack (hold to steer)", "RMB\toff hand; empty: shove (drag to toss)"])
		if _client3d != null:
			lines.append_array(["W / S\ttilt", "A / D\tturn", "MMB drag\tpan (springs back)", "Wheel\tzoom"])
	for i in Net.phrases.size():
		lines.append("%d\t%s" % [i + 1, Net.phrases[i]])
	lines.append_array(["RMB, shield\tblock while held", "RMB, bow\tdraw; let go to shoot at the cursor",
		"E\topen a chest, crate, cart, door; your companion's pack", "I\tyour pack",
		"F\tpick up", "G\tput down (hand, else pack)", "T\tthrow at the cursor",
		"E hold\tbandage an ally beside you, else yourself (a kit, out of combat)",
		"RMB in pack\tuse it (eat, open a purse, bandage)",
		"Enter\ttalk (/w whisper)", "Tab\ttalk log", "M\tmap", "L\tlantern",
		"R\treset the room", "O\toptions", "F3\tdebug", "F11\tfullscreen", "H\thide these"])
	if Net.mode == Net.Mode.HOST:
		lines.append("B\tbuilder mode")
	return lines


## Esc: whatever is open closes first (the options, an open chest or
## companion's pack, the pause itself); with nothing open, the pause.
func escape() -> void:
	if pause_panel != null and pause_panel.visible:
		pause_panel.open(false)
	elif options_panel != null and options_panel.visible:
		toggle_options()
	elif pack_panel != null and pack_panel.other != null:
		close_other()
	elif main_menu == null or not main_menu.visible:
		if pause_panel == null:
			pause_panel = PausePanel.new()
			pause_panel.resume_pressed.connect(func() -> void: pause_panel.open(false))
			pause_panel.options_pressed.connect(toggle_options)
			pause_panel.leave_pressed.connect(_leave_game)
			pause_panel.quit_pressed.connect(_quit_game)
			$HUD.add_child(pause_panel)
		pause_panel.open(true)


## O: the options shown or hidden; hiding writes what changed.
func toggle_options() -> void:
	if options_panel != null:
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


## Opens [param target]'s row (a chest, or a companion's pack), with its sound.
func open_other(target: GridEntity) -> void:
	_pack_wanted = null
	if pack_panel != null:
		if pack_panel.other != target:
			_sound(SoundKit.opening(target), target)
		pack_panel.open(target)
	if shop_panel != null and target is Chest and (target as Chest).shop and shop_panel.shop != target:
		shop_panel.open(target)
		var player := _local_player()
		if player != null:
			World.command(player, "shop", {"shop": str(target.get_path())})


func close_other() -> void:
	_pack_wanted = null
	if pack_panel != null:
		pack_panel.open(null)
	if shop_panel != null:
		shop_panel.open(null)


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
				if not World.ground_uids(each).is_empty() and World.try_pick_up(player, each):
					return
		"drop":
			var slot := held
			if player.slots[slot].is_empty():
				slot = -1
				for i in Items.PACK:
					if not player.slots[i].is_empty():
						slot = i
			if slot >= 0:
				World.try_drop(player, slot)
		"throw":
			if cell != null:
				World.try_throw(player, held, cell)


## Server: what lay on the ground in a snapshot's zone section, back where
## it was, each thing its saved instance where the book still has it.
func _restore_ground(ground: Array) -> void:
	for pile: Dictionary in ground:
		var ids: Array = pile["ids"]
		var uids: Array = pile.get("items", [])
		for i in ids.size():
			var id := str(ids[i])
			if not Items.exists(id):
				continue
			var uid := int(uids[i]) if i < uids.size() and (uids[i] is float or uids[i] is int) else 0
			var at := World.items.at_of(uid)
			if World.items.id_of(uid) != id or not at in ["", "%s@%d,%d" % [World.zone.name, pile["cell"].x, pile["cell"].y]]:
				uid = World.items.mint(id, "migrated", "the ground", World.zone.name, pile["cell"])
			World.put_on_ground(uid, pile["cell"])


## Server: World's ground changed on [param cell] (of the zone World is
## in): its GroundPile spawned,
## changed or freed (the spawner does the same on the clients that see it).
func _on_ground_changed(_zone_name: String, cell: Vector2i, thrown_from: Vector2i) -> void:
	var ids := World.ground_at(cell)
	var pile: GroundPile = World.zone.piles.get(cell)
	if ids.is_empty():
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
		return
	var spec := {"script": PILE, "name": GroundPile.name_for(cell), "tile": [cell.x, cell.y], "zone": World.zone.name,
		"ids": Array(ids)}
	if thrown_from != World.NO_CELL:
		spec["thrown_from"] = [thrown_from.x, thrown_from.y]
		spec["thrown_tick"] = World.tick
	Net.interest.add(spawner.spawn(spec))


## The pack panel's drop: a command, so the server decides (World.try_transfer).
func _transfer(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int) -> void:
	var player := _local_player()
	if player == null:
		return
	World.command(player, "transfer", {"from": str(from.get_path()), "from_slot": from_slot,
		"to": str(to.get_path()), "to_slot": to_slot})


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
## The minimap's marks, from what is replicated: you (pointing where the
## camera looks), your companion, the other players in their tints, and the
## doors. No monsters.
func _minimap_marks() -> Array:
	var out: Array = []
	var me := _local_player()
	for entity in World.get_entities():
		if not is_instance_valid(entity) or not entity.spawned:
			continue
		if entity is Player:
			if entity == me:
				out.append({"cell": Vector2(entity.tile), "kind": "you", "facing": view_forward()})
			else:
				out.append({"cell": Vector2(entity.tile), "kind": "player", "colour": entity.tint})
		elif entity is Companion and entity.keeper_peer == Net.local_id:
			out.append({"cell": Vector2(entity.tile), "kind": "companion",
				"colour": me.tint.lightened(0.35) if me != null else Color(0.8, 0.9, 1.0)})
	for door: Door in World.get_doors():
		if is_instance_valid(door):
			out.append({"cell": Vector2(door.key.x, door.key.y), "kind": "door"})
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


## One console command; the reply is what the operator sees.
func admin_command(line: String) -> String:
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
		"help":
			return "reset | respawn | players | net | version | restart|stop [<seconds>] [<why>] | restart cancel | reload <zone>|all | raids [on|off|send <camp> <town>] | companions | zones | zone reset <name> | zone move <player> <zone> | " \
				+ "mind scripted|ollama | mind log on|off | mind last <name> | perception list|grid|both | " \
				+ "transcript <name> [<date>] | companion facts <player> | companion forget <player> <id> | save | builder | builder export | builder drop <name> | hour [<h>] | day_minutes [<m>] | season [<name>] | season_days [<n>] | weather [<kind>|auto|reload] [<minutes>] [<region>|all]"
	return "unknown command %s (try help)" % words[0]


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
		_test_ordered = true
		_test_target = player.tile + Net.test_move
		World.command_move(player, _test_target)
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
			"talk":
				talk.add_line("Wren", "(a test line) The door's barred from the other side.")
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
			"pause":
				escape()
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
	_test_contested = true
	World.command_move(player, Net.test_contest_tile)
	print("[test] contest: %s at %s ordered to %s, now showing %s" % [
		player.name, player.tile, Net.test_contest_tile, player.shown_tile()])


## --test-steer: hold-to-move with the cursor kept three cells from the
## player and swung a quarter turn every that many seconds, as a hand
## steering does (the 3D camera following makes every frame a new target).
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
		World.command_move(player, want)


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


func _record_walk(player: Player) -> void:
	if not Net.test_walk.is_empty() and _walk_index != -1:
		_walk_samples.append([Time.get_ticks_msec(), Iso.local_to_grid(player.position)])


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
		print("[smooth] rtt %.0f ms, %s" % [Net.rtt_ms(), Net.stats.client_text()])
	if Net.screenshot_path != "":
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(Net.screenshot_path)
		print("[test] screenshot %s: %s" % [Net.screenshot_path, "saved" if error == OK else error_string(error)])
	print("[test] final tick=%d entities=%d occupancy_consistent=%s" % [
		World.tick, World.get_entities().size(), World.is_occupancy_consistent()])
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
