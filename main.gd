class_name Main
extends Node2D
## Builds the test room, starts networking, and turns clicks into orders.
## This is view/input glue plus level setup: on the server it asks World and
## the MultiplayerSpawner to create entities; it never touches entity state.

const FLOOR_SOURCE := 0
const FIRE_SOURCE := 2
const DOOR := "res://sim/door.gd"
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
const MONSTER := "res://sim/monster.gd"
const PUSHABLE := "res://sim/pushable.gd"
const PLAYER := "res://sim/player.gd"
const COMPANION := "res://sim/companion.gd"
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
const COMPANION_NAMES: Array[String] = ["Pip", "Nix", "Tamsin", "Bram", "Ozzie", "Wren", "Juno", "Fenn"]
const COMPANION_CARD := "Loyal and cautious. Guards the one she travels with, and speaks little."
## Companions' cards, a paragraph each, by name; any companion not in it
## keeps the card in its record (COMPANION_CARD for a new one).
const COMPANION_CARDS := "res://levels/companions.json"
static var _cards: Dictionary[String, String] = {}
## Cards earlier builds gave every companion, which spoke of "its friend":
## a record that still has one gets COMPANION_CARD.
const OLD_COMPANION_CARDS: Array[String] = ["A loyal, cautious companion who guards its friend and speaks little.",
	"A loyal, cautious companion who guards its friend."]
const COMPANION_TINT := Color(0.45, 0.95, 0.85)
## What a companion says as she falls.
const COMPANION_DEATH_LINES: Array[String] = ["Go on... without me.", "I'm sorry.", "Tell them I tried.", "Keep... going."]
## Ticks between a player dying and reappearing at a start tile.
const RESPAWN_TICKS := 20
## A player is not put down (on respawn or on coming back) with a hostile
## this close to the intended tile; it goes to the safest start tile instead.
const SPAWN_SAFE_DISTANCE := 5
## Ticks a newly spawned player is ignored by monsters, unless it moves or
## attacks first.
const SPAWN_GRACE_TICKS := 30
## With --state, the server writes its snapshot this often.
const SNAPSHOT_EVERY_TICKS := 30
## A dead level entity (monster killed, crate broken) comes back at its spawn
## tile once this many ticks have passed since it died...
const RESPAWN_DELAY_TICKS := 600
## ...and no player is within this many tiles of that spawn tile.
const RESPAWN_MIN_DISTANCE := 6

## Server only: peer id -> that peer's player entity.
var _players: Dictionary[int, Player] = {}
## Server only: peer id -> the player_id it joined with.
var _peer_ids: Dictionary[int, String] = {}
## Server only: everyone who has ever joined, by player_id. Saved in the
## snapshot, so a player comes back where they left off, in their colour.
var _records: Dictionary[String, PlayerRecord] = {}
## Server only: peer id -> tick at which its dead player comes back.
var _respawn_at: Dictionary[int, int] = {}
## Server only: player_id -> that player's live companion.
var _companions: Dictionary[String, Companion] = {}
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
## Which mind new decisions use: "scripted" or "ollama" (console: mind ...).
var mind_kind := "scripted"
## Server only: level_entities index -> the entity holding that slot now.
var _alive_slots: Dictionary[int, GridEntity] = {}
## Server only: level_entities index -> tick its entity died or broke.
var _dead_since: Dictionary[int, int] = {}
# Server console: lines from stdin (read on a thread) and from --admin-port.
var _stdin_thread: Thread
var _stdin_mutex := Mutex.new()
var _stdin_lines: Array[String] = []
var _admin: TCPServer
var _admin_clients: Array[StreamPeerTCP] = []
var _test_target := Vector2i.ZERO
var _test_ordered := false
var _test_arrived := false
var _test_contested := false
var _test_reset_sent := false
var _test_door_sent := false
## Everything said this session (speech, last words, chat), shown with Tab.
var talk: TalkPanel
## Server: since when each player (instance id) has had no hostile near.
var _player_calm_since: Dictionary[int, int] = {}
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
## Right button held on this entity: released without a drag it is a shove,
## dragged it is a toss in the dragged direction.
var _toss_target: GridEntity
var _toss_from := Vector2.ZERO
## WASD: the camera's lean toward the cursor, in grid units (see
## CAMERA_LEAN_*).
var _lead := Vector2.ZERO
## The ground point under the cursor this frame, picked once after the
## camera has moved (see _update_pick): the hover shows it and every
## click this frame uses it, so the two always agree.
var _pick_grid := Vector2(NAN, NAN)
## 3D: the screen point a middle drag went down at (x NAN when none), and
## what it is: UNDECIDED until it has moved (let go so, in the click
## scheme, a middle click), then TURN or PITCH (WASD) or MOVED (click: a
## drag, which does nothing).
enum Drag { UNDECIDED, TURN, PITCH, MOVED }
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
## Every wall face, far and near, for turning the view.
var _walls: Array[WallEdge] = []
## Left button held after a move click: the cell it last sent the player
## to. Moving the cursor to another cell retargets; NONE when not held.
const NONE := Vector2i(-1, -1)
var _held_target := NONE

