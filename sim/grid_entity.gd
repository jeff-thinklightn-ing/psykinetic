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
## Lost [param amount] hp to [param cause] (&"attack", &"shot", &"impact", &"fire").
## On every peer (relayed to clients), for the views' sounds and bars.
signal struck(amount: int, cause: StringName)
## An attack or a swing at air went [param direction]: views lunge.
signal swung(direction: Vector2i)
## A shot (World.shoot) flew from here to [param to], the point it stopped
## at in cell units (a cell's centre at Vector2(cell); decision 583),
## stopped by [param struck]: &"body", &"wood", &"stone", or &"ground"
## (its range spent: it comes down past the point). Views draw the arrow.
## On every peer.
signal shot(to: Vector2, struck: StringName)
## A thing it held (Items id [param item_id]) was thrown down a line
## (World.hurl, decision 606) and came down at [param to]: views draw its
## flight with the thing's art. On every peer.
signal hurled(item_id: String, to: Vector2i)
## A blow or a shot was taken on its guard, or [param broken] it
## (World._meet_guard): views knock and stagger. On every peer.
signal guarded(broken: bool)
## A blow is wound up toward [param direction], to be struck in
## [param ticks]; 0 ticks, a wind-up given up (decision 392: a heavy
## weapon's, World.try_wind_up; a brute's, Monster's HEAVY tactic). Views
## wind up, or stop. On every peer.
signal winding(direction: Vector2i, ticks: int)

# Not called "Material"/"material": CanvasItem already owns that name.
## FLESH is a creature (hazards hurt it). WOOD takes impact and breaks at 0 hp.
## STONE and METAL never break.
enum BodyMaterial { FLESH, WOOD, STONE, METAL }
enum Order { NONE, ATTACK, SHOVE, SWING, SIGNATURE }

## The only state sent over the network, besides World's tick.
const REPLICATED: Array[String] = ["tile", "hp", "facing", "stamina", "protected", "winded"]
## Reconciliation: a misprediction this far off or less is blended away over
## RECONCILE_BLEND_TICKS and the walk goes on; anything further ends the
## walk and slides there from where it is drawn, RECOVER_TICKS_PER_TILE a
## tile of the way, between RECONCILE_BLEND_TICKS and RECOVER_MAX_TICKS
## (decision 339); only TELEPORT_TILES or more is snapped.
const SNAP_TILES := 2
const RECONCILE_BLEND_TICKS := 2.0
const RECOVER_TICKS_PER_TILE := 0.75
const RECOVER_MAX_TICKS := 4.0
const TELEPORT_TILES := 8
## A mirror's slide that starts late (its turn came after the one before
## ended, or a burst arrived) is drawn up to this many times faster until
## it is back on time (_catch_up, decision 350).
const CATCH_UP_SPEED := 2.0
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
## A corner rounded as the body walks (decision 655): the bend round a
## cell's centre reaches this far along the step before it and the step
## after (half a step: midpoint to midpoint), and only this far in a
## narrow way (a cell with a wall beside it, a 1-cell door edge), so the
## body keeps nearer the cell it is on.
const BEND_REACH := 0.5
const BEND_REACH_NARROW := 0.25
## No tile known: the step before or after the one shown (655).
const UNKNOWN_TILE := Vector2i(-99999, -99999)
## A push not yet drawn this many ticks after it came is taken as over.
const PUSH_SHOWN_TICKS := 14.0
## A refused or corrected step eases to a stop over this many ticks.
const STOP_EASE_TICKS := 2.0
const IMPACT_FLASH := Color(4.0, 4.0, 4.0)
const HURT_TINT := Color(1.0, 0.3, 0.3)

