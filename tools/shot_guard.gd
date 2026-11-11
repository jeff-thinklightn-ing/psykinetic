extends RefCounted
## A shot scene's check that it draws one game view (the coordinator, 2026-11-11): a still that
## hosts main.tscn uses main's own Client3D (windowed, main builds it in _ready, _show_3d) and never
## adds a second, which doubled the sun, the lamps and the environment in trees' scratch stills.
## No class_name: preload("res://tools/shot_guard.gd").count(rig), then .ok(counts) before any still.
##
## A rig is a Client3D that runs: the neighbour zone's view and the zone glimpses are Client3Ds with
## processing off and no light of their own. A sun or an environment counts when it draws in the
## town's world (the root's): the item icons' and the character preview's sit in worlds of their own.
## The rig's body fill (858), a second DirectionalLight3D culled to bodies, is not a sun.
##
## The other traps a shot scene meets (environment's 858 proof, nine starts for one row, most of the
## void stills the scene's own): a body set by tile alone isn't drawn there and the camera doesn't
## follow it (put, at_spot); after a jump into cover the camera turns to find the player, so an off
## and an on still taken a second apart aren't the same view (settle_yaw, YawPin); a told cell's
## projected rect can land on a wall beside a half-hidden mark (measure the mark's own pixels: the
## frame again with it dropped); and _update_sky writes the ambient and the floor every frame, so a
## value set once is undone (set it in RenderingServer.frame_pre_draw).
const FreeNet := preload("res://net/free_net.gd")


## {"rigs", "suns", "environments", "apart", "lines"}: the counts in the town's world, how many
## lights and environments sit apart, and one line per node counted or set aside, with its path.
## [param rig] is the scene's view (main's _client3d); its body fill is left out.
static func count(rig: Node) -> Dictionary:
	var tree := rig.get_tree()
	var town := tree.root.world_3d
	var fill: Variant = rig.get("_body_fill") if "_body_fill" in rig else null
	var rigs := 0
	var suns := 0
	var environments := 0
	var apart := 0
	var lines := PackedStringArray()
	for node in tree.root.find_children("*", "", true, false):
		var line := ""
		if node is Client3D:
			var view := node as Client3D
			var runs := view.is_processing() and not view._glimpse
			rigs += int(runs)
			line = "rig" if runs else "still view (processing off, glimpse %s)" % view._glimpse
		elif node is DirectionalLight3D and fill != null and node == fill:
			line = "the rig's body fill (858), culled to bodies: not a sun"
		elif node is DirectionalLight3D or node is WorldEnvironment:
			var lit := node.get_viewport().world_3d == town and (node is WorldEnvironment or (node as Node3D).is_visible_in_tree())
			if node is DirectionalLight3D:
				suns += int(lit)
			else:
				environments += int(lit)
			apart += int(not lit)
			line = "in the town's world" if lit else "apart (own world or hidden)"
		if line != "":
			lines.append("%s %s: %s" % [node.get_class(), node.get_path(), line])
	return {"rigs": rigs, "suns": suns, "environments": environments, "apart": apart, "lines": lines}


## Whether [param counts] (from count) is one rig, one sun and one environment.
static func ok(counts: Dictionary) -> bool:
	return int(counts["rigs"]) == 1 and int(counts["suns"]) == 1 and int(counts["environments"]) == 1


## The counts as one line, for a scene's log.
static func summary(counts: Dictionary) -> String:
	return "rigs %d, suns %d, environments %d in the town's world (%d apart), display %s" % [counts["rigs"],
		counts["suns"], counts["environments"], counts["apart"], DisplayServer.get_name()]