## The 3D view (the default; see Net.renderer); the 2D nodes are hidden.
var _client3d: Client3D
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
## The player's slots and an open chest's (I; a click on a chest beside you).
var slots_panel: SlotsPanel
## A chest clicked from afar: opened once the player is beside it.
var _chest_wanted: GridEntity
var _test_chest_done := false
var _test_chest_walking := false
@onready var toss_aim: Line2D = $TossAim
## The map as parsed once at start: floor, fire, edges (see Terrain).
var _terrain: Dictionary = {}


func _ready() -> void:
	# After every other node: see _process.
	process_priority = 10
	var probe := Vector2i(3, 5)
	if not ground.map_to_local(probe).is_equal_approx(Iso.tile_to_local(probe)):
		push_error("Iso math disagrees with the TileSet: %s vs %s" % [
			Iso.tile_to_local(probe), ground.map_to_local(probe)])

	near_walls.self_modulate.a = NEAR_WALL_ALPHA
	World.zone_switched.connect(_on_zone_switched)
	_build_talk()
	_load_level(Net.map_name if not Net.map_name.is_empty() else Level.DEFAULT_MAP)
	_paint_level()
	Iso.set_azimuth(Net.test_azimuth)
	_apply_azimuth()
	camera.position = Iso.tile_to_local(level_centre)
	if Net.renderer == "3d" and Net.mode != Net.Mode.SERVER and DisplayServer.get_name() != "headless":
		_show_3d()
	RenderingServer.set_default_clear_color(VOID)

	World.ticked.connect(_on_world_ticked)
	World.stepped.connect(_on_world_stepped)
	if Net.test_exit_after > 0.0:
		get_tree().create_timer(Net.test_exit_after).timeout.connect(_on_test_exit)
	if Net.test_click_after > 0.0:
		get_tree().create_timer(Net.test_click_after).timeout.connect(_test_click)
	if Net.test_fullscreen_after > 0.0:
		get_tree().create_timer(Net.test_fullscreen_after).timeout.connect(Net.toggle_fullscreen)

	if Net.needs_setup:
		# An exported client with no settings.cfg yet: ask once, then join.
		var setup := SetupScreen.new()
		setup.submitted.connect(_on_setup_submitted)
		add_child(setup)
		hud.text = "enter the server address and token"
		return
	_go_online()


func _on_setup_submitted(address: String, port: int, token: String, player_name: String) -> void:
	if not Net.save_settings(address, port, token, player_name):
		hud.text = "could not write %s" % Net.settings_path()
	Net.configure_client(address, port, token)
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
		World.entity_pushed.connect(_narrate_push)
		World.entity_damaged.connect(_narrate_damage)
		World.entity_bumped.connect(_on_bumped)
		World.entity_died.connect(_on_entity_died)
		World.command_received.connect(_on_command)
		World.slots_changed.connect(_on_slots_changed)
		if Net.llm_url != "" and Net.llm_model != "":
			mind_kind = "ollama"
		if Net.mode == Net.Mode.SERVER:
			World.entity_moved.connect(_log_player_move)
		World.entity_moved.connect(_on_entity_moved)
		_boot()
		_start_console()
	else:
		# Terrain is static level data, not replicated state. The zone's
		# entities arrive through its spawner; the server says which zone.
		_zone_nodes(map_name)
		World.mirror_reset()
		World.mirror_terrain(_terrain)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		multiplayer.connection_failed.connect(
				func() -> void: hud.text = "connection failed")
		Net.join_rejected.connect(_on_join_rejected)
	Net.message_received.connect(_on_message)


## Main processes after everything else (process_priority, set in
## _ready): the entities have placed themselves and the 3D view has moved
## its camera, so the pick below is made against the frame as drawn.
func _process(delta: float) -> void:
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
	_run_test_steer()
	# Hover is the floor cell under the cursor, on the ground plane alone:
	# nothing standing on the map intercepts it.
	var tile := _mouse_tile()
	if _client3d != null:
		_client3d.hover(tile, World.is_walkable(tile))
	else:
		cursor.visible = World.is_walkable(tile)
		cursor.position = Iso.tile_to_local(tile)
		cursor.polygon = PackedVector2Array([Iso.project(Vector2(-0.5, 0.5)), Iso.project(Vector2(-0.5, -0.5)),
				Iso.project(Vector2(0.5, -0.5)), Iso.project(Vector2(0.5, 0.5))])
	_retarget_held()
	_update_chest()
	if compass != null:
		compass.north_on_screen = screen_north()
	if debug_overlay.visible:
		debug_overlay.text = _debug_text()
	_update_toss_aim()
	_poll_console()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if is_typing():
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB:
		talk.visible = not talk.visible
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
	if key != null and key.pressed and not key.echo and key.keycode == KEY_I:
		toggle_slots()
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
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_4:
		say_phrase(key.keycode - KEY_0)
		return
	var click := event as InputEventMouseButton
	if click == null:
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
	if click.button_index == MOUSE_BUTTON_LEFT and target is Chest:
		_click_chest(player, target)
		return
	if click.button_index == MOUSE_BUTTON_RIGHT:
		var door := _door_under_mouse()
		if door != null and player.tile in Terrain.edge_cells(door.key):
			World.command(player, "door", {"edge": [door.key.x, door.key.y, door.key.z]})
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
## click scheme a drag does nothing (it is then no middle click); in WASD
## it is a turn or a pitch peek by the axis it first moves on.
func _middle_drag(offset: Vector2) -> void:
	if _drag == Drag.MOVED:
		return
	if _drag == Drag.UNDECIDED:
		if absf(offset.x) < DRAG_AXIS_PX and absf(offset.y) < DRAG_AXIS_PX:
			return
		if Net.controls == "click":
			_drag = Drag.MOVED
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
		Drag.UNDECIDED:
			# Let go without moving: a middle click, which resets the zoom.
			_client3d.reset_zoom()
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
	var floor_at := func(cell: Vector2i) -> bool: return cell in _terrain["floor"]
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
	_chest_wanted = null
	_held_target = tile
	if tile == NONE:
		return
	World.command_move(player, tile)
	if _client3d != null:
		_client3d.ripple(tile)
	else:
		ripple.start(Iso.tile_to_local(tile))


