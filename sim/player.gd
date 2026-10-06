class_name Player
extends GridEntity
## Carries out orders set through World.order_move / order_attack / order_shove.
## An action order (attack, shove) walks up to its target if it is out of
## reach, fires once when in reach and off cooldown, and clears. A move order
## re-paths every step so it reacts to things moving; stepping into the
## ordered tile pushes whatever is on it, if World allows.


func _sim_tick() -> void:
	if action_order != Order.NONE:
		_pursue_action()
		return

	if not has_move_order or World.tick < next_move_tick:
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


func _pursue_action() -> void:
	if not is_instance_valid(action_target) or not action_target.spawned:
		_clear_action()
		return
	if World.can_melee(tile, action_target.tile):
		# World refuses hits during the cooldown and while still mid-step.
		if World.tick < maxi(next_attack_tick, next_move_tick):
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
	if World.tick < next_move_tick:
		return
	var path := World.find_path(tile, action_target.tile, true)
	if path.is_empty() or not World.try_move(self, path[0] - tile):
		_clear_action()


func _clear_action() -> void:
	action_order = Order.NONE
	action_target = null
	action_direction = Vector2i.ZERO
