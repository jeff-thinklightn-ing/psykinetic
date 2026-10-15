class_name Player
extends GridEntity
## Carries out orders set through World.order_move / order_step /
## order_attack / order_shove / order_swing.
## An action order (attack, shove) walks up to its target if it is out of
## reach, fires once when in reach and off cooldown, and clears; a swing
## fires where the player stands. A move order walks the tiles it came with
## first (move_via: the steps its client already shows), then re-paths every
## step so it reacts to things moving; stepping into the ordered tile pushes
## whatever is on it, if World allows. WASD steps (queued_steps) are taken
## one per free tick, in order, and win over everything else.

## Slots a player has for things (Items): the pack and two hands
## (Items.RIGHT_HAND, LEFT_HAND), from the start, empty.
const SLOTS := Items.CARRIED
const RIGHT_HAND := Items.RIGHT_HAND
const LEFT_HAND := Items.LEFT_HAND
## Its lantern's light (GridEntity.emit_light) while lit.
const LANTERN := 0.9

## WASD steps waiting for the movement timer: {direction, predicted}.
var queued_steps: Array[Dictionary] = []
## How many of this player's predicted WASD steps have been refused. A
## step its client sent before hearing of the latest refusal carries an
## older count and is dropped (see World.order_step): the client had
## already given that walk up.
var refusals := 0
## Server only: whose player this is (PlayerRecord.player_id), so the
## things it carries know (World.holder_key).
var player_id := ""


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
	replicate("mending")
	replicate("buffs")
	replicate("raised")
	replicate("raised_tick")
	replicate("down_until")
	# Its lantern lit or covered (L): what the views draw and monsters see by.
	replicate("emit_light")



## L: its lantern covered (no light: it cannot be seen in the dark, nor see
## by it), or lit again.
func toggle_lantern() -> void:
	emit_light = 0.0 if emit_light > 0.0 else LANTERN

func _sim_tick() -> void:
	if not queued_steps.is_empty():
		_take_queued_step()
		return
	if action_order != Order.NONE:
		# The steps the client was showing when it sent the strike first.
		if not move_via.is_empty() and World.tick >= next_move_tick and _walk_via():
			return
		_pursue_action()
		return

	if not has_move_order or World.tick < next_move_tick:
		return
	if _walk_via():
		return
	if tile == move_order:
		has_move_order = false
		return
	var path := World.find_path(tile, move_order, true)
	if path.is_empty():
		has_move_order = false
	elif not World.try_move(self, path[0] - tile):
		# Someone took that tile first this tick. If it was the destination
		# itself the contest is decided: give up. Otherwise keep the order and
		# path around it next tick. Either way the client re-plans now.
		if path[0] == move_order:
			has_move_order = false
		World.report_move_refused(self, path[0])


## The next WASD step, when the timer allows. A refused step that the
## client was showing ends the walk: the rest of the queue is dropped and
## the client is told, with the new refusal count.
func _take_queued_step() -> void:
	if World.tick < next_move_tick:
		return
	var step: Dictionary = queued_steps.pop_front()
	var direction: Vector2i = step["direction"]
	if World.try_move(self, direction):
		return
	if step["predicted"]:
		refusals += 1
		queued_steps.clear()
		World.report_move_refused(self, tile + direction, refusals)


## One step through the order's via tiles, if any are left. Tiles already
## behind the player are dropped; a via tile that is no longer one step
## away (the player was pushed) drops them all, and so does a way of the
## server's own to the destination World.DETOUR_STEPS shorter than the rest
## of them (a passage that was taken when the client planned round it has
## cleared):
## the server's own way is walked then, as before there were via tiles.
## True if a step was tried.
func _walk_via() -> bool:
	var reached := move_via.find(tile)
	if reached != -1:
		move_via = move_via.slice(reached + 1)
	if move_via.is_empty():
		return false
	var next: Vector2i = move_via[0]
	if World.distance(tile, next) != 1:
		move_via.clear()
		return false
	if has_move_order and move_via.back() == move_order:
		var own := World.find_path(tile, move_order, true)
		if not own.is_empty() and own.size() + World.DETOUR_STEPS <= move_via.size():
			move_via.clear()
			return false
	move_via.pop_front()
	if not World.try_move(self, next - tile):
		move_via.clear()
		# Into the destination itself: decided, as in _sim_tick (refused once,
		# not again next tick by the path round it).
		if has_move_order and next == move_order:
			has_move_order = false
		World.report_move_refused(self, next)
	return true


func _pursue_action() -> void:
	if action_order == Order.SWING:
		if World.tick < maxf(next_attack_tick, next_move_tick):
			return
		var swing := action_direction
		_clear_action()
		World.try_swing(self, swing)
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
		if order == Order.ATTACK:
			World.try_attack(self, target)
		else:
			World.try_shove(self, target, direction)
		return
	# Out of reach: close in, re-pathing each step in case the target moves.
	# No way, or the step taken first: the order is dropped, and the client
	# told at once, or it walks on showing the approach till it gives up
	# waiting and is pulled back.
	if World.tick < next_move_tick:
		return
	var path := World.find_path(tile, action_target.tile, true)
	if path.is_empty():
		World.report_move_refused(self, action_target.tile, World.ORDER_DROPPED)
		_clear_action()
	elif not World.try_move(self, path[0] - tile):
		World.report_move_refused(self, path[0], World.ORDER_DROPPED)
		_clear_action()


func _clear_action() -> void:
	action_order = Order.NONE
	action_target = null
	action_direction = Vector2i.ZERO