## Left button held after a move click: when the cursor reaches another
## cell, that is the new target, with its own ripple.
func _retarget_held() -> void:
	if _held_target == NONE or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_held_target = NONE
		return
	var player := _local_player()
	if player == null:
		_held_target = NONE
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
	var in_viewport: Vector2 = _client3d.screen_of_tile(Net.test_hover_tile) if _client3d != null 			else get_global_transform_with_canvas() * Iso.tile_to_local(Net.test_hover_tile)
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
func _paint_level() -> void:
	ground.clear()
	for wall in _walls:
		wall.queue_free()
	_walls.clear()
	var edges: Dictionary = _terrain["edges"]
	var kind_at := func(key: Vector3i) -> int: return edges.get(key, Terrain.Edge.OPEN)
	var fire: Array[Vector2i] = _terrain["fire"]
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
		if WallEdge.is_near(key, func(cell: Vector2i) -> bool: return cell in _terrain["floor"]):
			near_walls.add_child(wall)
		else:
			$YSort.add_child(wall)
		wall.setup(key, kind_at, WALL_VALUE)
		_walls.append(wall)


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
	player_starts.assign(loaded["starts"])
	level_centre = loaded["centre"]
	print("[level] %s: %d cells, %d entities, %d starts, %d links" % [map_name, _terrain["floor"].size(),
		level_entities.size(), player_starts.size(), loaded["links"].size()])
	return true


## Draws the terrain afresh in both views (a map loaded live).
func _repaint() -> void:
	_paint_level()
	if _client3d != null:
		_client3d.rebuild(_terrain, level_centre)


# --- Zones (server) -------------------------------------------------------------

## The zone a player with no zone of their own goes to: --map's, or the
## default map.
func default_zone() -> String:
	return Net.map_name if not Net.map_name.is_empty() and Level.exists(Net.map_name) else Level.DEFAULT_MAP


## Server start: every zone the snapshot holds, back as it was saved, and
## the default zone; the player records; and a host's own player.
func _boot() -> void:
	var snapshot := Snapshot.load(Net.state_path) if Net.state_path != "" else {"ok": false, "zones": {}, "players": []}
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
		"dead_since": _dead_since, "spawner": spawner, "entities": entities, "party_log": party_log}
	if to.main.is_empty():
		# A zone being opened: fresh state, until its level loads.
		level = {}
		level_entities = []
		player_starts = []
		_terrain = {}
		_alive_slots = {}
		_dead_since = {}
		party_log = PartyLog.new()
		return
	level = to.main["level"]
	level_entities = to.main["level_entities"]
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
	if peer == Net.local_id:
		return
	if peer in multiplayer.get_peers():
		for entity in leaving:
			if is_instance_valid(entity) and entity.sync != null and entity.is_inside_tree():
				entity.sync.update_visibility(peer)
	if not old.is_empty() and old != zone_name:
		World.update_visibility(peer, old)
	Net.message_to(peer, "map", {"name": zone_name})
	World.update_visibility(peer, zone_name)


## Server: [param peer]'s player (and their companion) go to zone
## [param to_map], at its spawn point [param to_spawn] ("" for its first
## start); nobody else moves. The zone is opened if need be. False if there
## is no such map or no such player.
func travel(peer: int, to_map: String, to_spawn := "") -> bool:
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
		World.despawn(pet)
	_travelling = false
	_players.erase(peer)
	_companions.erase(id)
	_respawn_at.erase(peer)
	World.enter(target)
	var spawns: Dictionary = level.get("spawn_points", {})
	record.tile = spawns.get(to_spawn, player_starts[0] if not player_starts.is_empty() else Vector2i.ZERO)
	record.zone = to_map
	if not record.companion.is_empty():
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