## [param entity] moved to [param cell] and drawn there, with [param rig]'s camera on it if it is
## the player. World._relocate keeps the occupancy and free_pos as the World would. A free body
## (decision 689) is drawn from its own predicted place (FreeNet.Own), which a bare tile = cell
## leaves behind, so the prediction is cleared; with the World stopped no tick puts it back. And
## the view freezes any body far from the camera's aim (Client3D._sync_puppets), the player's own
## too, so after a long jump neither the body nor the camera would move: the puppet and the aim are
## put at the cell here, and the view takes the body up again on its next frame.
static func put(rig: Client3D, entity: GridEntity, cell: Vector2i) -> void:
	World._relocate(entity, cell)
	entity._display_caught_up()
	if entity.get("free_view") is FreeNet.Own:
		var own: FreeNet.Own = entity.free_view
		own.base = Vector2.INF
		own.error = Vector2.ZERO
		own.pending.clear()
		own.open_intent = Vector2.ZERO
		own.open_seconds = 0.0
	var at := rig._tile_position(cell)
	var puppet := rig._puppets.get(entity.get_instance_id()) as Node3D
	if puppet != null:
		puppet.position = at
	if entity is Player and (entity as Player).is_local():
		rig._camera_target = at
		rig._camera_ease._offset = Vector3.ZERO
		rig._camera_ease._last = at


## {"ok", "line"}: whether [param player]'s puppet and [param rig]'s camera aim stand at
## [param cell] (its tile the cell, drawn within a cell of it, the aim within 1.5 of the drawn
## body), and a line for the log with the cells and the puppet's distance from the aim. A scene
## saves nothing for a spot that isn't ok, so a bad spot costs nothing and the others still count.
static func at_spot(rig: Client3D, player: GridEntity, cell: Vector2i) -> Dictionary:
	var puppet := rig._puppets.get(player.get_instance_id()) as Node3D
	if puppet == null:
		return {"ok": false, "line": "spot %s: no puppet" % [cell]}
	var drawn := Vector2(puppet.position.x, puppet.position.z)
	var at := rig._tile_position(cell)  # The cell's own place: a level's centre offset makes it differ from the cell.
	var aim := Vector2(rig._camera_target.x, rig._camera_target.z)
	var ok := player.tile == cell and drawn.distance_to(Vector2(at.x, at.z)) < 1.0 and drawn.distance_to(aim) < 1.5
	return {"ok": ok, "line": "spot %s, tile %s, drawn (%.1f, %.1f), aim (%.1f, %.1f), puppet to aim %.2f%s" % [cell, player.tile,
		drawn.x, drawn.y, aim.x, aim.y, drawn.distance_to(aim), "" if ok else ": NOT AT THE SPOT"]}


## The yaw to hold for a spot's stills (a coroutine: await it). [param rig] starts again from
## [param yaw] (the game's own, so one spot's turn doesn't carry into the next), lets a hidden
## player's turn play out for [param frames] (Net.camera_turn on: a jump into cover turns the
## camera to find him), stops a turn still going where it stands (as a hand on the camera does),
## and turns the camera's own turning off. Hold the result with a YawPin for every still at the
## spot, print the yaw per still, and refuse a pair whose yaw moved. Net.camera_turn is left off:
## set it back after the shots.
static func settle_yaw(rig: Client3D, yaw: float, frames := 120) -> float:
	rig._set_yaw(yaw)
	rig._yaw_step = yaw
	rig._hand_yaw = yaw
	Net.camera_turn = true
	for i in frames:
		await rig.get_tree().process_frame
	if rig._turn_view.turning:
		rig._turn_view.manual()
	Net.camera_turn = false
	return rig.yaw


## A yaw held on [param rig] each frame before the view's own _process, while the scene keeps it:
## var pin := preload("res://tools/shot_guard.gd").YawPin.new(rig, yaw) ... pin.stop(). An object, not a lambda: a lambda's
## Callable from a static func crashed at exit (a Godot gotcha these trees met before).
class YawPin extends RefCounted:
	var rig: Client3D
	var yaw := 0.0

	func _init(on: Client3D, held: float) -> void:
		rig = on
		yaw = held
		rig.get_tree().process_frame.connect(_hold)

	func _hold() -> void:
		if is_instance_valid(rig):
			rig.yaw = yaw
			rig._yaw_step = yaw
			rig._hand_yaw = yaw
			rig._ease_t = 1.0

	func stop() -> void:
		if is_instance_valid(rig) and rig.get_tree().process_frame.is_connected(_hold):
			rig.get_tree().process_frame.disconnect(_hold)
