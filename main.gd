extends Node2D
## Builds the test room, starts networking, and turns clicks into orders.
## This is view/input glue plus level setup: on the server it asks World and
## the MultiplayerSpawner to create entities; it never touches entity state.

const FLOOR_SOURCE := 0
const WALL_SOURCE := 1
const FIRE_SOURCE := 2
## 14x14. '#' wall, '.' floor, '~' fire. The corridor is row 8, x 1..5, with
## its dead end at x 1. Under the wall at row 10, rows 11-12 x 7..11 are a
## two-wide passage open at both ends, where two players can pass each other.
const LEVEL: Array[String] = [
	"##############",
	"#............#",
	"#............#",
	"#............#",
	"#............#",
	"#......~~~...#",
	"#............#",
	"######.......#",
	"#............#",
	"######.......#",
	"#......#####.#",
	"#............#",
	"#............#",
	"##############",
]
const MONSTER := "res://sim/monster.gd"
const PUSHABLE := "res://sim/pushable.gd"
const PLAYER := "res://sim/player.gd"
const COMPANION := "res://sim/companion.gd"
## Spawned by the server in this order, which is also entity id order. Each
## spec is built by EntityFactory on every peer: script, shape, tint, scale,
## label, and "props" set on the instance before it enters the tree.
const LEVEL_ENTITIES: Array[Dictionary] = [
	# Imps come in different masses; Monster shades them darker as they get heavier.
	{"script": MONSTER, "shape": "capsule", "name": "CorridorImp1", "tile": Vector2i(1, 8), "props": {"mass": 25.0}},
	{"script": MONSTER, "shape": "capsule", "name": "CorridorImp2", "tile": Vector2i(2, 8), "props": {"mass": 40.0}},
	{"script": MONSTER, "shape": "capsule", "name": "CorridorImp3", "tile": Vector2i(3, 8), "props": {"mass": 60.0}},
	# These two doze in the open: they only notice what comes within 3 tiles.
	{"script": MONSTER, "shape": "capsule", "name": "Imp1", "tile": Vector2i(1, 6), "props": {"mass": 30.0, "sight_range": 3}},
	{"script": MONSTER, "shape": "capsule", "name": "Imp2", "tile": Vector2i(2, 6), "props": {"mass": 70.0, "sight_range": 3}},
	{"script": PUSHABLE, "shape": "cube", "name": "Crate1", "tile": Vector2i(8, 2), "tint": Color(0.8, 0.6, 0.35)},
	{"script": PUSHABLE, "shape": "cube", "name": "Crate2", "tile": Vector2i(8, 3), "tint": Color(0.8, 0.6, 0.35)},
	{"script": PUSHABLE, "shape": "cube", "name": "Crate3", "tile": Vector2i(4, 2), "tint": Color(0.8, 0.6, 0.35)},
	{"script": PUSHABLE, "shape": "sphere", "name": "Boulder", "tile": Vector2i(6, 3), "tint": Color(0.55, 0.55, 0.6),
		"scale": 1.4, "props": {"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE}},
]
## A joining peer's player takes the first of these that is free.
const PLAYER_STARTS: Array[Vector2i] = [
	Vector2i(11, 2), Vector2i(12, 1), Vector2i(11, 1), Vector2i(12, 2),
	Vector2i(10, 1), Vector2i(10, 2), Vector2i(12, 3), Vector2i(11, 3),
]
## Indexed by join order.
const PLAYER_TINTS: Array[Color] = [
	Color(0.35, 0.65, 1.0), Color(0.4, 0.9, 0.45), Color(1.0, 0.85, 0.3), Color(0.95, 0.5, 0.9),
	Color(0.4, 0.9, 0.9), Color(1.0, 0.6, 0.3), Color(0.75, 0.75, 0.8), Color(0.7, 0.55, 1.0),
]

## World pixels the cursor must travel with the right button held before a
## shove becomes an aimed toss.
const TOSS_DRAG_MIN := 10.0
const TOSS_AIM_LENGTH := 26.0
const COMPANION_NAMES: Array[String] = ["Pip", "Nix", "Tamsin", "Bram", "Ozzie", "Wren", "Juno", "Fenn"]
const COMPANION_CARD := "A loyal, cautious companion who guards its friend and speaks little."
const COMPANION_TINT := Color(0.45, 0.95, 0.85)
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
## Server only: what happened, in words, for companion minds and the log.
var party_log := PartyLog.new()
## Which mind new decisions use: "scripted" or "ollama" (console: mind ...).
var mind_kind := "scripted"
## Server only: LEVEL_ENTITIES index -> the entity holding that slot now.
var _alive_slots: Dictionary[int, GridEntity] = {}
## Server only: LEVEL_ENTITIES index -> tick its entity died or broke.
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
## Client: whether this peer has ever had a player, to tell a rejected join
## from a later disconnect.
var _had_player := false
## Client: the server said why it turned us away; keep that message up.
var _rejected := false
## Right button held on this entity: released without a drag it is a shove,
## dragged it is a toss in the dragged direction.
var _toss_target: GridEntity
var _toss_from := Vector2.ZERO

@onready var ground: TileMapLayer = $Ground
@onready var walls: TileMapLayer = $YSort/Walls
@onready var entities: Node2D = $YSort/Entities
@onready var spawner: MultiplayerSpawner = $Spawner
@onready var cursor: Polygon2D = $Cursor
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $HUD/Label
@onready var debug_overlay: Label = $HUD/Debug
@onready var toss_aim: Line2D = $TossAim


func _ready() -> void:
	var probe := Vector2i(3, 5)
	if not ground.map_to_local(probe).is_equal_approx(Iso.tile_to_local(probe)):
		push_error("Iso math disagrees with the TileSet: %s vs %s" % [
			Iso.tile_to_local(probe), ground.map_to_local(probe)])

	_paint_level()
	var last_tile := Vector2i(LEVEL[0].length() - 1, LEVEL.size() - 1)
	camera.position = (Iso.tile_to_local(Vector2i.ZERO) + Iso.tile_to_local(last_tile)) * 0.5

	# Every peer builds entities the same way; only the server decides when.
	spawner.spawn_function = _build_entity
	World.ticked.connect(_on_world_ticked)
	if Net.test_exit_after > 0.0:
		get_tree().create_timer(Net.test_exit_after).timeout.connect(_on_test_exit)

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
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		World.entity_despawned.connect(_on_entity_despawned)
		World.entity_pushed.connect(_narrate_push)
		World.entity_damaged.connect(_narrate_damage)
		World.command_received.connect(_on_command)
		if Net.llm_url != "" and Net.llm_model != "":
			mind_kind = "ollama"
		if Net.mode == Net.Mode.SERVER:
			World.entity_moved.connect(_log_player_move)
		_start_level(true)
		_start_console()
	else:
		# Terrain is static level data, not replicated state.
		World.mirror_reset()
		World.mirror_terrain(ground.get_used_cells(), walls.get_used_cells(),
				ground.get_used_cells_by_id(FIRE_SOURCE))
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		multiplayer.connection_failed.connect(
				func() -> void: hud.text = "connection failed")
		Net.join_rejected.connect(_on_join_rejected)
	Net.message_received.connect(_on_message)


func _process(_delta: float) -> void:
	var hovered := _entity_under_mouse()
	var tile := hovered.tile if hovered != null else _mouse_tile()
	cursor.visible = World.is_walkable(tile)
	cursor.position = Iso.tile_to_local(tile)
	if debug_overlay.visible:
		debug_overlay.text = _debug_text()
	_update_toss_aim()
	_poll_console()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		debug_overlay.visible = not debug_overlay.visible
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		if Net.is_authority():
			_start_level()
		return
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var local := _local_player()
		if local != null:
			World.command(local, "order", {"slot": key.keycode - KEY_0})
		return
	var click := event as InputEventMouseButton
	if click == null:
		return
	var player := _local_player()
	if player == null:
		_toss_target = null
		return
	if click.button_index == MOUSE_BUTTON_RIGHT and not click.pressed:
		_release_toss(player)
		return
	if not click.pressed:
		return
	# A sprite under the cursor wins over the tile under the cursor.
	var target := _entity_under_mouse()
	var tile := target.tile if target != null else _mouse_tile()
	if target == null:
		target = World.get_entity_at(tile)
	var targetable := target != null and target != player and World.can_target(player, target)
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			# A creature: go to it and attack. Anything else: walk there (and push).
			if targetable and target.is_creature():
				World.command_attack(player, target)
			else:
				World.command_move(player, tile)
		MOUSE_BUTTON_RIGHT:
			# Any entity: go to it and shove. Sent on release, so that
			# dragging first can aim it.
			if targetable:
				_toss_target = target
				_toss_from = get_global_mouse_position()


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
	return Vector2((direction.x - direction.y) * Iso.HALF.x, (direction.x + direction.y) * Iso.HALF.y)


## An arrow from the held target showing which way it will be tossed.
func _update_toss_aim() -> void:
	var direction := Vector2i.ZERO
	if is_instance_valid(_toss_target) and _toss_target.spawned:
		direction = _toss_direction()
	else:
		_toss_target = null
	toss_aim.visible = direction != Vector2i.ZERO
	if not toss_aim.visible:
		return
	var along := _screen_vector(direction).normalized()
	var tail := _toss_target.position + Vector2(0, -8)
	var tip := tail + along * TOSS_AIM_LENGTH
	toss_aim.points = PackedVector2Array([
		tail, tip, tip + along.rotated(2.6) * 7.0, tip, tip + along.rotated(-2.6) * 7.0])


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


## Screen -> grid: the canvas transform (camera, stretch) is undone by
## get_global_mouse_position(), then Iso inverts the diamond projection.
func _mouse_tile() -> Vector2i:
	return Iso.local_to_tile(ground.to_local(get_global_mouse_position()))


func _paint_level() -> void:
	for y in LEVEL.size():
		for x in LEVEL[y].length():
			var tile := Vector2i(x, y)
			var symbol := LEVEL[y][x]
			ground.set_cell(tile, FIRE_SOURCE if symbol == "~" else FLOOR_SOURCE, Vector2i.ZERO)
			if symbol == "#":
				walls.set_cell(tile, WALL_SOURCE, Vector2i.ZERO)


# --- Server: level and players ------------------------------------------------

## (Re)builds the room. Also the R restart: removing the old entities and
## spawning new ones replicates to every client through the spawner.
## With [param from_snapshot], entities come from the --state file when it
## has one; the room itself is always the ASCII map.
func _start_level(from_snapshot := false) -> void:
	if not Net.is_authority():
		return
	# Whoever is online keeps their place through the rebuild.
	for peer: int in _players:
		var player: Player = _players[peer]
		if is_instance_valid(player) and player.spawned and _records.has(_peer_ids.get(peer, "")):
			_records[_peer_ids[peer]].remember(player)
	World.reset()
	for child in entities.get_children():
		entities.remove_child(child)
		child.queue_free()
	World.load_terrain(ground.get_used_cells(), walls.get_used_cells(),
			ground.get_used_cells_by_id(FIRE_SOURCE))
	_players.clear()
	_peer_ids.clear()
	_respawn_at.clear()
	_alive_slots.clear()
	_dead_since.clear()
	_companions.clear()
	# Level entities first (from the snapshot if there is one), then the
	# players: a returning player's tile must be known to be free or taken.
	# Player records survive a rebuild; a snapshot brings its own.
	if from_snapshot:
		_records.clear()
	if not (from_snapshot and _spawn_from_snapshot()):
		for slot in LEVEL_ENTITIES.size():
			_spawn(_slot_spec(slot))
	if Net.mode != Net.Mode.SERVER:
		_join_player(Net.local_id, Net.player_id, Net.player_name)
	for peer in multiplayer.get_peers():
		var id := Net.player_of(peer)
		if id != "":
			_join_player(peer, id, _records[id].name if _records.has(id) else Net.DEFAULT_NAME)


## True if a usable snapshot was found; its entities are then in the room and
## its player records are known, so players joining next come back as they were.
func _spawn_from_snapshot() -> bool:
	if Net.state_path == "":
		return false
	var snapshot := Snapshot.load(Net.state_path)
	if not snapshot["ok"]:
		return false
	for record: PlayerRecord in snapshot["players"]:
		_records[record.player_id] = record
	var restored := 0
	for entry: Dictionary in snapshot["entities"]:
		var spec: Dictionary = entry["spec"]
		var entity := _spawn(spec)
		if entity == null:
			continue
		World.restore(entity, entry["hp"], entry["stamina"], entry["facing"])
		restored += 1
	# Slots with no entity are dead: pick up their timers, or start one now.
	for respawn: Dictionary in snapshot["respawns"]:
		if not _alive_slots.has(respawn["spawn"]):
			_dead_since[respawn["spawn"]] = World.tick - (RESPAWN_DELAY_TICKS - respawn["ticks_left"])
	for slot in LEVEL_ENTITIES.size():
		if not _alive_slots.has(slot) and not _dead_since.has(slot):
			_dead_since[slot] = World.tick
	print("[state] loaded %d entities and %d player records from %s (saved at tick %d)" % [
		restored, snapshot["players"].size(), Net.state_path, snapshot["tick"]])
	return true


## The spawn table entry for [param slot], tagged with its index so the
## entity can be tracked through death and respawn.
func _slot_spec(slot: int) -> Dictionary:
	var spec: Dictionary = LEVEL_ENTITIES[slot].duplicate(true)
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
		if is_instance_valid(player) and player.spawned and World.distance(player.tile, tile) <= distance:
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
	var respawns: Array[Dictionary] = []
	for slot: int in _dead_since:
		respawns.append({"spawn": slot,
			"ticks_left": maxi(RESPAWN_DELAY_TICKS - (World.tick - _dead_since[slot]), 0)})
	Snapshot.save(Net.state_path, World.tick, World.get_entities(), records, respawns)


func _exit_tree() -> void:
	# Clean shutdown (quit, window closed): keep the last state.
	_save_state()
	# The stdin thread ends on its own once stdin is closed; join it then. One
	# still blocked on a live terminal cannot be joined and is left to die.
	if _stdin_thread != null and _stdin_thread.is_started() and not _stdin_thread.is_alive():
		_stdin_thread.wait_to_finish()


func _spawn(spec: Dictionary) -> GridEntity:
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
	record.remember(player)
	_players[peer] = player
	_peer_ids[peer] = id
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
		existing.request_decision("owner back")
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
	var saved: Variant = Snapshot.vector(record.companion.get("tile"))
	var wanted: Vector2i = saved if saved != null and not is_new else player.tile
	var tile := _nearest_free(wanted)
	if not World.is_free(tile):
		print("[net] no free tile for %s's companion %s near %s" % [record.name, record.companion["name"], wanted])
		return
	var pet := _spawn({
		"script": COMPANION, "shape": "capsule", "name": String(record.companion["name"]), "tile": tile,
		"tint": COMPANION_TINT, "label": String(record.companion["name"]),
	}) as Companion
	if pet == null:
		return
	pet.keeper_id = record.player_id
	pet.keeper = player
	pet.card = str(record.companion.get("card", COMPANION_CARD))
	pet.party_log = party_log
	pet.mind = _make_mind()
	pet.said.connect(_on_companion_said.bind(pet))
	if int(record.companion.get("hp", 0)) > 0:
		World.restore(pet, int(record.companion["hp"]), int(record.companion.get("stamina", pet.max_stamina)), pet.facing)
	_companions[record.player_id] = pet
	print("[net] %s's companion %s is at %s%s" % [
		record.name, pet.name, tile, " (new)" if is_new else ""])


func _make_mind() -> CompanionMind:
	if mind_kind == "ollama" and Net.llm_url != "" and Net.llm_model != "":
		return OllamaMind.new(Net.llm_url, Net.llm_model, self)
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


## "order" {slot}: 1 follow, 2 hold here, 3 attack my current target,
## 4 fall back; 5..9 are accepted and ignored for now.
func _on_command(entity: GridEntity, command_name: String, args: Dictionary) -> void:
	if command_name == "order" and entity is Player:
		handle_order(entity, int(args.get("slot", 0)))


func handle_order(player: Player, slot: int) -> void:
	var id: String = _peer_ids.get(player.owner_peer, "")
	var pet: Companion = _companions.get(id)
	if not is_instance_valid(pet) or not pet.spawned:
		return
	var record: PlayerRecord = _records.get(id)
	var who := record.name if record != null else String(player.name)
	match slot:
		1:
			pet.give_order("follow")
		2:
			pet.give_order("hold")
		3:
			var target: GridEntity = player.action_target
			if not is_instance_valid(target) or not target.spawned:
				target = _nearest_monster_to(pet)
			pet.give_order("attack", target)
		4:
			pet.give_order("fallback")
		_:
			return
	var order_names := {1: "follow", 2: "hold here", 3: "attack", 4: "fall back"}
	party_log.add("%s ordered %s to %s." % [who, pet.name, order_names[slot]])
	print("[order] %s -> %s: %s" % [who, pet.name, order_names[slot]])


func _nearest_monster_to(entity: GridEntity) -> GridEntity:
	var best: GridEntity = null
	var best_distance := 99
	for other in World.get_entities():
		if other is Monster and other.spawned and World.distance(entity.tile, other.tile) < best_distance:
			best = other
			best_distance = World.distance(entity.tile, other.tile)
	return best


func _on_companion_said(text: String, pet: Companion) -> void:
	Net.broadcast("speech", {"entity": String(pet.get_path()), "text": text})


func _on_message(kind: String, data: Dictionary) -> void:
	if kind == "speech":
		var entity := get_node_or_null(NodePath(str(data.get("entity", "")))) as GridEntity
		if entity != null:
			entity.say(str(data.get("text", "")))
			print("[speech] %s: %s" % [entity.name, data.get("text", "")])


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
	if entity is Companion:
		entity.request_decision("pushed")


func _narrate_damage(entity: GridEntity, amount: int, source: GridEntity, cause: StringName) -> void:
	match cause:
		&"fire":
			party_log.add("%s burned for %d." % [_display_name(entity), amount])
		&"impact":
			party_log.add("%s took %d from the impact." % [_display_name(entity), amount])
		_:
			if source != null:
				party_log.add("%s hit %s for %d." % [_display_name(source), _display_name(entity), amount])
	if entity is Companion:
		entity.request_decision("hurt")
	elif entity is Player:
		for pet: Companion in _companions.values():
			if is_instance_valid(pet) and pet.keeper == entity:
				pet.request_decision("owner hurt")


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
	for start in PLAYER_STARTS:
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
		if World.is_free(tile) and not World.is_fire(tile):
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
	for tile in PLAYER_STARTS:
		if World.is_free(tile):
			return tile
	for y in LEVEL.size():
		for x in LEVEL[y].length():
			if World.is_free(Vector2i(x, y)) and not World.is_fire(Vector2i(x, y)):
				return Vector2i(x, y)
	return PLAYER_STARTS[0]


## MultiplayerSpawner's spawn function: runs on the server and on every client
## with the same data, so static configuration never needs replicating.
func _build_entity(spec: Dictionary) -> Node:
	return EntityFactory.build(spec)


func _on_peer_authenticated(peer: int, id: String, player_name: String) -> void:
	_join_player(peer, id, player_name)


func _on_peer_disconnected(peer: int) -> void:
	var player: Player = _players.get(peer)
	var id: String = _peer_ids.get(peer, "")
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
	if entity.spawn_spec.has("spawn"):
		var slot: int = entity.spawn_spec["spawn"]
		if _alive_slots.get(slot) == entity:
			_alive_slots.erase(slot)
			_dead_since[slot] = World.tick
	var peer := entity.owner_peer
	if entity is Player and _players.get(peer) == entity:
		_players.erase(peer)
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
		if tick >= _respawn_at[peer]:
			_respawn_at.erase(peer)
			var id: String = _peer_ids.get(peer, "")
			if id != "" and _records.has(id):
				_join_player(peer, id, _records[id].name, true)


# --- HUD, logging, test hooks -------------------------------------------------

func _on_world_ticked(tick: int) -> void:
	if Net.is_authority():
		_respawn_due_players(tick)
		_check_respawns(tick)
		if tick % SNAPSHOT_EVERY_TICKS == 0:
			_save_state()
	var player := _local_player()
	var hp_text := "no player" if Net.mode == Net.Mode.SERVER else "dead, respawning"
	if player != null:
		hp_text = "HP %d/%d" % [player.hp, player.max_hp]
	var mode_text: String = Net.Mode.keys()[Net.mode].to_lower()
	if not Net.online:
		mode_text = "offline"
	hud.text = "%s   %s   tick %d   LMB move / attack   RMB shove (drag to toss)   R restart (host)   F3 debug" % [
		mode_text, hp_text, tick]
	if player != null:
		_had_player = true
	if player != null:
		player.enable_prediction()
	_run_test_move(player)
	_run_test_contest(player, tick)


func _debug_text() -> String:
	var lines: Array[String] = ["peer id: %d (%s)" % [
		Net.local_id, Net.Mode.keys()[Net.mode].to_lower() if Net.online else "offline"]]
	var player := _local_player()
	if player != null:
		lines.append("stamina: %d / %d" % [player.stamina, player.max_stamina])
	if Net.mode == Net.Mode.CLIENT:
		lines.append("rtt: %d ms" % roundi(Net.rtt_ms()))
		lines.append("mispredicts: %d / min (%d total)" % [
			Net.mispredicts_per_minute(), Net.mispredicts_total])
		lines.append("snaps: %d / min (%d total)" % [Net.snaps_per_minute(), Net.snaps_total])
		lines.append("display delay: %d ticks" % World.display_delay_ticks)
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
		for line in chunk.split("
", false):
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
		"reset":
			_start_level()
			return "room rebuilt from the map; %d player records kept" % _records.size()
		"respawn":
			return "respawned %d" % _check_respawns(World.tick, true)
		"players":
			var lines: Array[String] = []
			for peer: int in _players:
				var player: Player = _players[peer]
				if not is_instance_valid(player) or not player.spawned:
					continue
				var id: String = _peer_ids.get(peer, "")
				var record: PlayerRecord = _records.get(id)
				lines.append("%s %s (%s) peer %d at %s hp %d/%d" % [
					player.name, record.name if record != null else "?", id.left(8), peer,
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
				lines.append("%s of %s (%s) at %s hp %d/%d intent %s%s mind %s, last answer %s" % [
					pet.name, record.name if record != null else "?", id.left(8), pet.tile, pet.hp, pet.max_hp,
					pet.intent_name(), " " + pet.intent_target.name if pet.intent_target != null else "",
					pet.mind.kind if pet.mind != null else "none", pet.last_mind])
			return "%d companions\n%s" % [lines.size(), "\n".join(lines)] if not lines.is_empty() else "0 companions"
		"mind":
			if words.size() < 2 or words[1] not in ["scripted", "ollama"]:
				return "usage: mind scripted|ollama (now %s)" % mind_kind
			if words[1] == "ollama" and (Net.llm_url == "" or Net.llm_model == ""):
				return "no --llm-model configured"
			mind_kind = words[1]
			for pet: Companion in _companions.values():
				if is_instance_valid(pet):
					pet.mind = _make_mind()
			return "companion minds: %s" % mind_kind
		"help":
			return "reset | respawn | players | companions | mind scripted|ollama | save"
	return "unknown command %s (try help)" % words[0]


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
func _run_test_contest(player: Player, tick: int) -> void:
	if Net.test_contest_tick <= 0 or _test_contested or player == null \
			or tick < Net.test_contest_tick:
		return
	_test_contested = true
	World.command_move(player, Net.test_contest_tile)
	print("[test] contest: %s at %s ordered to %s, now showing %s" % [
		player.name, player.tile, Net.test_contest_tile, player.shown_tile()])


func _on_test_exit() -> void:
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
	Net.shutdown()
	get_tree().quit()