## Server: one Door node per door edge, through the spawner so every client
## gets it. Wood, 20 hp.
func _spawn_doors() -> void:
	var edges: Dictionary = _terrain["edges"]
	for key: Vector3i in edges:
		if edges[key] == Terrain.Edge.DOOR:
			spawner.spawn({"script": DOOR, "name": "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"],
				"edge": [key.x, key.y, key.z], "zone": World.zone.name,
				"props": {"max_hp": 20, "body_material": GridEntity.BodyMaterial.WOOD}})


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
	for peer in peers:
		var id: String = ids[peer]
		if id != "":
			_join_player(peer, id, _records[id].name if _records.has(id) else (Net.player_name if peer == Net.local_id
				else Net.DEFAULT_NAME))
	if not from_snapshot and whole:
		# A rebuilt room starts whole: every player at full hp and stamina.
		for player: Player in _players.values():
			if is_instance_valid(player) and player.spawned and player.zone == here:
				World.restore(player, player.max_hp, player.max_stamina, player.facing)
				var record: PlayerRecord = _records.get(_peer_ids.get(player.owner_peer, ""))
				if record != null:
					record.remember(player)


## A snapshot's section for the zone World is in ({entities, respawns}): its
## entities in the room again. False if it has none to restore.
func _spawn_saved(section: Dictionary) -> bool:
	var saved: Array = section.get("entities", [])
	if saved.is_empty() and section.get("respawns", []).is_empty():
		return false
	for entry: Dictionary in saved:
		var spec := _level_spec_for(entry["spec"])
		var entity := _spawn(spec)
		if entity == null:
			continue
		World.restore(entity, entry["hp"], entry["stamina"], entry["facing"])
		if entry.get("slots") != null:
			World.set_slots(entity, entry["slots"])
	# Slots with no entity and a saved timer are dead: pick their timers up.
	for respawn: Dictionary in section.get("respawns", []):
		if not _alive_slots.has(respawn["spawn"]):
			_dead_since[respawn["spawn"]] = World.tick - (RESPAWN_DELAY_TICKS - respawn["ticks_left"])
	# Slots with neither are new in the level since the save (every dead
	# slot's timer is saved): there now, or dead from now if their tile is taken.
	for slot in level_entities.size():
		if not _alive_slots.has(slot) and not _dead_since.has(slot):
			print("[state] %s is new in the level since the save" % level_entities[slot]["name"])
			if _spawn(_slot_spec(slot)) == null:
				_dead_since[slot] = World.tick
	return true


## What a level entity is — script, shape, tint, scale, props — always comes
## from the spawn table as it is now; a snapshot only says where it stands
## (and, separately, its hp, stamina and facing). Otherwise an entity saved by
## an older build would keep that build's looks for ever. The slot is the
## saved one, or for a snapshot from before slots, the table entry of the
## same name. Anything that is not a level entity is returned as saved.
func _level_spec_for(saved: Dictionary) -> Dictionary:
	var slot := int(saved.get("spawn", -1))
	if slot < 0 or slot >= level_entities.size():
		slot = -1
		for i in level_entities.size():
			if level_entities[i]["name"] == saved.get("name") and not _alive_slots.has(i):
				slot = i
				break
	if slot == -1 or _alive_slots.has(slot):
		return saved
	var spec := _slot_spec(slot)
	spec["tile"] = saved["tile"]
	return spec


## The spawn table entry for [param slot], tagged with its index so the
## entity can be tracked through death and respawn.
func _slot_spec(slot: int) -> Dictionary:
	var spec: Dictionary = level_entities[slot].duplicate(true)
	spec["spawn"] = slot
	return spec


## Brings dead level entities back: after RESPAWN_DELAY_TICKS, with no player
## within RESPAWN_MIN_DISTANCE of the spawn tile, onto a free tile. With
## [param force], at once regardless of time and distance. Returns how many.
func _check_respawns(tick: int, force := false) -> int:
	var count := 0
	for slot: int in _dead_since.keys():
		if not force and tick - _dead_since[slot] < RESPAWN_DELAY_TICKS:
			continue
		var spec := _slot_spec(slot)
		var tile: Vector2i = spec["tile"]
		if not World.is_free(tile):
			continue
		if not force and _player_within(tile, RESPAWN_MIN_DISTANCE):
			continue
		if _spawn(spec) == null:
			continue
		count += 1
		print("[world] respawned %s at %s" % [EntityFactory.type_name(spec), tile])
	return count


func _player_within(tile: Vector2i, distance: int) -> bool:
	for player: Player in _players.values():
		if is_instance_valid(player) and player.spawned and player.zone == World.zone.name \
				and World.distance(player.tile, tile) <= distance:
			return true
	return false


func _save_state() -> void:
	if not Net.is_authority() or Net.state_path == "":
		return
	for peer: int in _players.keys():
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.spawned and _records.has(_peer_ids.get(peer, "")):
			_records[_peer_ids[peer]].remember(player)
	for id: String in _companions.keys():
		_remember_companion(id)
	var records: Array[PlayerRecord] = []
	records.assign(_records.values())
	var zones := {}
	var was := World.zone
	for each: Zone in World.zones.values():
		World.enter(each)
		var respawns: Array[Dictionary] = []
		for slot: int in _dead_since:
			respawns.append({"spawn": slot,
				"ticks_left": maxi(RESPAWN_DELAY_TICKS - (World.tick - _dead_since[slot]), 0)})
		zones[each.name] = {"tick": World.tick, "entities": World.get_entities(), "respawns": respawns}
	World.enter(was)
	Snapshot.save(Net.state_path, zones, records)


## Once every awake zone has stepped: the snapshot, every SNAPSHOT_EVERY_TICKS.
func _on_world_stepped() -> void:
	if Net.is_authority() and World.steps % SNAPSHOT_EVERY_TICKS == 0:
		_save_state()


