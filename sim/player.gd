class_name Player
extends GridEntity
## Carries out orders set through World.order_move / World.order_action.
## An action order (attack, shove) waits for the cooldown, fires once, and
## clears. A move order re-paths every step so it reacts to things moving;
## stepping into the ordered tile pushes whatever is on it, if World allows.


func _sim_tick() -> void:
	if action_order != Order.NONE:
		# World refuses hits during the cooldown and while still mid-step.
		if World.tick < maxi(next_attack_tick, next_move_tick):
			return
		var order := action_order
		action_order = Order.NONE
		if is_instance_valid(action_target):
			if order == Order.ATTACK:
				World.try_attack(self, action_target)
			else:
				World.try_shove(self, action_target)
		action_target = null
		return

	if not has_move_order or World.tick < next_move_tick:
		return
	if tile == move_order:
		has_move_order = false
		return
	var path := World.find_path(tile, move_order, true)
	if path.is_empty() or not World.try_move(self, path[0] - tile):
		has_move_order = false
