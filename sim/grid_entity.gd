class_name GridEntity
extends Node2D
## Base class for everything that occupies a tile.
##
## Sim state (tile, hp, facing, cooldowns, orders) is written only by World,
## or by _sim_tick(), which World calls from inside the server-gated tick.
## Node2D.position is a render-only value derived from that state in
## _process(); nothing else may write it. See docs/design.md.
##
## On a client the entity is a mirror: tile, hp and facing arrive through the
## MultiplayerSynchronizer built in _init(), nothing here runs the sim, and
## the setters below only drive visuals and World's rebuilt occupancy.

# All three are emitted by World (on clients, relayed by the _net_* RPCs).
@warning_ignore("unused_signal")
signal damaged(amount: int)
## Shoved by a push; [param tiles] may be 0 if it was stopped at once.
signal pushed(tiles: int)
## Stopped with force left over, or hit by something that was.
signal impacted(amount: int)

# Not called "Material"/"material": CanvasItem already owns that name.
## FLESH is a creature (hazards hurt it). WOOD takes impact and breaks at 0 hp.
## STONE and METAL never break.
enum BodyMaterial { FLESH, WOOD, STONE, METAL }
enum Order { NONE, ATTACK, SHOVE }

## The only state sent over the network, besides World's tick.
const REPLICATED: Array[String] = ["tile", "hp", "facing"]
const HOP_HEIGHT := 6.0
const PIP_REACH := 4.0
const IMPACT_FLASH := Color(4.0, 4.0, 4.0)
const HURT_TINT := Color(1.0, 0.3, 0.3)

@export var start_tile := Vector2i.ZERO
@export var mass := 10.0
@export var body_material := BodyMaterial.FLESH
## Can be shoved along by something walking into it. Force pushes ignore this.
@export var pushable := false
@export var blocks_sight := false
## Ticks one step takes; also the cooldown before the next step.
@export var move_ticks := 2
## 0 means indestructible.
@export var max_hp := 0
@export var attack_damage := 0
## Push force (tiles) carried by a melee attack.
@export var attack_force := 0
## Push force of a shove; 0 means this entity cannot shove.
@export var shove_force := 0
## Cooldown shared by attack and shove.
@export var attack_ticks := 10
## Sprite colour override; alpha 0 means keep the scene's colour.
@export var tint := Color(0, 0, 0, 0)

## Assigned by World at spawn, ascending. Decides resolution order. Server only.
var id := 0
## Peer whose input may order this entity; 0 for none. Same on every peer.
var owner_peer := 0
var tile := Vector2i.ZERO:
	set(value):
		var old := tile
		tile = value
		if _mirroring and old != value:
			_mirror_tile_changed(old)
var hp := 0:
	set(value):
		var old := hp
		hp = value
		if _mirroring and value < old:
			_start_hurt_fade()
## Direction of the last step or attack.
var facing := Vector2i(0, 1)
var spawned := false
var next_move_tick := 0
var next_attack_tick := 0
var has_move_order := false
var move_order := Vector2i.ZERO
var action_order := Order.NONE
var action_target: GridEntity

# Render interpolation: slide from _from_tile to tile over _move_duration ticks.
var _from_tile := Vector2i.ZERO
var _move_tick := 0.0
var _move_duration := 0
## True on a client once this mirror is registered with World.
var _mirroring := false

# Feedback visuals live on the Sprite child, never on this node's position.
var _sprite: Node2D
var _sprite_rest := Vector2.ZERO
var _pip: Node2D
var _pip_rest := Vector2.ZERO
var _hop: Tween
var _fade: Tween
var _flash_pending := false
var _flash_showing := false
var _hurt_after_flash := false


func _init() -> void:
	# Built in code so every entity scene replicates exactly the same state.
	var config := SceneReplicationConfig.new()
	for property in REPLICATED:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	synchronizer.replication_config = config
	add_child(synchronizer)


func _ready() -> void:
	_sprite = get_node_or_null("Sprite")
	if _sprite != null:
		_sprite_rest = _sprite.position
		if tint.a > 0.0:
			_sprite.modulate = tint
	_pip = get_node_or_null("Sprite/Facing")
	if _pip != null:
		_pip_rest = _pip.position
	damaged.connect(_on_damaged)
	pushed.connect(_on_pushed)
	impacted.connect(_on_impacted)
	if not Net.is_authority():
		World.mirror_add(self)
		_mirroring = true


func _exit_tree() -> void:
	if _mirroring:
		_mirroring = false
		World.mirror_remove(self)


