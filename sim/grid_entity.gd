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
## Stopped with force left over, or hit by something that was;
## [param against] is what it hit: &"stone", &"wood", &"body", or &"".
signal impacted(amount: int, against: StringName)
## Lost [param amount] hp to [param cause] (&"attack", &"impact", &"fire").
## On every peer (relayed to clients), for the views' sounds and bars.
signal struck(amount: int, cause: StringName)
## An attack or a swing at air went [param direction]: views lunge.
signal swung(direction: Vector2i)

# Not called "Material"/"material": CanvasItem already owns that name.
## FLESH is a creature (hazards hurt it). WOOD takes impact and breaks at 0 hp.
## STONE and METAL never break.
enum BodyMaterial { FLESH, WOOD, STONE, METAL }
enum Order { NONE, ATTACK, SHOVE, SWING }

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
## How fast the shown facing turns toward where it should point: about
## 100 ms to come round (an exponential ease at this rate per second).
const TURN_RATE := 30.0
## A push not yet drawn this many ticks after it came is taken as over.
const PUSH_SHOWN_TICKS := 14.0
## A refused or corrected step eases to a stop over this many ticks.
const STOP_EASE_TICKS := 2.0
const IMPACT_FLASH := Color(4.0, 4.0, 4.0)
const HURT_TINT := Color(1.0, 0.3, 0.3)

@export var start_tile := Vector2i.ZERO
@export var mass := 10.0
@export var body_material := BodyMaterial.FLESH
## Can be shoved along by something walking into it. Force pushes ignore this.
@export var pushable := false
@export var blocks_sight := false
## The zone (World.zones) this entity is in; its spawn spec says, and
## World.spawn makes sure. "" on a client, which has one.
var zone := ""
## Its synchronizer, whose visibility filter keeps it to its zone's clients.
var sync: MultiplayerSynchronizer
## Light and heat this body gives off where it stands (Fields): a carried
## lantern, a burning thing.
@export var emit_light := 0.0
@export var emit_heat := 0.0
## Ticks one step takes, maybe fractional; also the cooldown before the
## next step.
@export var move_ticks := 2.0
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
## A companion: the peer whose player it belongs to; 0 for anything else.
## Set from the spawn spec, and on a rejoin (a new peer) by Main; a
## companion replicates it, so a client always knows its own.
var keeper_peer := 0
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
## What it holds, a slot each: Items ids, "" for empty. None for most
## things; a player and a chest have theirs (Player.SLOTS, Chest.SLOTS),
## replicated (replicate). Written only by World (try_transfer, set_slots).
var slots := PackedStringArray()
var spawned := false
## The tick (maybe fractional) the next step may start; see World.try_move.
var next_move_tick := 0.0
var next_attack_tick := 0
## Set by World when a collision stuns this entity. Server only.
var stunned_until_tick := 0
var has_move_order := false
var move_order := Vector2i.ZERO
## Tiles to walk through, in order, before pathing to move_order: the steps
## the ordering client was already showing. Server only.
var move_via: Array[Vector2i] = []
## Where the local client points the body while it stands still (WASD:
## the cursor), in grid units from its tile; ZERO for none. Display only.
var aim := Vector2.ZERO
var action_order := Order.NONE
var action_target: GridEntity
## For a shove: the way to toss the target, or ZERO for straight away.
var action_direction := Vector2i.ZERO

