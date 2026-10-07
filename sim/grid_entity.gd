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
const REPLICATED: Array[String] = ["tile", "hp", "facing", "stamina", "protected"]
## Reconciliation: a misprediction this far off or less is blended away over
## this many ticks; anything further is snapped.
const SNAP_TILES := 2
const RECONCILE_BLEND_TICKS := 2.0
const HOP_HEIGHT := 6.0
## A body tossed overhead arcs this high instead, and for longer.
const LOFT_HEIGHT := 20.0
## Stamina shown on the body: the sprite's height at 0 stamina...
const TIRED_HEIGHT := 0.7
## ...and a slow bob once stamina is below this fraction.
const WINDED_BELOW := 0.25
const BOB_HEIGHT := 1.5
const BOB_HZ := 0.7
## A stunned body reels: sprite rotation swings this far, this fast.
const REEL_ANGLE := 0.35
const REEL_HZ := 2.5
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
## Drives push force (see World.push_force). 0 means it cannot push at all.
@export var strength := 0
## 0 means no stamina: never tires, never counts as exhausted.
@export var max_stamina := 0
## Cooldown shared by attack and shove.
@export var attack_ticks := 10
## Sprite colour override; alpha 0 means keep the scene's colour.
@export var tint := Color(0, 0, 0, 0)
## Name shown above the sprite; "" for none. Static, set at spawn on every peer.
@export var label := ""

## Assigned by World at spawn, ascending. Decides resolution order. Server only.
var id := 0
## Peer whose input may order this entity; 0 for none. Same on every peer.
var owner_peer := 0
## The MultiplayerSpawner spec this entity was built from, kept so a server
## snapshot can rebuild it. Set by Main on every peer.
var spawn_spec: Dictionary = {}
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
var stamina := 0
## Spawn grace: monsters do not target this entity. Set by World.protect();
## ends after a while or as soon as the entity moves or attacks. Replicated
## so clients can draw it faded.
var protected := false
## Server only: the tick the grace runs out.
var protected_until_tick := 0
## Direction of the last step or attack.
var facing := Vector2i(0, 1)
var spawned := false
var next_move_tick := 0
var next_attack_tick := 0
## Set by World when a collision stuns this entity. Server only.
var stunned_until_tick := 0
var has_move_order := false
var move_order := Vector2i.ZERO
var action_order := Order.NONE
var action_target: GridEntity
## For a shove: the way to toss the target, or ZERO for straight away.
var action_direction := Vector2i.ZERO

# Render interpolation: slide from _from_tile to tile over _move_duration ticks.
var _from_tile := Vector2i.ZERO
var _move_tick := 0.0
var _move_duration := 0
# Mirrors only. A mirror is drawn display_delay_ticks in the past, so by the
# time a tile change arrives the slide for the one before it is still on
# screen. Changes wait here ({from, to, tick, duration}) until the display
# clock reaches them; _to_tile is where the slide being shown ends.
var _slides: Array[Dictionary] = []
var _to_tile := Vector2i.ZERO
## True on a client once this mirror is registered with World.
var _mirroring := false
## Set only on the client that controls this entity. See MovePrediction.
var _prediction: MovePrediction

# Feedback visuals live on the Sprite child, never on this node's position.
var _sprite: Node2D
var _sprite_rest := Vector2.ZERO
var _sprite_rest_scale := Vector2.ONE
## How far the push hop currently lifts the sprite; tweened.
var _hop_offset := 0.0
## Whether the push being shown is an overhead toss (a higher, longer arc).
var _lofted := false
## Tick (this peer's clock) until which the sprite reels from a stun.
var _reel_until := 0.0
# Regen bookkeeping, written by World through the _world_note_* hooks.
var _exerted_tick := -1000
var _moved_tick := -1
var _moved_tiles := 0
var _pip: Node2D
var _pip_rest := Vector2.ZERO
var _name_label: Label
var _speech_label: Label
var _speech_tween: Tween
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
		_sprite_rest_scale = _sprite.scale
		if tint.a > 0.0:
			_sprite.modulate = tint
	_pip = get_node_or_null("Sprite/Facing")
	if _pip != null:
		_pip_rest = _pip.position
	if not label.is_empty():
		_name_label = _make_caption(label, -34.0, Color(1, 1, 1, 0.9))
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


## 0..1; always 1 for an entity that has no stamina.
func stamina_fraction() -> float:
	if max_stamina <= 0:
		return 1.0
	return clampf(float(stamina) / max_stamina, 0.0, 1.0)


## Out of stamina: cannot push, and counts as half its mass when pushed.
func is_exhausted() -> bool:
	return max_stamina > 0 and stamina <= 0


## Tick on which this entity last attacked, shoved, or was moved more than
## one tile. Stamina does not regenerate for a while after it.
func last_exertion_tick() -> int:
	return _exerted_tick


func is_breakable() -> bool:
	return max_hp > 0 \
			and (body_material == BodyMaterial.FLESH or body_material == BodyMaterial.WOOD)