@export var start_tile := Vector2i.ZERO
@export var mass := 10.0
## Server: its mass with nothing carried; mass is this plus what its slots
## weigh (World._carried_changed). -1 until it first carries anything.
var base_mass := -1.0
## Bandaging (World.try_bandage): 0 none, 1 being bandaged, 2 mending.
## A player's and a companion's replicate, for the views.
var mending := 0
## Buffs (World.try_use, a thing with effects consumed): kind ("mass",
## "aura", "wits", "speed": Items.BUFF_KINDS) -> [amount, the tick it fades]. Only
## ever above baseline. Reassigned whole on every change, so a player's
## and a companion's replicate, for the HUD.
var buffs := {}
## The right button's off hand (World.try_stance, decision 329): "" none,
## "block" a guard raised, "draw" a bow drawn. A player's and a monster's
## replicate, for the views and the HUD (decision 455).
var raised := ""
## The tick it was raised (World.tick): how long a bow has been drawn.
var raised_tick := 0
## Server: until this tick a broken guard cannot be raised again
## (World._meet_guard, decision 340).
var guard_broken_until := 0
## Server: a shield bash (World.try_bash, decision 379) is ready again at
## this tick, and until bash_moment_until its raised shield is down for the
## bash's moment (World.guarding finds no guard).
var next_bash_tick := 0
var bash_moment_until := 0
## Server: a heavy weapon's blow being wound up (World.try_wind_up, decision
## 392): {target, lands, direction, from}; {} for none.
var wind_up := {}
## Knocked down until this tick (World.knock_down, decision 343): lying,
## it cannot act and is easily pushed. A creature's replicates, for the
## views.
var down_until := 0
## Downed until this tick (World.lay_downed, decision 544): a blessed body
## beaten to 0 hp lies at 1, brought back by a channel or dead after. And a
## channeler's: the name of the body it is bringing back ("" none) and the
## tick it will be done. A player's and a companion's replicate, for the
## views.
var downed_until := 0
var channel_of := ""
var channel_until := 0
## A bandager's (World.try_bandage; the bandage kneel): the name of the body
## it is bandaging (its own for itself), "" when not. A player's and a
## companion's replicate, for the views (its kneel, sound's ruffle).
var tending := ""
## Server: its last step's velocity in cells a tick (World.try_move), for
## the momentum it carries into a blow (World.body_velocity, decision 592).
var step_velocity := Vector2.ZERO
## Server: the tick (maybe fractional) that step ends.
var step_until := -100000.0
## Server: the tick it last took a step (World.try_move): a spear is braced
## standing still (World.braced, decision 344).
var last_step_tick := -100000
## Server: the tick it was last hurt (World.damage); out of combat after a while.
var hurt_tick := -100000
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
## Winded (decision 597; World._regen_stamina): out of stamina, until back
## at World.recover_at. Slower steps, blows at half damage, no bash.
var winded := false
## Server: whether its swings cost stamina (decision 597, World.swing_cost):
## players and companions; a monster by its kind's "swing_stamina".
var pays_swings := true
## Server: stamina comes back only on every this many ticks (decision 603: a
## boss's slow breath; its kind's "stamina_regen_every").
var stamina_regen_every := 1
## Server: what each of those breaths gives back; 0, World.stamina_regen
## (603 amended: the draugr's, so a second spin comes a minute into a fight;
## its kind's "stamina_regen").
var stamina_regen_amount := 0
## Server only: the tick the grace runs out.
var protected_until_tick := 0
## Direction of the last step or attack.
var facing := Vector2i(0, 1)
## What it holds, a slot each: Items ids, "" for empty. None for most
## things; a player and a chest have theirs (Player.SLOTS, Chest.SLOTS),
## replicated (replicate). Written only by World (try_transfer, set_slots),
## always whole (_slots_set follows each write).
var slots := PackedStringArray():
	set(value):
		slots = value
		_slots_set()
## Server only, never sent: the instance in each slot (ItemBook uid), 0 for
## none yet (a level's chest: made on first need, World.slot_uid). Kept
## beside slots by the same World calls.
var slot_items := PackedInt32Array()
## Each slot's thing's note as it reads: its name ("Wren's dagger
## (quiet)"; decision 365) and its condition ("bundle of arrows, 6 of 10";
## decision 375), "" for a plain thing; empty when no slot has one.
## Replicated beside slots; written only by World (_show_notes).
var slot_notes := PackedStringArray()
## How many each slot holds (decision 619): empty while none holds more
## than one, else a count per slot (a stack's units). Replicated beside
## slots; written only by World (_show_counts).
var slot_counts := PackedInt32Array()
## What ails it (decision 375): kind ("burn", "bleed") -> [the tick it
## ends, every so many ticks, the hp each time]. Reassigned whole on every
## change, so a player's, a companion's and a monster's replicate, for the
## views. Written only by World (afflict).
var ailments := {}
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
## Mirrors only: the display clock as of the last frame drawn, where a
## slide hurried by the next cell's arrival goes on from (_mirror_tile_changed).
var _drawn_shown := -INF
## The facing as shown, an angle in grid space, turning toward the wanted
## one at TURN_RATE.
var _shown_angle := NAN
## 655: the tile the step before the one shown came from, when that step
## was drawn bending into this one (so this one starts on the bend), else
## UNKNOWN_TILE; and the tile this one bends toward at its end, settled as its
## tail began (the next slide known by then, or not), never changed under
## way, so the body never jumps onto or off a bend.
var _prev_tile := UNKNOWN_TILE
var _bend_next := UNKNOWN_TILE
var _bend_decided := false
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