func _exit_tree() -> void:
	# Clean shutdown (quit, window closed): keep the last state.
	_save_state()
	# The stdin thread ends on its own once stdin is closed; join it then. One
	# still blocked on a live terminal cannot be joined and is left to die.
	if _stdin_thread != null and _stdin_thread.is_started() and not _stdin_thread.is_alive():
		_stdin_thread.wait_to_finish()


func _spawn(spec: Dictionary) -> GridEntity:
	spec["zone"] = World.zone.name
	var entity := spawner.spawn(spec) as GridEntity
	if not World.spawn(entity, spec["tile"]):
		entities.remove_child(entity)
		entity.queue_free()
		return null
	if spec.has("spawn"):
		_alive_slots[spec["spawn"]] = entity
		_dead_since.erase(spec["spawn"])
	return entity


## Gives [param peer] the player its [param id] stands for: back where that
## player left off if the server has seen the id before (nearest free tile
## if its own is taken), fresh at a start tile if not. [param respawn] is a
## death: known player, but a start tile and full stats.
func _join_player(peer: int, id: String, player_name: String, respawn := false) -> void:
	var record: PlayerRecord = _records.get(id)
	var known := record != null
	if not known:
		record = PlayerRecord.new()
		record.player_id = id
		record.index = _records.size() + 1
		record.color = PLAYER_TINTS[(record.index - 1) % PLAYER_TINTS.size()]
		_records[id] = record
	record.name = player_name
	var back := known and not respawn
	var tile := _nearest_free(record.tile) if back else _free_start_tile()
	if not World.is_free(tile):
		print("[net] no free tile for %s (%s)" % [player_name, id.left(8)])
		return
	# Spawn safety: not next to a hostile. Applies to coming back and to
	# respawning; a first join is at a start tile anyway and gets the same check.
	var intended := tile
	var threat := _nearest_hostile_distance(intended)
	if threat <= SPAWN_SAFE_DISTANCE:
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
	World.set_slots(player, record.slots)
	record.remember(player)
	record.zone = World.zone.name
	if not World.peer_zone.has(peer):
		World.peer_zone[peer] = World.zone.name
	_players[peer] = player
	_peer_ids[peer] = id
	_fell_at.erase(peer)
	print("[net] %s (%s) joined as %s at %s%s" % [
		player_name, id.left(8), player.name, tile, " (back)" if back else ""])
	party_log.add("%s joined." % player_name)
	_join_companion(record, player)


# --- Companions ----------------------------------------------------------------

## Gives [param player] its record's companion: a new one on first join,
## spawned adjacent; the remembered one, where it was, if it is alive; none
## if it died. A companion that is already in the world (its owner was away)
## just gets its owner back.
func _join_companion(record: PlayerRecord, player: Player) -> void:
	if not Net.companions:
		return
	var existing: Companion = _companions.get(record.player_id)
	if is_instance_valid(existing) and existing.spawned:
		existing.keeper = player
		existing.current_intent = Companion.Intent.FOLLOW
		print("[net] %s's companion %s was waiting at %s and follows again" % [
			record.name, existing.name, existing.tile])
		return
	# A record from before companions existed, or one that never got one,
	# has none: give it one now.
	var is_new := record.companion.is_empty() or not record.companion.get("name") is String
	if is_new:
		record.companion = {
			"name": COMPANION_NAMES[posmod(record.index - 1, COMPANION_NAMES.size())],
			"card": COMPANION_CARD, "hp": 0, "stamina": 0,
			"tile": [player.tile.x, player.tile.y], "alive": true,
		}
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
	pet.card = str(record.companion.get("card", COMPANION_CARD))
	if pet.card in OLD_COMPANION_CARDS:
		pet.card = COMPANION_CARD
	# An authored card (levels/companions.json) wins over the record's.
	var authored := companion_card(String(record.companion["name"]))
	if not authored.is_empty():
		pet.card = authored
	record.companion["card"] = pet.card
	pet.restore_said(record.companion.get("said", []))
	pet.party_log = party_log
	pet.mind = _make_mind()
	pet.said.connect(_on_companion_said.bind(pet))
	if int(record.companion.get("hp", 0)) > 0:
		World.restore(pet, int(record.companion["hp"]), int(record.companion.get("stamina", pet.max_stamina)), pet.facing)
	_companions[record.player_id] = pet
	print("[net] %s's companion %s is at %s%s" % [
		record.name, pet.name, tile, " (new)" if is_new else ""])


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


## The card written for companion [param pet_name] in COMPANION_CARDS, or "".
static func companion_card(pet_name: String) -> String:
	if _cards.is_empty() and FileAccess.file_exists(COMPANION_CARDS):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMPANION_CARDS))
		if parsed is Dictionary:
			for key: String in parsed:
				if not key.begins_with("_") and parsed[key] is Dictionary:
					_cards[key] = str(parsed[key].get("card", ""))
		if _cards.is_empty():
			_cards["_none"] = ""  # Read once, even when empty.
	return str(_cards.get(pet_name, ""))


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