func _process(delta: float) -> void:
	var shown_facing := facing
	if _prediction != null and _prediction.advance(delta):
		# Not a correction but silence: the server is not doing this walk.
		_prediction.give_up()
		_mispredicted("no confirmation from the server")
	if spawned:
		if _prediction != null and _prediction.is_active():
			# The local player's own walking: shown ahead of the server.
			position = _prediction.position()
			shown_facing = _prediction.facing()
		else:
			# Mirrors are drawn slightly in the past, so a tile change is
			# always known before its slide has to start.
			var now := World.tick + World.tick_alpha
			var to := tile
			if _mirroring:
				now -= World.display_delay_ticks
				while not _slides.is_empty() and now >= _slides[0]["tick"]:
					var slide: Dictionary = _slides.pop_front()
					_from_tile = slide["from"]
					_to_tile = slide["to"]
					_move_tick = slide["tick"]
					_move_duration = slide["duration"]
				to = _to_tile
			var t := 1.0
			if _move_duration > 0:
				t = clampf((now - _move_tick) / _move_duration, 0.0, 1.0)
			position = Iso.tile_to_local(_from_tile).lerp(Iso.tile_to_local(to), t)
	if _pip != null:
		var screen_facing := Vector2(
				(shown_facing.x - shown_facing.y) * Iso.HALF.x,
				(shown_facing.x + shown_facing.y) * Iso.HALF.y)
		_pip.position = _pip_rest + screen_facing.normalized() * PIP_REACH
	_update_body()
	_update_flash()


## Stamina is read off the body: it sags toward TIRED_HEIGHT as stamina drops
## (feet stay planted) and bobs slowly when nearly spent. The push hop is
## added on top. All of it on the Sprite child, never on this node.
func _update_body() -> void:
	var body := _sprite as Sprite2D
	if body == null:
		return
	var offset := -_hop_offset
	if max_stamina > 0:
		var fraction := clampf(float(stamina) / max_stamina, 0.0, 1.0)
		var height := lerpf(TIRED_HEIGHT, 1.0, fraction)
		body.scale.y = _sprite_rest_scale.y * height
		offset += (1.0 - height) * body.get_rect().size.y * 0.5 * _sprite_rest_scale.y
		if fraction < WINDED_BELOW:
			var phase := Time.get_ticks_msec() / 1000.0 * TAU * BOB_HZ + get_instance_id() % 7
			offset += sin(phase) * BOB_HEIGHT
	body.position.y = _sprite_rest.y + offset
	# Spawn grace reads as a faded body.
	body.modulate.a = 0.5 if protected else 1.0
	# Stunned: reel from side to side until it wears off.
	if World.tick + World.tick_alpha < _reel_until:
		body.rotation = sin(Time.get_ticks_msec() / 1000.0 * TAU * REEL_HZ) * REEL_ANGLE
	else:
		body.rotation = 0.0


# --- World-only hooks. Do not call from anywhere else. ------------------------

func _world_place(new_id: int, at: Vector2i) -> void:
	id = new_id
	tile = at
	_from_tile = at
	_move_duration = 0
	hp = max_hp
	stamina = max_stamina
	stunned_until_tick = 0
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


func _world_note_exertion(on_tick: int) -> void:
	_exerted_tick = on_tick


func _world_note_moved(on_tick: int) -> void:
	if _moved_tick != on_tick:
		_moved_tick = on_tick
		_moved_tiles = 0
	_moved_tiles += 1
	# One tile is a step. More than one in a tick is being thrown.
	if _moved_tiles > 1:
		_exerted_tick = on_tick


func _world_pushed(tiles: int, lofted := false) -> void:
	_lofted = lofted
	pushed.emit(tiles)
	if not multiplayer.get_peers().is_empty():
		_net_pushed.rpc(tiles, lofted)


func _world_impacted(amount: int) -> void:
	impacted.emit(amount)
	if not multiplayer.get_peers().is_empty():
		_net_impacted.rpc(amount)


func _world_stunned(until_tick: int, ticks: int) -> void:
	stunned_until_tick = until_tick
	_reel_until = until_tick
	if not multiplayer.get_peers().is_empty():
		_net_stunned.rpc(ticks)


func _world_remove() -> void:
	spawned = false


# --- Client mirror ------------------------------------------------------------

## Called by World.mirror_add on a client.
func _mirror_attach() -> void:
	_mirror_rest()
	spawned = true


## Draw the mirror standing on its tile, with no slide shown or waiting.
func _mirror_rest() -> void:
	_from_tile = tile
	_to_tile = tile
	_move_duration = 0
	_slides.clear()


## A replicated tile arrived.
func _mirror_tile_changed(old: Vector2i) -> void:
	World.mirror_changed()
	if _prediction != null and _prediction.is_active():
		if _prediction.reconcile(tile):
			# Already on screen: the prediction showed this step.
			_mirror_rest()
		else:
			# Somewhere the prediction did not go (blocked, re-pathed, pushed).
			_mispredicted("the server moved it elsewhere")
		return
	# Interpolate: slide from the old tile, starting when the display clock
	# reaches the tick this arrived in. Until then the slide before it plays
	# out; replacing it here would cut every step short and jump to its end.
	# The client is not told why the entity moved, so the slide length comes
	# from the size of the jump (one step, or a push).
	var delta := tile - old
	var steps := maxi(absi(delta.x), absi(delta.y))
	_slides.append({"from": old, "to": tile, "tick": World.tick,
		"duration": World.step_ticks(self, delta) if steps == 1 else clampi(steps, 1, 3)})