# Render interpolation: slide from _from_tile to tile over _move_duration ticks.
var _from_tile := Vector2i.ZERO
## Where the slide being shown starts, in grid space: _from_tile's cell, or
## wherever the body was drawn when a present push took it (see _present).
var _from_pos := Vector2.ZERO
var _move_tick := 0.0
var _move_duration := 0.0
## The facing as shown, an angle in grid space, turning toward the wanted
## one at TURN_RATE.
var _shown_angle := NAN
# Mirrors only. A mirror is drawn display_delay_ticks in the past, so by the
# time a tile change arrives the slide for the one before it is still on
# screen. Changes wait here ({from, to, tick, duration}) until the display
# clock reaches them; _to_tile is where the slide being shown ends.
var _slides: Array[Dictionary] = []
var _to_tile := Vector2i.ZERO
## Mirrors only: the slide being shown is timed by the present clock, not
## the display clock: a push the local player made, or took, is drawn as
## soon as the server's word of it comes, from wherever the body is drawn,
## instead of display_delay_ticks later (decision 161).
var _present := false
## Mirrors only: a push the server has told of whose tile has not arrived
## yet: {from, to, tick, duration, present}.
var _pending_push := {}
## Mirrors only: a shove by the local player, guessed and shown before the
## server's word ({to, until}); and, once one of the server's two words
## (the push, the tile) has confirmed it, where, so the other changes
## nothing (see guess_knock).
var _guess := {}
var _guess_confirmed := Vector2i(-9999, -9999)
## The local player, on a client: the tick before which it is taken to be
## still cooling down from its last shove, for guessing (World._predict_shove).
var _guessed_ready_tick := 0
## The local player, on a client: when (display clock) a walk of its own was
## last shown. The server is a step behind the screen, so a shove soon after
## waits there for that step to end (see World._predict_shove).
var _walk_shown_at := -INF
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
## Whether the push being shown is a toss (aimed, or overhead), not a
## plain push back: the 3D view rolls it and lands it instead of
## backpedalling.
var tossed := false
## The last push, as drawn: WAITING until its slide shows, SLIDING while
## it does (a mirror may draw it as several shorter slides, and pause
## between them), OVER once it has reached where it was pushed to, or the
## body steps off on its own. Any slide from a tile to another along the
## push's line, its way, is the push's own: the body is knocked along it,
## not walking, so its shown facing does not turn to it. For the views.
enum PushShown { NONE, WAITING, SLIDING, OVER }
var push_shown := PushShown.NONE
## The way the last push sent the body, a grid step; ZERO for none.
var push_direction := Vector2i.ZERO
## True while the body is drawn taking a step of its own (any slide that is
## not its push's).
var stepping := false
var _push_from := Vector2i.ZERO
var _push_to := Vector2i.ZERO
## Tick (this peer's clock) of the last push.
var _pushed_tick := -INF
## Tick (this peer's clock) until which the sprite reels from a stun.
var _reel_until := 0.0
# Regen bookkeeping, written by World through the _world_note_* hooks.
var _exerted_tick := -1000
var _moved_tick := -1
var _moved_tiles := 0
var _pip: Node2D
var _pip_rest := Vector2.ZERO
var _name_label: Label
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
	# Spawned on, and synchronized to, only the clients in its zone. Asked
	# when it spawns and when a player changes zone (World.update_visibility),
	# not every frame: thousands of them asking each frame took a third of
	# a big map's frame.
	synchronizer.add_visibility_filter(_visible_to)
	synchronizer.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	add_child(synchronizer)
	sync = synchronizer


## Adds [param property] to what this entity replicates, on change, from
## its spawn on: for a subclass's own state (a chest's slots). Call it from
## _init, after super(), on every peer alike.
func replicate(property: String) -> void:
	var path := NodePath(".:" + property)
	sync.replication_config.add_property(path)
	sync.replication_config.property_set_spawn(path, true)
	sync.replication_config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)


## Whether the client [param peer] is sent this entity (World.peer_sees).
func _visible_to(peer: int) -> bool:
	return World.peer_sees(peer, zone)


## The peers its events go to: those it can be sent to whose players are in
## its zone (a peer elsewhere has no such node, and would be sent nothing it
## could take).
func viewers() -> Array[int]:
	var peers: Array[int] = []
	for peer in Net.sendable_peers():
		if _visible_to(peer):
			peers.append(peer)
	return peers


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


## Whether it has a turn of its own (_sim_tick): false for those that only
## ever move when moved (a crate, a chest), which World's act phase then
## passes over without asking.
var acts := true


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


## Whether the 2D view is drawn on this peer (Main._draws_2d): its sprites'
## frame-by-frame touches are skipped where it is not.
static var draws_2d := true