## "say" {text}: chat, typed or a quick phrase (_player_said).
## "reset": rebuild the room, as the console's reset does. From the
## authority's own player always; from anyone else only while
## Net.player_reset is on.
func _on_command(entity: GridEntity, command_name: String, args: Dictionary) -> void:
	if command_name == "say" and entity is Player:
		_player_said(entity, str(args.get("text", "")), int(args.get("phrase", 0)))
	elif command_name == "party" and entity is Player:
		_party_said(entity, str(args.get("text", "")))
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
	elif command_name == "reset" and entity is Player:
		var who := _display_name(entity)  # The rebuild frees the entity.
		if not Net.player_reset and entity.owner_peer != Net.local_id:
			print("[world] %s asked for a reset; players may not (--no-player-reset)" % who)
			return
		print("[world] %s reset the room" % who)
		_start_level()
		party_log.add("%s reset the room." % who)


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
	slots_panel = SlotsPanel.new()
	slots_panel.name = "Slots"
	slots_panel.transfer = _transfer
	$HUD.add_child(slots_panel)
	talk = TalkPanel.new()
	talk.anchor_left = 0.0
	talk.anchor_top = 1.0
	talk.anchor_bottom = 1.0
	talk.offset_left = 30
	talk.offset_bottom = -170
	talk.grow_vertical = Control.GROW_DIRECTION_BEGIN
	$HUD.add_child(talk)
	_chat_box = LineEdit.new()
	_chat_box.name = "ChatBox"
	_chat_box.max_length = CHAT_MAX_CHARS
	_chat_box.placeholder_text = "say it aloud; /p for party chat (Enter sends, Esc cancels)"
	_chat_box.visible = false
	_chat_box.anchor_top = 1.0
	_chat_box.anchor_bottom = 1.0
	_chat_box.offset_left = 30
	_chat_box.offset_right = 1500
	_chat_box.offset_top = -150
	_chat_box.offset_bottom = -60
	_chat_box.text_submitted.connect(_send_chat)
	_chat_box.gui_input.connect(func(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key != null and key.pressed and key.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled())
	$HUD.add_child(_chat_box)


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
	return _chat_box != null and _chat_box.visible


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
		if is_instance_valid(pet) and pet.spawned and pet != entity and World.distance(pet.tile, entity.tile) <= Companion.SIGHT_RANGE \
				and entity.is_creature():
			pet.note_death(_display_name(entity), entity == pet.keeper, entity)
	var line := ""
	if entity is Companion:
		# Always said: last words never wait on the speech rate limit.
		line = COMPANION_DEATH_LINES[randi() % COMPANION_DEATH_LINES.size()]
		party_log.add("%s said: \"%s\"" % [entity.name, line])
	Net.broadcast_to(World.peers_in(World.zone.name), "death", {"entity": String(entity.name),
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
func _player_said(player: Player, text: String, phrase := 0) -> void:
	var line := text.strip_edges().left(CHAT_MAX_CHARS)
	if line.is_empty():
		return
	var id := player.get_instance_id()
	if World.tick - _chat_tick.get(id, -100000) < roundi(CHAT_INTERVAL * World.TICK_RATE):
		print("[chat] %s: too soon after the last line; dropped" % _display_name(player))
		return
	_chat_tick[id] = World.tick
	var pet: Companion = _companions.get(_peer_ids.get(player.owner_peer, ""))
	# She hears it only in the same zone and within earshot.
	var hears := is_instance_valid(pet) and pet.spawned and pet.zone == player.zone \
			and World.distance(pet.tile, player.tile) <= HEARING_RANGE
	var to := String(pet.name) if hears else ""
	# Every other companion within earshot hears it too, labelled; her voice
	# decides whether it was meant for her.
	for entity in World.get_entities():
		var other := entity as Companion
		if other != null and other != pet and other.spawned and World.distance(other.tile, player.tile) <= HEARING_RANGE:
			other.overheard(_display_name(player), line)
	party_log.add("%s said%s: \"%s\"" % [_display_name(player), " to " + to if to != "" else "", line])
	Net.broadcast_to(hearers(player.tile), "chat", {"entity": String(player.get_path()), "from": _display_name(player),
		"to": to, "text": line})
	if to != "":
		pet.owner_spoke(line, phrase)


## The peers whose players can hear something said at [param at] in the
## zone World is in: there, within HEARING_RANGE; a fallen player, waiting
## to rise, hears from where they fell (but has no body to speak with).
func hearers(at: Vector2i) -> Array[int]:
	var peers: Array[int] = []
	for peer in World.peers_in(World.zone.name):
		var player: Player = _players.get(peer)
		var standing := is_instance_valid(player) and player.spawned and player.zone == World.zone.name
		var from: Vector2i = player.tile if standing else _fell_at.get(peer, NONE)
		if (standing or _fell_at.has(peer)) and World.distance(from, at) <= HEARING_RANGE:
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
	var record: PlayerRecord = _records.get(pet.keeper_id)
	if record != null:
		record.companion["said"] = pet.said_lines()
	Net.broadcast_to(hearers(pet.tile), "speech", {"entity": String(pet.get_path()), "speaker": String(pet.name), "text": text})


func _on_message(kind: String, data: Dictionary) -> void:
	if kind == "map":
		# The zone this client's player is in: it draws and predicts on that
		# map, and its entities arrive under that zone's node.
		var wanted := str(data.get("name", ""))
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


## A name for the party log: players by record name, everything else by its
## node name.
func _display_name(entity: GridEntity) -> String:
	if entity is Player:
		var record: PlayerRecord = _records.get(_peer_ids.get(entity.owner_peer, ""))
		if record != null:
			return record.name
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


func _narrate_damage(entity: GridEntity, amount: int, source: GridEntity, cause: StringName) -> void:
	match cause:
		&"fire":
			party_log.add("%s burned for %d." % [_display_name(entity), amount])
		&"impact":
			party_log.add("%s took %d from the impact." % [_display_name(entity), amount])
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
		if seen.size() > 200:
			break
		for direction in World.DIRECTIONS:
			var next := tile + direction
			if not seen.has(next) and World.is_walkable(next):
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
	return EntityFactory.build(spec)


func _on_peer_authenticated(peer: int, id: String, player_name: String) -> void:
	_admit(peer, id, player_name)


func _on_peer_disconnected(peer: int) -> void:
	var player: Player = _players.get(peer)
	var id: String = _peer_ids.get(peer, "")
	var was := World.enter_named(World.peer_zone.get(peer, World.zone.name))
	_leave(peer, player, id)
	World.peer_zone.erase(peer)
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
		_respawn_at[peer] = World.tick + RESPAWN_TICKS
		print("[net] %s died; respawning in %d ticks" % [entity.name, RESPAWN_TICKS])
	if entity is Companion:
		var record: PlayerRecord = _records.get(entity.keeper_id)
		if record != null and not record.companion.is_empty():
			record.companion["alive"] = false
		_companions.erase(entity.keeper_id)
	if entity.is_creature():
		party_log.add("%s died." % _display_name(entity))
	elif entity.body_material == GridEntity.BodyMaterial.WOOD:
		party_log.add("%s broke." % _display_name(entity))


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

## Server: out of combat (no hostile within Companion.CALM_RANGE for
## CALM_TICKS) a player heals 1 hp every HEAL_EVERY ticks, as a companion
## does.
func _heal_players(tick: int) -> void:
	for player: Player in _players.values():
		if not is_instance_valid(player) or not player.spawned or player.zone != World.zone.name:
			continue
		var id := player.get_instance_id()
		if not _player_calm_since.has(id) or Companion._hostile_near(player.tile, Companion.CALM_RANGE):
			_player_calm_since[id] = tick
			continue
		var calm := tick - _player_calm_since[id]
		if calm >= Companion.CALM_TICKS and player.hp < player.max_hp \
				and (calm - Companion.CALM_TICKS) % Companion.HEAL_EVERY == 0:
			World.heal(player, 1)


func _on_world_ticked(tick: int) -> void:
	if Net.is_authority():
		_respawn_due_players(tick)
		_heal_players(tick)
		_check_respawns(tick)
	if World.zone != World.home():
		return  # Another zone's tick: the HUD and the test hooks are this view's.
	var player := _local_player()
	var hp_text := "no player" if Net.mode == Net.Mode.SERVER else "dead, respawning"
	if player != null:
		hp_text = "HP %d/%d" % [player.hp, player.max_hp]
	var mode_text: String = Net.Mode.keys()[Net.mode].to_lower()
	if not Net.online:
		mode_text = "offline"
	hud.text = "%s   %s   tick %d" % [mode_text, hp_text, tick]
	if hint_panel != null:
		hint_panel.set_lines(hint_lines())
	if player != null:
		_had_player = true
	if player != null:
		player.enable_prediction()
	_run_test_move(player)
	_run_test_contest(player, tick)
	_run_test_reset(player, tick)
	_run_test_door(player, tick)
	_run_test_chest(player)


## The controls for the HUD's list, a line each, "key\twhat it does".
func hint_lines() -> Array[String]:
	var lines: Array[String] = []
	if Net.controls == "wasd":
		lines.append_array(["WASD\twalk", "Mouse\taim", "LMB\tattack (far: walk)", "RMB\tgrab (drag to toss)"])
		if _client3d != null:
			lines.append_array(["MMB drag\tturn, look up / down", "Wheel\tzoom (MMB click: 1x)"])
	else:
		lines.append_array(["LMB\tmove / attack (hold to steer)", "RMB\tshove (drag to toss)"])
		if _client3d != null:
			lines.append_array(["W / S\ttilt", "A / D\tturn", "Wheel\tzoom (MMB click: 1x)"])
	for i in Net.phrases.size():
		lines.append("%d\t%s" % [i + 1, Net.phrases[i]])
	lines.append_array(["LMB chest\topen it (drag items)", "I\tyour slots", "Enter\ttalk", "Tab\ttalk log",
		"R\treset the room", "F3\tdebug", "F11\tfullscreen", "H\thide these"])
	return lines


## I: the slots panel shown or hidden; with a chest open, the chest closed.
func toggle_slots() -> void:
	if slots_panel == null:
		return
	if slots_panel.chest != null:
		close_chest()
		return
	slots_panel.shown = not slots_panel.shown


## A left click on [param chest]: open beside it; from afar, walk to the
## nearest free cell beside it, and open on arrival (_update_chest).
func _click_chest(player: Player, chest: GridEntity) -> void:
	if World.can_melee(player.tile, chest.tile):
		open_chest(chest)
		return
	var beside := _beside(chest.tile, player.tile)
	if beside == NONE:
		return
	_move_click(player, beside)
	_chest_wanted = chest


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


func open_chest(chest: GridEntity) -> void:
	_chest_wanted = null
	if slots_panel != null:
		slots_panel.open(chest)


func close_chest() -> void:
	_chest_wanted = null
	if slots_panel != null:
		slots_panel.open(null)


## Each frame: the panel follows the local player; a chest walked to opens,
## and an open one closes once the player is no longer beside it.
func _update_chest() -> void:
	if slots_panel == null:
		return
	var player := _local_player()
	slots_panel.player = player
	if player == null:
		close_chest()
		return
	if is_instance_valid(_chest_wanted) and World.can_melee(player.tile, _chest_wanted.tile):
		open_chest(_chest_wanted)
	var chest := slots_panel.chest
	if chest != null and (not is_instance_valid(chest) or not World.can_melee(player.tile, chest.tile)):
		close_chest()


## The slots panel's drop: a command, so the server decides (World.try_transfer).
func _transfer(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int) -> void:
	var player := _local_player()
	if player == null:
		return
	World.command(player, "transfer", {"from": str(from.get_path()), "from_slot": from_slot,
		"to": str(to.get_path()), "to_slot": to_slot})


## Server: a player's slots changed: their record has it at once, so it
## survives a death, a trip and a restart.
func _on_slots_changed(entity: GridEntity) -> void:
	if not entity is Player:
		return
	var record: PlayerRecord = _records.get(_peer_ids.get(entity.owner_peer, ""))
	if record != null and _players.get(entity.owner_peer) == entity:
		record.slots = entity.slots.duplicate()


## H: the controls list shown or hidden, and remembered.
func toggle_hints() -> void:
	Net.hints = not Net.hints
	if hint_panel != null:
		hint_panel.visible = Net.hints
	Net.save_view_settings()


## Which way the level's north points on screen (unit, y down), in
## whichever view is showing.
func screen_north() -> Vector2:
	var north := Vector2(World.north)
	if _client3d != null:
		return _client3d.screen_direction(north)
	return (Iso.project(north) - Iso.project(Vector2.ZERO)).normalized()


func _debug_text() -> String:
	var lines: Array[String] = ["peer id: %d (%s)" % [
		Net.local_id, Net.Mode.keys()[Net.mode].to_lower() if Net.online else "offline"]]
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
		lines.append("display delay: %d ticks" % World.display_delay_ticks)
		lines.append("build: v%s %s" % [Net.version, Net.protocol()])
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
		hud.text = "client out of date: the server runs v%s, this is v%s. Run launch.bat to update." % [
			server_version, Net.version]
	else:
		hud.text = reason


func _on_server_disconnected() -> void:
	if _rejected:
		return  # The reason is already on screen.
	if _had_player:
		hud.text = "disconnected from server"
	else:
		hud.text = "authentication failed"
		print("[net] authentication failed: disconnected before a player was spawned")


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
	while true:
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
		"zone":
			return _zone_command(words)
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
			if words.size() < 2 or words[1] not in ["scripted", "ollama"]:
				return "usage: mind scripted|ollama | mind log on|off | mind last <name> (now %s)" % mind_kind
			if words[1] == "ollama" and (Net.llm_url == "" or Net.llm_model == ""):
				return "no --llm-model configured"
			mind_kind = words[1]
			for pet: Companion in _companions.values():
				if is_instance_valid(pet):
					pet.mind = _make_mind()
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
		"help":
			return "reset | respawn | players | companions | zones | zone reset <name> | zone move <player> <zone> | " \
				+ "mind scripted|ollama | mind log on|off | mind last <name> | perception list|grid|both | " \
				+ "transcript <name> [<date>] | save"
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
## it, and drag its first item into the player's first empty slot (take),
## or the player's first item into the chest's first empty slot (put),
## through the slots panel as a drag would.
func _run_test_chest(player: Player) -> void:
	if Net.test_chest.is_empty() or _test_chest_done or player == null or slots_panel == null:
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
			_click_chest(player, chest)
			print("[test] %s walks to %s" % [player.name, chest.name])
		return
	open_chest(chest)
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
	slots_panel.drop(from, from_slot, to, to_slot)


func _run_test_reset(player: Player, tick: int) -> void:
	if Net.test_reset_tick <= 0 or _test_reset_sent or player == null or tick < Net.test_reset_tick:
		return
	_test_reset_sent = true
	World.command(player, "reset", {})
	print("[test] %s asked for a room reset at tick %d" % [player.name, tick])


func _run_test_contest(player: Player, tick: int) -> void:
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
	var turns: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(0, -3)]
	var turn := int(Time.get_ticks_msec() / (Net.test_steer * 1000.0)) % turns.size()
	var want := player.shown_tile() + turns[turn]
	if World.is_walkable(want) and want != _test_target:
		_test_target = want
		World.command_move(player, want)


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


func _on_test_exit() -> void:
	_report_walk()
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
	Net.shutdown()
	get_tree().quit()