## Each time slots is written: a Monster keeps its hands from it (decision 483).
func _slots_set() -> void:
	pass


## Whether the client [param peer] is sent this entity (World.peer_sees).
func _visible_to(peer: int) -> bool:
	return World.peer_sees(peer, zone) and Net.interest.sees(peer, self)


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
## Whether World thinks for it by tier (World.Tier): a monster.
var tiered := false


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


## The view takes it up again after it was far off and not drawn
## (Client3D stops its _process meanwhile): shown where it is now, with
## none of the slides it was sent meanwhile played out.
func _display_caught_up() -> void:
	_slides.clear()
	_present = false
	_from_tile = tile
	_to_tile = tile
	_from_pos = Vector2(tile)
	_move_duration = 0.0
	position = Iso.grid_to_local(Vector2(tile))


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
				wanted = _prediction.shown_direction()  # 655: along its bend.
		else:
			# Mirrors are drawn slightly in the past, so a tile change is
			# always known before its slide has to start.
			var now := World.tick + World.tick_alpha
			var to := tile
			if _mirroring:
				var shown := now - World.display_delay_ticks
				_drawn_shown = shown
				# A present push plays out before anything after it, and a
				# slide on the display clock before the next (decision 350):
				# one that came due meanwhile starts as it ends, never cutting
				# it short (a jump to its end).
				var held := _present and now < _move_tick + _move_duration
				var busy := not _present and shown < _move_tick + _move_duration
				# Where the slide on screen has the body at this frame's time:
				# a slide that takes over starts here (_catch_up), not where
				# the last frame drew it, a sample behind.
				var here := _from_pos.lerp(Vector2(_to_tile), clampf((shown - _move_tick) / _move_duration, 0.0, 1.0)) 						if _move_duration > 0.0 else Iso.local_to_grid(position)
				while not held and not _slides.is_empty() \
						and (_slides[0].get("present", false) or not busy and shown >= _slides[0]["tick"]):
					var slide: Dictionary = _slides.pop_front()
					if Net.test_smooth and _move_duration > 0.0 and shown < _move_tick + _move_duration - 0.05 and not _present:
						# --test-smooth: a slide replaced before it ended (net_smooth.sh).
						print("[slide] cut %s: %s->%s at %.2f of %.2f+%.2f, next %s->%s at %.2f for %.2f%s, %d more queued" % [
							name, _from_tile, _to_tile, shown, _move_tick, _move_duration, slide["from"], slide["to"],
							slide["tick"], slide["duration"], " (present)" if slide.get("present", false) else "", _slides.size()])
					if _present and not slide.get("present", false) and shown > slide["tick"]:
						# Back to the display clock after a present push: what
						# came due meanwhile goes on from here, one after
						# another, not all at once (a jump to the last).
						var late: float = shown - slide["tick"]
						slide["tick"] = shown
						slide["from_pos"] = Iso.local_to_grid(position)
						for later: Dictionary in _slides:
							later["tick"] = later["tick"] + late
					# 655: this slide starts on the bend the last one ended on, if it did.
					_prev_tile = _from_tile if _bend_decided and _bend_next == slide["to"] and slide["from"] == _to_tile \
							and not slide.has("from_pos") else UNKNOWN_TILE
					_bend_decided = false
					_bend_next = UNKNOWN_TILE
					_from_tile = slide["from"]
					_to_tile = slide["to"]
					_move_tick = slide["tick"]
					_move_duration = slide["duration"]
					_present = slide.get("present", false)
					_from_pos = slide.get("from_pos", Vector2(_from_tile))
					if not _present:
						_catch_up(shown, here)
						busy = shown < _move_tick + _move_duration
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
			var bent := _bent_step(to, t)  # 655: the corners rounded; [] for a slide drawn straight.
			position = Iso.grid_to_local(bent[0] if not bent.is_empty() else _from_pos.lerp(Vector2(to), t))
			var sliding := t < 1.0 and to != _from_tile
			var knocked := sliding and _on_push_line(_from_tile, to)
			stepping = sliding and not knocked
			_note_push_shown(knocked, to, t)
			if stepping:
				wanted = bent[1] if not bent.is_empty() else Vector2(to - _from_tile)
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
	# 655: a slide given straight (the host's own body, whose next step is
	# not known) is drawn straight.
	_prev_tile = UNKNOWN_TILE
	_bend_next = UNKNOWN_TILE
	_bend_decided = false