func _process(delta: float) -> void:
	var wanted := Vector2(facing)
	if _prediction != null and _prediction.advance(delta):
		# Not a correction but silence: the server is not doing this walk.
		_prediction.give_up()
		_mispredicted("no confirmation from the server")
	elif _prediction != null and _prediction.take_route_changed():
		_resend_walk()  # Planned again on the way: the server walks the new plan.
	if spawned:
		if _prediction != null and _prediction.is_active():
			# The local player's own walking: shown ahead of the server.
			position = _prediction.position()
			_walk_shown_at = World.tick + World.tick_alpha
			if _prediction.facing() != Vector2i.ZERO:
				wanted = Vector2(_prediction.facing())
		else:
			# Mirrors are drawn slightly in the past, so a tile change is
			# always known before its slide has to start.
			var now := World.tick + World.tick_alpha
			var to := tile
			if _mirroring:
				var shown := now - World.display_delay_ticks
				# A present push plays out before anything after it.
				var held := _present and now < _move_tick + _move_duration
				while not held and not _slides.is_empty() \
						and (_slides[0].get("present", false) or shown >= _slides[0]["tick"]):
					var slide: Dictionary = _slides.pop_front()
					if _present and not slide.get("present", false) and shown > slide["tick"]:
						# Back to the display clock after a present push: what
						# came due meanwhile goes on from here, one after
						# another, not all at once (a jump to the last).
						var late: float = shown - slide["tick"]
						slide["tick"] = shown
						slide["from_pos"] = Iso.local_to_grid(position)
						for later: Dictionary in _slides:
							later["tick"] = later["tick"] + late
					_from_tile = slide["from"]
					_to_tile = slide["to"]
					_move_tick = slide["tick"]
					_move_duration = slide["duration"]
					_present = slide.get("present", false)
					_from_pos = slide.get("from_pos", Vector2(_from_tile))
					held = _present
				if not _present:
					now = shown
				if not _guess.is_empty() and World.tick + World.tick_alpha > float(_guess["until"]):
					_take_back_guess()
				to = _to_tile
			# Constant speed along the step, no easing at its ends: steps
			# that follow one another join up into one steady walk.
			var t := 1.0
			if _move_duration > 0.0:
				t = clampf((now - _move_tick) / _move_duration, 0.0, 1.0)
			position = Iso.grid_to_local(_from_pos.lerp(Vector2(to), t))
			var sliding := t < 1.0 and to != _from_tile
			var knocked := sliding and _on_push_line(_from_tile, to)
			stepping = sliding and not knocked
			_note_push_shown(knocked, to, t)
			if stepping:
				wanted = Vector2(to - _from_tile)
			elif aim != Vector2.ZERO:
				wanted = aim
	_turn_toward(wanted, delta)
	if not draws_2d:
		return  # Its sprite is not seen: no bob, reel or flash to draw.
	if _pip != null:
		var screen_facing := Iso.project(shown_facing())
		_pip.position = _pip_rest + screen_facing.normalized() * PIP_REACH
	_update_body()
	_update_flash()


## Whether a slide from [param from] to [param to] goes along the last
## push's line, its way: the push's own.
func _on_push_line(from: Vector2i, to: Vector2i) -> bool:
	if push_shown != PushShown.WAITING and push_shown != PushShown.SLIDING:
		return false
	var a := _push_index(from)
	var b := _push_index(to)
	return a >= 0 and b > a


## How many of the push's steps [param cell] is from where it started, or
## -1 if it is not on the push's line.
func _push_index(cell: Vector2i) -> int:
	var steps := maxi(absi(_push_to.x - _push_from.x), absi(_push_to.y - _push_from.y))
	for k in steps + 1:
		if _push_from + push_direction * k == cell:
			return k
	return -1


## Moves push_shown along from what is drawn this frame: [param knocked],
## a slide of the push's on screen, [param to] where the slide drawn ends,
## [param t] how far along it.
func _note_push_shown(knocked: bool, to: Vector2i, t: float) -> void:
	match push_shown:
		PushShown.WAITING:
			if knocked:
				push_shown = PushShown.SLIDING
			elif (to == _push_to and t >= 1.0) or World.tick - _pushed_tick > PUSH_SHOWN_TICKS:
				# Drawn there already without a slide (a client that skipped it).
				push_shown = PushShown.OVER
		PushShown.SLIDING:
			if stepping or (to == _push_to and t >= 1.0) or World.tick - _pushed_tick > PUSH_SHOWN_TICKS:
				push_shown = PushShown.OVER


## A push to show: from [param from] to [param to].
func _note_pushed(from: Vector2i, to: Vector2i) -> void:
	_pushed_tick = float(World.tick)
	_push_from = from
	_push_to = to
	push_direction = Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	push_shown = PushShown.WAITING if to != from else PushShown.OVER


