class_name GridEntity
extends Node2D
## Base class for everything that occupies a tile.
##
## Sim state (tile, hp, cooldowns) is written only by World, or by _sim_tick(),
## which World calls from inside the server-gated tick. Node2D.position is a
## render-only value derived from that state in _process(); nothing else may
## write it. See docs/design.md.

@warning_ignore("unused_signal")  # Emitted by World.damage().
signal damaged(amount: int)

# Not called "Material"/"material": CanvasItem already owns that name.
enum BodyMaterial { FLESH, WOOD, STONE, METAL }

@export var start_tile := Vector2i.ZERO
@export var mass := 10.0
@export var body_material := BodyMaterial.FLESH
@export var pushable := false
@export var blocks_sight := false
## Ticks one step takes; also the cooldown before the next step.
@export var move_ticks := 2
## 0 means indestructible.
@export var max_hp := 0
@export var attack_damage := 0
@export var attack_ticks := 10

var tile := Vector2i.ZERO
var spawned := false
var hp := 0
var next_move_tick := 0
var next_attack_tick := 0
var has_move_order := false
var move_order := Vector2i.ZERO

# Render interpolation: slide from _from_tile to tile over _move_duration ticks.
var _from_tile := Vector2i.ZERO
var _move_tick := 0
var _move_duration := 0


func _ready() -> void:
	damaged.connect(_on_damaged)


## One sim step. Called by World on the server, in spawn order. Decide what to
## do and ask World to do it (World.try_move, World.try_attack).
func _sim_tick() -> void:
	pass


func _process(_delta: float) -> void:
	if not spawned:
		return
	var t := 1.0
	if _move_duration > 0:
		t = clampf((World.tick + World.tick_alpha - _move_tick) / _move_duration, 0.0, 1.0)
	position = Iso.tile_to_local(_from_tile).lerp(Iso.tile_to_local(tile), t)


# --- World-only hooks. Do not call from anywhere else. ------------------------

func _world_place(at: Vector2i, _tick: int) -> void:
	tile = at
	_from_tile = at
	_move_duration = 0
	hp = max_hp
	next_move_tick = 0
	next_attack_tick = 0
	has_move_order = false
	spawned = true


func _world_set_tile(to: Vector2i, at_tick: int, duration: int) -> void:
	_from_tile = tile
	tile = to
	_move_tick = at_tick
	_move_duration = duration


func _world_remove() -> void:
	spawned = false


func _on_damaged(_amount: int) -> void:
	modulate = Color(1.0, 0.3, 0.3)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.25)