## 655: where the slide to [param to] at [param t] of its time is drawn
## with its corners rounded, and the way it points there: [position,
## tangent] in grid units; [] for a slide drawn straight: a push, one from
## off its cell's centre (a catch-up), a jump of more than a cell, or one
## with no corner known at either end. The bend at the end is settled as
## the tail begins (the next slide queued by then, joining straight on, or
## not) and never changes under way.
func _bent_step(to: Vector2i, t: float) -> Array:
	var delta := to - _from_tile
	if _present or _from_pos != Vector2(_from_tile) or maxi(absi(delta.x), absi(delta.y)) != 1:
		_bend_decided = false
		_bend_next = UNKNOWN_TILE
		return []
	var reach_out := bend_reach(to)
	if t > 1.0 - reach_out and not _bend_decided:
		_bend_decided = true
		_bend_next = _next_slide_to(to)
	if _prev_tile == UNKNOWN_TILE and _bend_next == UNKNOWN_TILE:
		return []
	var reach_in := bend_reach(_from_tile) if _prev_tile != UNKNOWN_TILE else 0.0
	return [bent_position(_prev_tile, _from_tile, to, _bend_next, t, reach_in, reach_out),
			bent_tangent(_prev_tile, _from_tile, to, _bend_next, t, reach_in, reach_out)]


## 655: the tile the next queued slide leads to, when it joins straight on
## from [param to] (a step of one cell, on the display clock, starting as
## the slide shown ends), else UNKNOWN_TILE.
func _next_slide_to(to: Vector2i) -> Vector2i:
	if _slides.is_empty():
		return UNKNOWN_TILE
	var slide: Dictionary = _slides[0]
	if slide.get("present", false) or slide.has("from_pos") or slide["from"] != to:
		return UNKNOWN_TILE
	if absf(float(slide["tick"]) - (_move_tick + _move_duration)) > 0.05:
		return UNKNOWN_TILE
	var delta: Vector2i = slide["to"] - to
	if maxi(absi(delta.x), absi(delta.y)) != 1:
		return UNKNOWN_TILE
	return slide["to"]


## 655: how far the bend round [param corner] reaches along the steps
## either side of it: half a step, or a quarter in a narrow way (a cell
## with a wall on any side: a 1-cell door edge), so the body keeps nearer
## the cell it is on.
static func bend_reach(corner: Vector2i) -> float:
	for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not World.is_walkable(corner + side):
			return BEND_REACH_NARROW
	return BEND_REACH


## 655: where a body is on its step [param from] -> [param to] at
## [param t] of the step's time, its corners rounded: the first
## [param reach_in] of the step runs the bend round from (coming from the
## step before, [param prev]), the last [param reach_out] the bend round
## to (going on toward [param next]). Each bend is a quadratic with the
## cell's centre as its control point, from the reach point on one step
## to the reach point on the other, timed on each step's own time, so
## every reach point is crossed when the straight line would cross it:
## arrival times stay the server's, and a straight run is the straight
## line at the straight pace. UNKNOWN_TILE at either end, or a reach of 0,
## leaves that end straight. In grid units.
static func bent_position(prev: Vector2i, from: Vector2i, to: Vector2i, next: Vector2i, t: float,
		reach_in := BEND_REACH, reach_out := BEND_REACH) -> Vector2:
	var a := Vector2(from)
	var b := Vector2(to)
	reach_in = capped_reach(Vector2(prev), a, b, reach_in) if prev != UNKNOWN_TILE else 0.0
	reach_out = capped_reach(a, b, Vector2(next), reach_out) if next != UNKNOWN_TILE else 0.0
	if prev != UNKNOWN_TILE and reach_in > 0.0 and t < reach_in:
		return _bend_point(Vector2(prev), a, b, reach_in, 0.5 + t / (2.0 * reach_in))
	if next != UNKNOWN_TILE and reach_out > 0.0 and t > 1.0 - reach_out:
		return _bend_point(a, b, Vector2(next), reach_out, (t - 1.0 + reach_out) / (2.0 * reach_out))
	return a.lerp(b, t)


