extends Node2D
## Builds the test room, starts networking, and turns clicks into orders.
## This is view/input glue plus level setup: on the server it asks World and
## the MultiplayerSpawner to create entities; it never touches entity state.

const FLOOR_SOURCE := 0
const WALL_SOURCE := 1
const FIRE_SOURCE := 2
## 14x14. '#' wall, '.' floor, '~' fire. The corridor is row 8, x 1..5, with
## its dead end at x 1.
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
	"#............#",
	"#............#",
	"#............#",
	"##############",
]
const SCENES := {
	"player": preload("res://entities/player.tscn"),
	"monster": preload("res://entities/monster.tscn"),
	"pushable": preload("res://entities/pushable.tscn"),
}
## Spawned by the server in this order, which is also entity id order.
## "props" are set on the instance on every peer before it enters the tree.
const LEVEL_ENTITIES: Array[Dictionary] = [
	{"scene": "monster", "name": "CorridorImp1", "tile": Vector2i(1, 8)},
	{"scene": "monster", "name": "CorridorImp2", "tile": Vector2i(2, 8)},
	{"scene": "monster", "name": "CorridorImp3", "tile": Vector2i(3, 8)},
	{"scene": "monster", "name": "Imp1", "tile": Vector2i(2, 11)},
	{"scene": "monster", "name": "Imp2", "tile": Vector2i(5, 12)},
	{"scene": "pushable", "name": "Crate1", "tile": Vector2i(8, 2)},
	{"scene": "pushable", "name": "Crate2", "tile": Vector2i(8, 3)},
	{"scene": "pushable", "name": "Crate3", "tile": Vector2i(4, 2)},
	{"scene": "pushable", "name": "Boulder", "tile": Vector2i(6, 3), "props": {
		"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE,
		"modulate": Color(0.55, 0.55, 0.6)}},
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

## Ticks between a player dying and reappearing at a start tile.
const RESPAWN_TICKS := 20

## Server only: peer id -> that peer's player.
var _players: Dictionary[int, Player] = {}
## Server only: peer id -> join order, so a respawn keeps its name and tint.
var _player_index: Dictionary[int, int] = {}
## Server only: peer id -> tick at which its dead player comes back.
var _respawn_at: Dictionary[int, int] = {}
var _next_player_index := 0
var _test_target := Vector2i.ZERO
var _test_ordered := false
var _test_arrived := false

@onready var ground: TileMapLayer = $Ground
@onready var walls: TileMapLayer = $YSort/Walls
@onready var entities: Node2D = $YSort/Entities
@onready var spawner: MultiplayerSpawner = $Spawner
@onready var cursor: Polygon2D = $Cursor
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $HUD/Label


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
	Net.start()
	if Net.is_authority():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		World.entity_despawned.connect(_on_entity_despawned)
		if Net.mode == Net.Mode.SERVER:
			World.entity_moved.connect(_log_player_move)
		_start_level()
	else:
		# Terrain is static level data, not replicated state.
		World.mirror_reset()
		World.mirror_terrain(ground.get_used_cells(), walls.get_used_cells(),
				ground.get_used_cells_by_id(FIRE_SOURCE))
		multiplayer.server_disconnected.connect(
				func() -> void: hud.text = "disconnected from server")

	World.ticked.connect(_on_world_ticked)
	if Net.test_exit_after > 0.0:
		get_tree().create_timer(Net.test_exit_after).timeout.connect(_on_test_exit)


func _process(_delta: float) -> void:
	var tile := _mouse_tile()
	cursor.visible = World.is_walkable(tile)
	cursor.position = Iso.tile_to_local(tile)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		if Net.is_authority():
			_start_level()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var player := _local_player()
	if player == null:
		return
	var tile := _mouse_tile()
	var target := World.get_entity_at(tile)
	var in_reach := target != null and target != player and World.can_melee(player.tile, tile)
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			# Adjacent creature: attack. Anything else: walk there (and push).
			if in_reach and target.is_creature():
				World.command_attack(player, target)
			else:
				World.command_move(player, tile)
		MOUSE_BUTTON_RIGHT:
			if in_reach:
				World.command_shove(player, target)


## The player this peer's input controls, or null (dedicated server, dead,
## or not spawned yet).
func _local_player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.owner_peer == Net.local_id and entity.spawned:
			return entity
	return null


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
func _start_level() -> void:
	if not Net.is_authority():
		return
	World.reset()
	for child in entities.get_children():
		entities.remove_child(child)
		child.queue_free()
	World.load_terrain(ground.get_used_cells(), walls.get_used_cells(),
			ground.get_used_cells_by_id(FIRE_SOURCE))
	_players.clear()
	_player_index.clear()
	_respawn_at.clear()
	_next_player_index = 0
	# The local player first, so in single-player it keeps the lowest id.
	if Net.mode != Net.Mode.SERVER:
		_spawn_player(Net.local_id)
	for spec in LEVEL_ENTITIES:
		_spawn(spec)
	for peer in multiplayer.get_peers():
		_spawn_player(peer)


func _spawn(spec: Dictionary) -> GridEntity:
	var entity := spawner.spawn(spec) as GridEntity
	if not World.spawn(entity, spec["tile"]):
		entities.remove_child(entity)
		entity.queue_free()
		return null
	return entity


func _spawn_player(peer: int) -> void:
	var tile := _free_start_tile()
	if not World.is_free(tile):
		print("[net] no free start tile for peer %d" % peer)
		return
	if not _player_index.has(peer):
		_player_index[peer] = _next_player_index
		_next_player_index += 1
	var index := _player_index[peer]
	var player := _spawn({
		"scene": "player", "name": "Player%d" % (index + 1), "tile": tile, "peer": peer,
		"props": {"tint": PLAYER_TINTS[index % PLAYER_TINTS.size()]},
	}) as Player
	if player == null:
		return
	_players[peer] = player
	print("[net] peer %d joined as %s at %s" % [peer, player.name, tile])


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
	var entity: GridEntity = SCENES[spec["scene"]].instantiate()
	entity.name = spec["name"]
	var props: Dictionary = spec.get("props", {})
	for property: String in props:
		entity.set(property, props[property])
	entity.owner_peer = spec.get("peer", 0)
	entity.start_tile = spec["tile"]
	# Placeholders until World (server) or the synchronizer (client) says otherwise.
	entity.tile = spec["tile"]
	entity.hp = entity.max_hp
	return entity


func _on_peer_connected(peer: int) -> void:
	_spawn_player(peer)


func _on_peer_disconnected(peer: int) -> void:
	var player: Player = _players.get(peer)
	_players.erase(peer)
	_player_index.erase(peer)
	_respawn_at.erase(peer)
	if is_instance_valid(player) and player.spawned:
		World.despawn(player)
	print("[net] peer %d left" % peer)


## A player that dies comes back after RESPAWN_TICKS, as long as its peer is
## still here. Placeholder rule so the test room stays usable.
func _on_entity_despawned(entity: GridEntity) -> void:
	var peer := entity.owner_peer
	if entity is Player and _players.get(peer) == entity:
		_players.erase(peer)
		_respawn_at[peer] = World.tick + RESPAWN_TICKS
		print("[net] %s died; respawning in %d ticks" % [entity.name, RESPAWN_TICKS])


func _respawn_due_players(tick: int) -> void:
	for peer: int in _respawn_at.keys():
		if tick >= _respawn_at[peer]:
			_respawn_at.erase(peer)
			_spawn_player(peer)


# --- HUD, logging, test hooks -------------------------------------------------

func _on_world_ticked(tick: int) -> void:
	if Net.is_authority():
		_respawn_due_players(tick)
	var player := _local_player()
	var hp_text := "no player" if Net.mode == Net.Mode.SERVER else "dead, respawning"
	if player != null:
		hp_text = "HP %d/%d" % [player.hp, player.max_hp]
	var mode_text: String = Net.Mode.keys()[Net.mode].to_lower()
	if not Net.online:
		mode_text = "offline"
	hud.text = "%s   %s   tick %d   LMB move / attack   RMB shove   R restart (host)" % [
		mode_text, hp_text, tick]
	_run_test_move(player)


func _log_player_move(entity: GridEntity, from: Vector2i, to: Vector2i) -> void:
	if entity is Player:
		print("[net] %s (peer %d) moved %s -> %s occupancy_consistent=%s" % [
			entity.name, entity.owner_peer, from, to, World.is_occupancy_consistent()])


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


func _on_test_exit() -> void:
	print("[test] final tick=%d entities=%d occupancy_consistent=%s" % [
		World.tick, World.get_entities().size(), World.is_occupancy_consistent()])
	Net.shutdown()
	get_tree().quit()