## Turns on prediction of this entity's own walking. Only meaningful on the
## client that controls it; everywhere else it does nothing.
func enable_prediction() -> void:
	if _mirroring and _prediction == null:
		_prediction = MovePrediction.new(self)


## The local player just ordered a move: start showing it now.
func predict_move(target: Vector2i) -> void:
	if _prediction != null:
		_prediction.order(target)


## The local player just ordered an attack or shove on something standing on
## [param target_tile]: show the walk up to it. The hit itself is not predicted.
func predict_approach(target_tile: Vector2i) -> void:
	if _prediction != null:
		_prediction.order(target_tile, false)


## Tile the sprite is drawn on, which on the predicting client may be ahead
## of [member tile].
func shown_tile() -> Vector2i:
	return Iso.local_to_tile(position)


## The server's result wins: snap to its tile and forget the predicted path.
## The server's result wins. A small error is blended away over
## RECONCILE_BLEND_TICKS and the path re-planned from the server's tile; an
## error of more than SNAP_TILES is snapped.
func _mispredicted(reason: String) -> void:
	var predicted := _prediction.predicted_tile()
	var error := World.distance(predicted, tile)
	Net.record_mispredict()
	_mirror_rest()
	if error > SNAP_TILES:
		_prediction.clear()
		Net.record_snap()
		print("[net] mispredict: %s predicted %s, server has %s, %d tiles off: snapped (%s)" % [
			name, predicted, tile, error, reason])
	else:
		_prediction.rebase(tile, RECONCILE_BLEND_TICKS)
		print("[net] mispredict: %s predicted %s, server has %s: blending (%s)" % [
			name, predicted, tile, reason])


## The server refused a step into [param refused] this tick. Re-plan from
## its tile now rather than waiting out the deadline.
func _on_move_refused(refused: Vector2i) -> void:
	if _prediction == null or not _prediction.is_active():
		return
	Net.record_mispredict()
	_mirror_rest()
	# A refused step into the destination itself: the server has dropped the
	# order (see Player._sim_tick), so there is nothing left to predict.
	if refused == _prediction.target():
		_prediction.give_up()
	_prediction.rebase(tile, RECONCILE_BLEND_TICKS)
	print("[net] mispredict: %s step into %s refused, server has %s: %s" % [
		name, refused, tile, "re-planned" if _prediction.has_target() else "order given up"])


# Cosmetic only: they replay feedback, they carry no sim state.
@rpc("authority", "call_remote", "reliable")
func _net_pushed(tiles: int, lofted: bool) -> void:
	_lofted = lofted
	pushed.emit(tiles)


@rpc("authority", "call_remote", "reliable")
func _net_impacted(amount: int) -> void:
	impacted.emit(amount)


@rpc("authority", "call_remote", "reliable")
func _net_stunned(ticks: int) -> void:
	_reel_until = World.tick + ticks


## A line of speech over the sprite for a few seconds. Visual only.
func say(text: String) -> void:
	if _speech_label == null:
		_speech_label = _make_caption("", -46.0, Color(1, 0.95, 0.6))
	_speech_label.text = text
	_speech_label.visible = true
	if _speech_tween != null:
		_speech_tween.kill()
	_speech_tween = create_tween()
	_speech_tween.tween_interval(3.0)
	_speech_tween.tween_callback(func() -> void: _speech_label.visible = false)


## A caption 8 world px tall. Fonts are rasterised at the viewport's
## scale, not the camera's, so the label is set in a font the camera zoom
## times larger and scaled back down, to come out sharp on screen.
func _make_caption(text: String, y: float, color: Color) -> Label:
	var caption := Label.new()
	var camera := get_viewport().get_camera_2d() if is_inside_tree() else null
	var zoom := camera.zoom.x if camera != null else 1.0
	caption.text = text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", roundi(8 * zoom))
	caption.add_theme_color_override("font_color", color)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	caption.add_theme_constant_override("outline_size", roundi(2 * zoom))
	caption.size = Vector2(120, 12) * zoom
	caption.scale = Vector2.ONE / zoom
	caption.position = Vector2(-60, y)
	caption.z_index = 5
	add_child(caption)
	return caption


# --- Feedback visuals ---------------------------------------------------------

func _on_pushed(_tiles: int) -> void:
	if _sprite == null:
		return
	if _hop != null:
		_hop.kill()
	_hop_offset = 0.0
	_hop = create_tween()
	var height := LOFT_HEIGHT if _lofted else HOP_HEIGHT
	var stretch := 1.8 if _lofted else 1.0
	_hop.tween_property(self, "_hop_offset", height, 0.08 * stretch) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_hop.tween_property(self, "_hop_offset", 0.0, 0.12 * stretch) \
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
