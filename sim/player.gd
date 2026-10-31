class_name Player
extends GridEntity
## A free body (decision 688; since 703 the only way a player walks): its
## client's input commands move it (World.free_input, tend_free_body). It
## carries out the action orders set through World.order_attack /
## order_shove / order_swing / order_signature: an attack or a shove fires
## once in reach and off cooldown, its client closing in (697), and clears;
## a swing fires where the player stands.

## Slots a player has for things (Items): the pack, two hands
## (Items.RIGHT_HAND, LEFT_HAND) and the armour worn (Items.ARMOUR; decision
## 622), from the start, empty.
const SLOTS := Items.CARRIED
const FreeNet := preload("res://net/free_net.gd")
const RIGHT_HAND := Items.RIGHT_HAND
const LEFT_HAND := Items.LEFT_HAND
## Its lantern's light (GridEntity.emit_light) while lit.
const LANTERN := 0.9
## How long a free body's attack or shove order waits for its client's
## chase to bring it into reach before it is given up (4 s).
const FREE_CHASE_TICKS := 4 * World.TICK_RATE

## The armour it wears (decision 622): the Items id in its armour slot
## (Items.ARMOUR), "" for none. Replicated, for the views' covering (read
## Items.armour_of); written only by World as its slots change.
var worn := ""
## Server: a free body's input commands waiting (World.free_input, decision
## 688): {intent, ticks}, applied in order against free_bank.
var free_inputs: Array[Dictionary] = []
## Server: the real time a free body may still move, in ticks (688): one
## more each tick, at most World.FREE_BANK_TICKS, so more commands than
## time cannot make it run fast.
var free_bank := 0.0
## Server: the seq of the last command it is done with, applied or dropped
## (688 amended, World._free_acked): -1 for none. Its client replays only
## those after it (ui's 689).
var free_acked := -1
## Server: the ticks the head command has had so far (688 amended); 0 for
## none.
var free_used := 0.0
## Server: the tick it last bumped its own companion as a free body (688).
var free_bumped_tick := -100000
## Server: the ticks its free body has pressed each straight way against an
## edge of free_press_tile it cannot cross (688 amended (4),
## World._free_pressed): {Vector2i: ticks}.
var free_press: Dictionary[Vector2i, int] = {}
var free_press_tile := Vector2i(-99999, -99999)
## Its free body on the wire (decision 689; FreeNet.pack_state): the
## server's centre, the last command applied and the tick; empty while it
## walks the grid. Replicated. Each peer feeds its view from it (free_view).
var free_state := PackedByteArray():
	set(value):
		free_state = value
		_free_heard()
## Client and host: the view of its free body, a FreeNet.Own for one's own
## player (the replay), a FreeNet.Mirror for another's; null on the grid.
var free_view: RefCounted = null
## Server: the newest command seq taken from its client (World.take_free),
## -1 for none yet, and its client's command allowance (World.FREE_COMMANDS_PER_SECOND).
var free_seen := -1
var free_allowance := 0.0
var free_allowance_at := 0
## Server only: whose player this is (PlayerRecord.player_id), so the
## things it carries know (World.holder_key).
var player_id := ""
## The body this player wears (Net.BODIES; decision 388): their setting, from
## their record. What the views draw and sound voices them by.
var body: StringName = &"male"
## The companion leading this player somewhere (decision 551), by name;
## "" when none. While it is set the server walks their body at her heel,
## and their own step or order takes it back.
var led_by := ""
## Where she leads them (decision 551 amended, ui's map and HUD): the
## place's Holdings id or the area's name she set off for; "" when not led.
var led_to := ""
## The resurrection charges they hold and the most they may (decision 573):
## the server sets both from their record; the client's pack line reads them.
var charges := 0
var charge_room := 0
## The quest they are on (747, ui's tracker): {} for none, else {title,
## giver, items: [{name, done}], ready}; the server sets it from their
## record (Main._sync_quest).
var quest: Dictionary = {}
## Mortally Wounded (Jeff's down screen): the heart while downed, in beats a
## minute (field rules' heart.beats: 120, 80, 40), 0 when not downed;
## replicated for the heartbeat and the hold's read. Server only: whether
## Slow Heart is held, when the heart last stepped, and the window's ticks
## owed by a slower heart (Main._tend_hearts).
var heart := 0
var heart_held := false
var heart_at := 0
var heart_debt := 0.0


func _init() -> void:
	super()
	mass = 80.0
	emit_light = LANTERN  # The lantern the 3D view draws above the head.
	# 4 cells a second.
	move_ticks = 2.5
	max_hp = 20
	attack_damage = 2
	strength = 10
	max_stamina = 100
	attack_ticks = 5
	slots = Items.tidy([], SLOTS)
	replicate("slots")
	replicate("slot_notes")
	replicate("slot_counts")
	replicate("worn")
	replicate("load_arms")
	replicate("load_body")
	replicate("mending")
	replicate("buffs")
	replicate("ailments")
	replicate("raised")
	replicate("raised_tick")
	replicate("lobbing")  # Decision 677: the bow aimed at the sky.
	replicate("down_until")
	replicate("downed_until")  # Decision 544: downed, and bringing back the downed.
	replicate("channel_of")
	replicate("tending")
	replicate("channel_until")
	# Its lantern lit or covered (L): what the views draw and monsters see by.
	replicate("emit_light")
	replicate("body")
	replicate("led_by")
	replicate("led_to")
	replicate("charges")  # Decision 573: the resurrection charges, and the most they may hold.
	replicate("charge_room")
	replicate("quest")  # 747: the fallen knight's quest, for the tracker.
	replicate("heart")  # Mortally Wounded: the heart while downed.
	replicate("free_state")  # Decision 689: its free body's centre.