## 655: the way the body points on that step at [param t]: a unit vector
## in grid units along the bend's tangent, else along the step.
static func bent_tangent(prev: Vector2i, from: Vector2i, to: Vector2i, next: Vector2i, t: float,
		reach_in := BEND_REACH, reach_out := BEND_REACH) -> Vector2:
	var a := Vector2(from)
	var b := Vector2(to)
	var tangent := b - a
	reach_in = capped_reach(Vector2(prev), a, b, reach_in) if prev != UNKNOWN_TILE else 0.0
	reach_out = capped_reach(a, b, Vector2(next), reach_out) if next != UNKNOWN_TILE else 0.0
	if prev != UNKNOWN_TILE and reach_in > 0.0 and t < reach_in:
		tangent = _bend_slope(Vector2(prev), a, b, reach_in, 0.5 + t / (2.0 * reach_in))
	elif next != UNKNOWN_TILE and reach_out > 0.0 and t > 1.0 - reach_out:
		tangent = _bend_slope(a, b, Vector2(next), reach_out, (t - 1.0 + reach_out) / (2.0 * reach_out))
	return tangent.normalized() if not tangent.is_zero_approx() else (b - a).normalized()


## 655 amended: [param reach] round [param centre], coming from
## [param before] and going on to [param after], cut so the corner is never
## cut by more than a quarter cell. The bend's apex lies reach / 4 of the
## turn (the step out less the step in) from the centre: 0.18 cells at a
## right angle and 0.25 at a reversal with the half-step reach, but 0.35
## at a diagonal reversal, where the body left its cell.
static func capped_reach(before: Vector2, centre: Vector2, after: Vector2, reach: float) -> float:
	var turn := (after - centre) - (centre - before)
	if turn.length_squared() < 0.0001:
		return reach
	return minf(reach, 1.0 / turn.length())


## The quadratic round [param centre], from [param reach] of the way back
## toward [param before] to [param reach] of the way on toward
## [param after], at [param u] (0..1); and its slope there.
static func _bend_point(before: Vector2, centre: Vector2, after: Vector2, reach: float, u: float) -> Vector2:
	var p0 := centre.lerp(before, reach)
	var p2 := centre.lerp(after, reach)
	var v := 1.0 - u
	return p0 * (v * v) + centre * (2.0 * u * v) + p2 * (u * u)


static func _bend_slope(before: Vector2, centre: Vector2, after: Vector2, reach: float, u: float) -> Vector2:
	var p0 := centre.lerp(before, reach)
	var p2 := centre.lerp(after, reach)
	return (centre - p0) * (2.0 * (1.0 - u)) + (p2 - centre) * (2.0 * u)


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


func _world_shot(to: Vector2, struck: StringName) -> void:
	shot.emit(to, struck)
	for peer in viewers():
		_net_shot.rpc_id(peer, to, struck)


func _world_hurled(item_id: String, to: Vector2i) -> void:
	hurled.emit(item_id, to)
	for peer in viewers():
		_net_hurled.rpc_id(peer, item_id, to)


func _world_guarded(broken: bool) -> void:
	guarded.emit(broken)
	for peer in viewers():
		_net_guarded.rpc_id(peer, broken)


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


