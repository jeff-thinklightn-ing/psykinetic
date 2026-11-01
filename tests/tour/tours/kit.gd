extends RefCounted
## What the player's own body shows of the weapon in hand (a cut's lines),
## read from the drawn puppet, so it runs with a renderer (--offscreen):
##   TOUR_SERVER_ARGS="--test-foe=draugr,giant_axe" sh tools/tour.sh kit --offscreen
## a heavy axe: each blow plays Axe_Sweep (750 amended, bc2def64), its length
## logged against the swing's own times;
##   TOUR_SERVER_ARGS="--test-foe=rat,bow" sh tools/tour.sh kit --offscreen
## a bow: not drawn, it lies on the sling socket (662 (d) amended, a578ba94),
## and in the left hand while drawn.

const SWEEP := "Axe_Sweep"


func run(bot: Node) -> void:
	await bot.settled()
	await bot.seconds(3.0)
	var held := str(World.wielded(bot.me()))
	bot.log_line("in hand: %s" % held)
	if "axe" in held:
		await _sweep(bot)
	elif "bow" in held:
		await _bow(bot)
	else:
		bot.expect(false, "a heavy axe or a bow in hand (TOUR_SERVER_ARGS --test-foe)", "in hand %s" % held)


func _puppet(bot: Node) -> Node3D:
	var c3: Node = bot.main._client3d
	if c3 == null or bot.me() == null:
		return null
	return (c3.get("_puppets") as Dictionary).get(bot.me().get_instance_id())


func _rig(bot: Node) -> AnimRig:
	var puppet := _puppet(bot)
	return puppet.get_meta("rig") as AnimRig if puppet != null and puppet.has_meta("rig") else null


## Swing at the test foe for a while; every strike the rig starts logged:
## its clip and how long it plays (start to the strike's end).
func _sweep(bot: Node) -> void:
	await bot.until(func() -> bool: return _rig(bot) != null, 20.0)
	if not bot.expect(_rig(bot) != null, "my own body is drawn, with its rig", "no puppet (run --offscreen)"):
		return
	var foe: GridEntity = null
	for body: GridEntity in bot.seen(""):
		# --test-foe's own (Main._test_foe): named "Foe", or made as its kind's class (the axes tour's finder).
		if not body is Monster or not (String(body.name).begins_with("Foe") or "raugr" in bot.label(body)):
			continue
		if foe == null or World.distance(body.tile, bot.cell()) < World.distance(foe.tile, bot.cell()):
			foe = body
	bot.log_line("the foe: %s %s at %s" % [foe.name if foe != null else "none", bot.label(foe) if foe != null else "", foe.tile if foe != null else Vector2i.ZERO])
	if not bot.expect(foe != null, "the test foe is in view"):
		return
	if "raugr" in bot.label(foe):
		# The draugr speaks first (his challenge): refused, "and he fights you for it" (as the axes tour).
		await bot.click(foe.tile)
		await bot.seconds(2.0)
		for answer: String in ["refuse", "fight", "no"]:
			if bot.press(answer):
				break
		await bot.seconds(2.0)
	var strikes: Array = []  # [clip, seen msec, its end msec]
	var last := {"end": -1}
	var sample := func() -> void:
		var rig := _rig(bot)
		if rig != null and rig.striking() and int(rig.get("_strike_msec")) != int(last["end"]):
			last["end"] = int(rig.get("_strike_msec"))
			strikes.append([str(rig.get("_action_clip")), Time.get_ticks_msec(), int(last["end"])])
	bot.get_tree().process_frame.connect(sample)
	await bot.fight(foe, 25.0)
	bot.get_tree().process_frame.disconnect(sample)
	bot.log_line("strikes seen: %d" % strikes.size())
	for s: Array in strikes:
		bot.log_line("  %s, playing %.2f s from its start" % [s[0], (int(s[2]) - int(s[1])) / 1000.0])
	bot.expect(not strikes.is_empty(), "my blows play a strike clip", "none seen in 25 s")
	var sweeps: Array = strikes.filter(func(s: Array) -> bool: return SWEEP in str(s[0]))
	bot.expect(not strikes.is_empty() and sweeps.size() == strikes.size(), "every blow with a %s plays %s" % [str(World.wielded(bot.me())), SWEEP],
		"clips %s" % [strikes.map(func(s: Array) -> String: return str(s[0]))])
	var lengths: Array = sweeps.map(func(s: Array) -> float: return (int(s[2]) - int(s[1])) / 1000.0)
	bot.expect(not lengths.is_empty() and lengths.all(func(l: float) -> bool: return l >= 0.9 and l <= 2.0),
		"each sweep plays about its 1.3 s (0.9 to 2 s, as the swing's times stretch it)", "lengths %s" % [lengths])


## The bow, not drawn, on the sling; drawn, in the left hand.
func _bow(bot: Node) -> void:
	await bot.until(func() -> bool: return _puppet(bot) != null, 20.0)
	var puppet := _puppet(bot)
	if not bot.expect(puppet != null, "my own body is drawn", "no puppet (run --offscreen)"):
		return
	var sockets: Dictionary = puppet.get_meta("sockets", {})
	var sling := sockets.get("sling") as Node3D
	bot.log_line("sockets: %s" % [sockets.keys()])
	# Calm (Client3D._calm): the test foe left behind, stood still a while.
	var away: Vector2i = bot.cell() + Vector2i(-14, 0)
	await bot.walk_to(away, 2, 30.0)
	await bot.seconds(6.0)
	var where := _bow_on(sockets)
	bot.log_line("standing, not drawn: the bow on %s (bow_state %s)" % [where, puppet.get_meta("bow_state", "")])
	bot.expect(sling != null and where == "sling", "the bow, not drawn, lies on the sling socket", "on %s; bow_state %s" % [where, puppet.get_meta("bow_state", "")])
	var quiver_seen := false
	for socket: Variant in sockets.values():
		if socket is Node3D:
			for child: Node in (socket as Node3D).get_children():
				if "uiver" in String(child.name):
					quiver_seen = true
	bot.log_line("a quiver on the body: %s" % quiver_seen)


func _bow_on(sockets: Dictionary) -> String:
	for key: Variant in sockets:
		var socket := sockets[key] as Node3D
		if socket != null and (socket.get_node_or_null("StowedBow") != null or socket.get_node_or_null("Held") != null and key == "hand_l"):
			return str(key)
	return "nowhere"