## One sim step. Called by World on the server, in ascending id order. Decide
## what to do and ask World to do it (try_move, try_attack, try_shove).
func _sim_tick() -> void:
	pass


func is_creature() -> bool:
	return body_material == BodyMaterial.FLESH


func is_breakable() -> bool:
	return max_hp > 0 \
			and (body_material == BodyMaterial.FLESH or body_material == BodyMaterial.WOOD)


func _process(_delta: float) -> void:
	if spawned:
		var t := 1.0
		if _move_duration > 0:
			t = clampf((World.tick + World.tick_alpha - _move_tick) / _move_duration, 0.0, 1.0)
		position = Iso.tile_to_local(_from_tile).lerp(Iso.tile_to_local(tile), t)
	if _pip != null:
		var screen_facing := Vector2(
				(facing.x - facing.y) * Iso.HALF.x, (facing.x + facing.y) * Iso.HALF.y)
		_pip.position = _pip_rest + screen_facing.normalized() * PIP_REACH
	_update_flash()


# --- World-only hooks. Do not call from anywhere else. ------------------------

func _world_place(new_id: int, at: Vector2i) -> void:
	id = new_id
	tile = at
	_from_tile = at
	_move_duration = 0
	hp = max_hp
	next_move_tick = 0
	next_attack_tick = 0
	has_move_order = false
	action_order = Order.NONE
	action_target = null
	spawned = true


func _world_set_tile(to: Vector2i) -> void:
	tile = to


func _world_set_facing(direction: Vector2i) -> void:
	facing = direction


## Render hint: the entity just went from [param from] to its current tile.
func _world_slide_from(from: Vector2i, at_tick: int, duration: int) -> void:
	_from_tile = from
	_move_tick = at_tick
	_move_duration = duration


func _world_pushed(tiles: int) -> void:
	pushed.emit(tiles)
	if not multiplayer.get_peers().is_empty():
		_net_pushed.rpc(tiles)


func _world_impacted(amount: int) -> void:
	impacted.emit(amount)
	if not multiplayer.get_peers().is_empty():
		_net_impacted.rpc(amount)


func _world_remove() -> void:
	spawned = false


# --- Client mirror ------------------------------------------------------------

## Called by World.mirror_add on a client.
func _mirror_attach() -> void:
	_from_tile = tile
	_move_duration = 0
	spawned = true


## A replicated tile arrived. The client does not know why the entity moved,
## so it picks a slide length from the size of the jump.
func _mirror_tile_changed(old: Vector2i) -> void:
	var delta := tile - old
	var steps := maxi(absi(delta.x), absi(delta.y))
	_from_tile = old
	_move_tick = World.tick + World.tick_alpha
	_move_duration = World.step_ticks(self, delta) if steps == 1 else clampi(steps, 1, 3)
	World.mirror_changed()


# Cosmetic only: they replay feedback, they carry no sim state.
@rpc("authority", "call_remote", "reliable")
func _net_pushed(tiles: int) -> void:
	pushed.emit(tiles)


@rpc("authority", "call_remote", "reliable")
func _net_impacted(amount: int) -> void:
	impacted.emit(amount)


# --- Feedback visuals ---------------------------------------------------------

func _on_pushed(_tiles: int) -> void:
	if _sprite == null:
		return
	if _hop != null:
		_hop.kill()
	_sprite.position = _sprite_rest
	_hop = create_tween()
	_hop.tween_property(_sprite, "position:y", _sprite_rest.y - HOP_HEIGHT, 0.08) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_hop.tween_property(_sprite, "position:y", _sprite_rest.y, 0.12) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _on_impacted(_amount: int) -> void:
	_flash_pending = true


func _on_damaged(_amount: int) -> void:
	_start_hurt_fade()


## Impact flash: overbright for exactly one rendered frame, then the hurt fade.
func _update_flash() -> void:
	if _sprite == null:
		return
	if _flash_pending:
		_flash_pending = false
		_flash_showing = true
		if _fade != null:
			_fade.kill()
		_sprite.self_modulate = IMPACT_FLASH
	elif _flash_showing:
		_flash_showing = false
		_sprite.self_modulate = Color.WHITE
		if _hurt_after_flash:
			_hurt_after_flash = false
			_start_hurt_fade()


func _start_hurt_fade() -> void:
	if _sprite == null:
		return
	# Never cut the one-frame impact flash short; fade once it has shown.
	if _flash_pending or _flash_showing:
		_hurt_after_flash = true
		return
	if _fade != null:
		_fade.kill()
	_sprite.self_modulate = HURT_TINT
	_fade = create_tween()
	_fade.tween_property(_sprite, "self_modulate", Color.WHITE, 0.25)