## Eases the shown facing toward [param wanted] (grid units), the short
## way round, at TURN_RATE.
func _turn_toward(wanted: Vector2, delta: float) -> void:
	if wanted == Vector2.ZERO:
		return
	var target := wanted.angle()
	if is_nan(_shown_angle):
		_shown_angle = target
		return
	var step := angle_difference(_shown_angle, target) * (1.0 - exp(-TURN_RATE * delta))
	_shown_angle = wrapf(_shown_angle + step, -PI, PI)


## Puts the shown facing at [param angle] (grid space), to turn back from
## there to the facing, smoothly: a view that turned the body its own way
## hands it back so.
func turn_shown_from(angle: float) -> void:
	_shown_angle = wrapf(angle, -PI, PI)


## The facing as shown: a unit vector in grid units, turning smoothly.
func shown_facing() -> Vector2:
	if is_nan(_shown_angle):
		return Vector2(facing).normalized()
	return Vector2.from_angle(_shown_angle)


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
func _world_slide_from(from: Vector2i, at_tick: float, duration: float) -> void:
	_from_tile = from
	_from_pos = Vector2(from)
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


## Pushed from [param from] to here, drawn sliding from [param at_tick] for
## [param duration] ticks; [param by_peer] is the shover's player's peer
## (0 for anything else). The clients get all of it, so each draws the same
## slide, and the shover's draws it at once.
func _world_pushed(tiles: int, lofted: bool, toss: bool, from: Vector2i, at_tick: float,
		duration: float, by_peer: int) -> void:
	_lofted = lofted
	tossed = toss
	_note_pushed(from, tile)
	pushed.emit(tiles)
	for peer in viewers():
		_net_pushed.rpc_id(peer, tiles, lofted, toss, from, tile, at_tick, duration, by_peer)


func _world_impacted(amount: int, against: StringName) -> void:
	impacted.emit(amount, against)
	for peer in viewers():
		_net_impacted.rpc_id(peer, amount, against)


func _world_damaged(amount: int, cause: StringName) -> void:
	damaged.emit(amount)
	struck.emit(amount, cause)
	for peer in viewers():
		_net_struck.rpc_id(peer, amount, cause)


func _world_swung(direction: Vector2i) -> void:
	swung.emit(direction)
	for peer in viewers():
		_net_swung.rpc_id(peer, direction)


func _world_stunned(until_tick: int, ticks: int) -> void:
	stunned_until_tick = until_tick
	_reel_until = until_tick
	for peer in viewers():
		_net_stunned.rpc_id(peer, ticks)


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
	_from_pos = Vector2(tile)
	_to_tile = tile
	_move_duration = 0.0
	_present = false
	_slides.clear()


## A replicated tile arrived.
func _mirror_tile_changed(old: Vector2i) -> void:
	World.mirror_changed()
	if tile == _guess_confirmed:
		# The push's word came first and confirmed the guess being shown.
		_guess_confirmed = Vector2i(-9999, -9999)
		return
	if not _guess.is_empty():
		var guessed: Vector2i = _guess["to"]
		_guess = {}
		if tile == guessed:
			# Right: the guess being shown is the push; its word changes nothing.
			_guess_confirmed = tile
			return
	if not _pending_push.is_empty() and _pending_push["to"] == tile:
		# Thrown: the server said so before the tile came, with its timing.
		var push := _pending_push
		_pending_push = {}
		push["from"] = old
		_show_push(push)
		return
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
	# A step that follows straight on from the one before starts where it
	# ends, not on the tick it arrived in: the server takes a 2.5-tick step
	# on a whole tick, and the walk would otherwise stutter by the fraction.
	var start := float(World.tick)
	var previous_end := _move_tick + _move_duration
	if not _slides.is_empty():
		previous_end = _slides.back()["tick"] + _slides.back()["duration"]
	if steps == 1 and previous_end > start - 1.0 and previous_end < start + 1.0:
		start = previous_end
	_slides.append({"from": old, "to": tile, "tick": start,
		"duration": World.step_ticks(self, delta) if steps == 1 else float(clampi(steps, 1, 3))})


## True while this client is showing its own walk ahead of the server.
func predicting() -> bool:
	return _prediction != null and _prediction.is_active()