## The slide just taken from the queue (_from_pos.._to_tile from
## _move_tick for _move_duration), on the display clock at [param shown]:
## late (it waited for the one before, or a burst of changes came at once
## after a delay on the way), it starts now from where the body is drawn,
## and is drawn faster to end when it would have, but at no more than
## CATCH_UP_SPEED times its pace; the lag left is made up by the slides
## after it. On time, it is drawn as it is. [param here]: where the body
## is at [param shown] by the slide before.
func _catch_up(shown: float, here: Vector2) -> void:
	var late := shown - _move_tick
	if late <= 0.0:
		return
	_from_pos = here
	_move_duration = maxf(_move_duration - late, _move_duration / CATCH_UP_SPEED)
	_move_tick = shown


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
	var duration := World.step_ticks(self, delta, old) if steps == 1 else float(clampi(steps, 1, 3))
	var previous_present: bool = _slides.back().get("present", false) if not _slides.is_empty() else _present
	if steps == 1 and previous_end > start - 1.0 and previous_end < start + 1.0:
		start = previous_end
	elif steps == 1 and previous_end > start + 1.0 and not previous_present:
		# The server moved it a cell faster than its own step takes to draw
		# (a rush or a charge: a cell a tick, decision 604), so the slide
		# before this would still be playing when this one is due, and
		# every cell after would wait its turn, the whole run drawn at half
		# the body's step at best (_catch_up): a draugr's rush arrived on
		# screen a second after its blow. Paced by arrival instead
		# (decision 646): the slide before ends at this arrival's tick
		# (hurried on from where it is drawn, never a jump), and this one
		# takes the gap since the last arrival, a tick at least.
		var previous_tick: float = _slides.back()["tick"] if not _slides.is_empty() else _move_tick
		var gap := maxf(start - previous_tick, 1.0)
		if not _slides.is_empty():
			_slides.back()["duration"] = gap
			start = previous_tick + gap
		elif _move_duration > 0.0:
			var shown := _drawn_shown if is_finite(_drawn_shown) else World.tick + World.tick_alpha - World.display_delay_ticks
			_from_pos = Iso.local_to_grid(position)
			_move_duration = maxf(previous_tick + gap - shown, 0.5)
			_move_tick = shown
			start = _move_tick + _move_duration
		duration = minf(duration, gap)
	_slides.append({"from": old, "to": tile, "tick": start, "duration": duration})


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


## 655 amended: WASD, each frame: the direction the keys hold now (ZERO
## for none), so the walk shown bends toward the step that will follow.
func hint_step(direction: Vector2i) -> void:
	if _prediction != null:
		_prediction.hint(direction)


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
## RECONCILE_BLEND_TICKS and the path re-planned from the server's tile; a
## larger one ends the walk and slides there from where the body is drawn
## (_recover); only TELEPORT_TILES or more is snapped.
func _mispredicted(reason: String) -> void:
	var predicted := _prediction.predicted_tile()
	var error := World.distance(predicted, tile)
	var off := (Iso.local_to_grid(position) - Vector2(tile)).length()
	var drawn := Iso.local_to_grid(position)
	Net.record_mispredict()
	Net.stats.record_correction(off, error >= TELEPORT_TILES)
	_mirror_rest()
	if error >= TELEPORT_TILES:
		_prediction.clear()
		Net.record_snap()
		print("[net] mispredict: %s predicted %s, server has %s, %d tiles off: snapped (%s)" % [
			name, predicted, tile, error, reason])
	elif error > SNAP_TILES:
		_prediction.clear()
		var ticks := _recover(drawn)
		print("[net] mispredict: %s predicted %s, server has %s, %d tiles off: walk ended, sliding there over %.1f ticks (%s)" % [
			name, predicted, tile, error, ticks, reason])
	else:
		_prediction.rebase(tile, RECONCILE_BLEND_TICKS)
		_resend_walk()
		print("[net] mispredict: %s predicted %s, server has %s: blending (%s), %.2f tiles off" % [
			name, predicted, tile, reason, off])


## A slide from [param drawn] to the tile, at once (on the present clock),
## its length by how far that is: no snap on a large correction. Returns
## the slide's ticks.
func _recover(drawn: Vector2) -> float:
	var ticks := clampf(drawn.distance_to(Vector2(tile)) * RECOVER_TICKS_PER_TILE, RECONCILE_BLEND_TICKS, RECOVER_MAX_TICKS)
	_slides.append({"from": tile, "to": tile, "tick": World.tick + World.tick_alpha, "duration": ticks,
		"present": true, "from_pos": drawn})
	return ticks


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
	_prediction.server_dropped_queue()  # A refused WASD step empties it (decision 543).
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


@rpc("authority", "call_remote", "reliable")
func _net_shot(to: Vector2, struck: StringName) -> void:
	shot.emit(to, struck)


@rpc("authority", "call_remote", "reliable")
func _net_hurled(item_id: String, to: Vector2i) -> void:
	hurled.emit(item_id, to)


@rpc("authority", "call_remote", "reliable")
func _net_guarded(broken: bool) -> void:
	guarded.emit(broken)


func _world_winding(direction: Vector2i, ticks: int) -> void:
	winding.emit(direction, ticks)
	for peer in viewers():
		_net_winding.rpc_id(peer, direction, ticks)


@rpc("authority", "call_remote", "reliable")
func _net_winding(direction: Vector2i, ticks: int) -> void:
	winding.emit(direction, ticks)


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