## Its own free body pushed (688 amended (2)): the view stops replaying
## till the slide is over.
func _free_pushed(tiles: int) -> void:
	if free_view is FreeNet.Own:
		(free_view as FreeNet.Own).pushed(tiles)


## The packed state of its free body heard (decision 689): one's own
## player's replay told what the server applied, another's mirror given a
## sample; empty, the view dropped (back on the grid).
func _free_heard() -> void:
	if free_state.is_empty():
		free_view = null
		return
	var state := FreeNet.unpack_state(free_state, World.tick)
	if state.is_empty():
		return
	if is_local():
		if not free_view is FreeNet.Own:
			free_view = FreeNet.Own.new()
			if not pushed.is_connected(_free_pushed):
				pushed.connect(_free_pushed)
		(free_view as FreeNet.Own).confirm(self, state)
	elif not Net.is_authority():
		if not free_view is FreeNet.Mirror:
			free_view = FreeNet.Mirror.new()
		(free_view as FreeNet.Mirror).add(state)


## Placed (a spawn, a respawn, a join): its client's commands count from
## the start again (decision 689; its view on the client starts afresh).
func _world_place(new_id: int, at: Vector2i) -> void:
	super(new_id, at)
	free_inputs.clear()
	free_seen = -1
	free_acked = -1
	free_used = 0.0
	free_press.clear()


## Whether this is the player this peer plays.
func is_local() -> bool:
	return owner_peer == Net.local_id  # As Main._local_player.


func _free_shown() -> Array:
	if free_view is FreeNet.Own:
		var own := free_view as FreeNet.Own
		return [own.shown(self), own.going()]
	if free_view is FreeNet.Mirror:
		var drawn: Array = (free_view as FreeNet.Mirror).at(World.tick + World.tick_alpha - World.display_delay_ticks)
		return drawn if drawn[0] != Vector2.INF else []
	return []


## Server: its packed state after its turn (decision 689), written when the
## centre or what was applied changed, and standing still once every
## FreeNet.STATE_RESEND_TICKS (689 amended (2): a client that missed its
## first state, its body placed again, was left on the grid, its steps
## cleared, the body never moving); empty off the free walk.
func pack_free() -> void:
	if not World.free_body(self):
		if not free_state.is_empty():
			free_state = PackedByteArray()
		return
	var was := FreeNet.unpack_state(free_state, World.tick)
	if not was.is_empty() and (was["pos"] as Vector2).distance_to(free_pos) < 0.5 / FreeNet.POS_SCALE \
			and int(was["acked"]) == free_acked & 0xFFFF and absf(float(was["used"]) - free_used) < 0.5 / FreeNet.USED_SCALE and was["held"] == tile \
			and World.tick - int(was["tick"]) < FreeNet.STATE_RESEND_TICKS:
		return
	free_state = FreeNet.pack_state(free_pos, free_acked, free_used, World.tick, tile)


## L: its lantern covered (no light: it cannot be seen in the dark, nor see
## by it), or lit again.
func toggle_lantern() -> void:
	emit_light = 0.0 if emit_light > 0.0 else LANTERN

func _sim_tick() -> void:
	# A free body (decision 688): its commands, not steps or routes.
	World.tend_free_body(self)
	pack_free()
	if action_order != Order.NONE:
		_pursue_action()


func _pursue_action() -> void:
	if action_order == Order.SWING:
		if World.tick < maxf(next_attack_tick, next_move_tick):
			return
		var swing := action_direction
		_clear_action()
		var struck := World.stand_target(self, swing)  # Whatever is in the way takes it (decision 593).
		if struck == null:
			World.try_swing(self, swing)
		elif World.windup_ticks(self) > 0:
			World.try_wind_up(self, struck)
		else:
			World.try_attack(self, struck)
		return
	if action_order == Order.SIGNATURE:
		# From where it stands (decision 593): out of reach, dropped.
		if not is_instance_valid(action_target) or not action_target.spawned or not World.in_reach(self, action_target, true):
			_clear_action()
			return
		if World.tick < maxi(next_bash_tick, next_move_tick):
			return
		var marked := action_target
		_clear_action()
		if World.signature_of(self) == "bash":
			World.try_bash(self, marked)
		return
	if not is_instance_valid(action_target) or not action_target.spawned:
		_clear_action()
		return
	if World.in_reach(self, action_target, action_order != Order.ATTACK):
		# World refuses hits during the cooldown and while still mid-step.
		if World.tick < maxf(next_attack_tick, next_move_tick):
			return
		var order := action_order
		var target := action_target
		var direction := action_direction
		_clear_action()
		if order == Order.ATTACK and World.windup_ticks(self) > 0:
			World.try_wind_up(self, target)  # A heavy weapon winds up first (decision 392).
		elif order == Order.ATTACK:
			World.try_attack(self, target)
		else:
			World.try_shove(self, target, direction)
		return
	# Out of reach: a free body (688) closes in by its own commands, its
	# client chasing (697): the order held till in reach, given up after
	# FREE_CHASE_TICKS.
	if World.tick - action_tick > FREE_CHASE_TICKS:
		_clear_action()


func _clear_action() -> void:
	action_order = Order.NONE
	action_target = null
	action_direction = Vector2i.ZERO