## Turns on prediction of this entity's own walking. Only meaningful on the
## client that controls it; everywhere else it does nothing.
func enable_prediction() -> void:
	if _mirroring and _prediction == null:
		_prediction = MovePrediction.new(self)


## The local player just ordered a move: start showing it now. Returns the
## tiles of the steps already on screen that the server has not confirmed,
## which it must walk first (see World.command_move).
func predict_move(target: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if _prediction == null:
		return none
	return _prediction.order(target)


## WASD: the local player asked for one step that way. Shown at once
## unless the replicated world refuses it; true if it is shown.
func predict_step(direction: Vector2i) -> bool:
	if _prediction == null:
		return false
	return _prediction.step(direction)


## Whether the local player's walk is ready for its next WASD step: the
## one on screen is ending. Always true without prediction (the server
## queues and times the steps itself).
func ready_for_step() -> bool:
	return _prediction == null or _prediction.ready_for_step()


## Where the walk on screen ends: the last predicted step's tile, or the
## entity's own.
func walk_end() -> Vector2i:
	if _prediction != null and _prediction.is_active():
		return _prediction._steps.back().to
	return tile


## Refusals of this entity's steps the client has heard of (see
## World.order_step).
func step_epoch() -> int:
	return _prediction.epoch if _prediction != null else 0


## The local player just ordered an attack or shove on something standing on
## [param target_tile]: show the walk up to it. The hit itself is not predicted.
## Closing in on [param target] to strike: shown at once. Returns the steps
## already under way on screen that the server has not confirmed: it walks
## them before closing in (World._order_action).
func predict_approach(target_tile: Vector2i, target: GridEntity = null) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if _prediction == null:
		return none
	_prediction.order(target_tile, false)
	_prediction.follow(target)
	return _prediction.in_flight()


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
	var off := (Iso.local_to_grid(position) - Vector2(tile)).length()
	Net.record_mispredict()
	Net.stats.record_correction(off, error > SNAP_TILES)
	_mirror_rest()
	if error > SNAP_TILES:
		_prediction.clear()
		Net.record_snap()
		print("[net] mispredict: %s predicted %s, server has %s, %d tiles off: snapped (%s)" % [
			name, predicted, tile, error, reason])
	else:
		_prediction.rebase(tile, RECONCILE_BLEND_TICKS)
		_resend_walk()
		print("[net] mispredict: %s predicted %s, server has %s: blending (%s), %.2f tiles off" % [
			name, predicted, tile, reason, off])


## After a correction: the walk re-planned from the server's tile goes to
## the server as the order, so it walks it rather than a way of its own.
func _resend_walk() -> void:
	if _prediction.is_walking_to_target():
		World.resend_move(self, _prediction.target(), _prediction.unconfirmed())


## The server refused a step into [param refused] this tick. Re-plan from
## its tile now rather than waiting out the deadline. [param epoch] is the
## server's refusal count for WASD steps.
func _on_move_refused(refused: Vector2i, epoch: int) -> void:
	if _prediction == null:
		return
	_prediction.epoch = maxi(_prediction.epoch, epoch)
	if not _prediction.is_active():
		return
	Net.record_mispredict()
	var off := (Iso.local_to_grid(position) - Vector2(tile)).length()
	Net.stats.record_correction(off, false)
	_mirror_rest()
	# A refused step into the destination itself, or a strike's closing in
	# that the server gave up (World.ORDER_DROPPED): the server has dropped
	# the order (Player._sim_tick, _pursue_action), so there is nothing left
	# to predict.
	if refused == _prediction.target() or epoch == World.ORDER_DROPPED:
		_prediction.give_up()
	_prediction.rebase(tile, RECONCILE_BLEND_TICKS)
	_resend_walk()
	print("[net] mispredict: %s step into %s refused, server has %s: %s, %.2f tiles off" % [
		name, refused, tile, "re-planned" if _prediction.has_target() else "order given up", off])


# Cosmetic only: they replay feedback, they carry no sim state.
@rpc("authority", "call_remote", "reliable")
func _net_pushed(tiles: int, lofted: bool, toss: bool, from: Vector2i, to: Vector2i, at_tick: float,
		duration: float, by_peer: int) -> void:
	_lofted = lofted
	tossed = toss
	var guessed: Vector2i = Vector2i(-9999, -9999) if _guess.is_empty() else _guess["to"]
	_guess = {}
	if to == _guess_confirmed or to == guessed:
		# The guess being shown was right: on with it, the knock already
		# under way. Its tile, if still to come, changes nothing either.
		_note_pushed(from, to)
		_guess_confirmed = to if tile != to else Vector2i(-9999, -9999)
		return
	if guessed != Vector2i(-9999, -9999):
		print("[net] shove guess: %s guessed %s, server has %s" % [name, guessed, to])
	_note_pushed(from, to)
	pushed.emit(tiles)
	if not _mirroring or tiles <= 0:
		if guessed != Vector2i(-9999, -9999):
			_take_back_guess()
		return
	var push := {"from": from, "to": to, "tick": at_tick, "duration": duration,
		"present": by_peer == multiplayer.get_unique_id() or _prediction != null}
	if tile != to:
		# The tile comes after: the slide waits for it (_mirror_tile_changed).
		_pending_push = push
		return
	# The tile came first and its slide was guessed from the jump: the
	# server's timing goes on it.
	if not push["present"]:
		for slide: Dictionary in _slides:
			if slide["to"] == to:
				slide["tick"] = at_tick
				slide["duration"] = duration
				return
	if push["present"] or (_to_tile == to and _from_tile == from):
		push["from"] = _from_tile if _to_tile == to else from
		_show_push(push)


## Client: the local player's shove will throw this body to [param to]:
## shown now, over [param duration] ticks, as if the server had said so.
## Its word (the push, the tile) confirms it, or puts it where the server
## did; none by Net.rtt_ticks() and two ticks more, and it slides back.
func guess_knock(to: Vector2i, duration: float) -> void:
	if not _mirroring or _prediction != null or to == tile:
		return
	tossed = false
	_lofted = false
	_note_pushed(tile, to)
	pushed.emit(World.distance(tile, to))
	var now := World.tick + World.tick_alpha
	_guess = {"to": to, "until": now + Net.rtt_ticks() + 2.0}
	_slides.clear()
	_slides.append({"from": tile, "to": to, "tick": now, "duration": duration, "present": true,
		"from_pos": Iso.local_to_grid(position)})
	_present = false


## A guessed knock nobody confirmed: back to the tile, from wherever it is.
func _take_back_guess() -> void:
	if not _guess.is_empty():
		print("[net] shove guess: %s guessed %s, no push came: taken back" % [name, _guess["to"]])
	_guess = {}
	push_shown = PushShown.OVER
	_slides.clear()
	_slides.append({"from": _to_tile, "to": tile, "tick": World.tick + World.tick_alpha, "duration": 2.0,
		"present": true, "from_pos": Iso.local_to_grid(position)})
	_present = false


## Shows [param push] ({from, to, tick, duration, present}): a present one
## at once, from wherever the body is drawn, dropping what was waiting (the
## steps before it, already past for the server); any other in its turn on
## the display clock, as the server timed it.
func _show_push(push: Dictionary) -> void:
	if _prediction != null and _prediction.is_active():
		# The local player, thrown: no misprediction, just the server's slide.
		_prediction.clear()
	var slide := {"from": push["from"], "to": push["to"], "tick": push["tick"], "duration": push["duration"]}
	if push["present"]:
		slide["present"] = true
		slide["tick"] = World.tick + World.tick_alpha
		slide["from_pos"] = Iso.local_to_grid(position)
		_slides.clear()
		_present = false
	elif _to_tile == push["to"] and _from_tile == push["from"]:
		# Already being shown, guessed: retimed in place.
		_move_tick = push["tick"]
		_move_duration = push["duration"]
		return
	_slides.append(slide)


@rpc("authority", "call_remote", "reliable")
func _net_impacted(amount: int, against: StringName) -> void:
	impacted.emit(amount, against)


@rpc("authority", "call_remote", "reliable")
func _net_struck(amount: int, cause: StringName) -> void:
	struck.emit(amount, cause)


@rpc("authority", "call_remote", "reliable")
func _net_stunned(ticks: int) -> void:
	_reel_until = World.tick + ticks


@rpc("authority", "call_remote", "reliable")
func _net_swung(direction: Vector2i) -> void:
	swung.emit(direction)


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


func _on_impacted(_amount: int, _against: StringName) -> void:
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
